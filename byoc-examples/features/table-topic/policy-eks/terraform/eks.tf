module "eks-env" {
  source = "../../../../setup/kubernetes/aws/terraform"

  region          = var.region
  resource_suffix = local.resource_suffix
}
