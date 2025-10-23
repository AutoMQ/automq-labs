#cloud-config
bootcmd:
  - |
    if [ ! -f "/opt/cmp/config.properties" ]; then
      touch /opt/cmp/config.properties
      echo "cmp.provider.credential=vm-role://${aws_iam_instance_profile_arn_encoded}@aws" >> /opt/cmp/config.properties
      echo 'cmp.provider.databucket=${automq_data_bucket}' >> /opt/cmp/config.properties
      echo 'cmp.provider.opsBucket=${automq_ops_bucket}' >> /opt/cmp/config.properties
      echo 'cmp.provider.instanceSecurityGroup=${instance_security_group_id}' >> /opt/cmp/config.properties
      echo 'cmp.provider.instanceDNS=${instance_dns}' >> /opt/cmp/config.properties
      echo 'cmp.provider.instanceProfile=${instance_profile_arn}' >> /opt/cmp/config.properties
      echo 'cmp.environmentId=${environment_id}' >> /opt/cmp/config.properties
    fi
