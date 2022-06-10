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
    aksMCRGName=$(az aks show -n $aksClusterName -g $aksClusterRGName -o tsv --query "nodeResourceGroup")
    ret=$(az group exists -n ${aksMCRGName})
    if [ "${ret,,}" == "false" ]; then
        echo "AKS namaged resource group ${aksMCRGName} does not exist."
        exit 1
    fi

    aksNetWorkId=$(az resource list -g ${aksMCRGName} --resource-type Microsoft.Network/virtualNetworks -o tsv --query '[*].id')
    aksNetworkName=$(az resource list -g ${aksMCRGName} --resource-type Microsoft.Network/virtualNetworks -o tsv --query '[*].name')
    az network vnet peering create \
        --name aks-appgw-peer \
        --remote-vnet ${aksNetWorkId} \
        --resource-group ${curRGName} \
        --vnet-name ${appgwVNetName} \
        --allow-vnet-access
    utility_validate_status "Create network peers for $aksNetWorkId and ${appgwVNetName}."

    appgwNetworkId=$(az resource list -g ${curRGName} --name ${appgwVNetName} -o tsv --query '[*].id')
    az network vnet peering create \
        --name aks-appgw-peer \
        --remote-vnet ${appgwNetworkId} \
        --resource-group ${aksMCRGName} \
        --vnet-name ${aksNetworkName} \
        --allow-vnet-access

    utility_validate_status "Create network peers for $aksNetWorkId and ${appgwVNetName}."

    # For Kbectl network plugin: https://azure.github.io/application-gateway-kubernetes-ingress/how-tos/networking/#with-kubenet
    # find route table used by aks cluster
    routeTableId=$(az network route-table list -g $aksMCRGName --query "[].id | [0]" -o tsv)

    # get the application gateway's subnet
    appGatewaySubnetId=$(az network application-gateway show -n $appgwName -g $curRGName -o tsv --query "gatewayIpConfigurations[0].subnet.id")

    # associate the route table to Application Gateway's subnet
    az network vnet subnet update \
        --ids $appGatewaySubnetId \
        --route-table $routeTableId

    utility_validate_status "Associate the route table ${routeTableId} to Application Gateway's subnet ${appGatewaySubnetId}"
}

