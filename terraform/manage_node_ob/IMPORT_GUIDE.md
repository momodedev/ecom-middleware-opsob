# Resource Import Strategy Guide

This document explains how the Terraform code handles existing resources and provides guidance on importing them into Terraform state.

## Overview

The updated Terraform configuration implements a **dual-approach strategy** for handling existing resources:

1. **Automatic Detection**: Uses Azure data sources to detect existing resources
2. **Conditional Creation**: Only creates resources that don't exist in Azure
3. **State Import**: Provides tooling to import existing resources into Terraform state

## How It Works

### 1. Data Source Detection

For each resource type, the code first attempts to find an existing resource using data sources:

```hcl
# Example: Check if Resource Group exists
data "azurerm_resource_group" "existing" {
  name  = var.resource_group_name
}
```

### 2. Conditional Resource Creation

Resources are only created if they don't exist:

```hcl
# Example: Create RG only if it doesn't exist
resource "azurerm_resource_group" "example" {
  count    = data.azurerm_resource_group.existing.id == "" ? 1 : 0
  # ... configuration
}
```

### 3. Smart Locals

Local variables determine which resource ID to use (existing or new):

```hcl
locals {
  resource_group_id = data.azurerm_resource_group.existing.id != "" 
    ? data.azurerm_resource_group.existing.id 
    : azurerm_resource_group.example[0].id
}
```

## Resource Detection Order

The code checks for existing resources in this order:

1. **Resource Group** → `data.azurerm_resource_group.existing`
2. **Virtual Network** → `data.azurerm_virtual_network.existing`
3. **Subnet** → `data.azurerm_subnet.existing`
4. **Network Security Group** → `data.azurerm_network_security_group.existing`
5. **Public IP** → `data.azurerm_public_ip.existing`
6. **Network Interface** → `data.azurerm_network_interface.existing`
7. **Virtual Machine** → `data.azurerm_linux_virtual_machine.existing`
8. **Role Assignment** → `data.azurerm_role_assignment.existing`

## Usage Scenarios

### Scenario 1: All Resources Already Exist

If you have existing infrastructure in Azure:

1. **Update `secret.tfvars`** with your existing resource names
2. **Run import script**:
   ```bash
   bash import_existing.sh
   ```
3. **Verify plan**:
   ```bash
   terraform plan -var-file='secret.tfvars'
   ```
4. **Apply** (should show no changes if everything imported correctly):
   ```bash
   terraform apply -var-file='secret.tfvars'
   ```

### Scenario 2: Some Resources Exist

