# Task Prompt: Implement Qualys KB Codeless Connector Components

## Context
I have completed the architecture and planning phase for converting an Azure Function-based Qualys KB connector to a codeless connector. The foundation files have been created and the implementation specification is ready.

## Task Objective
Build the remaining codeless connector components and create a complete ARM deployment template for the Qualys VM Knowledgebase codeless connector.

## Current Status
**✅ COMPLETED:**
- Architecture analysis and design
- Custom table definition: `Data Connectors/CodelessConnector/QualysKB_CustomTable.json`
- Implementation specification: `QualysKB_CodelessConnector_Implementation_Plan.md`

**🔄 REMAINING TASKS:**
1. Create Data Collection Rule (DCR) with KQL transformations
2. Create Data Connector UI Definition for connector gallery
3. Create RestApiPoller configuration for API integration  
4. Build complete ARM deployment template
5. Create deployment documentation

## Key Requirements

### 1. **Data Collection Rule (DCR)**
- **File**: `Data Connectors/CodelessConnector/QualysKB_DCR.json`
- **API Version**: `2023-03-11`
- **Stream Name**: `Custom-QualysKB`
- **Output Table**: `Custom-QualysKB_CL`
- **Critical**: Implement KQL transforms that replicate the PowerShell `Html-ToText` function from the original Azure Function
- **Field Mapping**: 23 fields from XML structure to QualysKB_CL table schema
- **CDATA Handling**: Use `['#cdata-section']` notation for XML CDATA extraction

### 2. **Data Connector UI Definition** 
- **File**: `Data Connectors/CodelessConnector/QualysKB_UIDefinition.json`
- **Kind**: `Customizable`
- **Connectivity Criteria**: `hasDataConnectors`
- **Authentication Form**: Basic auth (username/password) input fields
- **Instructions**: Connection setup steps adapted from existing connector
- **Connection Button**: `ConnectionToggleButton` type for deployment trigger

### 3. **RestApiPoller Configuration**
- **File**: `Data Connectors/CodelessConnector/QualysKB_PollingConfig.json`
- **API Version**: `2025-03-01`
- **Kind**: `RestApiPoller`
- **Auth Type**: `Basic` (username/password)
- **API Endpoint**: `{{apiServerUrl}}/api/2.0/fo/knowledge_base/vuln/`
- **Query Parameters**: `action=list`, `published_after={_QueryWindowStartTime}`
- **Response Format**: `xml`
- **XML Path**: `$.KNOWLEDGE_BASE_VULN_LIST_OUTPUT.RESPONSE.VULN_LIST.VULN`
- **Query Window**: 10 minutes (matching reference pattern)

### 4. **ARM Deployment Template**
- **File**: `Data Connectors/CodelessConnector/QualysKB_ARMTemplate.json`
- **Structure**: Follow Microsoft's CCF ARM template pattern with 5 resource sections
- **Parameters**: Secure handling of credentials using `securestring`
- **Variables**: Solution metadata, connector IDs, versions
- **Resources**: contentTemplates, dataConnectorDefinitions, metadata, contentPackages
- **Template Variables**: Use `{{}}` notation for dynamic values

## Reference Files to Use
- **Existing Analysis**: `QualysKB_CodelessConnector_Analysis.md`
- **Implementation Spec**: `QualysKB_CodelessConnector_Implementation_Plan.md`
- **Original PowerShell**: `Data Connectors/AzureFunctionQualysKB/run.ps1` (for field mapping and HTML processing logic)
- **Custom Table**: `Data Connectors/CodelessConnector/QualysKB_CustomTable.json`

## Critical Technical Details

### **KQL Transformation Requirements**
The DCR must replicate the HTML cleaning logic from the PowerShell function:
- Strip HTML tags using `replace_regex()`
- Handle CDATA sections with `['#cdata-section']` notation  
- Map complex nested XML structures to flat table fields
- Convert datetime strings to proper datetime types
- Serialize threat intelligence data to JSON strings

### **Authentication Pattern**
- Use **Basic Auth** (NOT session management - codeless connectors don't support sessions)
- Follow the same pattern as the existing Qualys VM codeless connector
- Parameters: `userName` and `password` with ARM template escaping: `[[parameters('username')]`

### **API Integration Pattern**
- Use time window management: `{_QueryWindowStartTime}` instead of checkpoint files
- XML response parsing through CCF built-in capabilities
- Error handling through CCF infrastructure (no custom PowerShell error logic needed)

## Success Criteria
1. **Functional Parity**: Same data ingestion to QualysKB_CL table with identical schema
2. **Backward Compatibility**: Existing analytics rules and workbooks continue working
3. **Deployment Ready**: Complete ARM template that can be deployed to Azure
4. **Documentation**: Clear deployment and migration instructions
5. **Testing Guidance**: Validation steps for connector functionality

## Expected Deliverables
- `QualysKB_DCR.json` - Data Collection Rule with KQL transforms
- `QualysKB_UIDefinition.json` - Connector gallery interface  
- `QualysKB_PollingConfig.json` - API polling configuration
- `QualysKB_ARMTemplate.json` - Complete deployment template
- `QualysKB_Deployment_Guide.md` - Implementation and migration documentation

Please implement these components following the Microsoft Sentinel CCF patterns and ensure all JSON files are properly formatted with correct API versions and required fields.