function install_helm() {
    # Install Helm
    browserURL=$(curl -m ${curlMaxTime} -s https://api.github.com/repos/helm/helm/releases/latest |
        grep "browser_download_url.*linux-amd64.tar.gz.asc" |
        cut -d : -f 2,3 |
        tr -d \")
    helmLatestVersion=${browserURL#*download\/}
    helmLatestVersion=${helmLatestVersion%%\/helm*}
    helmPackageName=helm-${helmLatestVersion}-linux-amd64.tar.gz
    curl -m ${curlMaxTime} -fL https://get.helm.sh/${helmPackageName} -o /tmp/${helmPackageName}
    tar -zxvf /tmp/${helmPackageName} -C /tmp
    mv /tmp/linux-amd64/helm /usr/local/bin/helm
    echo "Helm version"
    helm version
    utility_validate_status "Finished installing Helm."
}

function install_azure_ingress() {
    # create sa and bind cluster-admin role to grant azure ingress required permissions
    kubectl apply -f ${scriptDir}/appgw-ingress-clusterAdmin-roleBinding.yaml

    install_helm
    helm repo add application-gateway-kubernetes-ingress ${appgwIngressHelmRepo}
    helm repo update

    # generate Helm config for azure ingress
    customAppgwHelmConfig=${scriptDir}/appgw-helm-config.yaml
    cp ${scriptDir}/appgw-helm-config.yaml.template ${customAppgwHelmConfig}
    subID=${subID#*\/subscriptions\/}
    sed -i -e "s:@SUB_ID@:${subID}:g" ${customAppgwHelmConfig}
    sed -i -e "s:@APPGW_RG_NAME@:${curRGName}:g" ${customAppgwHelmConfig}
    sed -i -e "s:@APPGW_NAME@:${appgwName}:g" ${customAppgwHelmConfig}
    sed -i -e "s:@WATCH_NAMESPACE@:${watchNamespace}:g" ${customAppgwHelmConfig}
    sed -i -e "s:@SP_ENCODING_CREDENTIALS@:${spBase64String}:g" ${customAppgwHelmConfig}

    helm upgrade --install ingress-azure \
        -f ${customAppgwHelmConfig} \
        application-gateway-kubernetes-ingress/ingress-azure \
        --version ${azureAppgwIngressVersion}

    utility_validate_status "Install app gateway ingress controller."

    attempts=0
    podState="running"
    while [ "$podState" == "running" ] && [ $attempts -lt ${checkPodStatusMaxAttemps} ]; do
        podState="completed"
        attempts=$((attempts + 1))
        echo Waiting for Pod running...${attempts}
        sleep ${checkPodStatusInterval}

        ret=$(kubectl get pod -o json |
            jq '.items[] | .status.containerStatuses[] | select(.name=="ingress-azure") | .ready')
        if [[ "${ret}" == "false" ]]; then
            podState="running"
        fi
    done

    if [ "$podState" == "running" ] && [ $attempts -ge ${checkPodStatusMaxAttemps} ]; then
        echo "Failed to install app gateway ingress controller."
        exit 1
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

    kubectl -n ${appNamespace} create secret tls ${appgwFrontendSecretName} \
        --key="${scriptDir}/$appgwFrontCertKeyDecrytedFileName" \
        --cert="${scriptDir}/$appgwFrontPublicCertFileName"

    utility_validate_status "create k8s tsl secret for app gateway frontend ssl termination."
}

function connect_to_aks_cluster() {
    # Install kubectl
    rm -rf apps && mkdir apps && cd apps
    az aks install-cli
    kubectl --help
    utility_validate_status "Install kubectl."
    cd ..

    # Connect to cluster
    az aks get-credentials --resource-group ${aksClusterRGName} --name ${aksClusterName} --overwrite-existing
    utility_validate_status "Connect to the AKS cluster."
}

function create_gateway_ingress() {
    # connect to the aks cluster
    connect_to_aks_cluster
    # create network peers between gateway vnet and aks vnet
    network_peers_aks_appgw
    # install azure ingress controllor
    install_azure_ingress
    # create tsl/ssl frontend secrets
    output_create_gateway_ssl_k8s_secret
}

# Initialize
script="${BASH_SOURCE[0]}"
scriptDir="$(cd "$(dirname "${script}")" && pwd)"

aksClusterRGName=${AKS_CLUSTER_RG_NAME}
aksClusterName=${AKS_CLUSTER_NAME}

subID=${SUBSCRIPTION_ID}
curRGName=${CUR_RG_NAME}
spBase64String=${SERVICE_PRINCIPAL}

appgwName=${APP_GW_NAME}
appgwAlias=${APP_GW_ALIAS}
appgwVNetName=${APP_GW_VNET_NAME}

appgwFrontendSSLCertData=${APP_GW_FRONTEND_SSL_CERT_DATA}
appgwFrontendSSLCertPsw=${APP_GW_FRONTEND_SSL_CERT_PSW}
appgwCertificateOption=${APP_GW_CERTIFICATE_OPTION}
appgwFrontendSecretName=${APP_FRONTEND_TLS_SECRET_NAME}
appNamespace=default=${APP_PROJ_NAME}

appgwIngressHelmRepo="https://appgwingress.blob.core.windows.net/ingress-azure-helm-package/"
appgwFrontCertFileName="appgw-frontend-cert.pfx"
appgwFrontCertKeyDecrytedFileName="appgw-frontend-cert-decryted.key"
appgwFrontCertKeyFileName="appgw-frontend-cert.key"
appgwFrontPublicCertFileName="appgw-frontend-cert.crt"

appgwSelfsignedCert="generateCert"
azureAppgwIngressVersion="1.5.1"
watchNamespace='""'

curlMaxTime=120
checkPodStatusMaxAttemps=30
checkPodStatusInterval=20

create_gateway_ingress
