# Qualys KB Codeless Connector - Deployment and Migration Guide

## Overview

This guide provides comprehensive instructions for deploying and migrating to the Qualys Vulnerability Management KnowledgeBase (KB) Codeless Connector for Microsoft Sentinel. The new connector uses Microsoft's Codeless Connector Framework (CCF) to replace the existing Azure Function-based implementation.

## Architecture Overview

### Current Architecture (Azure Function)
- **Components**: Azure Function App, PowerShell script, timer trigger
- **Authentication**: Session-based (login/logout)
- **Scheduling**: 5-minute timer trigger
- **Checkpointing**: Custom CSV file management
- **Infrastructure**: Customer-managed Function App resources

### New Architecture (Codeless Connector)
- **Components**: CCF RestApiPoller, Data Collection Rule, Custom Table
- **Authentication**: Basic authentication (username/password)
- **Scheduling**: 10-minute query window
- **Checkpointing**: Built-in time window management
- **Infrastructure**: Microsoft-managed, serverless

## Prerequisites

### Required Permissions
- **Microsoft Sentinel Workspace**: Contributor or Microsoft Sentinel Contributor role
- **Resource Group**: Contributor permissions on the target resource group
- **Qualys API**: Valid Qualys VM username and password with API access

### Qualys API Requirements
- **API Access**: Enabled API access for the Qualys user account
- **API Endpoint**: Correct Qualys API server URL for your region
- **Permissions**: User must have permissions to access KnowledgeBase vulnerability data

### Common Qualys API Server URLs by Region
| Region | API Server URL |
|--------|----------------|
| US Platform 1 | `https://qualysapi.qualys.com/api/2.0` |
| US Platform 2 | `https://qualysapi.qg2.apps.qualys.com/api/2.0` |
| US Platform 3 | `https://qualysapi.qg3.apps.qualys.com/api/2.0` |
| US Platform 4 | `https://qualysapi.qg4.apps.qualys.com/api/2.0` |
| EU Platform 1 | `https://qualysapi.qualys.eu/api/2.0` |
| EU Platform 2 | `https://qualysapi.qg2.apps.qualys.eu/api/2.0` |
| India Platform | `https://qualysapi.qg1.apps.qualys.in/api/2.0` |
| Canada Platform | `https://qualysapi.qg1.apps.qualys.ca/api/2.0` |

## Deployment Methods

### Method 1: Azure Portal Deployment (Recommended)

