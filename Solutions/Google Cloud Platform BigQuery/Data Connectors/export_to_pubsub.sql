EXPORT DATA OPTIONS (
  format = 'CLOUD_PUBSUB',
  uri = 'https://pubsub.googleapis.com/projects/PUBSUB_PROJECT_ID/topics/TOPIC_ID'
) AS (
  SELECT TO_JSON_STRING(STRUCT(
    source._CHANGE_TIMESTAMP AS TimeGenerated,
    'SOURCE_PROJECT_ID' AS ProjectId,
    'DATASET_ID' AS DatasetId,
    'TABLE_ID' AS TableId,
    source AS Record
  )) AS message
  FROM APPENDS(
    TABLE `SOURCE_PROJECT_ID.DATASET_ID.TABLE_ID`,
    CURRENT_TIMESTAMP() - INTERVAL 10 MINUTE
  ) AS source
);
