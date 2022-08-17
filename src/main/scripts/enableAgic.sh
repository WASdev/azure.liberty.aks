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

function connect_to_aks_cluster() {
    # Install kubectl
    az aks install-cli 2>/dev/null
    kubectl --help
    utility_validate_status "Install kubectl."

    # Connect to cluster
    az aks get-credentials --resource-group ${AKS_CLUSTER_RG_NAME} --name ${AKS_CLUSTER_NAME} --overwrite-existing
    utility_validate_status "Connect to the AKS cluster."
}

function install_azure_ingress() {
    local identityLength=$(az aks show -g ${AKS_CLUSTER_RG_NAME} -n ${AKS_CLUSTER_NAME} | jq '.identity | length')
    echo "identityLength ${identityLength}"

    if [ $identityLength -lt 1 ]; then
        echo "enable managed identity..."
        # Your cluster is using service principal, and you are going to update the cluster to use systemassigned managed identity.
        # After updating, your cluster's control plane and addon pods will switch to use managed identity, but kubelet will KEEP USING SERVICE PRINCIPAL until you upgrade your agentpool.
        az aks update -y -g ${AKS_CLUSTER_RG_NAME} -n ${AKS_CLUSTER_NAME} --enable-managed-identity

        utility_validate_status "Enable Applciation Gateway Ingress Controller for ${AKS_CLUSTER_NAME}."
    fi

    local agicEnabled=$(az aks show -n ${AKS_CLUSTER_NAME} -g ${AKS_CLUSTER_RG_NAME} | jq '.addonProfiles.ingressApplicationGateway.enabled')
    local agicGatewayId=""
    if [[ "${agicEnabled,,}" == "true" ]]; then
        agicGatewayId=$(az aks show -n ${AKS_CLUSTER_NAME} -g ${AKS_CLUSTER_RG_NAME} |
            jq '.addonProfiles.ingressApplicationGateway.config.applicationGatewayId' |
            tr -d "\"")
    fi

    local appgwId=$(az network application-gateway show \
        -n ${APP_GW_NAME} \
        -g ${CURRENT_RG_NAME} -o tsv --query "id")

    if [[ "${agicGatewayId}" != "${appgwId}" ]]; then
        az aks enable-addons -n ${AKS_CLUSTER_NAME} -g ${AKS_CLUSTER_RG_NAME} --addons ingress-appgw --appgw-id $appgwId
        utility_validate_status "Install app gateway ingress controller."
    fi
}

function validate_azure_ingress() {
    local ret=$(kubectl get pod -n kube-system | grep "ingress-appgw-deployment-*" | grep "Running")
    if [[ -z "$ret" ]]; then
        echo_stderr "Failed to enable azure ingress."
        exit 1
    fi

    echo "appgw ingress is running."
}

# Main script
set -Eo pipefail

connect_to_aks_cluster

install_azure_ingress

validate_azure_ingress
