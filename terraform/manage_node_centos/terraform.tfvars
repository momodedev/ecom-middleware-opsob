control_vnet_name                       = "control-au-vnet"   # same VNet for control + Kafka
control_subnet_name                     = "control-au-subnet" # reuse same subnet for control (or set a dedicated subnet name if it exists)
ARM_SUBSCRIPTION_ID  = "8d6bd1eb-ae31-4f2c-856a-0f8e47115c4b" #"8d6bd1eb-ae31-4f2c-856a-0f8e47115c4b"
resource_group_name      = "control-au-rg"             # control node resources will live in this RG (existing)
resource_group_location = "australiaeast"
use_existing_control_network             = true
control_nsg_id                          = "/subscriptions/8d6bd1eb-ae31-4f2c-856a-0f8e47115c4b/resourceGroups/control-au-rg/providers/Microsoft.Network/networkSecurityGroups/control-au-nsg"                   # use existing NSG for control node
control_vm_size = "Standard_D8ls_v6"


