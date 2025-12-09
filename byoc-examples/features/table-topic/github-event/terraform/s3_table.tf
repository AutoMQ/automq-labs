resource "aws_s3tables_table_bucket" "event_table_bucket" {
  name = "${local.resource_suffix}-event-analytics-bucket"
}

resource "aws_s3tables_namespace" "event_namespace" {
  table_bucket_arn = aws_s3tables_table_bucket.event_table_bucket.arn
  namespace        = "event_data"
}

output "s3_table_bucket_arn" {
  description = "S3 Table Bucket ARN"
  value       = aws_s3tables_table_bucket.event_table_bucket.arn
}

resource "aws_s3_bucket" "athena_results" {
  bucket = "${local.resource_suffix}-athena-query-results"
  force_destroy = true
}


resource "aws_athena_workgroup" "lab-athena-workgroup" {
  name = "${local.resource_suffix}-primary" # 覆盖默认的 primary 工作组
  force_destroy = true

  configuration {
    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/output/"
    }
  }
}