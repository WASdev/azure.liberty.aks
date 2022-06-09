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

param _artifactsLocation string = deployment().properties.templateLink.uri
@secure()
param _artifactsLocationSasToken string = ''
param location string

param identity object

@allowed([
  'haveCert'
  'haveKeyVault'
  'generateCert'
])
@description('Three scenarios we support for deploying app gateway')
param appgwCertificateOption string = 'haveCert'
@secure()
param appgwFrontendSSLCertData string = newGuid()
@secure()
param appgwFrontendSSLCertPsw string = newGuid()

param appgwAlias string = 'appgw-contoso-alias'
param appgwName string = 'appgw-contoso'
param appgwVNetName string = 'vnet-contoso'
@secure()
param servicePrincipal string = newGuid()

param aksClusterRGName string = 'aks-contoso-rg'
param aksClusterName string = 'aks-contoso'

param enableCookieBasedAffinity bool = false

param utcValue string = utcNow()

var const_appgwHelmConfigTemplate='appgw-helm-config.yaml.template'
var const_appgwSARoleBindingFile='appgw-ingress-clusterAdmin-roleBinding.yaml'
var const_createGatewayIngressSvcScript = 'createAppGatewayIngress.sh'
var const_scriptLocation = uri(_artifactsLocation, 'scripts/')
var const_primaryScript = 'createAppGatewayIngress.sh'
//var name_deploymentName='ds-networking-deployment'

resource deploymentScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'ds-networking-deployment'
  location: location
  kind: 'AzureCLI'
  identity: identity
  properties: {
    azCliVersion: '2.15.0'
    environmentVariables: [
      {
        name: 'AKS_CLUSTER_RG_NAME'
        value: aksClusterRGName
      }
      {
        name: 'AKS_CLUSTER_NAME'
        value: aksClusterName
      }
      {
        name: 'SUBSCRIPTION_ID'
        value: subscription().id
      }
      {
        name: 'CUR_RG_NAME'
        value: resourceGroup().name
      }
      {
        name: 'SERVICE_PRINCIPAL'
        secureValue: servicePrincipal
      }
      {
        name: 'APP_GW_NAME'
        value: appgwName
      }
      {
        name: 'APP_GW_ALIAS'
        value: appgwAlias
      }
      {
        name: 'APP_GW_VNET_NAME'
        value: appgwVNetName
      }
      {
        name: 'APP_GW_FRONTEND_SSL_CERT_DATA'
        value: appgwFrontendSSLCertData
      }
      {
        name: 'APP_GW_FRONTEND_SSL_CERT_PSW'
        secureValue: appgwFrontendSSLCertPsw
      }
      {
        name: 'APP_GW_CERTIFICATE_OPTION'
        value: appgwCertificateOption
      }
      {
        name: 'ENABLE_COOKIE_BASED_AFFINITY'
        value: string(enableCookieBasedAffinity)
      }
    ]
    primaryScriptUri: uri(const_scriptLocation, '${const_primaryScript}${_artifactsLocationSasToken}')
    supportingScriptUris: [
      uri(const_scriptLocation, '${const_appgwHelmConfigTemplate}${_artifactsLocationSasToken}')
      uri(const_scriptLocation, '${const_appgwSARoleBindingFile}${_artifactsLocationSasToken}')
      uri(const_scriptLocation, '${const_createGatewayIngressSvcScript}${_artifactsLocationSasToken}')
    ]
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'P1D'
    forceUpdateTag: utcValue
  }
}

//output clusterLBUrl string = (!enableCustomSSL) && length(lbSvcValues) > 0 && (reference(name_deploymentName).outputs.clusterEndpoint != 'null') ? format('http://{0}/',reference(name_deploymentName).outputs.clusterEndpoint): ''
//output clusterLBSecuredUrl string = enableCustomSSL && length(lbSvcValues) > 0 && (reference(name_deploymentName).outputs.clusterEndpoint != 'null') ? format('https://{0}/',reference(name_deploymentName).outputs.clusterEndpoint): ''
