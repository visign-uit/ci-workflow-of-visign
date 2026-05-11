// ============================================================
// NETWORK MODULE
// VNet + NAT Gateway + 2 subnets
//
// NAT Gateway ở đây vì:
//   → Pods nằm trong private subnet, không có public IP riêng
//   → Cần đường ra internet để gọi Clerk, OpenAI, Neon...
//   → NAT Gateway cho IP outbound cố định (không như LB SNAT)
//   → Tách biệt inbound (qua Load Balancer) và outbound (qua NAT)
// ============================================================

param location string
param vnetName string

// ── Public IP cho NAT Gateway ────────────────────────────────

resource natPublicIP 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: '${vnetName}-nat-ip'
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// ── NAT Gateway ──────────────────────────────────────────────

resource natGateway 'Microsoft.Network/natGateways@2023-09-01' = {
  name: '${vnetName}-nat'
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIpAddresses: [
      { id: natPublicIP.id }
    ]
    idleTimeoutInMinutes: 4
  }
}

// ── VNet + Subnets ───────────────────────────────────────────

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.0.0.0/8']
    }
    subnets: [
      {
        // AKS pods live here.
        // NAT Gateway handles all outbound → fixed public IP
        name: 'aks-subnet'
        properties: {
          addressPrefix: '10.240.0.0/16'
          natGateway: { id: natGateway.id }  // ← Outbound via NAT
        }
      }
      {
        // PostgreSQL lives here. Private, no public endpoint.
        // Delegated to PostgreSQL flexible server service.
        name: 'db-subnet'
        properties: {
          addressPrefix: '10.241.0.0/24'
          delegations: [
            {
              name: 'postgres-delegation'
              properties: {
                serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'
              }
            }
          ]
        }
      }
    ]
  }
}

// ── Outputs ──────────────────────────────────────────────────

output vnetId      string = vnet.id
output aksSubnetId string = vnet.properties.subnets[0].id
output dbSubnetId  string = vnet.properties.subnets[1].id
output natGatewayId string = natGateway.id
output natPublicIP  string = natPublicIP.properties.ipAddress
