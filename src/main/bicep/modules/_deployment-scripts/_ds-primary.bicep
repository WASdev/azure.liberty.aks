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
param name string = ''
param identity object = {}
param arguments string = ''
param deployApplication bool = false
param enableAppGWIngress bool = false
param appFrontendTlsSecretName string =''
param enableCookieBasedAffinity bool = false

param utcValue string = utcNow()

var const_scriptLocation = uri(_artifactsLocation, 'scripts/')
var const_olaTemplate='open-liberty-application.yaml.template'
var const_olaAgicTemplate='open-liberty-application-agic.yaml.template'
var const_primaryScript = 'install.sh'

resource deploymentScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: name
  location: location
  kind: 'AzureCLI'
  identity: identity
  properties: {
    azCliVersion: '2.15.0'
    environmentVariables: [
      {
        name: 'ENABLE_APP_GW_INGRESS'
        value: string(enableAppGWIngress)
      }
      {
        name: 'APP_FRONTEND_TLS_SECRET_NAME'
        value: string(appFrontendTlsSecretName)
      }
      {
        name: 'ENABLE_COOKIE_BASED_AFFINITY'
        value: string(enableCookieBasedAffinity)
      }
    ]
    arguments: arguments
    primaryScriptUri: uri(const_scriptLocation, '${const_primaryScript}${_artifactsLocationSasToken}')
    supportingScriptUris: [
      uri(const_scriptLocation, format('{0}{1}', const_olaTemplate, _artifactsLocationSasToken))
      uri(const_scriptLocation, format('{0}{1}', const_olaAgicTemplate, _artifactsLocationSasToken))
    ]
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'P1D'
    forceUpdateTag: utcValue
  }
}

output appEndpoint string = (deployApplication && !enableAppGWIngress) ? deploymentScript.properties.outputs.appEndpoint : ''
output appDeploymentYaml string = deploymentScript.properties.outputs.appDeploymentYaml
