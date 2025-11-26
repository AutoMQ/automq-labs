# Create a private Route 53 hosted zone or you can use an existing one
resource "aws_route53_zone" "private_r53" {
  name = "${local.name_suffix}.automq.private"

  vpc {
    vpc_id = var.vpc_id
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "automq-private-zone-${local.env_id}"
  })
}

locals {
  route53_hosted_zone_id = aws_route53_zone.private_r53.zone_id
}
