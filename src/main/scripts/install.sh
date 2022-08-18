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

MAX_RETRIES=299

wait_deployment_complete() {
    deploymentName=$1
    namespaceName=$2
    logFile=$3

    cnt=0
    kubectl get deployment ${deploymentName} -n ${namespaceName}
    while [ $? -ne 0 ]
    do
        if [ $cnt -eq $MAX_RETRIES ]; then
            echo "Timeout and exit due to the maximum retries reached." >> $logFile 
            return 1
        fi
        cnt=$((cnt+1))

        echo "Unable to get the deployment ${deploymentName}, retry ${cnt} of ${MAX_RETRIES}..." >> $logFile
        sleep 5
        kubectl get deployment ${deploymentName} -n ${namespaceName}
    done

    cnt=0
    read -r -a replicas <<< `kubectl get deployment ${deploymentName} -n ${namespaceName} -o=jsonpath='{.spec.replicas}{" "}{.status.readyReplicas}{" "}{.status.availableReplicas}{" "}{.status.updatedReplicas}{"\n"}'`
    while [[ ${#replicas[@]} -ne 4 || ${replicas[0]} != ${replicas[1]} || ${replicas[1]} != ${replicas[2]} || ${replicas[2]} != ${replicas[3]} ]]
    do
        if [ $cnt -eq $MAX_RETRIES ]; then
            echo "Timeout and exit due to the maximum retries reached." >> $logFile 
            return 1
        fi
        cnt=$((cnt+1))

        # Delete pods in ImagePullBackOff status
        podIds=`kubectl get pod -n ${namespaceName} | grep ImagePullBackOff | awk '{print $1}'`
        read -r -a podIds <<< `echo $podIds`
        for podId in "${podIds[@]}"
        do
            echo "Delete pod ${podId} in ImagePullBackOff status" >> $logFile
            kubectl delete pod ${podId} -n ${namespaceName}
        done

        sleep 5
        echo "Wait until the deployment ${deploymentName} completes, retry ${cnt} of ${MAX_RETRIES}..." >> $logFile
        read -r -a replicas <<< `kubectl get deployment ${deploymentName} -n ${namespaceName} -o=jsonpath='{.spec.replicas}{" "}{.status.readyReplicas}{" "}{.status.availableReplicas}{" "}{.status.updatedReplicas}{"\n"}'`
    done
    echo "Deployment ${deploymentName} completed." >> $logFile
}

wait_service_available() {
    serviceName=$1
    namespaceName=$2
    logFile=$3

    cnt=0
    kubectl get svc ${serviceName} -n ${namespaceName}
    while [ $? -ne 0 ]
    do
        if [ $cnt -eq $MAX_RETRIES ]; then
            echo "Timeout and exit due to the maximum retries reached." >> $logFile 
            return 1
        fi
        cnt=$((cnt+1))

        echo "Unable to get the service ${serviceName}, retry ${cnt} of ${MAX_RETRIES}..." >> $logFile
        sleep 5
        kubectl get svc ${serviceName} -n ${namespaceName}
    done

    cnt=0
    appEndpoint=$(kubectl get svc ${serviceName} -n ${namespaceName} -o=jsonpath='{.status.loadBalancer.ingress[0].ip}:{.spec.ports[0].port}')
    echo "ip:port is ${appEndpoint}" >> $logFile
    while [[ $appEndpoint = :* ]] || [[ -z $appEndpoint ]]
    do
        if [ $cnt -eq $MAX_RETRIES ]; then
            echo "Timeout and exit due to the maximum retries reached." >> $logFile 
            return 1
        fi
        cnt=$((cnt+1))

        sleep 5
        echo "Wait until the IP address and port of the service ${serviceName} are available, retry ${cnt} of ${MAX_RETRIES}..." >> $logFile
        appEndpoint=$(kubectl get svc ${serviceName} -n ${namespaceName} -o=jsonpath='{.status.loadBalancer.ingress[0].ip}:{.spec.ports[0].port}')
        echo "ip:port is ${appEndpoint}" >> $logFile
    done
}

wait_ingress_available() {
    ingressName=$1
    namespaceName=$2
    logFile=$3

    cnt=0
    kubectl get ingress ${ingressName} -n ${namespaceName}
    while [ $? -ne 0 ]
    do
        if [ $cnt -eq $MAX_RETRIES ]; then
            echo "Timeout and exit due to the maximum retries reached." >> $logFile 
            return 1
        fi
        cnt=$((cnt+1))

        echo "Unable to get the ingress ${ingressName}, retry ${cnt} of ${MAX_RETRIES}..." >> $logFile
        sleep 5
        kubectl get ingress ${ingressName} -n ${namespaceName}
    done

    cnt=0
    ip=$(kubectl get ingress ${ingressName} -n ${namespaceName} -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
    echo "ip is ${ip}" >> $logFile
    while [ -z $ip ]
    do
        if [ $cnt -eq $MAX_RETRIES ]; then
            echo "Timeout and exit due to the maximum retries reached." >> $logFile 
            return 1
        fi
        cnt=$((cnt+1))

        sleep 30
        echo "Wait until the IP address of the ingress ${ingressName} is available, retry ${cnt} of ${MAX_RETRIES}..." >> $logFile
        ip=$(kubectl get ingress ${ingressName} -n ${namespaceName} -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
        echo "ip is ${ip}" >> $logFile
    done
}

clusterRGName=$1
clusterName=$2
acrName=$3
deployApplication=$4
sourceImagePath=$5
export Application_Name=$6
export Project_Name=$7
export Application_Image=$8
export Application_Replicas=$9
logFile=deployment.log

# Install utilities
apk update
apk add gettext
apk add docker-cli

# Install `kubectl` and connect to the AKS cluster
az aks install-cli 2>/dev/null
az aks get-credentials -g $clusterRGName -n $clusterName --overwrite-existing >> $logFile

# Install Open Liberty Operator
OPERATOR_VERSION=0.8.2
mkdir -p overlays/watch-all-namespaces
wget https://raw.githubusercontent.com/OpenLiberty/open-liberty-operator/main/deploy/releases/${OPERATOR_VERSION}/kustomize/overlays/watch-all-namespaces/olo-all-namespaces.yaml -q -P ./overlays/watch-all-namespaces
wget https://raw.githubusercontent.com/OpenLiberty/open-liberty-operator/main/deploy/releases/${OPERATOR_VERSION}/kustomize/overlays/watch-all-namespaces/cluster-roles.yaml -q -P ./overlays/watch-all-namespaces
wget https://raw.githubusercontent.com/OpenLiberty/open-liberty-operator/main/deploy/releases/${OPERATOR_VERSION}/kustomize/overlays/watch-all-namespaces/kustomization.yaml -q -P ./overlays/watch-all-namespaces
mkdir base
wget https://raw.githubusercontent.com/OpenLiberty/open-liberty-operator/main/deploy/releases/${OPERATOR_VERSION}/kustomize/base/kustomization.yaml -q -P ./base
wget https://raw.githubusercontent.com/OpenLiberty/open-liberty-operator/main/deploy/releases/${OPERATOR_VERSION}/kustomize/base/open-liberty-crd.yaml -q -P ./base
wget https://raw.githubusercontent.com/OpenLiberty/open-liberty-operator/main/deploy/releases/${OPERATOR_VERSION}/kustomize/base/open-liberty-operator.yaml -q -P ./base
kubectl apply -k overlays/watch-all-namespaces
if [[ $? -ne 0 ]]; then
  echo "Failed to install Open Liberty Operator, please check if required directories and files exist" >&2
  exit 1
fi
wait_deployment_complete olo-controller-manager default ${logFile}
if [[ $? -ne 0 ]]; then
  echo "The Open Liberty Operator is not available." >&2
  exit 1
fi

# Create project namespace if it doesn't exist before
kubectl get namespace ${Project_Name}
if [[ $? -ne 0 ]]; then
  kubectl create namespace ${Project_Name} >> $logFile
fi

# Retrieve login server and credentials of the ACR
LOGIN_SERVER=$(az acr show -n $acrName --query 'loginServer' -o tsv)
USER_NAME=$(az acr credential show -n $acrName --query 'username' -o tsv)
PASSWORD=$(az acr credential show -n $acrName --query 'passwords[0].value' -o tsv)

# Choose right template by checking if AGIC is enabled
appDeploymentTemplate=open-liberty-application.yaml.template
if [ "$ENABLE_APP_GW_INGRESS" = True ]; then
    appDeploymentTemplate=open-liberty-application-agic.yaml.template
fi

appDeploymentFile=open-liberty-application.yaml
export Enable_Cookie_Based_Affinity="${ENABLE_COOKIE_BASED_AFFINITY,,}"
export Frontend_Tls_Secret=${APP_FRONTEND_TLS_SECRET_NAME}

# Deploy application image if it's requested by the user
if [ "$deployApplication" = True ]; then
    # Log into the ACR and import application image
    docker login $LOGIN_SERVER -u $USER_NAME -p $PASSWORD >> $logFile 2>/dev/null
    az acr import -n $acrName --source ${sourceImagePath} -t ${Application_Image} >> $logFile
    if [[ $? != 0 ]]; then
        echo "Unable to import source image ${sourceImagePath} to the Azure Container Registry instance. Please check if it's a public image and the source image path is correct" >&2
        exit 1
    fi
    Application_Image=${LOGIN_SERVER}/${Application_Image}

    # Deploy open liberty application and output its base64 encoded deployment yaml file content
    envsubst < "$appDeploymentTemplate" > "$appDeploymentFile"
    appDeploymentYaml=$(cat $appDeploymentFile | base64)
    kubectl apply -f $appDeploymentFile >> $logFile

    # Wait until the application deployment completes
    wait_deployment_complete ${Application_Name} ${Project_Name} ${logFile}
    if [[ $? != 0 ]]; then
        echo "The OpenLibertyApplication ${Application_Name} is not available." >&2
        exit 1
    fi

    # Wait until the public IP address of the load balancer service or ingress is available
    if [ "$ENABLE_APP_GW_INGRESS" = False ]; then
        wait_service_available ${Application_Name} ${Project_Name} ${logFile}
        if [[ $? != 0 ]]; then
            echo "The service ${Application_Name} is not available." >&2
            exit 1
        fi
        appEndpoint=$(kubectl get svc ${Application_Name} -n ${Project_Name} -o=jsonpath='{.status.loadBalancer.ingress[0].ip}:{.spec.ports[0].port}')
    else
        wait_ingress_available ${Application_Name}-ingress-tls ${Project_Name} ${logFile}
        if [[ $? != 0 ]]; then
            echo "The ingress ${Application_Name}-ingress-tls is not available." >&2
            exit 1
        fi
        wait_ingress_available ${Application_Name}-ingress ${Project_Name} ${logFile}
        if [[ $? != 0 ]]; then
            echo "The ingress ${Application_Name}-ingress is not available." >&2
            exit 1
        fi
    fi
else
    Application_Image=${LOGIN_SERVER}"/$"{Application_Image}
    # Output base64 encoded deployment template yaml file content
    appDeploymentYaml=$(cat $appDeploymentTemplate \
        | sed -e "s/\${Project_Name}/${Project_Name}/g" -e "s/\${Application_Replicas}/${Application_Replicas}/g" \
        | sed -e "s#\${Application_Image}#${Application_Image}#g" \
        | sed -e "s#\${Enable_Cookie_Based_Affinity}#${Enable_Cookie_Based_Affinity}#g" \
        | sed -e "s#\${Frontend_Tls_Secret}#${Frontend_Tls_Secret}#g" \
        | base64)
fi

# Write outputs to deployment script output path
result=$(jq -n -c --arg appDeploymentYaml "$appDeploymentYaml" '{appDeploymentYaml: $appDeploymentYaml}')
if [ "$deployApplication" = True ] && [ "$ENABLE_APP_GW_INGRESS" = False ]; then
    result=$(echo "$result" | jq --arg appEndpoint "$appEndpoint" '{"appEndpoint": $appEndpoint} + .')
fi
echo "Result is: $result" >> $logFile
echo $result > $AZ_SCRIPTS_OUTPUT_PATH

# Delete uami generated before
az identity delete --ids ${AZ_SCRIPTS_USER_ASSIGNED_IDENTITY}
