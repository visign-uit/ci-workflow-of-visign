// ============================================================
// CONTAINER REGISTRY MODULE
// adminUserEnabled: false → access via Managed Identity only
// ============================================================

param location string
param acrName  string

@allowed(['Basic', 'Standard', 'Premium'])
param acrSku string = 'Basic'

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name    : acrName
  location: location
  sku     : { name: acrSku }
  properties: {
    adminUserEnabled   : false          // Managed Identity only, no username/password
    publicNetworkAccess: 'Enabled'      // AKS pulls from public ACR endpoint
    zoneRedundancy     : acrSku == 'Premium' ? 'Enabled' : 'Disabled'
  }
}

output acrId          string = acr.id
output acrName        string = acr.name
output acrLoginServer string = acr.properties.loginServer
