#!/bin/bash

# Set environment variables
export ORACLE_SID={{ databases[database_name].db_sid }}
export ORACLE_HOME={{ databases[database_name].oracle_db_home }}
export PATH={{ databases[database_name].oracle_db_home }}/bin:$PATH

MASTER_LOG="{{ done_dir }}/standby_post_restore.log"
FAILURE_LOG="{{ done_dir }}/standby_post_restore_failure.log"
RESTORE_LOG_FILE="{{ done_dir }}/standby_rman_restore.log"
PFILE=${ORACLE_HOME}/dbs/init${ORACLE_SID}.ora
TMP_FILE="${PFILE}.tmp"

# Ensure log files are empty before running
> "$MASTER_LOG"
> "$FAILURE_LOG"

# Check if RMAN Restore was successful
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

# Capture SQL*Plus exit status
sqlplus_exit_code=$?

# Validate SQL*Plus exit status
if [[ $sqlplus_exit_code -ne 0 ]]; then
    echo "ERROR: SQL*Plus command failed. Check logs for details." | tee -a "$FAILURE_LOG"
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
rm -f "$FAILURE_LOG"
exit 0