1. **Navigate to Custom Deployment**
   - Go to [Azure Portal](https://portal.azure.com)
   - Search for "Deploy a custom template"
   - Select "Build your own template in the editor"

2. **Upload Template**
   - Copy the contents of `mainTemplate.json` from the generated solution package
   - Paste into the template editor
   - Click "Save"

3. **Configure Parameters**
   - **Subscription**: Select your target subscription
   - **Resource Group**: Select resource group containing your Sentinel workspace
   - **Workspace Name**: Enter your Log Analytics workspace name
   - **Location**: Select the same region as your workspace
   - **Username**: Enter your Qualys VM API username
   - **Password**: Enter your Qualys VM API password
   - **API Server URL**: Enter your Qualys API server URL
   - **Filter Parameters**: (Optional) Additional API filter parameters

4. **Deploy**
   - Click "Review + Create"
   - Verify all parameters
   - Click "Create" to deploy

### Method 2: Azure CLI Deployment

```bash
# Set variables
RESOURCE_GROUP="your-resource-group"
WORKSPACE_NAME="your-workspace-name"
LOCATION="your-location"
TEMPLATE_FILE="mainTemplate.json"
PARAMETERS_FILE="parameters.json"

# Deploy the template
az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file $TEMPLATE_FILE \
  --parameters @$PARAMETERS_FILE
```

### Method 3: PowerShell Deployment

```powershell
# Set variables
$ResourceGroup = "your-resource-group"
$WorkspaceName = "your-workspace-name"
$Location = "your-location"
$TemplateFile = "mainTemplate.json"
$ParameterFile = "parameters.json"

# Deploy the template
New-AzResourceGroupDeployment `
  -ResourceGroupName $ResourceGroup `
  -TemplateFile $TemplateFile `
  -TemplateParameterFile $ParameterFile
```

## Configuration Steps

### 1. Configure the Data Connector

1. **Access Data Connectors**
   - Navigate to your Microsoft Sentinel workspace
   - Go to **Configuration** > **Data connectors**
   - Search for "Qualys Vulnerability Management KnowledgeBase (KB)"

2. **Configure Connection**
   - Click "Open connector page"
   - Enter your Qualys API credentials:
     - **API Server URL**: Your Qualys platform URL
     - **Username**: Qualys VM API username
     - **Password**: Qualys VM API password
   - Click "Connect"

3. **Verify Connection**
   - Monitor the connection status in the data connector page
   - Check for any error messages in the connector logs

### 2. Validate Data Ingestion

1. **Check Data Collection**
   ```kql
   QualysKB_CL
   | where TimeGenerated > ago(1h)
   | take 10
   ```

2. **Verify Field Mapping**
   ```kql
   QualysKB_CL
   | where TimeGenerated > ago(24h)
   | project QID, Title, Category, Severity_Level, Published_DateTime
   | take 5
   ```

3. **Compare with Previous Data**
   ```kql
   QualysKB_CL
   | where TimeGenerated > ago(7d)
   | summarize Count = count() by bin(TimeGenerated, 1d)
   | render timechart
   ```

## Migration from Azure Function Connector

### Migration Strategy Options

#### Option 1: Side-by-Side Migration (Recommended)
- Deploy the new codeless connector alongside the existing Function App
- Allow both to run in parallel for validation
- Disable the Function App once validation is complete

#### Option 2: Direct Replacement
- Stop the existing Function App
- Deploy the codeless connector
- Validate data ingestion immediately

### Pre-Migration Checklist

- [ ] Document current Function App configuration
- [ ] Export existing analytics rules and workbooks
- [ ] Verify Qualys API credentials and permissions
- [ ] Test connectivity to Qualys API endpoint
- [ ] Backup current QualysKB_CL data if needed

### Migration Steps

1. **Prepare for Migration**
   ```kql
   // Document current data volume
   QualysKB_CL
   | where TimeGenerated > ago(30d)
   | summarize 
       TotalRecords = count(),
       LatestRecord = max(TimeGenerated),
       UniqueQIDs = dcount(QID)
   ```

2. **Deploy Codeless Connector**
   - Follow deployment steps above
   - Configure with same Qualys API credentials
   - Test connection and initial data ingestion

3. **Validate Data Consistency**
   ```kql
   // Compare field mappings
   QualysKB_CL
   | where TimeGenerated > ago(2h)
   | extend HasAllRequiredFields = 
       isnotempty(QID) and 
       isnotempty(Title) and 
       isnotempty(Category)
   | summarize 
       TotalRecords = count(),
       ValidRecords = countif(HasAllRequiredFields),
       ValidationPercentage = (countif(HasAllRequiredFields) * 100.0) / count()
   ```

4. **Update Analytics Rules** (if needed)
   - Most analytics rules should work unchanged
   - Review any rules that depend on specific field formats
   - Test all analytics rules with new data

5. **Disable Function App**
   ```bash
   # Stop the Function App
   az functionapp stop --name "your-function-app-name" --resource-group "your-resource-group"
   ```

6. **Monitor and Validate**
   - Monitor data ingestion for 24-48 hours
   - Verify analytics rule performance
   - Check dashboard and workbook functionality

### Rollback Procedure

If issues arise, you can rollback to the Function App:

1. **Disable Codeless Connector**
   - Go to the data connector page
   - Click "Disconnect"

2. **Re-enable Function App**
   ```bash
   az functionapp start --name "your-function-app-name" --resource-group "your-resource-group"
   ```

3. **Monitor Data Resumption**
   - Verify Function App logs
   - Check data ingestion resumes

## Key Differences and Considerations

### Authentication Changes
- **Before**: Session-based authentication with login/logout
- **After**: Basic authentication per API request
- **Impact**: Simplified authentication, no session management

### Scheduling Changes  
- **Before**: 5-minute timer trigger
- **After**: 10-minute query window
- **Impact**: Slightly longer collection intervals

### HTML Processing Changes
- **Before**: PowerShell Html-ToText function
- **After**: KQL regex-based cleaning
- **Impact**: Functionally equivalent, may have minor text formatting differences

### Infrastructure Benefits
- **Zero Infrastructure**: No Function Apps to manage
- **Built-in Monitoring**: Native CCF health monitoring
- **Auto-scaling**: Microsoft-managed scaling
- **Cost Optimization**: No compute charges for polling
- **Simplified Updates**: No code deployment required

## Troubleshooting

### Common Issues

#### 1. Connection Failures
**Symptoms**: Connector shows "Disconnected" status
**Solutions**:
- Verify Qualys API credentials
- Check API server URL format
- Confirm user has API access permissions
- Test connectivity from Azure region to Qualys endpoint

#### 2. No Data Ingestion
**Symptoms**: No records in QualysKB_CL table
**Solutions**:
- Check Data Collection Rule deployment
- Verify custom table creation
- Review connector error logs
- Confirm API returns data for the time range

#### 3. Data Quality Issues
**Symptoms**: Missing fields or unexpected data formats
**Solutions**:
- Review KQL transformation logic
- Compare with original PowerShell processing
- Check for API response format changes

#### 4. Performance Issues
**Symptoms**: Slow data ingestion or high latency
**Solutions**:
- Review API rate limiting settings
- Check query window configuration
- Monitor DCE performance metrics

### Diagnostic Queries

#### Connection Status
```kql
_LogOperation_CL
| where Category == "DataConnector"
| where OperationName contains "QualysKB"
| project TimeGenerated, Level, Message
| order by TimeGenerated desc
```

#### Data Collection Performance
```kql
QualysKB_CL
| summarize 
    RecordsPerHour = count(),
    AvgRecordsPerBatch = avg(todouble(1))
by bin(TimeGenerated, 1h)
| render timechart
```

#### Field Validation
```kql
QualysKB_CL
| where TimeGenerated > ago(1d)
| extend 
    MissingQID = isempty(QID),
    MissingTitle = isempty(Title),
    MissingCategory = isempty(Category)
| summarize 
    TotalRecords = count(),
    MissingQIDCount = countif(MissingQID),
    MissingTitleCount = countif(MissingTitle),
    MissingCategoryCount = countif(MissingCategory)
```

## Support and Maintenance

### Monitoring Recommendations
- Set up alerts for data ingestion failures
- Monitor connector health status
- Review data quality metrics regularly
- Track API rate limiting and quotas

### Regular Maintenance Tasks
- Review connector logs monthly
- Validate data quality quarterly
- Update analytics rules as needed
- Monitor Qualys API changes

### Getting Support
- **Microsoft Support**: For CCF platform and Sentinel issues
- **Qualys Support**: For API and data source issues
- **Community Forums**: For general troubleshooting

## Conclusion

The QualysKB Codeless Connector provides a modern, maintainable solution for ingesting Qualys vulnerability data into Microsoft Sentinel. The migration from the Azure Function-based approach offers significant operational benefits while maintaining full backward compatibility with existing analytics and workbooks.

For additional support or questions about this deployment guide, please refer to the Microsoft Sentinel documentation or contact your support team.