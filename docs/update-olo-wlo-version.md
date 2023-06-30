<!-- Copyright (c) Microsoft Corporation. -->
<!-- Copyright (c) IBM Corporation. -->

## How to update the version of Open Liberty Operator and WebSphere Liberty Operator

If there are no breaking changes in the new version of Open Liberty Operator / WebSphere Liberty Operator, you can easily update to that version with instructions below:

Update the version of Open Liberty Operator:

1. Open https://github.com/WASdev/azure.liberty.aks/blob/main/src/main/scripts/install.sh
1. Search `OLO_VERSION=`
1. Update its value with new version. For example, if you want to update to version `1.2.0`, specify it as `OLO_VERSION=1.2.0`

Update the version of WebSphere Liberty Operator:

1. Open https://github.com/WASdev/azure.liberty.aks/blob/main/src/main/scripts/install.sh
1. Search `WLO_VERSION=`
1. Update its value with new version. For example, if you want to update to version `1.2.0`, specify it as `WLO_VERSION=1.2.0`

Then bump verion in https://github.com/WASdev/azure.liberty.aks/blob/main/pom.xml#L23:

```
<version>THE_NEW_VERSION</version>
```

Next, you need to run `integration-test` workflow and publish the offer in partner center, pls refer [How to update IBM WebSphere Liberty and Open Liberty on Azure Kubernetes Service solution template offer in partner center](howto-update-offer-in-partner-center.md) for detailed instructions. 

If `integration-test` workflow or manual validation failed, you can go to [Installing the Open Liberty Operator using kustomize](https://github.com/OpenLiberty/open-liberty-operator/blob/main/deploy/releases/1.2.0/kustomize/README.adoc) (use version `1.2.0` as an example) or [Installing WebSphere Liberty operator with kustomize](https://www.ibm.com/docs/en/was-liberty/base?topic=cli-installing-kustomize) for more information, triage and fix accordingly.
