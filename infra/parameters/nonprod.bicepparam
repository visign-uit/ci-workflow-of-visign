// NON-PROD CLUSTER
// 1 AKS cluster chứa 3 môi trường, phân tách bằng namespace:
//   kubectl create namespace dev
//   kubectl create namespace test
//   kubectl create namespace staging
//
// Deploy:
//   az deployment sub create \
//     --location southeastasia \
//     --template-file main.bicep \
//     --parameters parameters/nonprod.bicepparam \
//     --parameters postgresAdminPassword='NonProdPassword123!'
using '../main.bicep'

param clusterType = 'nonprod'
param location = 'southeastasia'
param projectName = 'visign'

// Smaller VM — dev/test/staging không cần nhiều tài nguyên
param aksNodeVMSize = 'Standard_B2s_v2'
param aksNodeCount = 1
param aksAutoScaleMin = 1
param aksAutoScaleMax = 2
param aksAvailabilityZones = []

param acrSku = 'Basic'

param postgresAdminLogin = 'visignadmin'
param postgresAdminPassword = '' // Pass via CLI
param postgresHighAvailability = false // No HA for non-prod

param kvSoftDeleteDays = 7
