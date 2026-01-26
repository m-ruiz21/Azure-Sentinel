# Cisco Duo Security Data Connector for Azure Sentinel

This Azure Function connects Cisco Duo Security logs to Azure Sentinel, ingesting authentication, administrator, telephony, offline enrollment, activity, and trust monitor logs every 5 minutes.

## Prerequisites

- **Python 3.11+** (for local development)
- **Azure Functions Core Tools v4+** - [Download here](https://learn.microsoft.com/azure/azure-functions/functions-run-local)
- **Azure subscription** with an active Azure Sentinel workspace
- **Cisco Duo Admin API credentials** (Integration Key, Secret Key, API Hostname)

## Local Development Setup

### 1. Create and Activate Virtual Environment

**Windows (PowerShell):**

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
```

**Windows (CMD):**

```cmd
python -m venv .venv
.venv\Scripts\activate.bat
```

**Linux/macOS:**

```bash
python3 -m venv .venv
source .venv/bin/activate
```

### 2. Install Dependencies

```bash
pip install -r requirements.txt
```

### 3. Configure Local Settings

Create or update `local.settings.json` with your credentials:

```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "python",
    "WORKSPACE_ID": "<your-sentinel-workspace-id>",
    "SHARED_KEY": "<your-sentinel-primary-or-secondary-key>",
    "CISCO_DUO_API_HOSTNAME": "api-xxxxxxxx.duosecurity.com",
    "CISCO_DUO_INTEGRATION_KEY": "<your-integration-key>",
    "CISCO_DUO_SECRET_KEY": "<your-secret-key>",
    "CISCO_DUO_LOG_TYPES": "trust_monitor,authentication,administrator,telephony,offline_enrollment,activity",
    "logAnalyticsUri": "https://<workspace-id>.ods.opinsights.azure.com"
  }
}
```

**Getting Credentials:**

- **Cisco Duo:** Admin Panel → Applications → Protect an Application → Admin API
- **Azure Sentinel:** Log Analytics Workspace → Agents → Primary/Secondary Key and Workspace ID

> ⚠️ **Note:** `local.settings.json` should never be committed to source control.

### 4. Run Locally

```bash
func start
```

The function will execute based on the timer trigger (every 5 minutes by default). You can also:

**Trigger manually for testing:**

- The timer runs automatically, but you can modify the schedule in `AzureFunctionCiscoDuo/function.json`
- Watch the console output for log ingestion progress

**Expected output:**

```
[2026-01-26T17:00:00.123Z] Executing 'Functions.AzureFunctionCiscoDuo'
[2026-01-26T17:00:00.456Z] Starting script
[2026-01-26T17:00:01.789Z] Start processing trust_monitor logs
[2026-01-26T17:00:05.123Z] Script finished. Sent events: 150
```

## Packaging for Deployment

### 1. Install Dependencies to `.python_packages`

Before creating the deployment zip, install all required packages to the `.python_packages/lib/site-packages` directory:

**Windows (PowerShell):**

```powershell
pip install --target="./.python_packages/lib/site-packages" -r requirements.txt
```

**Windows (CMD):**

```cmd
pip install --target=.\.python_packages\lib\site-packages -r requirements.txt
```

**Linux/macOS:**

```bash
pip install --target="./.python_packages/lib/site-packages" -r requirements.txt
```

> 💡 **Note:** The `.python_packages` folder structure is required for Azure Functions Python consumption plan deployments.

### 2. Create Deployment Zip

**PowerShell (Windows):**

```powershell
Get-ChildItem -Path .python_packages,AzureFunctionCiscoDuo,host.json,proxies.json,requirements.txt -Recurse | Where-Object { $_.FullName -notmatch '__pycache__' } | Compress-Archive -DestinationPath CiscoDuoSecurity_func.zip -Force
```

**Bash (Linux/macOS):**

```bash
zip -r CiscoDuoSecurity_func.zip .python_packages AzureFunctionCiscoDuo host.json proxies.json requirements.txt -x '*/__pycache__/*' '*/.pyc'
```

> 💡 **Note:** The commands above exclude `__pycache__` directories and `.pyc` files from the deployment package to reduce size and avoid potential issues.
