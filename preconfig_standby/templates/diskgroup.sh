#!/bin/bash

export ORACLE_SID=$(ps -ef | grep pmon | grep ASM | awk '{match($NF, /\+ASM[0-9]*/); print substr($NF, RSTART, RLENGTH)}')
export ORACLE_HOME=$(awk -F: -v sid="$ORACLE_SID" '$1 == sid {print $2}' /etc/oratab)
export PATH=$PATH:$ORACLE_HOME/bin

MASTER_LOG="{{ done_dir }}/diskgroup.log"
FAILURE_LOG="{{ done_dir }}/diskgroup_failure.log"

# Ensure log files are empty before running
> "$MASTER_LOG"
> "$FAILURE_LOG"

# Fetch the disk group name from  ASM
su - {{ grid_user }} -c "sqlplus -s / as sysdba" <<SQL | awk 'NF {print $1}' > "$MASTER_LOG"
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SET LINESIZE 1000
SET TRIMOUT ON
SET TRIMSPOOL ON

-- Fetch ASM disk group
SELECT NAME FROM v\$asm_diskgroup WHERE STATE='MOUNTED';

SQL

# Read DBID from log file
DISKGROUP=$(cat "$MASTER_LOG")

# Check if disk group was retrieved
if [[ -z "$DISKGROUP" ]]; then
  echo "ERROR:Failed to fetch disk group from ASM, verify manually and retry" | tee -a "$FAILURE_LOG"
  exit 1
fi

diskgroup="+${DISKGROUP}"

# Print only the DBID (for Ansible to capture correctly)
echo "$diskgroup"

#Check for failures and exit accordingly
if [[ -s "$FAILURE_LOG" ]]; then
    cat "$FAILURE_LOG"
    rm -f "$FAILURE_LOG"
    exit 1
fi

rm -f "$FAILURE_LOG"
exit 0
