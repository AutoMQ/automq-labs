# Preserve the previous addresses when optionalizing existing defaults.
moved {
  from = aws_vpc_security_group_ingress_rule.automq_ingress_rule
  to   = aws_vpc_security_group_ingress_rule.automq_ingress_rule[0]
}
moved {
  from = helm_release.external_dns
  to   = helm_release.external_dns[0]
}
moved {
  from = module.cluster_exteranl_dns_irsa_role
  to   = module.cluster_exteranl_dns_irsa_role[0]
}
