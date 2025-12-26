output "region" {
  description = "Region"
  value       = var.region
}

output "vpc_id" {
  description = "VPC ID"
  value       = var.use_existing_vpc ? var.existing_vpc_id : module.vpc[0].vpc_id
}

output "public_subnets" {
  description = "Public Subnets"
  value       = var.use_existing_vpc ? var.existing_public_subnet_ids : module.vpc[0].public_subnets
}

output "private_subnets" {
  description = "Private Subnets"
  value       = var.use_existing_vpc ? var.existing_private_subnet_ids : module.vpc[0].private_subnets
}

output "public_subnets_map" {
  description = "Map of availability zones to subnet IDs"
  value = var.use_existing_vpc ? {
    for subnet in data.aws_subnet.existing_public :
    subnet.availability_zone => [subnet.id]...
    } : {
    for az in distinct([for subnet in module.vpc[0].public_subnet_objects : subnet.availability_zone]) :
    az => [for subnet in module.vpc[0].public_subnet_objects : subnet.id if subnet.availability_zone == az]
  }
}

output "private_subnets_map" {
  description = "Map of availability zones to subnet IDs"
  value = var.use_existing_vpc ? {
    for subnet in data.aws_subnet.existing_private :
    subnet.availability_zone => [subnet.id]...
    } : {
    for az in distinct([for subnet in module.vpc[0].private_subnet_objects : subnet.availability_zone]) :
    az => [for subnet in module.vpc[0].private_subnet_objects : subnet.id if subnet.availability_zone == az]
  }
}
