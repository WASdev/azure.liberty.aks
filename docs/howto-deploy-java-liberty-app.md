Based on [Deploy a Java application with Open Liberty or WebSphere Liberty on an Azure Kubernetes Service (AKS) cluster](https://learn.microsoft.com/en-us/azure/aks/howto-deploy-java-liberty-app) at [8a7a0447](https://github.com/MicrosoftDocs/azure-docs-pr/commit/8a7a0447ed4a954a10bacdaf264d8affdce2f2ba).

# Deploy a Java application with Open Liberty or WebSphere Liberty on an Azure Kubernetes Service (AKS) cluster

This workshop demonstrates how to:

* Run your Java, Java EE, Jakarta EE, or MicroProfile application on the Open Liberty or WebSphere Liberty runtime.
* Build the application Docker image using Open Liberty or WebSphere Liberty container images.
* Deploy the containerized application to an AKS cluster using the Open Liberty Operator.

The Open Liberty Operator simplifies the deployment and management of applications running on Kubernetes clusters. With the Open Liberty Operator, you can also perform more advanced operations, such as gathering traces and dumps.

For more information on Open Liberty, see [the Open Liberty project page](https://openliberty.io/). For more information on IBM WebSphere Liberty, see [the WebSphere Liberty product page](https://www.ibm.com/cloud/websphere-liberty).

## Prerequisites
Ensure the following prerequisites to successfully walk through this workshop.
1. Obtain your Azure login credentials, the name of the deployed resource group, and the name of your AKS namespace. A shared AKS cluster with the Liberty Operator installed and a shared registry has already been created for you. 
2. Obtain the shared Azure SQL database name, server name, login, and password.

## Get the cluster name

You will need the name of your AKS cluster.

1. Log into the [Azure portal](https://portal.azure.com) using the credentials you have.
1. In the upper left of any portal page, select the hamburger menu and select **Resource groups**.
1. In the box with the text **Filter for any field**, enter the first few characters of your resource group.
1. In the list of resources in the resource group, find the resource with **Type** of **Kubernetes service**.
1. Note and save aside the name of the resouce.

## Capture information about the registry

You will need to get some information about the registry you will deploy images to.

1. Log into the [Azure portal](https://portal.azure.com) using the credentials you have.
1. In the upper left of any portal page, select the hamburger menu and select **Resource groups**.
1. In the box with the text **Filter for any field**, enter the first few characters of your resource group.
1. In the list of resources in the resource group, select the resource with **Type** of **Container registry**.
1. In the navigation pane, under **Settings** select **Access keys**.
1. Save aside the values for **Login server**, **Registry name**, **Username**, and **password**. You may use the copy icon at the right of each field to copy the value of that field to the system clipboard.

## Configure and deploy the sample application

Follow the steps in this section to deploy the sample application on the Liberty runtime. These steps use Maven.

### Check out the application

Clone the sample code for this workshop. The sample is on [GitHub](https://github.com/m-reza-rahman/open-liberty-on-aks).

```azurecli-interactive
git clone https://github.com/m-reza-rahman/open-liberty-on-aks.git
cd open-liberty-on-aks
```

There are a few samples in the repository. We'll use *java-app/*. Here's the file structure of the application.

```
java-app
├─ src/main/
│  ├─ aks/
│  │  ├─ db-secret.yaml
│  │  ├─ openlibertyapplication.yaml
│  ├─ docker/
│  │  ├─ Dockerfile
│  │  ├─ Dockerfile-wlp
│  ├─ liberty/config/
│  │  ├─ server.xml
│  ├─ java/
│  ├─ resources/
│  ├─ webapp/
├─ pom.xml
```

The directories *java*, *resources*, and *webapp* contain the source code of the sample application. The code declares and uses a data source named `jdbc/JavaEECafeDB`.

In the *aks* directory, we placed two deployment files. *db-secret.xml* is used to create [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/) with DB connection credentials. The file *openlibertyapplication.yaml* is used to deploy the application image. In the *docker* directory, there are two files to create the application image with either Open Liberty or WebSphere Liberty.

In directory *liberty/config*, the *server.xml* file is used to configure the DB connection for the Open Liberty and WebSphere Liberty cluster.

### Build the project

Now that you've gathered the necessary properties, you can build the application. The POM file for the project reads many variables from the environment. As part of the Maven build, these variables are used to populate values in the YAML files located in *src/main/aks*. You can do something similar for your application outside Maven if you prefer.

```bash
cd <path-to-your-repo>/java-app

# The following variables will be used for deployment file generation into target.
export LOGIN_SERVER=<Azure_Container_Registery_Login_Server_URL>
export REGISTRY_NAME=<Azure_Container_Registery_Name>
export USER_NAME=<Azure_Container_Registery_Username>
export PASSWORD=<Azure_Container_Registery_Password>
export DB_SERVER_NAME=<Server name>.database.windows.net
export DB_NAME=<Database name>
export DB_USER=<Server admin login>@<Server name>
export DB_PASSWORD=<Server admin password>
export RESOURCE_GROUP=<The resource group name>
export CLUSTER_NAME=<The AKS cluster name>
export NAMESPACE=<Your unique namespace>

mvn clean package
```

### Test your project locally

You can now run and test the project locally before deploying to Azure. For convenience, we use the `liberty-maven-plugin`. To learn more about the `liberty-maven-plugin`, see [Building a web application with Maven](https://openliberty.io/guides/maven-intro.html). For your application, you can do something similar using any other mechanism, such as your local IDE. You can also consider using the `liberty:devc` option intended for development with containers. You can read more about `liberty:devc` in the [Liberty docs](https://openliberty.io/docs/latest/development-mode.html#_container_support_for_dev_mode).

1. Start the application using `liberty:run`. `liberty:run` will also use the environment variables defined in the previous step.

   ```bash
   cd <path-to-your-repo>/java-app
   mvn liberty:run
   ```

1. Verify the application works as expected. You should see a message similar to `[INFO] [AUDIT] CWWKZ0003I: The application javaee-cafe updated in 1.930 seconds.` in the command output if successful. Go to `http://localhost:9080/` in your browser and verify the application is accessible and all functions are working.

1. Press <kbd>Ctrl</kbd>+<kbd>C</kbd> to stop.

### Build image for AKS deployment

You can now run the `docker build` command to build the image. 

```bash
cd <path-to-your-repo>/java-app/target

# If you're running with Open Liberty
docker build -t javaee-cafe:v1 --pull --file=Dockerfile .

# If you're running with WebSphere Liberty
docker build -t javaee-cafe:v1 --pull --file=Dockerfile-wlp .
```

### Test the Docker image locally

You can now use the following steps to test the Docker image locally before deploying to Azure.

1. Run the image using the following command. Note we're using the environment variables defined previously.

   ```bash
   docker run -it --rm -p 9080:9080 \
       -e DB_SERVER_NAME=${DB_SERVER_NAME} \
       -e DB_NAME=${DB_NAME} \
       -e DB_USER=${DB_USER} \
       -e DB_PASSWORD=${DB_PASSWORD} \
       javaee-cafe:v1
   ```

1. Once the container starts, go to `http://localhost:9080/` in your browser to access the application.

1. Press <kbd>Ctrl</kbd>+<kbd>C</kbd> to stop.

### Upload image to ACR

Now, we upload the built image to the Azure Container Registry (ACR) instance.

```bash
docker tag javaee-cafe:v1 ${LOGIN_SERVER}/javaee-cafe:${NAMESPACE}-v1
docker login -u ${USER_NAME} -p ${PASSWORD} ${LOGIN_SERVER}
docker push ${LOGIN_SERVER}/javaee-cafe:${NAMESPACE}-v1
```

### Deploy the application

The following steps deploy and test the application.

1. Log in to Azure via the CLI using your credentials.

   ```bash
   az login
   ```

1. Connect to the AKS cluster.

   ```bash
   az aks get-credentials --resource-group ${RESOURCE_GROUP} --name ${CLUSTER_NAME}
   ```

1. Apply the DB secret.

   ```bash
   cd <path-to-your-repo>/java-app/target
   kubectl apply -f db-secret.yaml
   ```

   You'll see the output `secret/db-secret-postgres created`.

1. Apply the deployment file.

   ```bash
   kubectl apply -f openlibertyapplication.yaml
   ```

1. Wait until all pods are restarted successfully using the following command.

   ```bash
   kubectl get pods -n ${NAMESPACE} --watch
   ```

   You should see output similar to the following to indicate that all the pods are running.

   ```output
   NAME                                       READY   STATUS    RESTARTS   AGE
   javaee-cafe-cluster-67cdc95bc-2j2gr   1/1     Running   0          29s
   javaee-cafe-cluster-67cdc95bc-fgtt8   1/1     Running   0          29s
   javaee-cafe-cluster-67cdc95bc-h47qm   1/1     Running   0          29s
   ```

### Test the application

When the application runs, a Kubernetes load balancer service exposes the application front end to the internet. This process can take a while to complete.

To monitor progress, use the [kubectl get service](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#get) command with the `--watch` argument.

```bash
kubectl get services -n ${NAMESPACE} --watch
```

You should see output like the following.

```output
NAME                        TYPE           CLUSTER-IP     EXTERNAL-IP     PORT(S)          AGE
javaee-cafe-cluster         LoadBalancer   10.0.251.169   52.152.189.57   80:31732/TCP     68s
```

Once the *EXTERNAL-IP* address changes from *pending* to an actual public IP address, use <kbd>Ctrl</kbd>+<kbd>C</kbd> to stop the `kubectl` watch process.

Open a web browser to the external IP address of your service (`52.152.189.57` for the above example) to see the application home page. You should see the pod name of your application replicas displayed at the top-left of the page. Wait for a few minutes and refresh the page to see a different pod name displayed due to load balancing provided by the AKS cluster.

## Next steps

* [Azure Kubernetes Service](https://azure.microsoft.com/free/services/kubernetes-service/)
* [Open Liberty](https://openliberty.io/)
* [Open Liberty Operator](https://github.com/OpenLiberty/open-liberty-operator)
* [Open Liberty Server Configuration](https://openliberty.io/docs/ref/config/)
