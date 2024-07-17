#!/bin/bash

#      Copyright (c) Microsoft Corporation.
#      Copyright (c) IBM Corporation. 
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
# 
#           http://www.apache.org/licenses/LICENSE-2.0
# 
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

# Validate that the agic addon hasn't been enabled for an existing aks cluster
function validate_aks_agic() {
  local agicEnabled=$(az aks show -n ${AKS_CLUSTER_NAME} -g ${AKS_CLUSTER_RG_NAME} | jq '.addonProfiles.ingressApplicationGateway.enabled')
  if [[ "${agicEnabled,,}" == "true" ]]; then
    echo_stderr "The AGIC addon has already been enabled for the existing AKS cluster. It can't be enabled again with another Azure Application Gatway."
    exit 1
  fi
}

# To make sure the subnet only have application gateway
function validate_appgateway_vnet() {
  echo_stdout "VNET for application gateway: ${VNET_FOR_APPLICATIONGATEWAY}"
  local vnetName=$(echo ${VNET_FOR_APPLICATIONGATEWAY} | jq '.name' | tr -d "\"")
  local vnetResourceGroup=$(echo ${VNET_FOR_APPLICATIONGATEWAY} | jq '.resourceGroup' | tr -d "\"")
  local newOrExisting=$(echo ${VNET_FOR_APPLICATIONGATEWAY} | jq '.newOrExisting' | tr -d "\"")
  local subnetName=$(echo ${VNET_FOR_APPLICATIONGATEWAY} | jq '.subnets.gatewaySubnet.name' | tr -d "\"")

  if [[ "${newOrExisting,,}" != "new" ]]; then
    # the subnet can only have Application Gateway.
    # query ipConfigurations:
    # if lenght of ipConfigurations is greater than 0, the subnet fails to meet requirement of Application Gateway.
    local ret=$(az network vnet show \
      -g ${vnetResourceGroup} \
      --name ${vnetName} \
      | jq ".subnets[] | select(.name==\"${subnetName}\") | .ipConfigurations | length")

    if [ $ret -gt 0 ]; then
      echo_stderr "ERROR: invalid subnet for Application Gateway, the subnet has ${ret} connected device(s). Make sure the subnet is only for Application Gateway."
      exit 1
    fi
  fi
}

function get_application_gateway_certificate_from_keyvault() {
  # check key vault accessibility for template deployment
  local enabledForTemplateDeployment=$(az keyvault show --name ${APPLICATION_GATEWAY_SSL_KEYVAULT_NAME} --query "properties.enabledForTemplateDeployment")
  if [[ "${enabledForTemplateDeployment,,}" != "true" ]]; then
    echo_stderr "Make sure Key Vault ${APPLICATION_GATEWAY_SSL_KEYVAULT_NAME} is enabled for template deployment. "
    exit 1
  fi

  # allow the identity to access the keyvault
  local principalId=$(az identity show --ids ${AZ_SCRIPTS_USER_ASSIGNED_IDENTITY} --query "principalId" -o tsv)
  az keyvault set-policy --name ${APPLICATION_GATEWAY_SSL_KEYVAULT_NAME}  --object-id ${principalId} --secret-permissions get
  validate_status "grant identity permission to get secrets in key vault ${APPLICATION_GATEWAY_SSL_KEYVAULT_NAME}"

  # get cert data and set it to the environment variable
  APPLICATION_GATEWAY_SSL_FRONTEND_CERT_DATA=$(az keyvault secret show \
    --name ${APPLICATION_GATEWAY_SSL_KEYVAULT_FRONTEND_CERT_DATA_SECRET_NAME} \
    --vault-name ${APPLICATION_GATEWAY_SSL_KEYVAULT_NAME} --query value --output tsv)
  validate_status "get secret ${APPLICATION_GATEWAY_SSL_KEYVAULT_FRONTEND_CERT_DATA_SECRET_NAME} from key vault ${APPLICATION_GATEWAY_SSL_KEYVAULT_NAME}"

  # get cert password and set it to the environment variable
  APPLICATION_GATEWAY_SSL_FRONTEND_CERT_PASSWORD=$(az keyvault secret show \
    --name ${APPLICATION_GATEWAY_SSL_KEYVAULT_FRONTEND_CERT_PASSWORD_SECRET_NAME} \
    --vault-name ${APPLICATION_GATEWAY_SSL_KEYVAULT_NAME} --query value --output tsv)
  validate_status "get secret ${APPLICATION_GATEWAY_SSL_KEYVAULT_FRONTEND_CERT_PASSWORD_SECRET_NAME} from key vault ${APPLICATION_GATEWAY_SSL_KEYVAULT_NAME}"

  # reset key vault policy
  az keyvault delete-policy --name ${APPLICATION_GATEWAY_SSL_KEYVAULT_NAME}  --object-id ${principalId}
  validate_status "delete identity permission to get secrets in key vault ${APPLICATION_GATEWAY_SSL_KEYVAULT_NAME}"
}

