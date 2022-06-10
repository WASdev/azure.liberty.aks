/*
     Copyright (c) Microsoft Corporation.

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

          http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
*/

@description('DNS for ApplicationGateway')
param dnsNameforApplicationGateway string = format('olgw{0}', guidValue)
@description('Public IP Name for the Application Gateway')
param gatewayPublicIPAddressName string = format('gwip{0}', guidValue)
param nameSuffix string = ''
param location string
param guidValue string = take(replace(newGuid(), '-', ''), 6)

var const_nameSuffix = empty(nameSuffix) ? guidValue : nameSuffix
var const_subnetAddressPrefix = '172.16.0.0/28'
var const_virtualNetworkAddressPrefix = '172.16.0.0/24'
var name_appGateway = format('appgw{0}', const_nameSuffix)
var name_appGatewaySubnet = 'appGatewaySubnet'
var name_backendAddressPool = 'myGatewayBackendPool'
var name_frontEndIPConfig = 'appGwPublicFrontendIp'
var name_httpListener = 'HTTPListener'
var name_httpPort = 'httpport'
var name_httpSetting = 'myHTTPSetting'
var name_nsg = format('nsg{0}', const_nameSuffix)
var name_virtualNetwork = format('vnet{0}', const_nameSuffix)
var ref_appGatewaySubnet = resourceId('Microsoft.Network/virtualNetworks/subnets', name_virtualNetwork, name_appGatewaySubnet)
var ref_backendAddressPool = resourceId('Microsoft.Network/applicationGateways/backendAddressPools', name_appGateway, name_backendAddressPool)
var ref_backendHttpSettings = resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', name_appGateway, name_httpSetting)
var ref_frontendHTTPPort = resourceId('Microsoft.Network/applicationGateways/frontendPorts', name_appGateway, name_httpPort)
var ref_frontendIPConfiguration = resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', name_appGateway, name_frontEndIPConfig)
var ref_httpListener = resourceId('Microsoft.Network/applicationGateways/httpListeners', name_appGateway, name_httpListener)

resource nsg 'Microsoft.Network/networkSecurityGroups@2020-07-01' = {
  name: name_nsg
  location: location
  properties: {
    securityRules: [
      {
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '65200-65535'
          sourceAddressPrefix: 'GatewayManager'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 500
          direction: 'Inbound'
        }
        name: 'ALLOW_APPGW'
      }
      {
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 510
          direction: 'Inbound'
          destinationPortRanges: [
            '80'
            '443'
          ]
        }
        name: 'ALLOW_HTTP_ACCESS'
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2020-07-01' = {
  name: name_virtualNetwork
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        const_virtualNetworkAddressPrefix
      ]
    }
    subnets: [
      {
        name: name_appGatewaySubnet
        properties: {
          addressPrefix: const_subnetAddressPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
  dependsOn: [
    nsg
  ]
}

resource gatewayPublicIP 'Microsoft.Network/publicIPAddresses@2020-07-01' = {
  name: gatewayPublicIPAddressName
  sku: {
    name: 'Standard'
  }
  location: location
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: dnsNameforApplicationGateway
    }
  }
}

resource appGateway 'Microsoft.Network/applicationGateways@2020-07-01' = {
  name: name_appGateway
  location: location
  tags: {
    'managed-by-k8s-ingress': 'true'
  }
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
    }
    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: ref_appGatewaySubnet
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: name_frontEndIPConfig
        properties: {
          publicIPAddress: {
            id: gatewayPublicIP.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: name_httpPort
        properties: {
          port: 80
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'myGatewayBackendPool'
      }
    ]
    httpListeners: [
      {
        name: name_httpListener
        properties: {
          protocol: 'Http'
          frontendIPConfiguration: {
            id: ref_frontendIPConfiguration
          }
          frontendPort: {
            id: ref_frontendHTTPPort
          }
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: name_httpSetting
        properties: {
          port: 80
          protocol: 'Http'
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'HTTPRoutingRule'
        properties: {
          httpListener: {
            id: ref_httpListener
          }
          backendAddressPool: {
            id: ref_backendAddressPool
          }
          backendHttpSettings: {
            id: ref_backendHttpSettings
          }
        }
      }
    ]
    webApplicationFirewallConfiguration: {
      enabled: true
      firewallMode: 'Prevention'
      ruleSetType: 'OWASP'
      ruleSetVersion: '3.0'
    }
    enableHttp2: false
    autoscaleConfiguration: {
      minCapacity: 2
      maxCapacity: 3
    }
  }
  dependsOn: [
    vnet
  ]
}

output appGatewayAlias string = reference(gatewayPublicIP.id).dnsSettings.fqdn
output appGatewayName string = name_appGateway
output appGatewayURL string = 'http://${reference(gatewayPublicIP.id).dnsSettings.fqdn}/'
output appGatewaySecuredURL string = 'https://${reference(gatewayPublicIP.id).dnsSettings.fqdn}/'
output vnetName string = name_virtualNetwork
