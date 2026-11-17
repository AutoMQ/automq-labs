output "region" { value = var.region }
output "vpc_id" { value = aws_vpc.this.id }
output "private_subnet_ids_by_az" { value = { for az, subnet in aws_subnet.private : az => subnet.id } }
output "public_subnet_ids_by_az" { value = { for az, subnet in aws_subnet.public : az => subnet.id } }
output "s3_vpc_endpoint_id" { value = aws_vpc_endpoint.s3.id }
