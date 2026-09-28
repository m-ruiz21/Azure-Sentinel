# Google Cloud Platform BigQuery CCF connector

This connector ingests BigQuery rows using the [BigQuery export-to-Pub/Sub flow](https://cloud.google.com/bigquery/docs/export-to-pubsub):

```text
BigQuery table -> continuous query (EXPORT DATA) -> Pub/Sub topic
              -> dedicated pull subscription -> Sentinel GCP connector
              -> data collection rule -> GCPBigQuery_CL
```

The collector uses native CCF `kind: "GCP"` and workload identity federation. It does not poll the BigQuery REST API, require service account keys, or use Azure Functions. This is a row-export connector, not a BigQuery audit-log connector; do not configure a Cloud Logging sink.

## Prerequisites

- A Microsoft Sentinel-enabled Log Analytics workspace and permissions to deploy the connector, custom table, and data collection rule (DCR).
- BigQuery and Pub/Sub APIs enabled in the relevant Google Cloud projects.
- A supported BigQuery source table and location. Continuous queries require an **Enterprise or Enterprise Plus reservation** with a **CONTINUOUS assignment**. On-demand compute is not supported. BigQuery, Pub/Sub, and Azure ingestion/storage charges apply.
- A schema-free Pub/Sub topic and a dedicated pull subscription created **before starting the export**. Do not share this subscription with other consumers: they can consume and acknowledge messages before Sentinel receives them.
- Separate service accounts for the BigQuery exporter and Sentinel subscriber.

See [continuous query requirements and limitations](https://cloud.google.com/bigquery/docs/continuous-queries-introduction) before configuring capacity or selecting a source table.

## 1. Configure Google Cloud permissions

Use resource-scoped grants where possible.

| Identity | Required access |
| --- | --- |
| User submitting the continuous query | `bigquery.jobs.create` (for example, BigQuery Job User) in the job project and Service Account User on the exporter service account. API enablement additionally requires Service Usage Admin. |
| BigQuery exporter service account | BigQuery Data Viewer on the source data, including read/export permissions; Pub/Sub Publisher and Pub/Sub Viewer on the destination topic. |
| Sentinel subscriber service account | `pubsub.subscriptions.get` and `pubsub.subscriptions.consume` on the dedicated subscription, plus the workload identity federation binding described below. It does not need to query BigQuery or publish messages. |

Follow the [export permission requirements](https://cloud.google.com/bigquery/docs/export-to-pubsub#required_roles), including any organization-specific restrictions.

Create the topic and subscription using the Google Cloud console or the following commands after replacing the uppercase placeholders:

```sh
gcloud pubsub topics create TOPIC_ID --project=PUBSUB_PROJECT_ID
gcloud pubsub subscriptions create SUBSCRIPTION_ID \
  --project=PUBSUB_PROJECT_ID \
  --topic=TOPIC_ID \
  --ack-deadline=60
```

Do not attach a Pub/Sub schema to the topic or configure a push endpoint. Choose subscription message retention appropriate to your recovery requirements.

## 2. Configure Sentinel authentication

Reuse the existing Sentinel GCP authentication resources in the Pub/Sub project, or follow the shared setup:

- [Commercial Azure authentication Terraform](https://github.com/Azure/Azure-Sentinel/tree/master/DataConnectors/GCP/Terraform/sentinel_resources_creation/GCPInitialAuthenticationSetup)
- [Azure Government authentication Terraform](https://github.com/Azure/Azure-Sentinel/tree/master/DataConnectors/GCP/Terraform/sentinel_resources_creation_gov/GCPInitialAuthenticationSetupGov)
- [Microsoft Sentinel GCP connection guide](https://learn.microsoft.com/azure/sentinel/connect-google-cloud-platform)

Use **only the authentication setup** from these guides; the BigQuery export replaces their service-log setup and logging sink. Review the Terraform plan before applying. The shared script grants its custom subscriber role at project scope; for least privilege, scope the subscriber permissions to this connector's subscription when managing IAM yourself.

The native GCP collector expects the workload identity pool ID to be the Microsoft Entra tenant ID with hyphens removed. Use the Sentinel application audience, issuer, and federation binding from the setup for your Azure cloud. Keep the Pub/Sub subscription and authentication resources in the same GCP project for this setup; the source BigQuery table can be in a different project with the required permissions.

Record the Pub/Sub project ID and **numeric project number**, subscription ID, workload identity provider ID, and subscriber service account email. The provider ID is not the pool ID. No private key or service account JSON key file is needed.

## 3. Start the BigQuery continuous export

Edit [export_to_pubsub.sql](export_to_pubsub.sql), replacing:

| Placeholder | Value |
| --- | --- |
| `PUBSUB_PROJECT_ID` | Project containing the destination Pub/Sub topic and subscription. |
| `TOPIC_ID` | Destination topic ID. |
| `SOURCE_PROJECT_ID` | Project containing the BigQuery table, in both the table reference and exported `ProjectId`. |
| `DATASET_ID` | Source dataset, in both the table reference and exported `DatasetId`. |
| `TABLE_ID` | Source table, in both the table reference and exported `TableId`. |

In the BigQuery console, open **Query settings**, enable **Use continuous query mode**, and select the exporter service account. Run the edited SQL in the source dataset's location. Alternatively, submit it with the `bq` CLI:

```sh
bq query \
  --project_id=JOB_PROJECT_ID \
  --location=BIGQUERY_LOCATION \
  --use_legacy_sql=false \
  --continuous=true \
  --connection_property=service_account=EXPORTER_SERVICE_ACCOUNT_EMAIL \
  < export_to_pubsub.sql
```

The job project must have the CONTINUOUS reservation assignment. The SQL exports exactly one STRING column named `message`, as required by `CLOUD_PUBSUB`. `TO_JSON_STRING` serializes the envelope once; do not base64-encode it yourself or serialize `Record` separately. The GCP collector handles the Pub/Sub transport encoding.

The initial query reads appends from the preceding ten minutes and continues processing new appends. Change the start timestamp deliberately within the supported window. This is **not a full-table backfill or change-data-capture connector**: updates and deletes are not mirrored. Restarting with an overlapping start time can replay rows; starting after the last processed time can miss rows. See the [APPENDS reference](https://cloud.google.com/bigquery/docs/reference/standard-sql/time-series-functions#appends).

## Payload and destination schema

Every decoded Pub/Sub message must be a single JSON object with these case-sensitive fields:

| Column | Type | Meaning |
| --- | --- | --- |
| `TimeGenerated` | datetime | UTC `_CHANGE_TIMESTAMP` from APPENDS (row commit time, not necessarily business-event time). |
| `ProjectId` | string | Source table's GCP project ID, not necessarily the Pub/Sub project. |
| `DatasetId` | string | Source dataset ID. |
| `TableId` | string | Source table ID. |
| `Record` | dynamic | Nested JSON object containing the source row and APPENDS metadata. |

Example decoded message (illustrative timestamp):

```json
{
  "TimeGenerated": "2026-09-28T20:00:00Z",
  "ProjectId": "example-source-project",
  "DatasetId": "security",
  "TableId": "events",
  "Record": {
    "event_id": "example-event-1",
    "action": "login",
    "details": {"result": "success"},
    "labels": ["example"],
    "optional_value": null,
    "_CHANGE_TYPE": "INSERT",
    "_CHANGE_TIMESTAMP": "2026-09-28T20:00:00Z"
  }
}
```

The DCR accepts `Custom-GCPBigQuery` and writes to `Custom-GCPBigQuery_CL`. It preserves the envelope fields and nested `Record` without assuming a business schema or silently substituting timestamps. Unwrapped rows, arrays of rows, malformed JSON, and non-object `Record` values do not satisfy this contract. Pub/Sub transport metadata such as message ID and publish time is not part of this schema.

Use a separate continuous query per source table, keeping the same envelope. You can share the destination topic if every publisher follows this contract. To export only selected columns, replace `source AS Record` with a `STRUCT` of the desired source fields. Review the selected data for sensitive information before exporting. BigQuery's JSON encoding rules apply, including string encoding of large integers.

## 4. Connect in Microsoft Sentinel

The connector source consists of the four JSON files in `GCPBigQuery_CCF/`. The solution manifest registers its connector definition; the solution packaging tooling collects the adjacent polling configuration, DCR, and table files. Rebuild and publish the solution package through the repository packaging workflow before installing this new connector from that package. An existing released package does not contain these new source files.

After deploying the updated solution:

1. Open **Data connectors** and select **Google Cloud Platform BigQuery (via Codeless Connector Framework)**.
2. Select **Add new collector**.
3. Supply the Pub/Sub project ID, project number, subscription name (subscription ID), workload identity provider ID, and Sentinel subscriber service account email.
4. Select **Connect**. The native collector consumes from the pull subscription using workload identity federation.

## Verify and operate

Append a test row to the source table while the export job is running, then query:

```kusto
GCPBigQuery_CL
| where TimeGenerated > ago(1h)
| project TimeGenerated, ProjectId, DatasetId, TableId, Record
| top 20 by TimeGenerated desc
```

Query nested fields according to your source schema, for example:

```kusto
GCPBigQuery_CL
| extend EventId = tostring(Record.event_id), Action = tostring(Record.action)
| project TimeGenerated, ProjectId, DatasetId, TableId, EventId, Action
```

- If no rows arrive, check that the continuous query is running, its reservation has capacity, and the export topic and subscription are correct. Check Pub/Sub backlog and publisher metrics before checking Sentinel collector health.
- For authorization errors, verify the exporter and subscriber permissions separately, including the pool ID, provider audience/issuer, and numeric project number. Do not replace federation with a service account key.
- For ingestion errors, check the decoded message against the envelope and confirm the DCR input stream, output table, and data collection endpoint. Use a separate diagnostic subscription if inspecting messages; pulling and acknowledging from the Sentinel subscription removes those messages from its backlog.
- Pub/Sub redelivery and overlapping exports can produce duplicates. Include a stable source event ID in `Record` and deduplicate in downstream queries if required; this connector does not promise exactly-once ingestion.
- Monitor and restart continuous query jobs as required by Google's runtime limits. Monitor subscription retention/backlog to avoid losing messages during outages. Source schema changes may require restarting the continuous query even though `Record` accepts arbitrary JSON fields.
- Pausing or deleting the Sentinel collector does not stop the BigQuery job or Pub/Sub charges. Stop the export job separately when decommissioning the integration.
