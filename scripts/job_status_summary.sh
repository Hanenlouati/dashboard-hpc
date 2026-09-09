#!/bin/bash
source /cassandra/opt/ibm/lsfsuite/lsf/conf/profile.lsf
export PATH=/cassandra/opt/anaconda/3-2024.10-1/bin:/opt/ibm/lsfsuite/lsf/10.1/linux3.10-glibc2.17-x86_64/bin:/usr/bin:/bin:/usr/sbin:/sbin
 

# File: job_status_summary.sh
# Description: Extracts LSF job state summary for a specified list of users in group "goco"
#              Pushes Prometheus metrics for every allowed user (zero if none).
# Usage: run this script periodically (e.g., every minute) so Prometheus scrapes fresh zero-values.

########## Configuration ##########

USERS_FILE="/work/cmcc/hl06625/dashboard/users.txt"
LOG_DIR="/work/cmcc/hl06625/dashboard/jobs_summary_logs"
PUSHGATEWAY_URL="http://192.168.96.42:9091"
LSF_USER_GROUP="goco"
#####################################
# Timestamps
now_epoch=$(date +%s)
date_human=$(date --iso-8601=seconds)

# Load allowed users
mapfile -t allowed_users < <(grep -Ev '^(#|$)' "$USERS_FILE")
if [[ ${#allowed_users[@]} -eq 0 ]]; then
    echo "[$(date)] WARN: No allowed users found in $USERS_FILE" 
    exit 1
fi

# Temp file for intermediate job states
pending_tmp="/tmp/pending_jobs_${now_epoch}.tmp"
: > "$pending_tmp"

now_epoch=$(date +%s)

# Collect jobs: user|PEND|age or user|RUN|0
bjobs -u "$LSF_USER_GROUP" -o "user stat submit_time" -noheader 2>/dev/null | while read -r user stat rest; do
    # Only allowed users
    is_allowed=1
    for au in "${allowed_users[@]}"; do
        if [[ "$user" == "$au" ]]; then
            is_allowed=0
            break
        fi
    done
    [[ $is_allowed -eq 0 ]] || continue

    if [[ "$stat" == "PEND" ]]; then
        submit_time="$rest $(date +%Y)"
        epoch=$(date -d "$submit_time" +%s 2>/dev/null)
        if [[ $? -ne 0 ]]; then
            age=0
            echo "[$(date)] WARN: cannot parse submit_time='$submit_time' for user=$user" 
        else
            age=$(( now_epoch - epoch ))
            (( age < 0 )) && age=0
        fi
        echo "$user|PEND|$age" >> "$pending_tmp"
    elif [[ "$stat" == "RUN" ]]; then
        echo "$user|RUN|0" >> "$pending_tmp"
    fi
done

# Prepare metrics
JOBS_REPORT=""

for user in "${allowed_users[@]}"; do
    # Initialize avg_age to 0 before any calculation
    avg_age=0

    # Count RUN and PEND
    run_count=$(awk -F'|' -v u="$user" '$1==u && $2=="RUN"' "$pending_tmp" | wc -l)
    pend_count=$(awk -F'|' -v u="$user" '$1==u && $2=="PEND"' "$pending_tmp" | wc -l)

    # Sum ages for pending jobs
    total_age=$(awk -F'|' -v u="$user" '$1==u && $2=="PEND" {sum+=$3} END {print sum+0}' "$pending_tmp")

    # Compute average pending age if any pending; else avg_age remains 0
    if (( pend_count > 0 )); then
        avg_age=$(( total_age / pend_count ))
    fi

    # Determine health
    if (( pend_count > 10 && avg_age > 3600 )); then
        health="red"
    elif (( pend_count > 5 )); then
        health="yellow"
    else
        health="green"
    fi

    echo "$user|$run_count|$pend_count|$avg_age|$health" 

    # Emit one composite metric
    JOBS_REPORT+="job_summary{user=\"$user\",running=\"$run_count\",pending=\"$pend_count\",avg_age=\"$avg_age\",health=\"$health\"} 1\n"
done

# Push to Pushgateway
THISHOST=$(hostname)
job="${THISHOST}_JobStatus"
instance="${THISHOST}"
REMOTE_URL="$PUSHGATEWAY_URL/metrics/job/${job}/instance/${instance}"

echo -e "$JOBS_REPORT" | curl -s --data-binary @- "$REMOTE_URL"
if [[ $? -eq 0 ]]; then
  echo "[$date_human] Pushed host metrics successfully"
else
  echo "[$date_human] ERROR pushing host metrics" >&2
fi


rm -f "$pending_tmp"
