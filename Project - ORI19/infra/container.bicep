param accountName string
param databaseName string
param containerId string
param partitionKeyPath string
param includedPaths array
param excludedPaths array
param uniqueKeys array

resource container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  name: '${accountName}/${databaseName}/${containerId}'
  properties: {
    resource: {
      id: containerId
      partitionKey: {
        paths: [ partitionKeyPath ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
        includedPaths: includedPaths
        excludedPaths: excludedPaths
        compositeIndexes: []
      }
      uniqueKeyPolicy: {
        uniqueKeys: uniqueKeys
      }
    }
    options: {
      throughput: 400
    }
  }
}
