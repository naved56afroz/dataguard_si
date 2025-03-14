#!/bin/bash

export ORACLE_SID={{ databases.primary.db_sid }}
export ORACLE_HOME={{ databases.primary.oracle_db_home }}
export PATH={{ databases.primary.oracle_db_home }}/bin:$PATH

MASTER_LOG="{{ done_dir }}/primary_dbid.log"
FAILURE_LOG="{{ done_dir }}/primary_dbid_failure.log"

# Ensure log files are empty before running
> "$MASTER_LOG"
> "$FAILURE_LOG"

# Fetch DBID and save only the value in the log file
su - {{ db_oracle_user }} -c "sqlplus -s / as sysdba" <<SQL | awk 'NF {print $1}' > "$MASTER_LOG"
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SET LINESIZE 1000
SET TRIMOUT ON
SET TRIMSPOOL ON

SELECT dbid FROM v\$database;

SQL

# Read DBID from log file
PRIMARY_DBID=$(cat "$MASTER_LOG")

# Validate DBID
if [[ -z "$PRIMARY_DBID" ]]; then
  echo "ERROR: Failed to fetch DBID from Primary Database, verify manually and retry" | tee -a "$FAILURE_LOG"
  exit 1
fi

# Print only the DBID (for Ansible to capture correctly)
echo "$PRIMARY_DBID"

#Check for failures and exit accordingly
if [[ -s "$FAILURE_LOG" ]]; then
    cat "$FAILURE_LOG"
    rm -f "$FAILURE_LOG"
    exit 1
fi

rm -f "$FAILURE_LOG"
exit 0
