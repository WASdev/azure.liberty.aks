# Deploy a Java application with Open Liberty or WebSphere Liberty on an Azure Kubernetes Service (AKS) cluster

## Prerequisites

1. You will need an Azure subscription. If you don't have one, you can get one for free for one year [here](https://azure.microsoft.com/free).
1. Install a Java SE implementation (for example, [AdoptOpenJDK OpenJDK 8 LTS/OpenJ9](https://adoptopenjdk.net/?variant=openjdk8&jvmVariant=openj9)).
1. Install [Maven](https://maven.apache.org/download.cgi) 3.5.0 or higher.
1. Install [Docker](https://docs.docker.com/get-docker/) for your OS.
1. Install [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli?view=azure-cli-latest&preserve-view=true) 2.0.75 or later.
1. Install [`jq`](https://stedolan.github.io/jq/download/)

## Steps of deployment

1. Checkout [azure-javaee-iaas](https://github.com/Azure/azure-javaee-iaas)
   1. Change to directory hosting the repo project & run `mvn clean install`
1. Checkout [arm-ttk](https://github.com/Azure/arm-ttk) under the specified parent directory
1. Checkout this repo under the same parent directory and change to directory hosting the repo project
1. Build the project by replacing all placeholder `${<place_holder>}` with valid values
   1. Create a new AKS cluster and a new Azure Container Registry (ACR) instance:

      ```bash

      mvn -Dgit.repo=<repo_user> -Dgit.tag=<repo_tag> -DidentityId=<user-assigned-managed-identity-id> -DcreateAKSCluster=true -DcreateACR=true -DuseOpenLibertyImage=<true or false> -DappReplicas=<number of replicas> -Dtest.args="-Test All" -Ptemplate-validation-tests clean install
      ```

   1. Or use an existing AKS cluster and an existing ACR instance:

      ```bash

      mvn -Dgit.repo=<repo_user> -Dgit.tag=<repo_tag> -DidentityId=<user-assigned-managed-identity-id> -DcreateAKSCluster=false -DaksClusterName=<aks-cluster-name> -DaksClusterRGName=<cluster-group-name> -DcreateACR=false -DacrName=<acr-instance-name> -DuseOpenLibertyImage=<true or false> -DappReplicas=<number of replicas> -Dtest.args="-Test All" -Ptemplate-validation-tests clean install
      ```

1. Change to `./target/arm` directory
1. Using `deploy.azcli` to deploy the application package to AKS cluster

   ```bash
   ./deploy.azcli -n <deploymentName> -i <subscriptionId> -g <resourceGroupName> -l <resourceGroupLocation> -f <application-package-path> 
   ```

## After deployment

1. If you check the resource group `resourceGroupName` in [Azure portal](https://portal.azure.com/), you will see related resources created:
   1. An new AKS cluster if it's specified;
   1. An new ACR instance if it's specified;
   1. An deployment script instance;
1. To visit the application home page:
   1. Open the resource group `resourceGroupName`;
   1. Navigate to "Deployments > `deploymentName` > Outputs";
   1. Copy value of property `result > applicationEndpoint` and open it in the browser;
