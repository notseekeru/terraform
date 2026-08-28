resource "aws_lb" "main" {
  name               = "main-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "main" {
  name     = "app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path = "/"
  }
}

resource "aws_acm_certificate" "alb" {
  count = var.alb_domain != "" ? 1 : 0

  domain_name       = var.alb_domain
  validation_method = "DNS"
}

resource "aws_acm_certificate_validation" "alb" {
  count           = var.alb_domain != "" ? 1 : 0
  certificate_arn = aws_acm_certificate.alb[0].arn
  # Validation is done via a CNAME added manually in Cloudflare (see the
  # alb_domain_validation_cname output). This resource polls until the cert
  # reaches ISSUED, so the :443 listener below only binds a valid certificate.
  timeouts {
    create = "10m"
  }
}


resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  count             = var.alb_domain != "" ? 1 : 0
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.alb[0].arn
  # Wait for ACM cert to reach ISSUED before binding :443
  depends_on = [aws_acm_certificate_validation.alb]

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}


data "aws_ssm_parameter" "al2023_arm64" {
  # Latest Amazon Linux 2023 ARM64 (Graviton) AMI, per instance_type default t4g.micro
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}
resource "aws_launch_template" "main" {
  name_prefix   = "app-lt-"
  image_id      = data.aws_ssm_parameter.al2023_arm64.value
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  network_interfaces {
    security_groups             = [aws_security_group.ec2.id]
    associate_public_ip_address = true
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    dnf install -y nginx
    systemctl start nginx
    systemctl enable nginx
    echo "<h1>Hello from ASG</h1>" > /usr/share/nginx/html/index.html
  EOF
  )
}

resource "aws_autoscaling_group" "main" {
  vpc_zone_identifier = aws_subnet.public[*].id
  target_group_arns   = [aws_lb_target_group.main.arn]
  health_check_type   = "ELB"
  min_size            = 1
  max_size            = 3

  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }
}

resource "aws_autoscaling_policy" "cpu" {
  name                   = "cpu-target-tracking"
  policy_type            = "TargetTrackingScaling"
  autoscaling_group_name = aws_autoscaling_group.main.name

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50.0
  }
}
