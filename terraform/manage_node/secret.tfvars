control_vnet_name                       = "rds-prod-vnet"   # same VNet for control + Kafka
control_subnet_name                     = "rds-prod-subnet" # reuse same subnet for control (or set a dedicated subnet name if it exists)
ARM_SUBSCRIPTION_ID  = "8d6bd1eb-ae31-4f2c-856a-0f8e47115c4b" #"8d6bd1eb-ae31-4f2c-856a-0f8e47115c4b"
resource_group_name      = "rds-prod"             # control node resources will live in this RG (existing)
resource_group_location = "westus"
use_existing_control_network             = true
control_nsg_id                          = "/subscriptions/8d6bd1eb-ae31-4f2c-856a-0f8e47115c4b/resourceGroups/rds-prod/providers/Microsoft.Network/networkSecurityGroups/rds-prod-nsg"                   # use existing NSG for control node
control_vm_size = "Standard_D8ls_v6"