Partial existing infrastructure (e.g., VNet and subnet exist, but VM doesn't):

1. **Configure variables** to reference existing resources
2. **Run import script** - it will detect and import what exists
3. **Run terraform apply** - will only create missing resources

Example output:
```
Plan: 3 to add, 0 to change, 0 to destroy.
  + azurerm_linux_virtual_machine.example
  + azurerm_network_interface.example
  + azurerm_public_ip.control
```

### Scenario 3: Brand New Deployment

No existing resources - everything will be created:

1. **Configure variables** with desired names
2. **Run terraform apply directly**:
   ```bash
   terraform apply -var-file='secret.tfvars'
   ```

## Import Script Usage

The `import_existing.sh` script automates the import process:

### Prerequisites

- Azure CLI installed and authenticated
- `secret.tfvars` configured with correct resource names
- Terraform initialized (`terraform init`)

### Running the Script

```bash
cd terraform/kafka/manage_node_ob
bash import_existing.sh
```

### What It Does

1. ✅ Reads configuration from `secret.tfvars`
2. ✅ Queries Azure for each resource using Azure CLI
3. ✅ Checks if resource is already in Terraform state
4. ✅ Imports resource if found and not in state
5. ✅ Skips resources that don't exist (will be created)
6. ✅ Provides summary of imported vs. to-be-created resources

### Script Output Example

```
[INFO] ==========================================
[INFO] Checking for existing resources to import
[INFO] ==========================================

[INFO] Step 1: Checking Resource Group...
[INFO] Found existing Resource Group: control-ob-rg
[INFO] Importing data.azurerm_resource_group.existing...
[INFO]   Resource ID: /subscriptions/.../resourceGroups/control-ob-rg
✓ Successfully imported data.azurerm_resource_group.existing

[INFO] Step 2: Checking Virtual Network...
[WARN] VNet control-ob-vnet not found, will be created

...

[INFO] ==========================================
[INFO] Import process completed!
[INFO] ==========================================
```

## Manual Import Commands

If you prefer manual control, here are the import commands:

```bash
# Get resource IDs from Azure
RG_ID=$(az group show --name "control-ob-rg" --query "id" --output tsv)
VNET_ID=$(az network vnet show --resource-group "control-ob-rg" --name "control-ob-vnet" --query "id" --output tsv)
SUBNET_ID=$(az network vnet subnet show --resource-group "control-ob-rg" --vnet-name "control-ob-vnet" --name "control-ob-subnet" --query "id" --output tsv)
NSG_ID=$(az network nsg show --resource-group "control-ob-rg" --name "control-ob-nsg" --query "id" --output tsv)
PIP_ID=$(az network public-ip show --resource-group "control-ob-rg" --name "control-ip" --query "id" --output tsv)
NIC_ID=$(az network nic show --resource-group "control-ob-rg" --name "control-nic" --query "id" --output tsv)
VM_ID=$(az vm show --resource-group "control-ob-rg" --name "control-node" --query "id" --output tsv)

# Import each resource
terraform import "data.azurerm_resource_group.existing" "$RG_ID"
terraform import "data.azurerm_virtual_network.existing" "$VNET_ID"
terraform import "data.azurerm_subnet.existing" "$SUBNET_ID"
terraform import "data.azurerm_network_security_group.existing" "$NSG_ID"
terraform import "data.azurerm_public_ip.existing" "$PIP_ID"
terraform import "data.azurerm_network_interface.existing" "$NIC_ID"
terraform import "data.azurerm_linux_virtual_machine.existing" "$VM_ID"
```

## Verification Steps

After importing, verify everything is correct:

### 1. List State

```bash
terraform state list
```

Expected output should show all imported data sources.

### 2. Plan Should Show No Changes (for fully imported)

```bash
terraform plan -var-file='secret.tfvars'
```

If all resources were imported correctly:
```
No changes. Your infrastructure matches the configuration.
```

If some resources need to be created:
```
Plan: 3 to add, 0 to change, 0 to destroy.
```

### 3. Show Resource Details

```bash
terraform state show data.azurerm_resource_group.existing
terraform state show data.azurerm_virtual_network.existing
# etc...
```

## Handling Existing NSG with Custom ID

If you have an existing NSG in a different resource group:

1. **Set in secret.tfvars**:
   ```hcl
   control_nsg_id = "/subscriptions/xxx/resourceGroups/yyy/providers/Microsoft.Network/networkSecurityGroups/nsg-name"
   ```

2. **The code will automatically**:
   - Parse the resource group from the ID
   - Use the existing NSG
   - Skip creating a new NSG
   - Add SSH rules if needed

## Troubleshooting

### Issue: "Resource not found" during import

**Solution**: Verify the resource exists in Azure:
```bash
az resource show --resource-group "RG_NAME" --name "RESOURCE_NAME"
```

### Issue: "Resource already in state"

**Solution**: The resource was already imported. Check with:
```bash
terraform state list | grep "resource_address"
```

### Issue: Import succeeds but plan shows changes

**Cause**: Minor configuration differences between Azure and Terraform defaults.

**Solution**: 
1. Review the planned changes
2. If acceptable, apply them
3. Or update your Terraform config to match actual state

### Issue: Role assignment import fails

**Cause**: Role assignments don't have a predictable ID format.

**Solution**: 
```bash
# Find the role assignment
az role assignment list \
  --assignee "PRINCIPAL_ID" \
  --role "Contributor" \
  --scope "/subscriptions/SUBSCRIPTION_ID"

# Import with the exact ID
terraform import "azurerm_role_assignment.control" "ROLE_ASSIGNMENT_ID"
```

## Best Practices

1. ✅ **Always backup state** before importing:
   ```bash
   terraform state pull > backup.tfstate
   ```

2. ✅ **Use the import script** for automated detection and import

3. ✅ **Verify with terraform plan** after importing

4. ✅ **Keep secret.tfvars updated** with accurate resource names

5. ✅ **Document any manual imports** for team knowledge

6. ✅ **Test import process** in non-production first

## Migration Path from Existing Infrastructure

For migrating existing Kafka infrastructure to Terraform management:

### Phase 1: Assessment
1. Document all existing resources
2. Note resource names, locations, configurations
3. Update `secret.tfvars` with actual values

### Phase 2: Import Control Node Resources
1. Run `import_existing.sh`
2. Verify all resources imported
3. Run `terraform plan` to confirm no unwanted changes

### Phase 3: Apply Terraform Management
1. Apply once to ensure state consistency
2. Future changes through Terraform only

### Phase 4: Ongoing Management
- All future changes via Terraform
- Regular state backups
- Version control for `secret.tfvars` (in secure vault)

## Summary Table

| Resource Type | Auto-Detect | Auto-Import | Conditional Create | Notes |
|--------------|-------------|-------------|-------------------|-------|
| Resource Group | ✅ | ✅ | ✅ | Root container |
| Virtual Network | ✅ | ✅ | ✅ | Network isolation |
| Subnet | ✅ | ✅ | ✅ | Within VNet |
| NSG | ✅ | ✅ | ✅ | Security rules |
| Public IP | ✅ | ✅ | ✅ | Static allocation |
| NIC | ✅ | ✅ | ✅ | Network interface |
| VM | ✅ | ✅ | ✅ | Control node |
| Role Assignment | ✅ | ✅ | ✅ | Contributor role |

✅ = Supported

## Next Steps

After successfully importing existing resources:

1. Enable state locking (use remote backend like Azure Storage)
2. Set up CI/CD pipeline for Terraform deployments
3. Configure monitoring and alerting
4. Document operational procedures

For questions or issues, refer to the main [README.md](README.md) or [QUICKSTART.md](QUICKSTART.md).
