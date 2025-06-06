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

function validate_gateway_frontend_certificates() {
  if [[ "${APPLICATION_GATEWAY_CERTIFICATE_OPTION}" == "generateCert" ]]; then
    return
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

# Check if image specified by SOURCE_IMAGE_PATH is accessible and supports amd64 architecture
if [[ "${DEPLOY_APPLICATION,,}" == "true" ]]; then
  # Install docker-cli
  apk update
  apk add docker-cli

  if [[ "${CREATE_ACR,,}" == "false" ]]; then
    # Login to the user specified Azure Container Registry to allow access to its images 
    ACR_LOGIN_SERVER=$(az acr show -n $ACR_NAME -g $ACR_RG_NAME --query 'loginServer' -o tsv)
    ACR_USER_NAME=$(az acr credential show -n $ACR_NAME -g $ACR_RG_NAME --query 'username' -o tsv)
    ACR_PASSWORD=$(az acr credential show -n $ACR_NAME -g $ACR_RG_NAME --query 'passwords[0].value' -o tsv)
    docker login $ACR_LOGIN_SERVER -u $ACR_USER_NAME -p $ACR_PASSWORD 2>/dev/null

    if [ $? -ne 0 ]; then
      echo_stderr "Failed to login to the Azure Container Registry server $ACR_LOGIN_SERVER."
      exit 1
    fi
  fi

  # Inspect the manifest of the image
  export DOCKER_CLI_EXPERIMENTAL=enabled
  docker manifest inspect $SOURCE_IMAGE_PATH > inspect_output.txt 2>&1
  if [ $? -ne 0 ]; then
    # The image is not accessible if the manifest inspect command fails
    echo_stderr "Failed to inspect image $SOURCE_IMAGE_PATH." $(cat inspect_output.txt)
    exit 1
  else
    # Check if the image supports amd64 architecture per the manifest
    arches=$(cat inspect_output.txt | jq -r '.manifests[].platform.architecture')
    if echo "$arches" | grep -q '^amd64$'; then
      echo_stdout "Image $SOURCE_IMAGE_PATH supports amd64 architecture." $(cat inspect_output.txt)
    else
      echo_stdout "No amd64 architecture found from the manifest of image $SOURCE_IMAGE_PATH." $(cat inspect_output.txt)
      # Retry by inspecting the manifest with --verbose option
      docker manifest inspect $SOURCE_IMAGE_PATH --verbose > inspect_verbose_output.txt 2>&1
      arches=$(cat inspect_verbose_output.txt | jq -r '.Descriptor.platform.architecture')
      if echo "$arches" | grep -q '^amd64$'; then
        echo_stdout "Image $SOURCE_IMAGE_PATH supports amd64 architecture." $(cat inspect_verbose_output.txt)
      else
        echo_stderr "Image $SOURCE_IMAGE_PATH does not support amd64 architecture." $(cat inspect_verbose_output.txt)
        exit 1
      fi
    fi
  fi
fi

# Get availability zones
if [[ "${CREATE_CLUSTER,,}" == "true" ]]; then
  # Get available zones for the specified region and vm size
  availableZones=$(az vm list-skus -l ${LOCATION} --size ${VM_SIZE} --zone true | jq -c '.[] | .locationInfo[] | .zones')
  echo_stdout "Available zones for region ${LOCATION} and vm size ${VM_SIZE} are: $availableZones"
else
  # Get available zones for the existing AKS cluster
  availableZones=$(az aks show -n ${AKS_CLUSTER_NAME} -g ${AKS_CLUSTER_RG_NAME} | jq '.agentPoolProfiles[] | select(.name=="agentpool") | .availabilityZones')
  echo_stdout "Available zones for the agent pool of the existing AKS cluster are: $availableZones"
fi

if [ -z "${availableZones}" ]; then  
  availableZones="[]"
fi

# Write outputs to deployment script output path
result=$(jq -n -c \
  --arg agentAvailabilityZones "$availableZones" \
  --arg vmSize "$vmSize" \
  '{agentAvailabilityZones: $agentAvailabilityZones, vmSize: $vmSize}')
echo_stdout "Result is: $result"
echo $result > $AZ_SCRIPTS_OUTPUT_PATH
