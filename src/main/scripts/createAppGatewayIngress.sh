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

echo "Script ${0} starts"

function echo_stderr() {
    echo >&2 "$@"
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

# Validate teminal status with $?, exit with exception if errors happen.
function utility_validate_status() {
  if [ $? == 1 ]; then
    echo_stderr "$@"
    echo_stderr "Errors happen, exit 1."
    exit 1
  else
    echo_stdout "$@"
  fi
}

# Create network peers for aks and appgw
function network_peers_aks_appgw() {
    # To successfully peer two virtual networks command 'az network vnet peering create' must be called twice with the values
    # for --vnet-name and --remote-vnet reversed.
    local aksMCRGName=$(az aks show -n $AKS_CLUSTER_NAME -g $AKS_CLUSTER_RG_NAME -o tsv --query "nodeResourceGroup")
    local ret=$(az group exists -n ${aksMCRGName})
    if [ "${ret,,}" == "false" ]; then
        echo_stderr "AKS namaged resource group ${aksMCRGName} does not exist."
        exit 1
    fi

    # query vnet from managed resource group
    local aksNetWorkId=$(az resource list -g ${aksMCRGName} --resource-type Microsoft.Network/virtualNetworks -o tsv --query '[*].id')
    
    # no vnet in managed resource group, then query vnet from aks agent
    if [ -z "${aksNetWorkId}" ]; then
        # assume all the agent pools are in the same vnet
        # e.g. /subscriptions/xxxx-xxxx-xxxx-xxxx/resourceGroups/foo-rg/providers/Microsoft.Network/virtualNetworks/foo-aks-vnet/subnets/default
        local aksAgent1Subnet=$(az aks show -n $AKS_CLUSTER_NAME -g $AKS_CLUSTER_RG_NAME | jq '.agentPoolProfiles[0] | .vnetSubnetId' | tr -d "\"")
        utility_validate_status "Get subnet id of aks agent 0."
        aksNetWorkId=${aksAgent1Subnet%\/subnets\/*}
    fi

    local aksNetworkName=${aksNetWorkId#*\/virtualNetworks\/}
    local aksNetworkRgName=${aksNetWorkId#*\/resourceGroups\/}
    local aksNetworkRgName=${aksNetworkRgName%\/providers\/*}

    local appGatewaySubnetId=$(az network application-gateway show -g ${CURRENT_RG_NAME} --name ${APP_GW_NAME} -o tsv --query "gatewayIpConfigurations[0].subnet.id")
    local appGatewayVnetResourceGroup=$(az network application-gateway show -g ${CURRENT_RG_NAME} --name ${APP_GW_NAME} -o tsv --query "gatewayIpConfigurations[0].subnet.resourceGroup")
    local appGatewaySubnetName=$(az resource show --ids ${appGatewaySubnetId} --query "name" -o tsv)
    local appgwNetworkId=$(echo $appGatewaySubnetId | sed s/"\/subnets\/${appGatewaySubnetName}"//)
    local appgwVnetName=$(az resource show --ids ${appgwNetworkId} --query "name" -o tsv)

    local toPeer=true
    # if the AKS and App Gateway have the same VNET, need not peer.
    if [ "${aksNetWorkId}" == "${appgwNetworkId}" ]; then
        echo_stdout "AKS and Application Gateway are in the same virtual network: ${appgwNetworkId}."
        toPeer=false
    fi

    # check if the Vnets have been peered.
    local ret=$(az network vnet peering list \
        --resource-group ${appGatewayVnetResourceGroup} \
        --vnet-name ${appgwVnetName} -o json \
        | jq ".[] | select(.remoteVirtualNetwork.id==\"${aksNetWorkId}\")")
    if [ -n "$ret" ]; then
        echo_stdout "VNET of AKS ${aksNetWorkId} and Application Gateway ${appgwNetworkId} is peering."
        toPeer=false
    fi

    if [ "${toPeer}" == "true" ]; then
        az network vnet peering create \
            --name aks-appgw-peer \
            --remote-vnet ${aksNetWorkId} \
            --resource-group ${appGatewayVnetResourceGroup} \
            --vnet-name ${appgwVnetName} \
            --allow-vnet-access
        utility_validate_status "Create network peers for $aksNetWorkId and ${appgwNetworkId}."

        az network vnet peering create \
            --name aks-appgw-peer \
            --remote-vnet ${appgwNetworkId} \
            --resource-group ${aksMCRGName} \
            --vnet-name ${aksNetworkName} \
            --allow-vnet-access

        utility_validate_status "Complete creating network peers for $aksNetWorkId and ${appgwNetworkId}."
    fi

    # For Kubectl network plugin: https://azure.github.io/application-gateway-kubernetes-ingress/how-tos/networking/#with-kubenet
    # find route table used by aks cluster
    local networkPlugin=$(az aks show -n $AKS_CLUSTER_NAME -g $AKS_CLUSTER_RG_NAME --query "networkProfile.networkPlugin" -o tsv)
    if [[ "${networkPlugin}" == "kubenet" ]]; then
        # the route table is in MC_ resource group
        routeTableId=$(az network route-table list -g $aksMCRGName --query "[].id | [0]" -o tsv)

        # associate the route table to Application Gateway's subnet
        az network vnet subnet update \
            --ids $appGatewaySubnetId \
            --route-table $routeTableId

        utility_validate_status "Associate the route table ${routeTableId} to Application Gateway's subnet ${appGatewaySubnetId}"
    fi
}

function output_create_gateway_ssl_k8s_secret() {
    echo "export gateway frontend certificates"
    echo "$appgwFrontendSSLCertData" | base64 -d >${scriptDir}/$appgwFrontCertFileName

    appgwFrontendSSLCertPassin=${appgwFrontendSSLCertPsw}
    if [[ "$appgwCertificateOption" == "${appgwSelfsignedCert}" ]]; then
        appgwFrontendSSLCertPassin="" # empty password
        appgwFrontendSSLCertPsw="null"
    fi

    openssl pkcs12 \
        -in ${scriptDir}/$appgwFrontCertFileName \
        -nocerts \
        -out ${scriptDir}/$appgwFrontCertKeyFileName \
        -passin pass:${appgwFrontendSSLCertPassin} \
        -passout pass:${appgwFrontendSSLCertPsw}

    utility_validate_status "Export key from frontend certificate."

    openssl rsa -in ${scriptDir}/$appgwFrontCertKeyFileName \
        -out ${scriptDir}/$appgwFrontCertKeyDecrytedFileName \
        -passin pass:${appgwFrontendSSLCertPsw}

    utility_validate_status "Decryte private key."

    openssl pkcs12 \
        -in ${scriptDir}/$appgwFrontCertFileName \
        -clcerts \
        -nokeys \
        -out ${scriptDir}/$appgwFrontPublicCertFileName \
        -passin pass:${appgwFrontendSSLCertPassin}

    utility_validate_status "Export cert from frontend certificate."

    # Create namespace if it doesn't exist before
    kubectl get namespace ${appNamespace}
    if [[ $? -ne 0 ]]; then
        kubectl create namespace ${appNamespace}
    fi

    kubectl -n ${appNamespace} create secret tls ${appgwFrontendSecretName} \
        --key="${scriptDir}/$appgwFrontCertKeyDecrytedFileName" \
        --cert="${scriptDir}/$appgwFrontPublicCertFileName"

    utility_validate_status "create k8s tsl secret for app gateway frontend ssl termination."
}

function connect_to_aks_cluster() {
    # Install kubectl
    az aks install-cli 2>/dev/null
    kubectl --help
    utility_validate_status "Install kubectl."

    # Connect to cluster
    az aks get-credentials --resource-group ${AKS_CLUSTER_RG_NAME} --name ${AKS_CLUSTER_NAME} --overwrite-existing
    utility_validate_status "Connect to the AKS cluster."
}

function create_gateway_ingress() {
    # connect to the aks cluster
    connect_to_aks_cluster

    # create network peers between gateway vnet and aks vnet
    network_peers_aks_appgw

    # create tsl/ssl frontend secrets
    output_create_gateway_ssl_k8s_secret
}

# Initialize
script="${BASH_SOURCE[0]}"
scriptDir="$(cd "$(dirname "${script}")" && pwd)"

appgwFrontendSSLCertData=${APP_GW_FRONTEND_SSL_CERT_DATA}
appgwFrontendSSLCertPsw=${APP_GW_FRONTEND_SSL_CERT_PSW}
appgwCertificateOption=${APP_GW_CERTIFICATE_OPTION}
appgwFrontendSecretName=${APP_FRONTEND_TLS_SECRET_NAME}
appNamespace=${APP_PROJ_NAME}

appgwFrontCertFileName="appgw-frontend-cert.pfx"
appgwFrontCertKeyDecrytedFileName="appgw-frontend-cert-decryted.key"
appgwFrontCertKeyFileName="appgw-frontend-cert.key"
appgwFrontPublicCertFileName="appgw-frontend-cert.crt"
appgwSelfsignedCert="generateCert"

create_gateway_ingress
