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

param location string

// https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles
var const_roleDefinitionIdOfOwner = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
var name_deploymentScriptUserDefinedManagedIdentity = 'ol-aks-deployment-script-user-defined-managed-itentity'
var name_deploymentScriptOwnerRoleAssignmentName = guid('${resourceGroup().id}${name_deploymentScriptUserDefinedManagedIdentity}Deployment Script')

// UAMI for deployment script
resource uamiForDeploymentScript 'Microsoft.ManagedIdentity/userAssignedIdentities@2021-09-30-preview' = {
  name: name_deploymentScriptUserDefinedManagedIdentity
  location: location
}

// Assign Owner role in subscription scope, we need the permission to get/update resource cross resource group.
module deploymentScriptUAMICotibutorRoleAssignment '_rolesAssignment/_roleAssignmentinSubscription.bicep' = {
  name: name_deploymentScriptOwnerRoleAssignmentName
  scope: subscription()
  params: {
    roleDefinitionId: const_roleDefinitionIdOfOwner
    principalId: reference(resourceId('Microsoft.ManagedIdentity/userAssignedIdentities', name_deploymentScriptUserDefinedManagedIdentity)).principalId
  }
}

output uamiIdForDeploymentScript string = uamiForDeploymentScript.id
