/*
     Copyright (c) Microsoft Corporation.
     Copyright (c) IBM Corporation.

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

param identity object = {}
param location string
param permission object = {
  certificates: [
    'get'
    'list'
    'update'
    'create'
  ]
}

@description('Price tier for Key Vault.')
param sku string = 'Standard'

@description('Subject name to create a certificate.')
param subjectName string = ''

@description('Current deployment time. Used as a tag in deployment script.')
param keyVaultName string = 'GEN_UNIQUE'

module keyVaultwithSelfSignedAppGatewaySSLCert '_keyvault/_keyvaultWithNewCert.bicep' = {
  name: 'kv-appgw-selfsigned-certificate-deployment'
  params: {
    identity: identity
    keyVaultName: keyVaultName
    location: location
    permission: permission
    subjectName: subjectName
    sku: sku
  }
}

output keyVaultName string = keyVaultwithSelfSignedAppGatewaySSLCert.outputs.keyVaultName
output sslCertDataSecretName string = keyVaultwithSelfSignedAppGatewaySSLCert.outputs.secretName
output sslCertPwdSecretName string = keyVaultwithSelfSignedAppGatewaySSLCert.outputs.secretName
output sslBackendCertDataSecretName string = ''

