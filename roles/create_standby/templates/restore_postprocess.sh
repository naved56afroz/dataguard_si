#!/bin/bash

export ORACLE_SID={{ databases.standby.db_sid }}
export ORACLE_HOME={{ databases.standby.oracle_db_home }}
export PATH={{ databases.standby.oracle_db_home }}/bin:$PATH

MASTER_LOG="{{ done_dir }}/standby_post_restore.log"
FAILURE_LOG="{{ done_dir }}/standby_post_restore_failure.log"
RESTORE_LOG_FILE="{{ done_dir }}/standby_rman_restore.log"
PFILE=${ORACLE_HOME}/dbs/init${ORACLE_SID}.ora
TMP_FILE="${PFILE}.tmp"

# Ensure log files are empty before running
> "$MASTER_LOG"
> "$FAILURE_LOG"

# Convert 'with_backup' variable to lowercase for consistency
WITH_BACKUP="$(echo {{ with_backup }} | tr '[:upper:]' '[:lower:]')"

# Check if RMAN Restore was successful
if [[ "$WITH_BACKUP" == "true" ]]; then 
  if ! grep -q "Finished recover at" "$RESTORE_LOG_FILE"; then
      echo "ERROR: RMAN Recover failed or incomplete. Exiting..." | tee -a "$FAILURE_LOG"
      exit 1
  fi
  
  # Extract Controlfile Location from RMAN Logs
  CONTROLFILE_PATH=$(grep "output file name=" "$RESTORE_LOG_FILE" | awk -F '=' '{print $2}' | tr -d ' ')
  if [[ -z "$CONTROLFILE_PATH" ]]; then
      echo "ERROR: Controlfile location not found in RMAN logs." | tee -a "$FAILURE_LOG"
      exit 1
  fi
  
  # Update PFILE with new Controlfile Location
  awk 'tolower($0) !~ /(control_files)/' "$PFILE" > "$TMP_FILE"
  echo "*.control_files = '$CONTROLFILE_PATH'" >> "$TMP_FILE"
  
  # Replace the original file
  mv "$TMP_FILE" "$PFILE"
  
  # Create SPFILE from PFILE on standby database
  su - {{ db_oracle_user }} -c "sqlplus -s / as sysdba" <<SQL | tee -a "$MASTER_LOG"
  CREATE SPFILE FROM PFILE='$PFILE';
  SHUTDOWN IMMEDIATE;
  STARTUP MOUNT;
  ALTER SYSTEM REGISTER;
  EXIT;
SQL

elif [[ "$WITH_BACKUP" == "false" ]]; then
  # Check if media recovery is active
  STATUS=$(su - {{ db_oracle_user }} -c "sqlplus -s / as sysdba" <<SQL | tee -a "$MASTER_LOG"
  SET HEADING OFF FEEDBACK OFF VERIFY OFF ECHO OFF
  SELECT COUNT(*) FROM V\$MANAGED_STANDBY WHERE PROCESS = 'MRP0';
  EXIT;
SQL
  )
  
  # Extract the result, removing whitespace
  STATUS=$(echo "$STATUS" | grep -Eo '^[0-9]+$')
  
  if [[ "$STATUS" -gt 0 ]]; then
      echo "Media recovery is already active. No action needed." | tee -a "$MASTER_LOG"
      touch "{{ done_dir }}/post_restore.success"
      exit 0
  else
      echo "Starting media recovery..." | tee -a "$MASTER_LOG"
      su - {{ db_oracle_user }} -c "sqlplus -s / as sysdba" <<SQL | tee -a "$MASTER_LOG"
      ALTER DATABASE RECOVER MANAGED STANDBY DATABASE DISCONNECT FROM SESSION;
      EXIT;
SQL
      touch "{{ done_dir }}/post_restore.success"
  fi

else
  echo "ERROR: Invalid value for 'with_backup'. Please provide 'true' or 'false'." | tee -a "$FAILURE_LOG"
  exit 1
fi

# Check for failures and exit accordingly
if [[ -s "$FAILURE_LOG" ]]; then
    cat "$FAILURE_LOG"
    rm -f "$FAILURE_LOG"
    exit 1
fi

echo "Dataguard recovery process started successfully" | tee -a "$MASTER_LOG"
touch "{{ done_dir }}/post_restore.success"
exit 0