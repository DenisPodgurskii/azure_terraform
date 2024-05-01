# Create a resource group for the Event Hub
resource "azurerm_resource_group" "splunk_logs_rg" {
  name     = "splunkResourceGroup"
  location = "East US"
}

# Create an Event Hub Namespace
resource "azurerm_eventhub_namespace" "splunk_log_hub_namespace" {
  name                = "splunkLogHubNamespace"
  location            = azurerm_resource_group.splunk_logs_rg.location
  resource_group_name = azurerm_resource_group.splunk_logs_rg.name
  sku                 = "Standard"
  capacity            = 1
}

# Create an Event Hub within the namespace
resource "azurerm_eventhub" "splunk_log_event_hub" {
  name                = "splunkLogEventHub"
  namespace_name      = azurerm_eventhub_namespace.splunk_log_hub_namespace.name
  resource_group_name = azurerm_resource_group.splunk_logs_rg.name
  partition_count     = 2
  message_retention   = 1
}

data "azurerm_eventhub_namespace_authorization_rule" "SharedAccessKey" {
  name                = "RootManageSharedAccessKey"
  namespace_name      = azurerm_eventhub_namespace.splunk_log_hub_namespace.name
  resource_group_name = azurerm_resource_group.splunk_logs_rg.name
}

# Create an Event Hub Authorization Rule
resource "azurerm_eventhub_authorization_rule" "splunk_log_hub_auth_rule" {
  name                = "RootManageSharedAccessKey"
  namespace_name      = azurerm_eventhub_namespace.splunk_log_hub_namespace.name
  eventhub_name       = azurerm_eventhub.splunk_log_event_hub.name
  resource_group_name = azurerm_resource_group.splunk_logs_rg.name
  listen              = true
  send                = true
  manage              = true
  depends_on = [
    azurerm_eventhub_namespace.splunk_log_hub_namespace,
  ]
}


data "azurerm_subscription" "current" {}

# Apply BuiltIn initiative/policy set - https://www.azadvertizer.net/azpolicyinitiativesadvertizer/1020d527-2764-4230-92cc-7035e4fcf8a7.html
#
# TODO - use SystemAssigned identity or create and manage it
#
data "azurerm_policy_set_definition" "auditLoggingEventHub" {
  display_name = "Enable audit category group resource logging for supported resources to Event Hub"
}

resource "azurerm_subscription_policy_assignment" "subscriptionPolicyAssignment" {
  name                 = "subscriptionPolicyAssignment"
  policy_definition_id = data.azurerm_policy_set_definition.auditLoggingEventHub.id
  subscription_id      = data.azurerm_subscription.current.id

  parameters = jsonencode({
    "resourceLocation" = {
      "value" = azurerm_resource_group.splunk_logs_rg.location
    },
    "eventHubAuthorizationRuleId" = {
      "value" = data.azurerm_eventhub_namespace_authorization_rule.SharedAccessKey.id
    },
    "eventHubName" = {
      "value" = azurerm_eventhub.splunk_log_event_hub.name
    }
  })
  location = azurerm_resource_group.splunk_logs_rg.location
  identity {
    type = "SystemAssigned"
  }

}

