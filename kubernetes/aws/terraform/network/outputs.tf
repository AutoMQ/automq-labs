output "region" {
  description = "Region"
  value       = var.region
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
  depends_on  = [module.vpc]
}

output "azs" {
  description = "Availability Zones"
  value       = module.vpc.azs
}

output "public_subnets" {
  description = "Public Subnets"
  value       = module.vpc.public_subnets
  depends_on  = [module.vpc]
}

output "private_subnets" {
  description = "Private Subnets"
  value       = module.vpc.private_subnets
  depends_on  = [module.vpc]
}

output "public_subnets_map" {
  description = "Map of availability zones to subnet IDs"
  value = { for az in distinct([for subnet in module.vpc.public_subnet_objects : subnet.availability_zone]) :
  az => [for subnet in module.vpc.public_subnet_objects : subnet.id if subnet.availability_zone == az] }
}

output "private_subnets_map" {
  description = "Map of availability zones to subnet IDs"
  value = { for az in distinct([for subnet in module.vpc.private_subnet_objects : subnet.availability_zone]) :
  az => [for subnet in module.vpc.private_subnet_objects : subnet.id if subnet.availability_zone == az] }
}
