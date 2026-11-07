locals {
  lambdas = {
    api     = { command = "dist/lambda.handler", timeout = 60, memory_size = 1024 }
    worker  = { command = "dist/worker.handler", timeout = 300, memory_size = 1024 }
    migrate = { command = "dist/migrate.handler", timeout = 300, memory_size = 1024 }
  }

  # AI HERE: a container function cannot be created before its image exists, and the edge
  # instance cannot boot before the Function URL it proxies to exists, so the first apply
  # creates everything that has no image dependency. Ceiling: two applies on a cold account.
  # Upgrade path: a separate state for the repository if this ever needs to be one apply.
  ready           = var.lambda_image_uri != ""
  lambdas_enabled = local.ready ? local.lambdas : {}
  api_host        = try(replace(aws_lambda_function_url.api["api"].function_url, "https://", ""), "")
}

resource "aws_ecr_repository" "lambda" {
  name                 = "sesume_backend_lambda"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "lambda" {
  repository = aws_ecr_repository.lambda.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "keep the last 10 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 10 }
      action       = { type = "expire" }
    }]
  })
}

resource "aws_lambda_function" "this" {
  for_each = local.lambdas_enabled

  function_name = "sesume-${each.key}"
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"
  image_uri     = var.lambda_image_uri
  timeout       = each.value.timeout
  memory_size   = each.value.memory_size

  image_config {
    command = [each.value.command]
  }

  environment {
    variables = { SSM_PREFIX = local.ssm_prefix }
  }

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  depends_on = [aws_iam_role_policy.lambda]

  # CD rolls the image; Terraform owns everything else.
  lifecycle {
    ignore_changes = [image_uri]
  }
}

resource "aws_lambda_function_url" "api" {
  for_each = { for name, fn in aws_lambda_function.this : name => fn if name == "api" }

  function_name      = each.value.function_name
  authorization_type = "NONE"
}

resource "aws_sqs_queue" "review_dlq" {
  name = "sesume-review-dlq"
}

resource "aws_sqs_queue" "review" {
  name                       = "sesume-review"
  visibility_timeout_seconds = 1800
  message_retention_seconds  = 86400

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.review_dlq.arn
    maxReceiveCount     = 3
  })
}

# The URL's own statement covers InvokeFunctionUrl only; anonymous calls also need this one.
resource "aws_lambda_permission" "api_url_invoke" {
  for_each = aws_lambda_function_url.api

  statement_id  = "FunctionURLInvokeFunction"
  action        = "lambda:InvokeFunction"
  function_name = each.value.function_name
  principal     = "*"
}

resource "aws_lambda_event_source_mapping" "worker" {
  for_each = { for name, fn in aws_lambda_function.this : name => fn if name == "worker" }

  event_source_arn        = aws_sqs_queue.review.arn
  function_name           = each.value.arn
  batch_size              = 1
  function_response_types = ["ReportBatchItemFailures"]
}

data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_instance" "edge" {
  count = local.ready ? 1 : 0

  ami                    = data.aws_ssm_parameter.al2023_arm64.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  iam_instance_profile   = aws_iam_instance_profile.edge.name
  vpc_security_group_ids = [aws_security_group.edge.id]

  # Required to forward the private subnets' traffic.
  source_dest_check = false

  metadata_options {
    http_tokens = "required"
  }

  user_data = base64encode(templatefile("${path.module}/edge.sh.tftpl", {
    region        = var.region
    ssm_prefix    = local.ssm_prefix
    bucket        = aws_s3_bucket.dist.bucket
    function_host = local.api_host
    domain        = var.domain
    vpc_cidr      = var.vpc_cidr
  }))

  user_data_replace_on_change = true

  # The boot script reads the SSM parameters and proxies to the Function URL, so both have
  # to exist first.
  depends_on = [aws_ssm_parameter.app, aws_lambda_function_url.api]

  tags = { Name = "sesume-edge" }
}

resource "aws_eip" "edge" {
  domain = "vpc"

  tags = { Name = "sesume-edge" }
}

resource "aws_eip_association" "edge" {
  count = length(aws_instance.edge)

  instance_id   = aws_instance.edge[0].id
  allocation_id = aws_eip.edge.id
}

resource "aws_route" "private_default" {
  count = length(aws_instance.edge)

  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.edge[0].primary_network_interface_id
}