# Apply custom policy - https://www.azadvertizer.net/azpolicyadvertizer/b2215d7b-25ea-411f-8b04-8c30dc61bad9.html
#
# TODO - use SystemAssigned identity or create and manage it
# TODO - deployment section has location hardcoded to eastus
#
resource "azurerm_policy_definition" "activityLogsEventHub" {
  name         = "activityLogsEventHub"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Configure Azure Activity logs to stream to specified Event Hub v2"

  metadata = <<METADATA
    {
      "version": "1.0.0",
      "category": "App Service"
    }
    METADATA

  policy_rule = <<POLICY_RULE
    {

        "if": {
          "field": "type",
          "equals": "Microsoft.Resources/subscriptions"
        },
        "then": {
          "effect": "[parameters(‘effect’)]",
          "details": {
            "type": "Microsoft.Insights/diagnosticSettings",
            "deploymentScope": "subscription",
            "existenceScope": "subscription",
            "name": "[parameters(‘profileName’)]",
            "existenceCondition": {
              "allOf": [
                {
                  "field": "Microsoft.Insights/diagnosticSettings/eventHubAuthorizationRuleId",
                  "equals": "[parameters(‘eventHubAuthorizationRuleId’)]"
                },
                {
                  "field": "Microsoft.Insights/diagnosticSettings/eventHubName",
                  "equals": "[parameters(‘eventHubName’)]"
                },
                {
                  "count": {
                    "field": "Microsoft.Insights/diagnosticSettings/logs[*]",
                    "where": {
                      "anyOf": [
                        {
                          "allOf": [
                            {
                              "field": "Microsoft.Insights/diagnosticSettings/logs[*].category",
                              "like": "Administrative"
                            },
                            {
                              "field": "Microsoft.Insights/diagnosticSettings/logs[*].enabled",
                              "notEquals": "[parameters(‘administrativeLogsEnabled’)]"
                            }
                          ]
                        },
                        {
                          "AllOf": [
                            {
                              "field": "Microsoft.Insights/diagnosticSettings/logs[*].category",
                              "like": "Alert"
                            },
                            {
                              "field": "Microsoft.Insights/diagnosticSettings/logs[*].enabled",
                              "notEquals": "[parameters(‘alertLogsEnabled’)]"
                            }
                          ]
                        },
                        {
                          "AllOf": [
                            {
                              "field": "Microsoft.Insights/diagnosticSettings/logs[*].category",
                              "like": "Autoscale"
                            },
                            {
                              "field": "Microsoft.Insights/diagnosticSettings/logs[*].enabled",
                              "notEquals": "[parameters(‘autoscaleLogsEnabled’)]"
                            }
                          ]
                        },
                        {
                          "AllOf": [
                            {
                              "field": "Microsoft.Insights/diagnosticSettings/logs[*].category",
                              "like": "Policy"
                            },
                            {
                              "field": "Microsoft.Insights/diagnosticSettings/logs[*].enabled",
                              "notEquals": "[parameters(‘policyLogsEnabled’)]"
                            }
                          ]
                        },
                        {
                          "AllOf": [
                            {
                              "field": "Microsoft.Insights/diagnosticSettings/logs[*].category",
                              "like": "Recommendation"
                            },
                            {
                              "field": "Microsoft.Insights/diagnosticSettings/logs[*].enabled",
                              "notEquals": "[parameters(‘recommendationLogsEnabled’)]"
                            }
                          ]
                        },
                        {
                          "AllOf": [
                            {
                              "field": "Microsoft.Insights/diagnosticSettings/logs[*].category",
                              "like": "ResourceHealth"
                            },
                            {
                              "field": "Microsoft.Insights/diagnosticSettings/logs[*].enabled",
                              "notEquals": "[parameters(‘resourceHealthLogsEnabled’)]"
                            }
                          ]
                        },
                        {
                          "AllOf": [
                            {
                              "field": "Microsoft.Insights/diagnosticSettings/logs[*].category",
                              "like": "Security"
                            },
                            {
                              "field": "Microsoft.Insights/diagnosticSettings/logs[*].enabled",
                              "notEquals": "[parameters(‘securityLogsEnabled’)]"
                            }
                          ]
                        },
                        {
                          "AllOf": [
                            {
                              "field": "Microsoft.Insights/diagnosticSettings/logs[*].category",
                              "like": "ServiceHealth"
                            },
                            {
                              "field": "Microsoft.Insights/diagnosticSettings/logs[*].enabled",
                              "notEquals": "[parameters(‘serviceHealthLogsEnabled’)]"
                            }
                          ]
                        }
                      ]
                    }
                  },
                  "equals": 0
                }
              ]
            },
            "deployment": {
              "location": "eastus",
              "properties": {
                "mode": "incremental",
                "template": {
                  "$schema": "https://schema.management.azure.com/schemas/2018-05-01/subscriptionDeploymentTemplate.json#",
                  "contentVersion": "1.0.0.0",
                  "parameters": {
                    "profileName": {
                      "type": "string"
                    },
                    "eventHubAuthorizationRuleId": {
                      "type": "string"
                    },
                    "eventHubName": {
                      "type": "string"
                    },
                    "administrativeLogsEnabled": {
                      "type": "string"
                    },
                    "alertLogsEnabled": {
                      "type": "string"
                    },
                    "autoscaleLogsEnabled": {
                      "type": "string"
                    },
                    "policyLogsEnabled": {
                      "type": "string"
                    },
                    "recommendationLogsEnabled": {
                      "type": "string"
                    },
                    "resourceHealthLogsEnabled": {
                      "type": "string"
                    },
                    "securityLogsEnabled": {
                      "type": "string"
                    },
                    "serviceHealthLogsEnabled": {
                      "type": "string"
                    }
                  },
                  "variables": {},
                  "resources": [
                    {
                      "name": "[parameters(‘profileName’)]",
                      "type": "Microsoft.Insights/diagnosticSettings",
                      "apiVersion": "2017-05-01-preview",
                      "location": "Global",
                      "properties": {
                        "eventHubAuthorizationRuleId": "[parameters(‘eventHubAuthorizationRuleId’)]",
                        "eventHubName": "[parameters(‘eventHubName’)]",
                        "logs": [
                          {
                            "category": "Administrative",
                            "enabled": "[parameters(‘administrativeLogsEnabled’)]"
                          },
                          {
                            "category": "Alert",
                            "enabled": "[parameters(‘alertLogsEnabled’)]"
                          },
                          {
                            "category": "Autoscale",
                            "enabled": "[parameters(‘autoscaleLogsEnabled’)]"
                          },
                          {
                            "category": "Policy",
                            "enabled": "[parameters(‘policyLogsEnabled’)]"
                          },
                          {
                            "category": "Recommendation",
                            "enabled": "[parameters(‘recommendationLogsEnabled’)]"
                          },
                          {
                            "category": "ResourceHealth",
                            "enabled": "[parameters(‘resourceHealthLogsEnabled’)]"
                          },
                          {
                            "category": "Security",
                            "enabled": "[parameters(‘securityLogsEnabled’)]"
                          },
                          {
                            "category": "ServiceHealth",
                            "enabled": "[parameters(‘serviceHealthLogsEnabled’)]"
                          }
                        ]
                      }
                    }
                  ],
                  "outputs": {}
                },
                "parameters": {
                  "profileName": {
                    "value": "[parameters(‘profileName’)]"
                  },
                  "eventHubName": {
                    "value": "[parameters(‘eventHubName’)]"
                  },
                  "eventHubAuthorizationRuleId": {
                    "value": "[parameters(‘eventHubAuthorizationRuleId’)]"
                  },
                  "administrativeLogsEnabled": {
                    "value": "[parameters(‘administrativeLogsEnabled’)]"
                  },
                  "alertLogsEnabled": {
                    "value": "[parameters(‘alertLogsEnabled’)]"
                  },
                  "autoscaleLogsEnabled": {
                    "value": "[parameters(‘autoscaleLogsEnabled’)]"
                  },
                  "policyLogsEnabled": {
                    "value": "[parameters(‘policyLogsEnabled’)]"
                  },
                  "recommendationLogsEnabled": {
                    "value": "[parameters(‘recommendationLogsEnabled’)]"
                  },
                  "resourceHealthLogsEnabled": {
                    "value": "[parameters(‘resourceHealthLogsEnabled’)]"
                  },
                  "securityLogsEnabled": {
                    "value": "[parameters(‘securityLogsEnabled’)]"
                  },
                  "serviceHealthLogsEnabled": {
                    "value": "[parameters(‘serviceHealthLogsEnabled’)]"
                  }
                }
              }
            },
            "roleDefinitionIds": [
              "/providers/Microsoft.Authorization/roleDefinitions/f526a384-b230-433a-b45c-95f59c4a2dec",
              "/providers/Microsoft.Authorization/roleDefinitions/92aaf0da-9dab-42b6-94a3-d43ce8d16293"
            ]
          }
        }
      }
    
    POLICY_RULE

  parameters = <<PARAMETERS
    {
      "profileName": {
            "type": "String",
            "metadata": {
              "displayName": "Profile name",
              "description": "The diagnostic settings profile name"
            },
            "defaultValue": "exportToEventHub"
          },
      "eventHubAuthorizationRuleId": {
        "type": "String",
        "metadata": {
          "displayName": "Event Hub Authorization Rule Id",
          "description": "Event Hub Authorization Rule Id - the authorization rule needs to be at Event Hub namespace level. e.g. /subscriptions/{subscription Id}/resourceGroups/{resource group}/providers/Microsoft.EventHub/namespaces/{Event Hub namespace}/authorizationrules/{authorization rule}",
          "strongType": "Microsoft.EventHub/Namespaces/AuthorizationRules",
          "assignPermissions": true
        }
      },
      "eventHubName": {
        "type": "String",
        "metadata": {
          "displayName": "Event Hub Name",
          "description": "Event Hub Name."
        }
      },
      "administrativeLogsEnabled": {
        "type": "String",
        "metadata": {
          "displayName": "Enable Administrative logs",
          "description": "Whether to enable Administrative logs stream to the Event Hub - true or false"
        },
        "allowedValues": [
          "true",
          "false"
        ],
        "defaultValue": "true"
      },
      "alertLogsEnabled": {
        "type": "String",
        "metadata": {
          "displayName": "Enable Alert logs",
          "description": "Whether to enable Alert logs stream to the Event Hub - true or false"
        },
        "allowedValues": [
          "true",
          "false"
        ],
        "defaultValue": "true"
      },
      "autoscaleLogsEnabled": {
        "type": "String",
        "metadata": {
          "displayName": "Enable Autoscale logs",
          "description": "Whether to enable Autoscale logs stream to the Event Hub - true or false"
        },
        "allowedValues": [
          "true",
          "false"
        ],
        "defaultValue": "true"
      },
      "policyLogsEnabled": {
        "type": "String",
        "metadata": {
          "displayName": "Enable Policy logs",
          "description": "Whether to enable Policy logs stream to the Event Hub - true or false"
        },
        "allowedValues": [
          "true",
          "false"
        ],
        "defaultValue": "true"
      },
      "recommendationLogsEnabled": {
        "type": "String",
        "metadata": {
          "displayName": "Enable Recommendation logs",
          "description": "Whether to enable Recommendation logs stream to the Event Hub - true or false"
        },
        "allowedValues": [
          "true",
          "false"
        ],
        "defaultValue": "true"
      },
      "resourceHealthLogsEnabled": {
        "type": "String",
        "metadata": {
          "displayName": "Enable ResourceHealth logs",
          "description": "Whether to enable ResourceHealth logs stream to the Event Hub - true or false"
        },
        "allowedValues": [
          "true",
          "false"
        ],
        "defaultValue": "true"
      },
      "securityLogsEnabled": {
        "type": "String",
        "metadata": {
          "displayName": "Enable Security logs",
          "description": "Whether to enable Security logs stream to the Event Hub - true or false"
        },
        "allowedValues": [
          "true",
          "false"
        ],
        "defaultValue": "true"
      },
      "serviceHealthLogsEnabled": {
        "type": "String",
        "metadata": {
          "displayName": "Enable ServiceHealth logs",
          "description": "Whether to enable ServiceHealth logs stream to the Event Hub - true or false"
        },
        "allowedValues": [
          "true",
          "false"
        ],
        "defaultValue": "true"
      },
      "effect": {
        "type": "String",
        "metadata": {
          "displayName": "Effect",
          "description": "DeployIfNotExists, AuditIfNotExists or Disabled the execution of the Policy"
        },
        "allowedValues": [
          "DeployIfNotExists",
          "AuditIfNotExists",
          "Disabled"
        ],
        "defaultValue": "DeployIfNotExists"
      }
    }
    PARAMETERS
}

