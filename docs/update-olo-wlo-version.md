## How to update the version of Open Liberty Operator and WebSphere Liberty Operator

Follow instructions below to update the version of Open Liberty Operator:

1. Open https://github.com/WASdev/azure.liberty.aks/blob/main/src/main/scripts/install.sh
1. Search `OLO_VERSION=`
1. Update its value with new version. For example, if you want to update to version `0.8.2`, specify it as `OLO_VERSION=0.8.2`

Follow instructions below to update the version of WebSphere Liberty Operator:

1. Open https://github.com/WASdev/azure.liberty.aks/blob/main/src/main/scripts/install.sh
1. Search `WLO_VERSION=`
1. Update its value with new version. For example, if you want to update to version `1.1.0`, specify it as `WLO_VERSION=1.1.0`

At the end, bump verion in https://github.com/WASdev/azure.liberty.aks/blob/main/pom.xml#L23:

```
<version>THE_NEW_VERSION</version>
```