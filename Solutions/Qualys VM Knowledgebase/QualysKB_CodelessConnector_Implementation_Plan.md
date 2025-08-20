# QualysKB Codeless Connector - Implementation Specification

## Architecture Decision: Basic Authentication

**Key Decision**: Use **Basic Authentication** (username/password) instead of session management, following the same pattern as the existing Qualys VM codeless connector.

**Rationale**: Codeless connectors **do not support session management** (login/logout flows). The Qualys APIs support both session-based and Basic auth - we'll use Basic auth for CCF compatibility.

## Implementation Specification

### 1. **Data Collection Rule (DCR) Design**

Based on the Qualys VM reference pattern and our KB field analysis:

```json
{
  "name": "QualysKBDCR",
  "apiVersion": "2023-03-11", 
  "type": "Microsoft.Insights/dataCollectionRules",
  "properties": {
    "dataCollectionEndpointId": "{{dataCollectionEndpointId}}",
    "streamDeclarations": {
      "Custom-QualysKB": {
        "columns": [
          {"name": "QID", "type": "string"},
          {"name": "TITLE", "type": "dynamic"},
          {"name": "CATEGORY", "type": "string"},
          {"name": "CONSEQUENCE", "type": "dynamic"},
          {"name": "DIAGNOSIS", "type": "dynamic"},
          {"name": "SOLUTION", "type": "dynamic"},
          {"name": "LAST_SERVICE_MODIFICATION_DATETIME", "type": "datetime"},
          {"name": "PATCHABLE", "type": "string"},
          {"name": "CVE_LIST", "type": "dynamic"},
          {"name": "VENDOR_REFERENCE_LIST", "type": "dynamic"},
          {"name": "PCI_FLAG", "type": "string"},
          {"name": "PUBLISHED_DATETIME", "type": "datetime"},
          {"name": "SEVERITY_LEVEL", "type": "string"},
          {"name": "SOFTWARE_LIST", "type": "dynamic"},
          {"name": "VULN_TYPE", "type": "string"},
          {"name": "DISCOVERY", "type": "dynamic"},
          {"name": "THREAT_INTELLIGENCE", "type": "dynamic"}
        ]
      }
    },
    "destinations": {
      "logAnalytics": [{
        "workspaceResourceId": "{{workspaceResourceId}}",
        "name": "clv2ws1"
      }]
    },
    "dataFlows": [{
      "streams": ["Custom-QualysKB"],
      "destinations": ["clv2ws1"],
      "transformKql": "/* KQL Transform Logic Here */",
      "outputStream": "Custom-QualysKB_CL"
    }]
  }
}
```

### 2. **KQL Transformation Logic**

Critical: Replicate the [`Html-ToText`](Data Connectors/AzureFunctionQualysKB/run.ps1:28-70) PowerShell function logic in KQL:

```kql
source 
| extend 
    // Basic field mappings
    QID = tostring(QID),
    Title = tostring(TITLE['#cdata-section']),
    Category = tostring(CATEGORY),
    
    // HTML cleaning for text fields (simplified approach)
    Consequence = replace_regex(tostring(CONSEQUENCE['#cdata-section']), '<[^>]*>', ''),
    Diagnosis = replace_regex(tostring(DIAGNOSIS['#cdata-section']), '<[^>]*>', ''),
    Solution = replace_regex(tostring(SOLUTION['#cdata-section']), '<[^>]*>', ''),
    
    // Date/time fields  
    Last_Service_Modification_DateTime = todatetime(LAST_SERVICE_MODIFICATION_DATETIME),
    Published_DateTime = todatetime(PUBLISHED_DATETIME),
    
    // CVE extraction from nested structure
    CVE_ID = tostring(CVE_LIST.CVE.ID['#cdata-section']),
    CVE_URL = tostring(CVE_LIST.CVE.URL['#cdata-section']),
    
    // Vendor reference extraction
    Vendor_Reference_ID = tostring(VENDOR_REFERENCE_LIST.VENDOR_REFERENCE.ID['#cdata-section']),
    Vendor_Reference_URL = tostring(VENDOR_REFERENCE_LIST.VENDOR_REFERENCE.URL['#cdata-section']),
    
    // Software information
    Software_Product = tostring(SOFTWARE_LIST.SOFTWARE.PRODUCT['#cdata-section']),
    Software_Vendor = tostring(SOFTWARE_LIST.SOFTWARE.VENDOR['#cdata-section']),
    
    // Other fields
    Patchable = tostring(PATCHABLE),
    PCI_Flag = tostring(PCI_FLAG), 
    Severity_Level = tostring(SEVERITY_LEVEL),
    Vuln_Type = tostring(VULN_TYPE),
    
    // Discovery fields
    Discovery_Additional_Info = tostring(DISCOVERY.ADDITIONAL_INFO),
    Discovery_Auth_Type = tostring(DISCOVERY.AUTH_TYPE_LIST.AUTH_TYPE),
    Discovery_Remote = tostring(DISCOVERY.REMOTE),
    
    // Threat Intelligence (JSON serialized)
    THREAT_INTELLIGENCE = tostring(THREAT_INTELLIGENCE.THREAT_INTEL),
    
    // System field
    TimeGenerated = now()
    
| project QID, Title, Category, Consequence, Diagnosis, Solution,
          Last_Service_Modification_DateTime, Patchable, CVE_ID, CVE_URL,
          Vendor_Reference_ID, Vendor_Reference_URL, PCI_Flag, Published_DateTime,
          Severity_Level, Software_Product, Software_Vendor, Vuln_Type,
          Discovery_Additional_Info, Discovery_Auth_Type, Discovery_Remote,
          THREAT_INTELLIGENCE, TimeGenerated
```

