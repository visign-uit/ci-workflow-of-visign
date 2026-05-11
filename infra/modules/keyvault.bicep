// ============================================================
// KEY VAULT MODULE
// RBAC authorization (not legacy access policies)
// AKS CSI addon + kubelet → Key Vault Secrets User
// ============================================================

param location                string
param kvName                  string
param aksKubeletPrincipalId   string
param aksCsiPrincipalId       string
param softDeleteRetentionDays int    = 7

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name    : kvName
  location: location
  properties: {
    sku: {
      family: 'A'
      name  : 'standard'
    }
    tenantId                : subscription().tenantId
    enableRbacAuthorization : true    // Modern RBAC, not access policies
    enableSoftDelete        : true
    softDeleteRetentionInDays: softDeleteRetentionDays
    publicNetworkAccess     : 'Enabled'  // AKS CSI reads from public endpoint
  }
}

// CSI addon reads secrets → mounts into pods as env vars
resource csiSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name : guid(kv.id, aksCsiPrincipalId, 'SecretsUser')
  scope: kv
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '4633458b-17de-408a-b874-0445c86b69e6' // Key Vault Secrets User
    )
    principalId  : aksCsiPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Kubelet identity reads secrets (workload identity flows)
resource kubeletSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name : guid(kv.id, aksKubeletPrincipalId, 'SecretsUser')
  scope: kv
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '4633458b-17de-408a-b874-0445c86b69e6' // Key Vault Secrets User
    )
    principalId  : aksKubeletPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output kvId   string = kv.id
output kvName string = kv.name
output kvUri  string = kv.properties.vaultUri
