// ============================================================
// CI/CD MANAGED IDENTITY MODULE
// Azure Pipelines / GitHub Actions dùng identity này để:
//   - Push Docker images → ACR
//   - Deploy K8s manifests → AKS
//   - Rotate secrets → Key Vault
// Không cần username/password, dùng Managed Identity token
// ============================================================

param location       string
param identityName   string
param acrId          string
param aksId          string
param kvId           string

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name    : identityName
  location: location
}

// Pipeline pushes Docker images to ACR
resource acrPush 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name : guid(acrId, identity.id, 'AcrPush')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '8311e382-0749-4cb8-b61a-304f252e45ec' // AcrPush
    )
    principalId  : identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Pipeline applies K8s manifests to AKS
resource aksContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name : guid(aksId, identity.id, 'AksContributor')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b' // AKS RBAC Cluster Admin
    )
    principalId  : identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Pipeline updates secrets in Key Vault (e.g. rotate Clerk keys)
resource kvSecretsOfficer 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name : guid(kvId, identity.id, 'SecretsOfficer')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'b86a8fe4-44ce-4948-aee5-eccb2c155cd7' // Key Vault Secrets Officer
    )
    principalId  : identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

output identityId  string = identity.id
output clientId    string = identity.properties.clientId
output principalId string = identity.properties.principalId
