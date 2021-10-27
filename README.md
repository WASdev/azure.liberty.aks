# Related Repositories

* [tWAS cluster on Azure VMs](https://github.com/WASdev/azure.websphere-traditional.cluster)
* [Base images used in tWAS cluster](https://github.com/WASdev/azure.websphere-traditional.image)
* [Liberty on ARO](https://github.com/WASdev/azure.liberty.aro)



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

      mvn -Dgit.repo=<repo_user> -Dgit.tag=<repo_tag> -DidentityId=<user-assigned-managed-identity-id> -DcreateCluster=true -DcreateACR=true -DdeployApplication=<true|false> -DappImagePath=<app-image-path> -DappReplicas=<number of replicas> -Dtest.args="-Test All" -Ptemplate-validation-tests clean install
      ```

   1. Or use an existing AKS cluster and an existing ACR instance:

      ```bash

      mvn -Dgit.repo=<repo_user> -Dgit.tag=<repo_tag> -DidentityId=<user-assigned-managed-identity-id> -DcreateCluster=false -DclusterName=<aks-cluster-name> -DclusterRGName=<cluster-group-name> -DcreateACR=false -DacrName=<acr-instance-name> -DdeployApplication=<true|false> -DappImagePath=<app-image-path> -DappReplicas=<number of replicas> -Dtest.args="-Test All" -Ptemplate-validation-tests clean install
      ```

1. Change to `./target/cli` directory
1. Using `deploy.azcli` to deploy the application package to AKS cluster

   ```bash
   ./deploy.azcli -n <deploymentName> -i <subscriptionId> -g <resourceGroupName> -l <resourceGroupLocation> 
   ```

## After deployment

1. If you check the resource group `resourceGroupName` in [Azure portal](https://portal.azure.com/), you will see related resources created:
   1. A new AKS cluster if it's specified;
   1. A new ACR instance if it's specified;
   1. A deployment script instance;
1. To visit the application home page:
   1. Open the resource group `resourceGroupName`;
   1. Navigate to "Deployments > `deploymentName` > Outputs";
   1. Copy value of property `appEndpoint` > append context root defined in the 'server.xml' of your application if it's not equal to '/' > open it in the browser;
