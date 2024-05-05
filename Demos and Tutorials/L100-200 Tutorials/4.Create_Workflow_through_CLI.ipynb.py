# Databricks notebook source
# MAGIC %md
# MAGIC

# COMMAND ----------

databricks jobs create --json '
{
  "name": "Orchestrating_SQL_Files_on_DBSQL_WAREHOUSE",
  "tasks": [
    {
      "task_key": "Create_Tables",
      "run_if": "ALL_SUCCESS",
      "sql_task": {
        "file": {
          "path": "Demos and Tutorials/L100-200 Tutorials/1.Create_Tables.sql",
          "source": "GIT"
        },
        "warehouse_id": "d1184b8c2a8a87eb"
      }
    },
    {
      "task_key": "Load_Data",
      "depends_on": [
        {
          "task_key": "Create_Tables"
        }
      ],
      "run_if": "ALL_SUCCESS",
      "sql_task": {
        "file": {
          "path": "/Repos/saurabh.shukla@databricks.com/dbsql_sme/Demos and Tutorials/L100-200 Tutorials/2.Load_Data.sql",
          "source": "WORKSPACE"
        },
        "warehouse_id": "d1184b8c2a8a87eb"
      }
    },
    {
      "task_key": "Query_Fact_Sales",
      "depends_on": [
        {
          "task_key": "Load_Data"
        }
      ],
      "run_if": "ALL_SUCCESS",
      "sql_task": {
        "file": {
          "path": "/Repos/saurabh.shukla@databricks.com/dbsql_sme/Demos and Tutorials/L100-200 Tutorials/3.Query_Fact_Sales.sql",
          "source": "WORKSPACE"
        },
        "warehouse_id": "d1184b8c2a8a87eb"
      }
    }
  ],
  "git_source": {
    "git_url": "https://github.com/saurabhshukla-db/dbsql_sme.git",
    "git_provider": "gitHub",
    "git_branch": "feature_branch_sqlfiles"
  },
  "run_as": {
    "user_name": "saurabh.shukla@databricks.com"
  }
}
'

# COMMAND ----------

databricks jobs create --json '
{
  "name": "Orchestrating_SQL_Files_on_DBSQL_WAREHOUSE",
  "tasks": [
    {
      "task_key": "Create_Tables",
      "run_if": "ALL_SUCCESS",
      "sql_task": {
        "file": {
          "path": "<GITPATH>/1.Create_Tables.sql",
          "source": "GIT"
        },
        "warehouse_id": "<DBSQL warehouse_id>"
      }
    },
    {
      "task_key": "Load_Data",
      "depends_on": [
        {
          "task_key": "Create_Tables"
        }
      ],
      "run_if": "ALL_SUCCESS",
      "sql_task": {
        "file": {
          "path": "<GITPATH>/2.Load_Data.sql",
          "source": "WORKSPACE"
        },
        "warehouse_id": "<DBSQL warehouse_id>"
      }
    },
    {
      "task_key": "Query_Fact_Sales",
      "depends_on": [
        {
          "task_key": "Load_Data"
        }
      ],
      "run_if": "ALL_SUCCESS",
      "sql_task": {
        "file": {
          "path": "<GITPATH>/3.Query_Fact_Sales.sql",
          "source": "WORKSPACE"
        },
        "warehouse_id": "<DBSQL warehouse_id>"
      }
    }
  ],
  "git_source": {
    "git_url": "https://github.com/<GITUSERNAME>/dbsql_sme.git",
    "git_provider": "gitHub",
    "git_branch": "feature_branch_sqlfiles"
  },
  "run_as": {
    "user_name": "<username>@<domain>.com"
  }
}
'
