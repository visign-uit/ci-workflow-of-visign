// ============================================================
// AKS MODULE
// outboundType: userAssignedNATGateway
//   → Pods dùng NAT Gateway để ra internet (không phải LB SNAT)
//   → IP outbound cố định
//   → Inbound (từ internet vào app) vẫn qua Load Balancer / Ingress
// ============================================================

param location string
param aksName string
param aksSubnetId string
param natGatewayId string
param acrId string

param nodeVMSize string = 'Standard_B2s'
param nodeCount int = 2
param autoScaleMin int = 1
param autoScaleMax int = 4
param availabilityZones array = ['2', '3']

// ── AKS Cluster ──────────────────────────────────────────────

resource aks 'Microsoft.ContainerService/managedClusters@2024-01-01' = {
  name: aksName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: aksName
    enableRBAC: true

    agentPoolProfiles: [
      {
        name: 'systempool'
        count: nodeCount
        vmSize: nodeVMSize
        osType: 'Linux'
        mode: 'System'
        type: 'VirtualMachineScaleSets'
        availabilityZones: length(availabilityZones) > 0 ? availabilityZones : null
        vnetSubnetID: aksSubnetId
        enableAutoScaling: true
        minCount: autoScaleMin
        maxCount: autoScaleMax
        osDiskSizeGB: 50
        maxPods: 110
      }
    ]

    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
      loadBalancerSku: 'standard'
      // NAT Gateway handles outbound. Pods reach Clerk, OpenAI, Neon, etc.
      // via fixed NAT public IP — not shared with inbound LB traffic.
      outboundType: 'userAssignedNATGateway'
      serviceCidr: '10.50.0.0/16'
      dnsServiceIP: '10.50.0.10'
    }

    addonProfiles: {
      // CSI driver: mount Key Vault secrets as env vars / volume in pods
      azureKeyvaultSecretsProvider: {
        enabled: true
        config: {
          enableSecretRotation: 'true'
          rotationPollInterval: '2m'
        }
      }
    }

    // Workload Identity + OIDC:
    // Pods authenticate to Azure (Key Vault, ACR) without storing credentials
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }

    aadProfile: {
      managed: true
      enableAzureRBAC: true
    }
  }
}

// AKS kubelet identity → AcrPull (pull Docker images from ACR)
resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aks.id, acrId, 'AcrPull')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '7f951dda-4ed3-4680-a7ca-43fe172d538d' // AcrPull
    )
    principalId: aks.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
  }
}

// ── Outputs ──────────────────────────────────────────────────

output aksId string = aks.id
output aksName string = aks.name
output kubeletPrincipalId string = aks.properties.identityProfile.kubeletidentity.objectId
output csiPrincipalId string = aks.properties.addonProfiles.azureKeyvaultSecretsProvider.identity.objectId
output oidcIssuerUrl string = aks.properties.oidcIssuerProfile.issuerURL
