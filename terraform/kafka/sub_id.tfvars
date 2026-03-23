ARM_SUBSCRIPTION_ID="8d6bd1eb-ae31-4f2c-856a-0f8e47115c4b"
kafka_instance_count=3
kafka_data_disk_iops=3000
kafka_data_disk_throughput_mbps=125
kafka_vm_size="Standard_D8s_v6"
resource_group_name="rds-prod"
resource_group_location="westus"
kafka_vm_zone=""
enable_availability_zones=false
use_premium_v2_disks=true
use_existing_kafka_network=true
existing_kafka_vnet_resource_group_name="rds-prod"
kafka_vnet_name="rds-prod-vnet"
kafka_subnet_name="rds-prod-subnet"
enable_kafka_nat_gateway=false
kafka_nsg_id="/subscriptions/8d6bd1eb-ae31-4f2c-856a-0f8e47115c4b/resourceGroups/rds-prod/providers/Microsoft.Network/networkSecurityGroups/rds-prod-nsg"
enable_vnet_peering=false
is_public=true

# Deployment paths for Ansible provisioning
repository_name="ecom-middleware-ops1"
control_node_user="azureadmin"
# ansible_venv_path="" # Uncomment to override, defaults to /home/{control_node_user}/ansible-venv
# repository_base_dir="" # Uncomment to override, defaults to /home/{control_node_user}/{repository_name}