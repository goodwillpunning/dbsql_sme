-- Databricks notebook source
-- MAGIC %md
-- MAGIC ## How to Create, manage, and sync Uniform - Icberg Tables in Databricks

-- COMMAND ----------

-- DBTITLE 1,Step 1 - Create a Uniform Table
CREATE CATALOG IF NOT EXISTS main;
CREATE SCHEMA IF NOT EXISTS main.cody_uniform_demo;
USE CATALOG main;
USE SCHEMA cody_uniform_demo;


-- COMMAND ----------

-- DBTITLE 1,Create new Uniform tables OOTB
CREATE OR REPLACE TABLE bronze_sensors
(
Id BIGINT GENERATED BY DEFAULT AS IDENTITY,
device_id INT,
user_id INT,
calories_burnt DECIMAL(10,2), 
miles_walked DECIMAL(10,2), 
num_steps DECIMAL(10,2), 
timestamp TIMESTAMP,
value STRING,
ingest_timestamp TIMESTAMP_NTZ DEFAULT current_timestamp()::timestamp_ntz
)
CLUSTER BY (ingest_timestamp)
TBLPROPERTIES(
  'delta.feature.allowColumnDefaults' = 'supported',
  'delta.feature.timestampNtz' = 'supported',
  'delta.columnMapping.mode' = 'name',
  'delta.enableIcebergCompatV2' = 'true',
  'delta.universalFormat.enabledFormats' = 'iceberg')

-- COMMAND ----------

-- DBTITLE 1,Idempotent Ingestion via COPY INTO
COPY INTO bronze_sensors
FROM (SELECT 
      id::bigint AS Id,
      device_id::integer AS device_id,
      user_id::integer AS user_id,
      calories_burnt::decimal(10,2) AS calories_burnt, 
      miles_walked::decimal(10,2) AS miles_walked, 
      num_steps::decimal(10,2) AS num_steps,
      timestamp::timestamp AS timestamp,
      value  AS value -- This is a JSON object
FROM "/databricks-datasets/iot-stream/data-device/")
FILEFORMAT = json -- csv, xml, txt, parquet, binary, etc.
COPY_OPTIONS('force'='true') --'true' always loads all data it sees. option to be incremental or always load all files
;

-- COMMAND ----------

-- DBTITLE 1,Manually Synchronously Update Iceberg Metadata
MSCK REPAIR TABLE bronze_sensors SYNC METADATA

-- COMMAND ----------

SELECT * FROM bronze_sensors

-- COMMAND ----------

-- DBTITLE 1,How to add new columns with default generated values
ALTER TABLE bronze_sensors ADD COLUMN name STRING; -- Must define the column first

ALTER TABLE bronze_sensors 
ALTER COLUMN name SET DEFAULT 'cody';

-- COMMAND ----------

-- DBTITLE 1,Manually sync iceberg metadata
MSCK REPAIR TABLE bronze_sensors SYNC METADATA

-- COMMAND ----------

-- DBTITLE 1,New columns are NOT automatically backfilled on existing data - only new writes
SELECT * FROM bronze_sensors

-- COMMAND ----------

-- DBTITLE 1,Must truncate and reload or update script
TRUNCATe TABLe bronze_sensors;

-- COMMAND ----------

COPY INTO bronze_sensors
FROM (SELECT 
      id::bigint AS Id,
      device_id::integer AS device_id,
      user_id::integer AS user_id,
      calories_burnt::decimal(10,2) AS calories_burnt, 
      miles_walked::decimal(10,2) AS miles_walked, 
      num_steps::decimal(10,2) AS num_steps,
      timestamp::timestamp AS timestamp,
      value  AS value -- This is a JSON object
FROM "/databricks-datasets/iot-stream/data-device/")
FILEFORMAT = json -- csv, xml, txt, parquet, binary, etc.
COPY_OPTIONS('force'='true') --'true' always loads all data it sees. option to be incremental or always load all files
;

-- COMMAND ----------

-- DBTITLE 1,Now new data honors new defaults
SELECT * FROM bronze_sensors;

-- COMMAND ----------

