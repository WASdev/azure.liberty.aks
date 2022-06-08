/*
     Copyright (c) Microsoft Corporation.

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

          http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
*/

@description('The base URI where artifacts required by this template are located. When the template is deployed using the accompanying scripts, a private location in the subscription will be used and this value will be automatically generated.')
param _artifactsLocation string = deployment().properties.templateLink.uri

@description('The sasToken required to access _artifactsLocation.  When the template is deployed using the accompanying scripts, a sasToken will be automatically generated. Use the defaultValue if the staging location is not secured.')
@secure()
param _artifactsLocationSasToken string = ''

@description('Location for all resources.')
param location string = resourceGroup().location

@description('User-assigned managed identity granted with contributor role of the same subscription')
param identity object

@description('Flag indicating whether to create a new cluster or not')
param createCluster bool = true

@description('The VM size of the cluster')
param vmSize string = 'Standard_DS2_v2'

@description('The minimum node count of the cluster')
param minCount int = 1

@description('The maximum node count of the cluster')
param maxCount int = 5

@description('Name for the existing cluster')
param clusterName string = ''

@description('Name for the resource group of the existing cluster')
param clusterRGName string = ''

@description('Flag indicating whether to create a new ACR or not')
param createACR bool = true

@description('Name for the existing ACR')
param acrName string = ''

@description('true to set up Application Gateway ingress.')
param enableAppGWIngress bool = false

@allowed([
  'haveCert'
  'haveKeyVault'
  'generateCert'
])
@description('Three scenarios we support for deploying app gateway')
param appGatewayCertificateOption string = 'haveCert'

@description('Public IP Name for the Application Gateway')
param appGatewayPublicIPAddressName string = 'gwip'

@description('The one-line, base64 string of the SSL certificate data.')
param appGatewaySSLCertData string = 'appgw-ssl-data'

@secure()
@description('The value of the password for the SSL Certificate')
param appGatewaySSLCertPassword string = newGuid()

@description('Resource group name in current subscription containing the KeyVault')
param keyVaultResourceGroup string = 'kv-contoso-rg'

@description('Existing Key Vault Name')
param keyVaultName string = 'kv-contoso'

@description('Price tier for Key Vault.')
param keyVaultSku string = 'Standard'

@description('The name of the secret in the specified KeyVault whose value is the SSL Certificate Data for Appliation Gateway frontend TLS/SSL.')
param keyVaultSSLCertDataSecretName string = 'kv-ssl-data'

@description('The name of the secret in the specified KeyVault whose value is the password for the SSL Certificate of Appliation Gateway frontend TLS/SSL')
param keyVaultSSLCertPasswordSecretName string = 'kv-ssl-psw'

@secure()
@description('Base64 string of service principal. use the command to generate a testing string: az ad sp create-for-rbac --sdk-auth | base64 -w0')
param servicePrincipal string = newGuid()

@description('true to enable cookie based affinity.')
param enableCookieBasedAffinity bool = false

@description('Flag indicating whether to deploy an application')
param deployApplication bool = false

@description('The image path of the application')
param appImagePath string = ''

@description('The number of application replicas to deploy')
param appReplicas int = 2

@secure()
param guidValue string = newGuid()

var const_appImage = format('{0}:{1}', const_appImageName, const_appImageTag)
var const_appImageName = format('image{0}', const_suffix)
var const_appImagePath = (empty(appImagePath) ? 'NA' : ((const_appImagePathLen == 1) ? format('docker.io/library/{0}', appImagePath) : ((const_appImagePathLen == 2) ? format('docker.io/{0}', appImagePath) : appImagePath)))
var const_appImagePathLen = length(split(appImagePath, '/'))
var const_appImageTag = '1.0.0'
var const_appName = format('app{0}', const_suffix)
var const_appProjName = 'default'
var const_arguments = format('{0} {1} {2} {3} {4} {5} {6} {7} {8}', const_clusterRGName, name_clusterName, name_acrName, deployApplication, const_appImagePath, const_appName, const_appProjName, const_appImage, appReplicas)
var const_availabilityZones = [
  '1'
  '2'
  '3'
]
var const_clusterRGName = (createCluster ? resourceGroup().name : clusterRGName)
var const_cmdToGetAcrLoginServer = format('az acr show -n {0} --query loginServer -o tsv', name_acrName)
var const_regionsSupportAvailabilityZones = [
  'australiaeast'
  'brazilsouth'
  'canadacentral'
  'centralindia'
  'centralus'
  'eastasia'
  'eastus'
  'eastus2'
  'francecentral'
  'germanywestcentral'
  'japaneast'
  'koreacentral'
  'northeurope'
  'norwayeast'
  'southeastasia'
  'southcentralus'
  'swedencentral'
  'uksouth'
  'usgovvirginia'
  'westeurope'
  'westus2'
  'westus3'
]
var const_scriptLocation = uri(_artifactsLocation, 'scripts/')
var const_suffix = take(replace(guidValue, '-', ''), 6)
var name_acrName = createACR ? format('acr{0}', const_suffix) : acrName
var name_clusterName = createCluster ? format('cluster{0}', const_suffix) : clusterName
var name_deploymentScriptName = format('script{0}', const_suffix)
var name_cpDeploymentScript = format('cpscript{0}', const_suffix)

