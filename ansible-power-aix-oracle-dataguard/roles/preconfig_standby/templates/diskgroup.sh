#!/bin/bash

export ORACLE_SID=$(ps -ef | grep pmon | grep ASM | awk '{match($NF, /\+ASM[0-9]*/); print substr($NF, RSTART, RLENGTH)}')
export ORACLE_HOME=$(awk -F: -v sid="$ORACLE_SID" '$1 == sid {print $2}' /etc/oratab)
export PATH=$PATH:$ORACLE_HOME/bin

# Fetch the disk group name from  ASM
su - {{ grid_user }} -c "sqlplus -s / as sysdba" <<SQL | tee "$MASTER_LOG"
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SET LINESIZE 1000
SET TRIMOUT ON
SET TRIMSPOOL ON

-- Fetch ASM disk group
SELECT 'DISKGROUP:' || NAME FROM v\$asm_diskgroup WHERE STATE='MOUNTED';

SQL

DISKGROUP=$(grep "DISKGROUP:" "$MASTER_LOG" | awk -F ':' '{print $2}')

# Check if disk group was retrieved
if [[ -z "$DISKGROUP" ]]; then
  echo "ERROR:Failed to fetch disk group from ASM, verify manually and retry" | tee -a "$FAILURE_LOG"
  exit 1
fi

diskgroup="+${DISKGROUP}"

# Print only the DBID (for Ansible to capture correctly)
echo "$diskgroup"

rm -f "$FAILURE_LOG"
exit 0
