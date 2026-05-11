// ============================================================
// VISIGN INFRASTRUCTURE — MAIN ENTRY POINT
// Scope : Subscription
//
// Architecture (theo yêu cầu giảng viên):
//   Cluster 1 — non-prod AKS (la moi truong dev nhung day du hon chia ra du 3 dev/test/staging)
//     └── namespace: dev / test / staging (phân tách bằng namespace)
//   Cluster 2 — prod AKS
//     └── namespace: prod
//
// NAT Gateway: mỗi cluster có NAT Gateway riêng
//   → IP outbound cố định
//   → Pods gọi Clerk, OpenAI, Neon... qua NAT (không phải LB SNAT)
//
// Deploy non-prod:
//   az deployment sub create \
//     --location southeastasia \
//     --template-file main.bicep \
//     --parameters parameters/nonprod.bicepparam \
//     --parameters postgresAdminPassword='...'
//
// Deploy prod:
//   az deployment sub create \
//     --location southeastasia \
//     --template-file main.bicep \
//     --parameters parameters/prod.bicepparam \
//     --parameters postgresAdminPassword='...'
// ============================================================
targetScope = 'subscription'

// ── Parameters ──────────────────────────────────────────────

@description('Target cluster: nonprod | prod')
@allowed(['nonprod', 'prod'])
param clusterType string

@description('Azure region')
param location string = 'southeastasia'

@description('Project name used as naming prefix')
param projectName string = 'visign'

@description('AKS node VM size')
param aksNodeVMSize string

@description('AKS initial node count')
param aksNodeCount int

@description('AKS autoscale min')
param aksAutoScaleMin int

@description('AKS autoscale max')
param aksAutoScaleMax int

@description('Availability zones for AKS nodes')
param aksAvailabilityZones array = ['2', '3']

@description('ACR SKU')
@allowed(['Basic', 'Standard', 'Premium'])
param acrSku string

@description('PostgreSQL admin username')
param postgresAdminLogin string = 'visignadmin'

@secure()
@description('PostgreSQL admin password — pass via CLI, never hardcode')
param postgresAdminPassword string

@description('Enable PostgreSQL Zone-Redundant HA')
param postgresHighAvailability bool

@description('Key Vault soft-delete retention in days')
param kvSoftDeleteDays int

// ── Variables ────────────────────────────────────────────────

var isProd = clusterType == 'prod'
var suffix = '-${clusterType}' // e.g. -nonprod | -prod

// Resource group name: visign-nonprod-rg | visign-prod-rg
var rgName = '${projectName}${suffix}-rg'

// ── Resource Group ───────────────────────────────────────────

resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: rgName
  location: location
  tags: {
    project: projectName
    clusterType: clusterType
    managedBy: 'bicep'
  }
}

// ── Modules ──────────────────────────────────────────────────

module network './modules/network.bicep' = {
  name: 'deploy-network${suffix}'
  scope: rg
  params: {
    location: location
    vnetName: '${projectName}${suffix}-vnet'
  }
}

module acr './modules/acr.bicep' = {
  name: 'deploy-acr${suffix}'
  scope: rg
  params: {
    location: location
    // ACR name must be globally unique & alphanumeric only
    acrName: toLower('${projectName}${clusterType}acr${take(uniqueString(rg.id), 6)}')
    acrSku: acrSku
  }
}

module aks './modules/aks.bicep' = {
  name: 'deploy-aks${suffix}'
  scope: rg
  params: {
    location: location
    aksName: '${projectName}${suffix}-aks'
    nodeVMSize: aksNodeVMSize
    nodeCount: aksNodeCount
    autoScaleMin: aksAutoScaleMin
    autoScaleMax: aksAutoScaleMax
    availabilityZones: aksAvailabilityZones
    aksSubnetId: network.outputs.aksSubnetId
    natGatewayId: network.outputs.natGatewayId
    acrId: acr.outputs.acrId
  }
}

module database './modules/database.bicep' = {
  name: 'deploy-database${suffix}'
  scope: rg
  params: {
    location: location
    serverName: '${projectName}${suffix}-psql'
    adminLogin: postgresAdminLogin
    adminPassword: postgresAdminPassword
    dbSubnetId: network.outputs.dbSubnetId
    vnetId: network.outputs.vnetId
    enableHighAvailability: postgresHighAvailability
  }
}

module keyvault './modules/keyvault.bicep' = {
  name: 'deploy-keyvault${suffix}'
  scope: rg
  params: {
    location: location
    kvName: toLower('${projectName}-${clusterType}-kv-${take(uniqueString(rg.id), 6)}')
    softDeleteRetentionDays: kvSoftDeleteDays
    aksKubeletPrincipalId: aks.outputs.kubeletPrincipalId
    aksCsiPrincipalId: aks.outputs.csiPrincipalId
  }
}

module cicdIdentity './modules/identity.bicep' = {
  name: 'deploy-cicd-identity${suffix}'
  scope: rg
  params: {
    location: location
    identityName: '${projectName}${suffix}-cicd-identity'
    acrId: acr.outputs.acrId
    aksId: aks.outputs.aksId
    kvId: keyvault.outputs.kvId
  }
}

// ── Outputs ──────────────────────────────────────────────────

output resourceGroup string = rg.name
output aksName string = aks.outputs.aksName
output acrLoginServer string = acr.outputs.acrLoginServer
output keyVaultName string = keyvault.outputs.kvName
output postgresHost string = database.outputs.postgresHost
output cicdClientId string = cicdIdentity.outputs.clientId
output natPublicIP string = network.outputs.natPublicIP

// Hint: namespaces to create inside non-prod cluster
output clusterUsage string = isProd ? 'namespace: prod' : 'namespaces: dev | test | staging'
