// Application Gateway with path-based routing. One public IP, five backends.
param location string = resourceGroup().location
param vnetName string
param subnetName string = 'agw-subnet'
param appsDomain string
param gatewayName string = 'shoplite-agw'

var gwId = resourceId('Microsoft.Network/applicationGateways', gatewayName)

var services = [
  { name: 'auth', host: 'auth.${appsDomain}', probePath: '/api/auth/health' }
  { name: 'catalogue', host: 'catalogue.${appsDomain}', probePath: '/api/catalogue/health' }
  { name: 'checkout', host: 'checkout.${appsDomain}', probePath: '/api/checkout/health' }
  { name: 'notify', host: 'notify.${appsDomain}', probePath: '/api/notify/health' }
  { name: 'web', host: 'web.${appsDomain}', probePath: '/healthz' }
]

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: vnetName
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: vnet
  name: subnetName
}

resource pip 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: '${gatewayName}-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource agw 'Microsoft.Network/applicationGateways@2023-11-01' = {
  name: gatewayName
  location: location
  properties: {
    sku: {
      name: 'Standard_v2'
      tier: 'Standard_v2'
      capacity: 1
    }
    gatewayIPConfigurations: [
      {
        name: 'gateway-ip'
        properties: {
          subnet: {
            id: subnet.id
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'public'
        properties: {
          publicIPAddress: {
            id: pip.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port80'
        properties: {
          port: 80
        }
      }
    ]
    backendAddressPools: [for s in services: {
      name: 'pool-${s.name}'
      properties: {
        backendAddresses: [
          {
            fqdn: s.host
          }
        ]
      }
    }]
    probes: [for s in services: {
      name: 'probe-${s.name}'
      properties: {
        protocol: 'Http'
        path: s.probePath
        interval: 30
        timeout: 30
        unhealthyThreshold: 3
        pickHostNameFromBackendHttpSettings: true
      }
    }]
    backendHttpSettingsCollection: [for s in services: {
      name: 'settings-${s.name}'
      properties: {
        port: 80
        protocol: 'Http'
        cookieBasedAffinity: 'Disabled'
        requestTimeout: 60
        pickHostNameFromBackendAddress: true
        probe: {
          id: '${gwId}/probes/probe-${s.name}'
        }
      }
    }]
    httpListeners: [
      {
        name: 'listener80'
        properties: {
          frontendIPConfiguration: {
            id: '${gwId}/frontendIPConfigurations/public'
          }
          frontendPort: {
            id: '${gwId}/frontendPorts/port80'
          }
          protocol: 'Http'
        }
      }
    ]
    urlPathMaps: [
      {
        name: 'shop-paths'
        properties: {
          defaultBackendAddressPool: {
            id: '${gwId}/backendAddressPools/pool-web'
          }
          defaultBackendHttpSettings: {
            id: '${gwId}/backendHttpSettingsCollection/settings-web'
          }
          pathRules: [
            {
              name: 'auth'
              properties: {
                paths: [
                  '/api/auth/*'
                ]
                backendAddressPool: {
                  id: '${gwId}/backendAddressPools/pool-auth'
                }
                backendHttpSettings: {
                  id: '${gwId}/backendHttpSettingsCollection/settings-auth'
                }
              }
            }
            {
              name: 'catalogue'
              properties: {
                paths: [
                  '/api/catalogue/*'
                ]
                backendAddressPool: {
                  id: '${gwId}/backendAddressPools/pool-catalogue'
                }
                backendHttpSettings: {
                  id: '${gwId}/backendHttpSettingsCollection/settings-catalogue'
                }
              }
            }
            {
              name: 'checkout'
              properties: {
                paths: [
                  '/api/checkout/*'
                ]
                backendAddressPool: {
                  id: '${gwId}/backendAddressPools/pool-checkout'
                }
                backendHttpSettings: {
                  id: '${gwId}/backendHttpSettingsCollection/settings-checkout'
                }
              }
            }
            {
              name: 'notify'
              properties: {
                paths: [
                  '/api/notify/*'
                  '/socket.io/*'
                ]
                backendAddressPool: {
                  id: '${gwId}/backendAddressPools/pool-notify'
                }
                backendHttpSettings: {
                  id: '${gwId}/backendHttpSettingsCollection/settings-notify'
                }
              }
            }
          ]
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'route-by-path'
        properties: {
          ruleType: 'PathBasedRouting'
          priority: 100
          httpListener: {
            id: '${gwId}/httpListeners/listener80'
          }
          urlPathMap: {
            id: '${gwId}/urlPathMaps/shop-paths'
          }
        }
      }
    ]
  }
}

output ip string = pip.properties.ipAddress
