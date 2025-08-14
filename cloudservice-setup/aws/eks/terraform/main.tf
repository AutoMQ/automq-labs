module "automq-byoc" {
  source  = "AutoMQ/automq-byoc-environment/aws"
  version = "0.3.2"

  cloud_provider_region = var.region
  automq_byoc_env_id    = var.resource_suffix

  create_new_vpc                           = false
  automq_byoc_vpc_id                       = module.eks-env.vpc_id
  automq_byoc_env_console_public_subnet_id = module.eks-env.public_subnets[0]
}

