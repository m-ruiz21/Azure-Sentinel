# Qualys KB Codeless Connector - Reference Analysis

## Reference Implementation Found

Based on the existing **Qualys VM codeless connector** implementation, I can see the exact patterns we need to follow:

### 1. **Polling Configuration Pattern** (from QualysVMHostLogs_PollingConfig.json)

```json
{
  "type": "Microsoft.SecurityInsights/dataConnectors",
  "apiVersion": "2025-03-01", 
  "name": "QualysVMLogsCCP",
  "kind": "RestApiPoller",
  "properties": {
    "connectorDefinitionName": "QualysVMLogsCCPDefinition",
    "dataType": "QualysHostDetectionV3_CL",
    "auth": {
      "type": "Basic",
      "userName": "[[parameters('username')]",
      "password": "[[parameters('password')]"
    },
    "request": {
      "apiEndpoint": "{{apiServerUrl}}/api/3.0/fo/asset/host/vm/detection/",
      "httpMethod": "GET",
      "QueryWindowInMin": 10,
      "queryTimeFormat": "yyyy-MM-ddTHH:mm:ssZ",
      "headers": {
        "X-Requested-With": "XMLHttpRequest",
        "User-Agent": "Scuba"
      },
      "queryParameters": {
        "action": "list",
        "truncation_limit": "1", 
        "status": "New,Fixed,Active,Re-Opened",
        "vm_processed_before": "{_QueryWindowEndTime}",
        "vm_processed_after": "{_QueryWindowStartTime}"
      }
    },
    "response": {
      "eventsJsonPaths": ["$.HOST_LIST_VM_DETECTION_OUTPUT.RESPONSE.HOST_LIST.HOST"],
      "format": "xml"
    },
    "dcrConfig": {
      "streamName": "Custom-QualysVM",
      "dataCollectionEndpoint": "{{dataCollectionEndpoint}}",
      "dataCollectionRuleImmutableId": "{{dataCollectionRuleImmutableId}}"
    },
    "paging": {
      "pagingType": "LinkHeader",
      "linkHeaderTokenJsonPath": "$.HOST_LIST_VM_DETECTION_OUTPUT.RESPONSE.WARNING.URL.#cdata-section"
    }
  }
}
```

### 2. **DCR Pattern** (from QualysVMHostLogs_DCR.json)

```json
{
  "name": "QualysVMDCR",
  "apiVersion": "2023-03-11",
  "type": "Microsoft.Insights/dataCollectionRules", 
  "location": "{{location}}",
  "properties": {
    "dataCollectionEndpointId": "{{dataCollectionEndpointId}}",
    "streamDeclarations": {
      "Custom-QualysVM": {
        "columns": [
          {"name": "ID", "type": "string"},
          {"name": "IP", "type": "string"},
          {"name": "OS", "type": "dynamic"},
          {"name": "DNS", "type": "dynamic"},
          {"name": "DETECTION_LIST", "type": "dynamic"}
        ]
      }
    },
    "destinations": {
      "logAnalytics": [
        {
          "workspaceResourceId": "{{workspaceResourceId}}",
          "name": "clv2ws1"
        }
      ]
    },
    "dataFlows": [
      {
        "streams": ["Custom-QualysVM"],
        "destinations": ["clv2ws1"],
        "transformKql": "source | extend HostId = tostring(ID), OperatingSystem = tostring(OS['#cdata-section']), DnsName = tostring(DNS['#cdata-section']) | project HostId, OperatingSystem, DnsName, TimeGenerated = now()",
        "outputStream": "Custom-QualysHostDetectionV3_CL"
      }
    ]
  }
}
```

## Key Insights for QualysKB Implementation

### **Critical Differences for KB vs VM API**
1. **API Endpoint**: KB uses `/api/2.0/fo/knowledge_base/vuln/` vs VM's `/api/3.0/fo/asset/host/vm/detection/`
2. **Query Parameters**: KB uses `published_after` vs VM's `vm_processed_after/before` 
3. **XML Path**: KB uses `KNOWLEDGE_BASE_VULN_LIST_OUTPUT.RESPONSE.VULN_LIST.VULN` vs VM's `HOST_LIST_VM_DETECTION_OUTPUT.RESPONSE.HOST_LIST.HOST`
4. **Session Management**: KB requires session login/logout, VM appears to use direct Basic auth
5. **Data Schema**: KB has 20+ vulnerability fields vs VM's host detection fields

### **Key Patterns to Follow**
✅ **API Version**: `2025-03-01` for dataConnectors, `2023-03-11` for DCR  
✅ **Basic Auth**: `userName`/`password` with `[[parameters()]]` template syntax  
✅ **XML Response**: `format: "xml"` with proper JSON path extraction  
✅ **Time Windows**: Use `{_QueryWindowStartTime}` and `{_QueryWindowEndTime}` for incremental collection  
✅ **CDATA Handling**: Use `['#cdata-section']` notation in KQL transforms  
✅ **Stream Names**: Follow `Custom-[ConnectorName]` pattern  

### **Adaptations Needed for QualysKB**

1. **Session-based Auth Challenge**: The existing VM connector uses direct Basic auth, but our KB API requires session management (login/logout). This may need special handling.

2. **Complex Field Mapping**: Need to handle 20+ fields with HTML cleaning in KQL transforms

3. **Different XML Structure**: Adapt paths and field extraction for KB-specific XML response format

## Next Steps

Based on this analysis, I'll create:
1. **QualysKB_DCR.json** - Following the VM DCR pattern but adapted for KB fields
2. **QualysKB_PollingConfig.json** - Following the VM polling pattern but adapted for KB API
3. **UI Definition** and **ARM Template** - Following established patterns

This reference gives us a solid foundation that we know works with the Qualys API infrastructure.