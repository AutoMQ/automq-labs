location            = "eastus"
subscription_id     = "218357d0-eaaf-4e3e-9ffa-6b4ccb7e2df9"
private_subnet_id   = "/subscriptions/218357d0-eaaf-4e3e-9ffa-6b4ccb7e2df9/resourceGroups/rg-demo-gezi/providers/Microsoft.Network/virtualNetworks/vnet-demo/subnets/snet-private-demo"
public_subnet_id    = "/subscriptions/218357d0-eaaf-4e3e-9ffa-6b4ccb7e2df9/resourceGroups/rg-demo-gezi/providers/Microsoft.Network/virtualNetworks/vnet-demo/subnets/snet-public-demo"
resource_group_name = "rg-automq-gezi"
vnet_id             = "/subscriptions/218357d0-eaaf-4e3e-9ffa-6b4ccb7e2df9/resourceGroups/rg-demo-gezi/providers/Microsoft.Network/virtualNetworks/vnet-demo"

# Storage account configuration
ops_storage_account_name   = "automqopsstorage"
ops_storage_resource_group = "rg-demo-gezi"
ops_container_name         = "automq-ops"

data_storage_account_name   = "automqdatastorage"
data_storage_resource_group = "rg-demo-gezi"
data_container_name         = "automq-data"
