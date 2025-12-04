param accountName string
param location string
param databaseName string = 'mailboxdb'
param throughput int = 400

// Cosmos DB account (SQL API)
resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: accountName
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    locations: [
      {
        locationName: location
        failoverPriority: 0
      }
    ]
    apiProperties: {
      serverVersion: '4.0'
    }
    capabilities: [
      {
        name: 'EnableAggregationPipeline'
      }
    ]
    enableFreeTier: false
    isVirtualNetworkFilterEnabled: false
    enableMultipleWriteLocations: false
    disableKeyBasedMetadataWriteAccess: false
    publicNetworkAccess: 'Enabled'
  }
}

// SQL database
resource sqlDb 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  name: '${cosmos.name}/${databaseName}'
  properties: {
    resource: {
      id: databaseName
    }
    options: {
      throughput: throughput
    }
  }
}

// Helper to create container
param uniqueKeys array = []

@description('Create a SQL container with id, partitionKeyPath, indexing, and optional unique keys')
module containerTemplate 'container.bicep' = {
  name: 'containerTemplate'
  params: {
    accountName: cosmos.name
    databaseName: databaseName
  }
}

// Mailboxes container
module mailboxes 'container.bicep' = {
  name: 'mailboxes'
  params: {
    accountName: cosmos.name
    databaseName: databaseName
    containerId: 'Mailboxes'
    partitionKeyPath: '/mailboxId'
    uniqueKeys: [
      {
        paths: [ '/mailboxId' ]
      }
    ]
    includedPaths: [
      { path: '/*' }
    ]
    excludedPaths: [
      { path: '/"_etag"/?' }
    ]
  }
  dependsOn: [ sqlDb ]
}

// MailboxFolders container
module mailboxFolders 'container.bicep' = {
  name: 'mailboxFolders'
  params: {
    accountName: cosmos.name
    databaseName: databaseName
    containerId: 'MailboxFolders'
    partitionKeyPath: '/mailboxId'
    uniqueKeys: []
    includedPaths: [ { path: '/*' } ]
    excludedPaths: [ { path: '/"_etag"/?' } ]
  }
  dependsOn: [ sqlDb ]
}

// FolderPermissions container
module folderPermissions 'container.bicep' = {
  name: 'folderPermissions'
  params: {
    accountName: cosmos.name
    databaseName: databaseName
    containerId: 'FolderPermissions'
    partitionKeyPath: '/mailboxId'
    uniqueKeys: []
    includedPaths: [ { path: '/*' } ]
    excludedPaths: [ { path: '/"_etag"/?' } ]
  }
  dependsOn: [ sqlDb ]
}

// SyncCheckpoints container
module syncCheckpoints 'container.bicep' = {
  name: 'syncCheckpoints'
  params: {
    accountName: cosmos.name
    databaseName: databaseName
    containerId: 'SyncCheckpoints'
    partitionKeyPath: '/mailboxId'
    uniqueKeys: [ { paths: [ '/mailboxId', '/checkpointType' ] } ]
    includedPaths: [ { path: '/*' } ]
    excludedPaths: [ { path: '/"_etag"/?' } ]
  }
  dependsOn: [ sqlDb ]
}

// AuditLog container
module auditLog 'container.bicep' = {
  name: 'auditLog'
  params: {
    accountName: cosmos.name
    databaseName: databaseName
    containerId: 'AuditLog'
    partitionKeyPath: '/tenantId'
    uniqueKeys: []
    includedPaths: [ { path: '/*' } ]
    excludedPaths: [ { path: '/"_etag"/?' } ]
  }
  dependsOn: [ sqlDb ]
}
