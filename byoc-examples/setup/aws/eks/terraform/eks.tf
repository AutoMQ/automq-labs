module "eks-env" {
  source = "../../../kubernetes/aws/terraform"

  region          = var.region
  resource_suffix = var.resource_suffix

  node_group = var.node_group
}
