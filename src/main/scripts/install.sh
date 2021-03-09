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

resourceGroupName=$1
aksClusterName=$2
acrName=$3
uploadAppPackage=$4
appPackageUrl=$5
contextRoot=$6
useOpenLibertyImage=$7
useJava8=$8
appReplicas=$9
appName=${10}

# Install utilities
apk update
apk add gettext
apk add docker-cli

# Install `kubectl` and connect to the AKS cluster
az aks install-cli
az aks get-credentials -g $resourceGroupName -n $aksClusterName --overwrite-existing

# Install Open Liberty Operator V0.7
OPERATOR_NAMESPACE=default
WATCH_NAMESPACE='""'
kubectl apply -f https://raw.githubusercontent.com/OpenLiberty/open-liberty-operator/master/deploy/releases/0.7.0/openliberty-app-crd.yaml
curl -L https://raw.githubusercontent.com/OpenLiberty/open-liberty-operator/master/deploy/releases/0.7.0/openliberty-app-cluster-rbac.yaml \
      | sed -e "s/OPEN_LIBERTY_OPERATOR_NAMESPACE/${OPERATOR_NAMESPACE}/" \
      | kubectl apply -f -
curl -L https://raw.githubusercontent.com/OpenLiberty/open-liberty-operator/master/deploy/releases/0.7.0/openliberty-app-operator.yaml \
      | sed -e "s/OPEN_LIBERTY_WATCH_NAMESPACE/${WATCH_NAMESPACE}/" \
      | kubectl apply -n ${OPERATOR_NAMESPACE} -f -

# Log into the ACR
LOGIN_SERVER=$(az acr show -n $acrName --query 'loginServer' -o tsv)
USER_NAME=$(az acr credential show -n $acrName --query 'username' -o tsv)
PASSWORD=$(az acr credential show -n $acrName --query 'passwords[0].value' -o tsv)
docker login $LOGIN_SERVER -u $USER_NAME -p $PASSWORD

# Copy templates to /tmp for customization
cp server.xml.template /tmp
cp Dockerfile.template /tmp
cp Dockerfile-wlp.template /tmp
cp openlibertyapplication.yaml.template /tmp
cd /tmp

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

# Build application image or use default base image
export Application_Name=$appName
if [ "$uploadAppPackage" = True ]; then
      export Context_Root=$contextRoot

      # Prepare artifacts for building image
      export Application_Package=${appName}.war
      wget -O ${Application_Package} "$appPackageUrl"

      envsubst < "server.xml.template" > "server.xml"
      envsubst < "Dockerfile.template" > "Dockerfile"
      envsubst < "Dockerfile-wlp.template" > "Dockerfile-wlp"

      # Build application image with Open Liberty or WebSphere Liberty base image
      if [ "$useOpenLibertyImage" = True ]; then
            az acr build -t ${Application_Name}:1.0.0 -r $acrName .
      else
            az acr build -t ${Application_Name}:1.0.0 -r $acrName -f Dockerfile-wlp .
      fi

      # Create image pull secret
      export Pull_Secret=${Application_Name}-secret
      kubectl create secret docker-registry ${Pull_Secret} \
            --docker-server=${LOGIN_SERVER} \
            --docker-username=${USER_NAME} \
            --docker-password=${PASSWORD}

      export Application_Image=${LOGIN_SERVER}/${Application_Name}:1.0.0
else
      export Context_Root=/
      
      # Remove image pull secret
      sed -i "/pullSecret/d" openlibertyapplication.yaml.template
      
      export Application_Image=$(echo "${Base_Image/kernel/full}")
fi

# Deploy openliberty application
export Application_Replicas=$appReplicas
envsubst < openlibertyapplication.yaml.template | kubectl create -f -

# Wait until the deployment completes
kubectl get deployment ${Application_Name}
while [ $? -ne 0 ]
do
      sleep 5
      kubectl get deployment ${Application_Name}
done
replicas=$(kubectl get deployment ${Application_Name} -o=jsonpath='{.spec.replicas}')
readyReplicas=$(kubectl get deployment ${Application_Name} -o=jsonpath='{.status.readyReplicas}')
availableReplicas=$(kubectl get deployment ${Application_Name} -o=jsonpath='{.status.availableReplicas}')
updatedReplicas=$(kubectl get deployment ${Application_Name} -o=jsonpath='{.status.updatedReplicas}')
while [[ $replicas != $readyReplicas || $readyReplicas != $availableReplicas || $availableReplicas != $updatedReplicas ]]
do
      sleep 5
      echo retry
      replicas=$(kubectl get deployment ${Application_Name} -o=jsonpath='{.spec.replicas}')
      readyReplicas=$(kubectl get deployment ${Application_Name} -o=jsonpath='{.status.readyReplicas}')
      availableReplicas=$(kubectl get deployment ${Application_Name} -o=jsonpath='{.status.availableReplicas}')
      updatedReplicas=$(kubectl get deployment ${Application_Name} -o=jsonpath='{.status.updatedReplicas}')
done
kubectl get svc ${Application_Name}
while [ $? -ne 0 ]
do
      sleep 5
      kubectl get svc ${Application_Name}
done
Application_Endpoint=$(kubectl get svc ${Application_Name} -o=jsonpath='{.status.loadBalancer.ingress[0].ip}:{.spec.ports[0].port}')
while [[ $Application_Endpoint = :* ]]
do
      sleep 5
      echo retry
      Application_Endpoint=$(kubectl get svc ${Application_Name} -o=jsonpath='{.status.loadBalancer.ingress[0].ip}:{.spec.ports[0].port}')
done
Application_Endpoint=$(echo ${Application_Endpoint}${Context_Root})

# Output application endpoint
echo "endpoint is: $Application_Endpoint"
result=$(jq -n -c --arg endpoint $Application_Endpoint '{applicationEndpoint: $endpoint}')
echo "result is: $result"
echo $result > $AZ_SCRIPTS_OUTPUT_PATH
