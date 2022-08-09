#!/bin/bash

#      Copyright (c) Microsoft Corporation.
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

function echo_stderr() {
  echo "$@" 1>&2
  # The function is used for scripts running within Azure Deployment Script
  # The value of AZ_SCRIPTS_OUTPUT_PATH is /mnt/azscripts/azscriptoutput
  echo -e "$@" >>${AZ_SCRIPTS_PATH_OUTPUT_DIRECTORY}/errors.log
}

function echo_stdout() {
  echo "$@"
  # The function is used for scripts running within Azure Deployment Script
  # The value of AZ_SCRIPTS_OUTPUT_PATH is /mnt/azscripts/azscriptoutput
  echo -e "$@" >>${AZ_SCRIPTS_PATH_OUTPUT_DIRECTORY}/debug.log
}

#Validate teminal status with $?, exit with exception if errors happen.
# $1 - error message
# $2 -  root cause message
function validate_status() {
  if [ $? != 0 ]; then
    echo_stderr "Errors happen during: $1." $2
    exit 1
  else
    echo_stdout "$1"
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
  
  validate_status "access application gateway frontend key." "Make sure the Application Gateway frontend certificate is correct."
}

function validate_service_principal() {
  local spObject=$(echo "${BASE64_FOR_SERVICE_PRINCIPAL}" | base64 -d)
  validate_status "decode the service principal base64 string." "Invalid service principal."

  local principalId=$(echo ${spObject} | jq '.clientId')
  validate_status "get client id from the service principal." "Invalid service principal."

  if [[ "${principalId}" == "null" ]] || [[ "${principalId}" == "" ]]; then
    echo_stderr "the service principal is invalid."
    exit 1
  fi

  echo_stdout "check if the service principal has Contributor or Owner role."
  local roleLength=$(az role assignment list --assignee ${principalId} |
    jq '[.[] | select(.roleDefinitionName=="Contributor" or .roleDefinitionName=="Owner")] | length')
  
  local re='^[0-9]+$'
  if ! [[ $roleLength =~ $re ]] ; then
    echo_stderr "You must grant the service principal with at least Contributor role."
  fi

  if [ ${roleLength} -lt 1 ]; then
    echo_stderr "You must grant the service principal with at least Contributor role."
  fi

  echo_stdout "Check service principal: passed!"
}

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

if [[ "${ENABLE_APPLICATION_GATEWAY_INGRESS_CONTROLLER,,}" == "true" ]]; then
  validate_appgateway_vnet
  validate_gateway_frontend_certificates
  validate_service_principal
fi