function validate_gateway_frontend_certificates() {
  if [[ "${APPLICATION_GATEWAY_CERTIFICATE_OPTION}" == "generateCert" ]]; then
    return
  fi

  if [[ "${APPLICATION_GATEWAY_CERTIFICATE_OPTION}" == "haveKeyVault" ]]; then
    get_application_gateway_certificate_from_keyvault
  fi

  local appgwFrontCertFileName=${AZ_SCRIPTS_PATH_OUTPUT_DIRECTORY}/gatewaycert.pfx
  echo "$APPLICATION_GATEWAY_SSL_FRONTEND_CERT_DATA" | base64 -d >$appgwFrontCertFileName

  openssl pkcs12 \
    -in $appgwFrontCertFileName \
    -nocerts \
    -out ${AZ_SCRIPTS_PATH_OUTPUT_DIRECTORY}/cert.key \
    -passin pass:${APPLICATION_GATEWAY_SSL_FRONTEND_CERT_PASSWORD} \
    -passout pass:${APPLICATION_GATEWAY_SSL_FRONTEND_CERT_PASSWORD}
  
  validate_status_with_hint "access application gateway frontend key." "Make sure the Application Gateway frontend certificate is correct."
}

# Initialize
script="${BASH_SOURCE[0]}"
scriptDir="$(cd "$(dirname "${script}")" && pwd)"
source ${scriptDir}/utility.sh

# Main script
# Get the type of managed identity
uamiType=$(az identity show --ids ${AZ_SCRIPTS_USER_ASSIGNED_IDENTITY} --query "type" -o tsv)
if [ $? == 1 ]; then
    echo "The user-assigned managed identity may not exist or has no access to the subscription, please check ${AZ_SCRIPTS_USER_ASSIGNED_IDENTITY}" >&2
    exit 1
fi

# Check if the managed identity is a user-assigned managed identity
if [[ "${uamiType}" != "Microsoft.ManagedIdentity/userAssignedIdentities" ]]; then
    echo "You must select a user-assigned managed identity instead of other types, please check ${AZ_SCRIPTS_USER_ASSIGNED_IDENTITY}" >&2
    exit 1
fi

# Query principal Id of the user-assigned managed identity
principalId=$(az identity show --ids ${AZ_SCRIPTS_USER_ASSIGNED_IDENTITY} --query "principalId" -o tsv)

# Check if the user assigned managed identity has Contributor role
roleAssignments=$(az role assignment list --assignee ${principalId})
roleLength=$(echo $roleAssignments | jq '[ .[] | select(.roleDefinitionName=="Contributor") ] | length')
if [ ${roleLength} -ne 1 ]; then
  echo "The user-assigned managed identity must have the Contributor role in the subscription, please check ${AZ_SCRIPTS_USER_ASSIGNED_IDENTITY}" >&2
  exit 1
fi

if [[ "${CREATE_CLUSTER,,}" == "false" ]] && [[ "${ENABLE_APPLICATION_GATEWAY_INGRESS_CONTROLLER,,}" == "true" ]]; then
  validate_aks_agic
fi

if [[ "${ENABLE_APPLICATION_GATEWAY_INGRESS_CONTROLLER,,}" == "true" ]]; then
  validate_appgateway_vnet
  validate_gateway_frontend_certificates
fi

# Get vm size of the AKS agent pool
if [[ "${CREATE_CLUSTER,,}" == "false" ]]; then
  vmSize=$(az aks show -n ${AKS_CLUSTER_NAME} -g ${AKS_CLUSTER_RG_NAME} \
    | jq '.agentPoolProfiles[] | select(.name=="agentpool") | .vmSize' \
    | tr -d "\"")
else
  vmSize=${VM_SIZE}
fi
echo_stdout "VM size for the AKS agent pool is: $vmSize"

# Check if vm size of the AKS agent pool is arm64 based
if [[ $vmSize == *"p"* ]]; then
  echo_stderr "The vm of the AKS cluster agent pool is based on ARM64 architecture. It is not supported by the Open Liberty/WebSphere Liberty Operator."
  exit 1
fi

# Check if image specified by SOURCE_IMAGE_PATH is publically accessible and supports amd64 architecture
if [[ "${DEPLOY_APPLICATION,,}" == "true" ]]; then
  # Install docker-cli to inspect the image
  apk update
  apk add docker-cli
  export DOCKER_CLI_EXPERIMENTAL=enabled
  docker manifest inspect $SOURCE_IMAGE_PATH > inspect_output.txt 2>&1
  if [ $? -ne 0 ]; then
    echo_stderr "Failed to inspect image $SOURCE_IMAGE_PATH." $(cat inspect_output.txt)
    exit 1
  else
    arches=$(cat inspect_output.txt | jq -r '.manifests[].platform.architecture')
    if echo "$arches" | grep -q '^amd64$'; then
      echo_stdout "Image $SOURCE_IMAGE_PATH supports amd64 architecture." $(cat inspect_output.txt)
    else
      echo_stderr "Image $SOURCE_IMAGE_PATH does not support amd64 architecture." $(cat inspect_output.txt)
      exit 1
    fi
  fi
fi

# Query available zones for selected region and vm size
if [[ "${CREATE_CLUSTER,,}" == "true" ]]; then
  availableZones=$(az vm list-skus -l ${LOCATION} --size ${VM_SIZE} --zone true | jq -c '.[] | .locationInfo[] | .zones')
  echo_stdout "Available zones for region ${LOCATION} and vm size ${VM_SIZE} are: $availableZones"
fi

if [ -z "${availableZones}" ]; then  
  availableZones="[]"
fi

# Write outputs to deployment script output path
result=$(jq -n -c \
  --arg agentAvailabilityZones "$availableZones" \
  '{agentAvailabilityZones: $agentAvailabilityZones}')
echo_stdout "Result is: $result"
echo $result > $AZ_SCRIPTS_OUTPUT_PATH
