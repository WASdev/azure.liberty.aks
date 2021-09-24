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

wait_deployment_complete() {
    deploymentName=$1
    namespaceName=$2
    logFile=$3

    kubectl get deployment ${deploymentName} -n ${namespaceName}
    while [ $? -ne 0 ]
    do
        echo "Wait until the deployment ${deploymentName} created..." >> $logFile
        sleep 5
        kubectl get deployment ${deploymentName} -n ${namespaceName}
    done
    read -r -a replicas <<< `kubectl get deployment ${deploymentName} -n ${namespaceName} -o=jsonpath='{.spec.replicas}{" "}{.status.readyReplicas}{" "}{.status.availableReplicas}{" "}{.status.updatedReplicas}{"\n"}'`
    while [[ ${#replicas[@]} -ne 4 || ${replicas[0]} != ${replicas[1]} || ${replicas[1]} != ${replicas[2]} || ${replicas[2]} != ${replicas[3]} ]]
    do
        # Delete pods in ImagePullBackOff status
        podIds=`kubectl get pod -n ${namespaceName} | grep ImagePullBackOff | awk '{print $1}'`
        read -r -a podIds <<< `echo $podIds`
        for podId in "${podIds[@]}"
        do
            echo "Delete pod ${podId} in ImagePullBackOff status" >> $logFile
            kubectl delete pod ${podId} -n ${namespaceName}
        done

        sleep 5
        echo "Wait until the deployment ${deploymentName} completes..." >> $logFile
        read -r -a replicas <<< `kubectl get deployment ${deploymentName} -n ${namespaceName} -o=jsonpath='{.spec.replicas}{" "}{.status.readyReplicas}{" "}{.status.availableReplicas}{" "}{.status.updatedReplicas}{"\n"}'`
    done
    echo "Deployment ${deploymentName} completed." >> $logFile
}

clusterRGName=$1
clusterName=$2
acrName=$3
uploadAppPackage=$4
appPackageUrl=$5
export Context_Root=$6
useOpenLibertyImage=$7
useJava8=$8
export Application_Name=$9
export Project_Name=${10}
export Application_Image=${11}
export Application_Replicas=${12}
logFile=deployment.log

# Install utilities
apk update
apk add gettext
apk add docker-cli

# Install `kubectl` and connect to the AKS cluster
az aks install-cli
az aks get-credentials -g $clusterRGName -n $clusterName --overwrite-existing >> $logFile

# Install Open Liberty Operator V0.7.1
version=0.7.1
OPERATOR_NAMESPACE=default
WATCH_NAMESPACE='""'
kubectl apply -f https://raw.githubusercontent.com/OpenLiberty/open-liberty-operator/master/deploy/releases/${version}/openliberty-app-crd.yaml
curl -L https://raw.githubusercontent.com/OpenLiberty/open-liberty-operator/master/deploy/releases/${version}/openliberty-app-cluster-rbac.yaml \
    | sed -e "s/OPEN_LIBERTY_OPERATOR_NAMESPACE/${OPERATOR_NAMESPACE}/" \
    | kubectl apply -f - >> $logFile
curl -L https://raw.githubusercontent.com/OpenLiberty/open-liberty-operator/master/deploy/releases/${version}/openliberty-app-operator.yaml \
    | sed -e "s/OPEN_LIBERTY_WATCH_NAMESPACE/${WATCH_NAMESPACE}/" \
    | kubectl apply -n ${OPERATOR_NAMESPACE} -f - >> $logFile
wait_deployment_complete open-liberty-operator $OPERATOR_NAMESPACE ${logFile}

# Create project namespace
kubectl create namespace ${Project_Name} >> $logFile

# Log into the ACR
LOGIN_SERVER=$(az acr show -n $acrName --query 'loginServer' -o tsv)
USER_NAME=$(az acr credential show -n $acrName --query 'username' -o tsv)
PASSWORD=$(az acr credential show -n $acrName --query 'passwords[0].value' -o tsv)
docker login $LOGIN_SERVER -u $USER_NAME -p $PASSWORD >> $logFile

# Determine base image
export Base_Image=
if [ "$useOpenLibertyImage" = True ] && [ "$useJava8" = True ]; then
    Base_Image="openliberty/open-liberty:kernel-java8-openj9-ubi"
elif [ "$useOpenLibertyImage" = True ] && [ "$useJava8" = False ]; then
    Base_Image="openliberty/open-liberty:kernel-java11-openj9-ubi"
elif [ "$useOpenLibertyImage" = False ] && [ "$useJava8" = True ]; then
    Base_Image="ibmcom/websphere-liberty:kernel-java8-openj9-ubi"
else
    Base_Image="ibmcom/websphere-liberty:kernel-java11-openj9-ubi"
fi
echo "Base_Image: $Base_Image" >> $logFile

# Build application image or use default base image
if [ "$uploadAppPackage" = True ]; then
    # Prepare artifacts for building image
    export Application_Package=${Application_Name}.war
    wget -O ${Application_Package} "$appPackageUrl"
    envsubst < "server.xml.template" > "server.xml"
    appServerXml=$(cat server.xml | base64)

    # Determine docker file template
    if [ "$useOpenLibertyImage" = True ]; then
        dockerFileTemplate=Dockerfile.template
    else
        dockerFileTemplate=Dockerfile-wlp.template
    fi
    echo "dockerFileTemplate: $dockerFileTemplate" >> $logFile
    envsubst < "$dockerFileTemplate" > "Dockerfile"
    appDockerfile=$(cat Dockerfile | base64)

    # Build application image with Open Liberty or WebSphere Liberty base image
    az acr build -t ${Application_Image} -r $acrName . >> $logFile

    # Create image pull secret
    export Pull_Secret=${Application_Name}-secret
    kubectl create secret docker-registry ${Pull_Secret} \
        --docker-server=${LOGIN_SERVER} \
        --docker-username=${USER_NAME} \
        --docker-password=${PASSWORD} \
        --namespace=${Project_Name} >> $logFile

    Application_Image=${LOGIN_SERVER}/${Application_Image}
else
    Context_Root=/

    # Remove image pull secret
    sed -i "/pullSecret/d" open-liberty-application.yaml.template

    Application_Image=$(echo "${Base_Image/kernel/full}")
fi

# Deploy openliberty application
envsubst < "open-liberty-application.yaml.template" > "open-liberty-application.yaml"
appDeploymentYaml=$(cat open-liberty-application.yaml | base64)
kubectl apply -f open-liberty-application.yaml >> $logFile

# Wait until the application deployment completes
wait_deployment_complete ${Application_Name} ${Project_Name} ${logFile}

# Get public IP address and port for the application service
kubectl get svc ${Application_Name} -n ${Project_Name}
while [ $? -ne 0 ]
do
    sleep 5
    echo "Wait until the service ${Application_Name} created..." >> $logFile
    kubectl get svc ${Application_Name} -n ${Project_Name}
done
appEndpoint=$(kubectl get svc ${Application_Name} -n ${Project_Name} -o=jsonpath='{.status.loadBalancer.ingress[0].ip}:{.spec.ports[0].port}')
echo "ip:port is ${appEndpoint}" >> $logFile
while [[ $appEndpoint = :* ]] || [[ -z $appEndpoint ]]
do
    sleep 5
    echo "Wait until the IP address is created for service ${Application_Name}..." >> $logFile
    appEndpoint=$(kubectl get svc ${Application_Name} -n ${Project_Name} -o=jsonpath='{.status.loadBalancer.ingress[0].ip}:{.spec.ports[0].port}')
    echo "ip:port is ${appEndpoint}" >> $logFile
done
appEndpoint=$(echo ${appEndpoint}${Context_Root})

# Output application endpoint
result=$(jq -n -c --arg appEndpoint $appEndpoint '{appEndpoint: $appEndpoint}')
if [ "$uploadAppPackage" = True ]; then
    result=$(echo "$result" | jq --arg appServerXml "$appServerXml" '{"appServerXml": $appServerXml} + .')
    result=$(echo "$result" | jq --arg appDockerfile "$appDockerfile" '{"appDockerfile": $appDockerfile} + .')
fi
result=$(echo "$result" | jq --arg appDeploymentYaml "$appDeploymentYaml" '{"appDeploymentYaml": $appDeploymentYaml} + .')
echo "Result is: $result" >> $logFile
echo $result > $AZ_SCRIPTS_OUTPUT_PATH