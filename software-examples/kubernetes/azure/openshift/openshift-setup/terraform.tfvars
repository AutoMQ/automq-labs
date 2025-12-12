location            = "eastus"
subscription_id     = "218357d0-eaaf-4e3e-9ffa-6b4ccb7e2df9"
resource_group_name = "AutoMQ-lab-openshift1211"
env_prefix          = "automqlabs"
vnet_cidr           = "10.0.0.0/16"

# OpenShift Cluster Configuration
create_openshift_cluster = true
openshift_cluster_name   = "demobe-openshift"
openshift_version        = null
master_vm_size           = "Standard_D8s_v3"
worker_vm_size           = "Standard_D4as_v5"
worker_node_count        = 5

