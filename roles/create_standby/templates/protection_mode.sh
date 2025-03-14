#!/bin/bash

# Set environment variables manually (Modify as needed)
export ORACLE_SID={{ databases[database_name].db_sid }}
export ORACLE_HOME={{ databases[database_name].oracle_db_home }}
export PATH={{ databases[database_name].oracle_db_home }}/bin:$PATH

# Set log_archive_dest_2 dynamically based on data protection modes
## Maximum Performance (Default - ASYNC)
if [[ "{{ dataguard_protection_mode | lower }}" == "maximum_performance" ]]; then
    dataguard_protection_mode="PERFORMANCE"
## Maximum Availability (SYNC)
elif [[ "{{ dataguard_protection_mode | lower }}" == "maximum_availability" ]]; then
    dataguard_protection_mode="AVAILABILITY"
## Maximum Protection (SYNC with AFFIRM)
elif [[ "{{ dataguard_protection_mode | lower }}" == "maximum_protection" ]]; then
    dataguard_protection_mode="PROTECTION"
else
    echo "Invalid data protection mode! Provide data protection modes out of three: maximum_availability, maximum_performance, or maximum_protection." | tee -a "$FAILURE_LOG"
    exit 1
fi

  # Change protection Mode in primary
  su - {{ db_oracle_user }} -c "sqlplus -s / as sysdba" <<SQL | tee -a "$MASTER_LOG"
  SET HEADING OFF
  SET FEEDBACK OFF
  SET PAGESIZE 0
  SET LINESIZE 1000
  SET TRIMOUT ON
  SET TRIMSPOOL ON
  SET ECHO ON;
  SET SERVEROUTPUT ON;
  WHENEVER SQLERROR EXIT SQL.SQLCODE;
  WHENEVER OSERROR EXIT FAILURE;
  ALTER DATABASE SET STANDBY DATABASE TO MAXIMIZE \$dataguard_protection_mode;
  -- Fetch dataguard protection mode
  SELECT 'PROTECTION_MODE:' || PROTECTION_MODE from v\$database;
  EXIT;
SQL
  )

PROTECTION_MODE=$(grep "PROTECTION_MODE:" "$MASTER_LOG" | awk -F ':' '{print $2}')


if [[ "$PROTECTION_MODE" == {{ dataguard_protection_mode }} ]]; then
    echo "Dataguard successfully configured with PROTECTION_MODE: {{ dataguard_protection_mode }}" | tee -a "$MASTER_LOG"
    touch "{{ done_dir }}/dataguard.success"
    /usr/bin/scp {{ done_dir }}/dataguard.success {{ standby_host }}:{{ done_dir }}/dataguard.success
else 
    echo "ERROR: Dataguard configuration failed , verify logs" | tee -a "$FAILURE_LOG"
fi

# Check for failures and exit accordingly
if [[ -s "$FAILURE_LOG" ]]; then
    cat "$FAILURE_LOG"
    rm -f "$FAILURE_LOG"
    exit 1
fi

echo "Dataguard recovery process started successfully" | tee -a "$MASTER_LOG"
touch "{{ done_dir }}/dataguard.success"
exit 0