resource "azurerm_subscription_policy_assignment" "subscriptionPolicyAssignmentActivityLogs" {
  name                 = "subscriptionPolicyAssignmentActivityLogs"
  policy_definition_id = azurerm_policy_definition.activityLogsEventHub.id
  subscription_id      = data.azurerm_subscription.current.id
  parameters = jsonencode({
    "eventHubAuthorizationRuleId" = {
      "value" = data.azurerm_eventhub_namespace_authorization_rule.SharedAccessKey.id
    },
    "eventHubName" = {
      "value" = azurerm_eventhub.splunk_log_event_hub.name
    }
  })
  location = azurerm_resource_group.splunk_logs_rg.location
  identity {
    type = "SystemAssigned"
  }
}

# # Create a Virtual Network
# resource "azurerm_virtual_network" "splunkNetwork" {
#   name                = "splunk-vnet"
#   address_space       = ["10.0.0.0/16"]
#   location            = azurerm_resource_group.splunk_logs_rg.location
#   resource_group_name = azurerm_resource_group.splunk_logs_rg.name
# }

# # Create a Subnet specifically for the Private Endpoint
# resource "azurerm_subnet" "splunkSubnet" {
#   name                 = "splunk-subnet"
#   resource_group_name  = azurerm_resource_group.splunk_logs_rg.name
#   virtual_network_name = azurerm_virtual_network.splunkNetwork.name
#   address_prefixes     = ["10.0.0.0/24"]
#   service_endpoints    = ["Microsoft.EventHub"]
# }

# # Create a Private Endpoint for the Event Hub
# resource "azurerm_private_endpoint" "splunkPrivateEndpoint" {
#   name                = "example-private-endpoint"
#   location            = azurerm_resource_group.splunk_logs_rg.location
#   resource_group_name = azurerm_resource_group.splunk_logs_rg.name
#   subnet_id           = azurerm_subnet.splunkSubnet.id

#   private_service_connection {
#     name                           = "example-private-connection"
#     private_connection_resource_id = azurerm_eventhub_namespace.splunk_log_hub_namespace.id
#     is_manual_connection           = false
#     subresource_names              = ["namespace"]
#   }
# }
