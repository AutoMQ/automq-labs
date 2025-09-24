awsRegion: ${region}

rbac:
  create: true
  serviceAccount:
    # This value should match local.k8s_service_account_name in locals.tf
    name: ${svc_account}
    annotations:
      # This value should match the ARN of the role created by module.irsa-autoscaler-role in irsa.tf
      eks.amazonaws.com/role-arn: "${role_arn}"

autoDiscovery:
  clusterName: ${cluster_name}
  enabled: true