module partnerCenterPid './modules/_pids/_empty.bicep' = {
  name: 'pid-68a0b448-a573-4012-ab25-d5dc9842063e-partnercenter'
  params: {}
}

module aksStartPid './modules/_pids/_empty.bicep' = {
  name: '628cae16-c133-5a2e-ae93-2b44748012fe'
  params: {}
}

resource checkPermissionDsDeployment 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: name_cpDeploymentScript
  location: location
  kind: 'AzureCLI'
  identity: identity
  properties: {
    azCliVersion: '2.15.0'
    primaryScriptUri: uri(const_scriptLocation, format('check-permission.sh{0}', _artifactsLocationSasToken))
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'P1D'
  }
}

resource acrDeployment 'Microsoft.ContainerRegistry/registries@2021-09-01' = if (createACR) {
  name: name_acrName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
  }
  dependsOn: [
    checkPermissionDsDeployment
  ]
}

resource clusterDeployment 'Microsoft.ContainerService/managedClusters@2021-02-01' = if (createCluster) {
  name: name_clusterName
  location: location
  properties: {
    enableRBAC: true
    dnsPrefix: format('{0}-dns', name_clusterName)
    agentPoolProfiles: [
      {
        name: 'agentpool'
        osDiskSizeGB: 0
        enableAutoScaling: true
        minCount: minCount
        maxCount: maxCount
        count: minCount
        vmSize: vmSize
        osType: 'Linux'
        type: 'VirtualMachineScaleSets'
        mode: 'System'
        availabilityZones: (contains(const_regionsSupportAvailabilityZones, location) ? const_availabilityZones : null)
      }
    ]
    networkProfile: {
      loadBalancerSku: 'standard'
      networkPlugin: 'kubenet'
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
  dependsOn: [
    acrDeployment
  ]
}

resource primaryDsDeployment 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: name_deploymentScriptName
  location: location
  kind: 'AzureCLI'
  identity: identity
  properties: {
    azCliVersion: '2.15.0'
    arguments: const_arguments
    primaryScriptUri: uri(const_scriptLocation, format('install.sh{0}', _artifactsLocationSasToken))
    supportingScriptUris: [
      uri(const_scriptLocation, format('open-liberty-application.yaml.template{0}', _artifactsLocationSasToken))
    ]
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'P1D'
  }
  dependsOn: [
    clusterDeployment
  ]
}

module aksEndPid './modules/_pids/_empty.bicep' = {
  name: '59f5f6da-0a6d-587d-b23c-177108cd8bbf'
  params: {}
  dependsOn: [
    primaryDsDeployment
  ]
}

output appEndpoint string = deployApplication ? primaryDsDeployment.properties.outputs.appEndpoint : ''
output clusterName string = name_clusterName
output clusterRGName string = const_clusterRGName
output acrName string = name_acrName
output cmdToGetAcrLoginServer string = const_cmdToGetAcrLoginServer
output appNamespaceName string = const_appProjName
output appName string = deployApplication ? const_appName : ''
output appImage string = deployApplication ? const_appImage : ''
output cmdToConnectToCluster string = format('az aks get-credentials -g {0} -n {1}', const_clusterRGName, name_clusterName)
output cmdToGetAppInstance string = deployApplication ? format('kubectl get openlibertyapplication {0}', const_appName) : ''
output cmdToGetAppDeployment string = deployApplication ? format('kubectl get deployment {0}', const_appName) : ''
output cmdToGetAppPods string = deployApplication ? 'kubectl get pod' : ''
output cmdToGetAppService string = deployApplication ? format('kubectl get service {0}', const_appName) : ''
output cmdToLoginInRegistry string = format('az acr login -n {0}', name_acrName)
output cmdToPullImageFromRegistry string = deployApplication ? format('docker pull $({0})/{1}', const_cmdToGetAcrLoginServer, const_appImage) : ''
output cmdToTagImageWithRegistry string = format('docker tag <source-image-path> $({0})/<target-image-name:tag>', const_cmdToGetAcrLoginServer)
output cmdToPushImageToRegistry string = format('docker push $({0})/<target-image-name:tag>', const_cmdToGetAcrLoginServer)
output appDeploymentYaml string = deployApplication? format('echo "{0}" | base64 -d', primaryDsDeployment.properties.outputs.appDeploymentYaml) : ''
output appDeploymentTemplateYaml string =  !deployApplication ? format('echo "{0}" | base64 -d', primaryDsDeployment.properties.outputs.appDeploymentYaml) : ''
output cmdToUpdateOrCreateApplication string = 'kubectl apply -f <application-yaml-file-path>'
