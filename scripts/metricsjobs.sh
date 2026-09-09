#!/usr/bin/env bash
source /cassandra/opt/ibm/lsfsuite/lsf/conf/profile.lsf
export PATH=/cassandra/opt/anaconda/3-2024.10-1/bin:/opt/ibm/lsfsuite/lsf/10.1/linux3.10-glibc2.17-x86_64/bin:/usr/bin:/bin:/usr/sbin:/sbin


set -euo pipefail
IFS=$'\n\t'

# Script: lsf_metrics_all_users.sh
# Description: For each user in USERS_FILE, logs LSF job metrics for multiple time windows and pushes to Prometheus Pushgateway.

now_epoch=$(date +%s)
date_human=$(date --iso-8601=seconds)

# Configuration
USERS_FILE="/work/cmcc/hl06625/dashboard/users.txt"
PUSHGATEWAY_URL="http://192.168.96.42:9091"
THISHOST=$(hostname)
JOB_NAME="metrics"

# Log and state directories


# Load allowed users
if [[ ! -f "$USERS_FILE" ]]; then
    echo "[$date_human] ERROR: USERS_FILE not found: $USERS_FILE" >&2
    exit 1
fi
mapfile -t allowed_users < <(grep -Ev '^(#|$)' "$USERS_FILE")
if [[ ${#allowed_users[@]} -eq 0 ]]; then
    echo "[$date_human] WARN: No users in $USERS_FILE" >&2
    exit 0
fi

# Time ranges to simulate
TIME_RANGES=("6h" "24h" "7d" "3d")

# Loop over each user and time range
for user in "${allowed_users[@]}"; do
  for range in "${TIME_RANGES[@]}"; do
    METRICS_PAYLOAD=""

    # Calculate epoch cutoff
    case "$range" in
      *h) delta=$(( ${range%h} * 3600 )) ;;
      *d) delta=$(( ${range%d} * 86400 )) ;;
      *) echo "[$date_human] ERROR: Unsupported time range: $range" >&2; continue ;;
    esac
    since=$(( now_epoch - delta ))

    # Job state counts
    pending=$(bjobs -u "$user" 2>/dev/null | awk '$3=="PEND"{c++}END{print c+0}')
    running=$(bjobs -u "$user" 2>/dev/null | awk '$3=="RUN"{c++}END{print c+0}')
    METRICS_PAYLOAD+="# TYPE job_pending_total gauge\n"
    METRICS_PAYLOAD+="job_pending_total{user=\"$user\"} $pending\n"
    METRICS_PAYLOAD+="# TYPE job_running_total gauge\n"
    METRICS_PAYLOAD+="job_running_total{user=\"$user\"} $running\n"

    # Average pending age
    ages=()
    while read -r stat rest; do
      [[ "$stat" != "PEND" ]] && continue
      epoch=$(date -d "$rest $(date +%Y)" +%s 2>/dev/null || echo 0)
      (( epoch>0 )) && ages+=( $(( now_epoch - epoch )) )
    done < <(bjobs -u "$user" -o "stat submit_time" -noheader 2>/dev/null)

    avg_age=0
    if (( ${#ages[@]}>0 )); then
      total=0
      for a in "${ages[@]}"; do total=$((total + a)); done
      avg_age=$(( total / ${#ages[@]} ))
    fi
    METRICS_PAYLOAD+="# TYPE avg_pending_age_seconds gauge\n"
    METRICS_PAYLOAD+="avg_pending_age_seconds{user=\"$user\"} $avg_age\n"

    # Push basic metrics (no range in URL)
    BASIC_METRICS=$(echo -e "$METRICS_PAYLOAD" | grep -E 'job_pending_total|job_running_total|avg_pending_age_seconds')
    if [[ -n "$BASIC_METRICS" ]]; then
        echo -e "$BASIC_METRICS" \
        | curl -s -X POST --data-binary @- "$PUSHGATEWAY_URL/metrics/job/${JOB_NAME}/instance/${THISHOST}/user/${user}"
        if [[ $? -ne 0 ]]; then
            echo "[$(date)] ERROR: Failed to push metrics to Pushgateway at $REMOTE_URL"
        fi
    fi

    # Throughput & success rate based on submit_time within range
    done_jobs=$(bjobs -d -u "$user" 2>/dev/null | awk -v since="$since" 'BEGIN{c=0} $3=="DONE"{
        cmd="date -d \""$8" "$9" "$10" $(date +%Y)\" +%s"; cmd|getline t; close(cmd)
        if (t>=since) c++
    } END{print c+0}')
    total_jobs=$(bjobs -d -u "$user" 2>/dev/null | awk -v since="$since" 'BEGIN{c=0} $3=="DONE"||$3=="EXIT"{
        cmd="date -d \""$8" "$9" "$10" $(date +%Y)\" +%s" ; cmd|getline t; close(cmd)
        if (t>=since) c++
    } END{print c+0}')
    success_rate=0
    if (( total_jobs>0 )); then
        success_rate=$(awk "BEGIN{printf \"%.2f\",100*$done_jobs/$total_jobs}")
    fi
    RANGED_METRICS="# TYPE job_throughput_total gauge\n"
    RANGED_METRICS+="job_throughput_total{user=\"$user\",range=\"$range\"} $done_jobs\n"
    RANGED_METRICS+="# TYPE job_success_rate_percent gauge\n"
    RANGED_METRICS+="job_success_rate_percent{user=\"$user\",range=\"$range\"} $success_rate\n"

    echo -e "$RANGED_METRICS" \
    | curl -s -X POST --data-binary @- "$PUSHGATEWAY_URL/metrics/job/${JOB_NAME}/instance/${THISHOST}/user/${user}/range/${range}"
    if [[ $? -ne 0 ]]; then
    echo "[$(date)] ERROR: Failed to push metrics to Pushgateway at $REMOTE_URL"
    fi
  done


done

# End of script
