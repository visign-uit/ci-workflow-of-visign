// PROD CLUSTER
// 1 AKS cluster riêng biệt cho production
//   namespace: prod
//
// Deploy:
//   az deployment sub create \
//     --location southeastasia \
//     --template-file main.bicep \
//     --parameters parameters/prod.bicepparam \
//     --parameters postgresAdminPassword='ProdPassword456!'
using '../main.bicep'

param clusterType = 'prod'
param location = 'southeastasia'
param projectName = 'visign'

// Larger VM + more nodes for production workloads
param aksNodeVMSize = 'Standard_D2s_v3'
param aksNodeCount = 2
param aksAutoScaleMin = 2
param aksAutoScaleMax = 4
param aksAvailabilityZones = []

param acrSku = 'Standard'

param postgresAdminLogin = 'visignadmin'
param postgresAdminPassword = '' // Pass via CLI
param postgresHighAvailability = true // Zone-Redundant HA

param kvSoftDeleteDays = 90