-- DBTITLE 1,Take Exising Table and Enable Uniform
CREATE OR REPLACE TABLE silver_sensors
(
Id BIGINT GENERATED BY DEFAULT AS IDENTITY,
device_id INT,
user_id INT,
calories_burnt DECIMAL(10,2), 
miles_walked DECIMAL(10,2), 
num_steps DECIMAL(10,2), 
timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
value STRING
)
CLUSTER BY (timestamp, user_id, device_id)
TBLPROPERTIES(
  'delta.feature.allowColumnDefaults' = 'supported',
  'delta.feature.timestampNtz' = 'supported',
  'delta.columnMapping.mode' = 'name',
  'delta.enableIcebergCompatV2' = 'true',
  'delta.universalFormat.enabledFormats' = 'iceberg')

-- COMMAND ----------

-- DBTITLE 1,Convert Existing Table To Unifrom
REORG TABLE silver_sensors APPLY (UPGRADE UNIFORM(ICEBERG_COMPAT_VERSION=2));

-- COMMAND ----------

-- DBTITLE 1,Load some data to Uniform tables!
-- Raw to Bronze

COPY INTO bronze_sensors
FROM (SELECT 
      id::bigint AS Id,
      device_id::integer AS device_id,
      user_id::integer AS user_id,
      calories_burnt::decimal(10,2) AS calories_burnt, 
      miles_walked::decimal(10,2) AS miles_walked, 
      num_steps::decimal(10,2) AS num_steps, 
      timestamp::timestamp AS timestamp,
      value  AS value -- This is a JSON object
FROM "/databricks-datasets/iot-stream/data-device/")
FILEFORMAT = json -- csv, xml, txt, parquet, binary, etc.
COPY_OPTIONS('force'='false') --'true' always loads all data it sees. option to be incremental or always load all files
;

MERGE INTO silver_sensors AS target
USING (
WITH de_dup (
SELECT Id::integer,
              device_id::integer,
              user_id::integer,
              calories_burnt::decimal,
              miles_walked::decimal,
              num_steps::decimal,
              timestamp::timestamp,
              value::string,
              ROW_NUMBER() OVER(PARTITION BY device_id, user_id, timestamp ORDER BY timestamp DESC) AS DupRank
              FROM bronze_sensors
              )
              
SELECT Id, device_id, user_id, calories_burnt, miles_walked, num_steps, timestamp, value
FROM de_dup
WHERE DupRank = 1
) AS source
ON source.Id = target.Id
AND source.user_id = target.user_id
AND source.device_id = target.device_id
WHEN MATCHED THEN UPDATE SET 
  target.calories_burnt = source.calories_burnt,
  target.miles_walked = source.miles_walked,
  target.num_steps = source.num_steps,
  target.timestamp = source.timestamp
WHEN NOT MATCHED THEN INSERT *;

-- This calculate table stats for all columns to ensure the optimizer can build the best plan
-- THIS IS NOT INCREMENTAL
ANALYZE TABLE silver_sensors COMPUTE STATISTICS FOR ALL COLUMNS;

-- Liquid Clustering
OPTIMIZE silver_sensors ;


-- Truncate bronze batch once successfully loaded

-- This is the classical batch design pattern - but we can also now use streaming tables

TRUNCATE TABLE bronze_sensors;

-- COMMAND ----------

-- DBTITLE 1,Review Table Uniform Metadata
-- Review table metadata
-- Latest Uniform Delta Version
-- Latest Iceberg Metadata File (for Snowflake Syncs)


-- 3 values - Metadatalocation, converted delta version, converted delta timestamp
DESCRIBE TABLE EXTENDED silver_sensors;

-- COMMAND ----------

-- DBTITLE 1,Programmatically Get Metadata (not DBSQL code)
-- MAGIC %python
-- MAGIC
-- MAGIC from pyspark.sql.functions import col
-- MAGIC
-- MAGIC uniform_metadata = spark.sql("DESCRIBE TABLE EXTENDED silver_sensors").filter(col("col_name") == "Metadata location").select("data_type").collect()[0][0]
-- MAGIC
-- MAGIC uniform_latdata_delta_verison = spark.sql("DESCRIBE TABLE EXTENDED silver_sensors").filter(col("col_name") == "Converted delta version").select("data_type").collect()[0][0]
-- MAGIC                                                                                            
-- MAGIC print(f"Latest Metadata: {uniform_metadata}")
-- MAGIC print(f"Latest Delta Version: {uniform_latdata_delta_verison}")

-- COMMAND ----------

-- DBTITLE 1,Manually Sync Metadata as needed
MSCK REPAIR TABLE silver_sensors SYNC METADATA

-- COMMAND ----------

-- MAGIC %environment
-- MAGIC "client": "1"
-- MAGIC "base_environment": ""
