#!/bin/bash

export ORACLE_SID={{ databases.standby.oracle_db_sid }}
export ORACLE_HOME={{ databases.standby.oracle_db_home }}
export PATH={{ databases.standby.oracle_db_home }}/bin:$PATH

MASTER_LOG="{{ done_dir }}/standby_post_restore.log"
FAILURE_LOG="{{ done_dir }}/standby_post_restore_failure.log"
RESTORE_LOG_FILE="{{ done_dir }}/standby_rman_restore.log"
PFILE={{ databases.standby.oracle_db_home }}/dbs/init{{ databases.standby.oracle_db_sid }}.ora
TMP_FILE="${PFILE}.tmp"

# Ensure log files are empty before running
> "$MASTER_LOG"
> "$FAILURE_LOG"

# Check if RMAN Restore was successful
if ! grep -q "Finished recover at" "$RESTORE_LOG_FILE"; then
    echo "RMAN Recover failed or incomplete. Exiting..." >&2
    exit 1
fi

# Extract Controlfile Location from RMAN Logs
CONTROLFILE_PATH=$(grep "output file name=" "$RESTORE_LOG_FILE" | awk -F '=' '{print $2}' | tr -d ' ')
if [[ -z "$CONTROLFILE_PATH" ]]; then
    echo "Error: Controlfile location not found in RMAN logs." >&2
    exit 1
fi

# Update PFILE with new Controlfile Location
# Remove all matching parameters in one go and create a temp file
awk 'tolower($0) !~ /(control_files)/' "$PFILE" > "$TMP_FILE"

# Append updated parameters at the end
cat <<EOF >> "$TMP_FILE"
*.control_files = ${CONTROLFILE_PATH}
EOF

# Replace the original file
mv "$TMP_FILE" "$PFILE"


# Create SPFILE from PFILE on standby database
su - {{ db_oracle_user }} -c "sqlplus -s / as sysdba" <<SQL | tee "$MASTER_LOG"
CREATE SPFILE FROM PFILE='$PFILE';
SQL

# Create SPFILE from PFILE on standby database
su - {{ db_oracle_user }} -c "sqlplus -s / as sysdba" <<SQL | tee "$MASTER_LOG"
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
alter system register;
EXIT;
SQL

# Check if media recovery is active

STATUS=$(su - {{ db_oracle_user }} -c "sqlplus -s / as sysdba" <<SQL | tee "$MASTER_LOG"
SET HEADING OFF FEEDBACK OFF VERIFY OFF ECHO OFF
SELECT COUNT(*) FROM V\$MANAGED_STANDBY WHERE PROCESS = 'MRP0';
EXIT;
SQL
)

# Extract the result, removing whitespace
STATUS=$(echo "$STATUS" | grep -Eo '^[0-9]+$')

if [[ "$STATUS" -gt 0 ]]; then
    echo "Media recovery is already active. No action needed."
    touch "{{ done_dir }}/dataguard.success"
    exit 0
else
    echo "Starting media recovery..."
    su - {{ db_oracle_user }} -c "sqlplus -s / as sysdba" <<SQL | tee -a "$MASTER_LOG"
    ALTER DATABASE RECOVER MANAGED STANDBY DATABASE DISCONNECT FROM SESSION;
    EXIT;
SQL
touch "{{ done_dir }}/dataguard.success"
fi

#Check for failures and exit accordingly
if [[ -s "$FAILURE_LOG" ]]; then
    cat "$FAILURE_LOG"
    rm -f "$FAILURE_LOG"
    exit 1
fi

echo "Database restarted successfully with SPFILE."
rm -f "$FAILURE_LOG"
exit 0