### 3. **RestApiPoller Configuration**

Based on Qualys VM pattern, adapted for KB API:

```json
{
  "type": "Microsoft.SecurityInsights/dataConnectors",
  "apiVersion": "2025-03-01",
  "name": "QualysKBLogsCCP", 
  "kind": "RestApiPoller",
  "properties": {
    "connectorDefinitionName": "QualysKBLogsCCPDefinition",
    "dataType": "QualysKB_CL",
    "auth": {
      "type": "Basic",
      "userName": "[[parameters('username')]",
      "password": "[[parameters('password')]"
    },
    "request": {
      "apiEndpoint": "{{apiServerUrl}}/api/2.0/fo/knowledge_base/vuln/",
      "httpMethod": "GET",
      "QueryWindowInMin": 10,
      "queryTimeFormat": "yyyy-MM-ddTHH:mm:ssZ",
      "headers": {
        "X-Requested-With": "XMLHttpRequest",
        "User-Agent": "Scuba"
      },
      "queryParameters": {
        "action": "list",
        "published_after": "{_QueryWindowStartTime}",
        // Add any filter parameters from env variable
        "{{filterParameters}}": ""
      }
    },
    "response": {
      "eventsJsonPaths": ["$.KNOWLEDGE_BASE_VULN_LIST_OUTPUT.RESPONSE.VULN_LIST.VULN"],
      "format": "xml"
    },
    "dcrConfig": {
      "streamName": "Custom-QualysKB",
      "dataCollectionEndpoint": "{{dataCollectionEndpoint}}",
      "dataCollectionRuleImmutableId": "{{dataCollectionRuleImmutableId}}"
    }
  }
}
```

### 4. **Key Differences from Azure Function Version**

| Aspect | Azure Function | Codeless Connector |
|--------|----------------|-------------------|
| **Authentication** | Session login/logout | Basic auth (username/password) |
| **Scheduling** | Timer trigger (5 min) | Built-in QueryWindowInMin (10 min) |
| **Checkpointing** | Custom CSV file | Built-in time window management |
| **HTML Processing** | PowerShell Html-ToText function | KQL regex replace operations |
| **Error Handling** | PowerShell try/catch | Built-in CCF error handling |
| **Infrastructure** | Azure Function App | Microsoft-managed CCF infrastructure |

### 5. **Migration Benefits**

✅ **Zero Infrastructure**: No Function Apps to manage  
✅ **Simplified Auth**: Basic auth vs complex session management  
✅ **Auto-scaling**: Microsoft-managed scaling  
✅ **Built-in Monitoring**: Native health monitoring  
✅ **Cost Optimization**: No compute charges  
✅ **Automatic Checkpointing**: Built-in time window management  

### 6. **Implementation Order**

1. ✅ Custom Table Definition (`QualysKB_CL`) - **COMPLETED**
2. 🔄 Data Collection Rule (DCR) with KQL transforms - **IN PROGRESS**  
3. ⏳ Data Connector UI Definition  
4. ⏳ RestApiPoller configuration  
5. ⏳ ARM template integration  
6. ⏳ Testing and validation  

This approach maintains full backward compatibility while modernizing to the CCF platform.