// ============================================================
// POSTGRESQL FLEXIBLE SERVER MODULE
// Private access via VNet delegation — no public endpoint
// Optional Zone-Redundant HA for prod
// ============================================================

param location string
param serverName string
param dbSubnetId string
param vnetId string
param adminLogin string

@secure()
param adminPassword string

param enableHighAvailability bool = false
param postgresVersion string = '16'

// ── Private DNS Zone ─────────────────────────────────────────

resource privateDns 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: '${serverName}.private.postgres.database.azure.com'
  location: 'global'
}

resource dnsVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDns
  name: 'vnet-link'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnetId }
    registrationEnabled: false
  }
}

// ── PostgreSQL Server ─────────────────────────────────────────

resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2023-06-01-preview' = {
  name: serverName
  location: location
  sku: {
    name: enableHighAvailability ? 'Standard_D2s_v3' : 'Standard_B2ms'
    tier: enableHighAvailability ? 'GeneralPurpose' : 'Burstable'
  }
  properties: {
    version: postgresVersion
    administratorLogin: adminLogin
    administratorLoginPassword: adminPassword

    // Private access: pods connect via VNet — internet cannot reach DB
    network: {
      delegatedSubnetResourceId: dbSubnetId
      privateDnsZoneArmResourceId: privateDns.id
    }

    highAvailability: {
      mode: enableHighAvailability ? 'ZoneRedundant' : 'Disabled'
      standbyAvailabilityZone: enableHighAvailability ? '3' : ''
    }

    availabilityZone: '' // Primary server in AZ-1; standby (if enabled) in AZ-3

    storage: {
      storageSizeGB: 32
      autoGrow: 'Enabled'
    }

    backup: {
      backupRetentionDays: enableHighAvailability ? 14 : 7
      geoRedundantBackup: 'Disabled'
    }
  }
  dependsOn: [dnsVnetLink]
}

// ── Database ──────────────────────────────────────────────────

resource visignDb 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-06-01-preview' = {
  parent: postgres
  name: 'visign_db'
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

output postgresId string = postgres.id
output postgresHost string = postgres.properties.fullyQualifiedDomainName
output databaseName string = visignDb.name
