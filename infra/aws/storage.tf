resource "aws_s3_bucket" "dist" {
  bucket = "sesume-dist-${local.account_id}"

  tags = { Name = "sesume-dist" }
}

resource "aws_s3_bucket_public_access_block" "dist" {
  bucket = aws_s3_bucket.dist.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "dist_tls" {
  bucket = aws_s3_bucket.dist.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyUnencryptedTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.dist.arn, "${aws_s3_bucket.dist.arn}/*"]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}
