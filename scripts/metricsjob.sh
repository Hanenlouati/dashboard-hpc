#!/bin/sh
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
LOG_DIR="/work/cmcc/hl06625/dashboard/logs"
mkdir -p "$LOG_DIR"

# Load allowed users
if [ ! -f "$USERS_FILE" ]; then
    echo "[$date_human] ERROR: USERS_FILE not found: $USERS_FILE" >&2
    exit 1
fi

allowed_users=""
while IFS= read -r line; do
    case "$line" in
        ''|\#*) ;;  # skip empty or comment lines
        *) allowed_users="$allowed_users $line" ;;
    esac
done < "$USERS_FILE"

if [ -z "$allowed_users" ]; then
    echo "[$date_human] WARN: No users in $USERS_FILE" >&2
    exit 0
fi

# Time ranges to simulate
TIME_RANGES="6h 24h 7d"

# Loop over each user and time range
for user in $allowed_users; do
    for range in $TIME_RANGES; do
        METRICS_PAYLOAD=""

        # Calculate epoch cutoff
        case "$range" in
            *h) delta=$(expr $(echo "$range" | sed 's/h//') \* 3600) ;;
            *d) delta=$(expr $(echo "$range" | sed 's/d//') \* 86400) ;;
            *) echo "[$date_human] ERROR: Unsupported time range: $range" >&2; continue ;;
        esac
        since=$(expr "$now_epoch" - "$delta")

        # Job state counts
        pending=$(bjobs -u "$user" 2>/dev/null | awk '$3=="PEND"{c++}END{print c+0}')
        running=$(bjobs -u "$user" 2>/dev/null | awk '$3=="RUN"{c++}END{print c+0}')

        METRICS_PAYLOAD="# TYPE job_pending_total gauge
job_pending_total0{user=\"$user\"} $pending
# TYPE job_running_total gauge
job_running_total0{user=\"$user\"} $running
"

        # Average pending age
        ages=""
        bjobs -u "$user" -o "stat submit_time" -noheader 2>/dev/null | while read stat rest; do
            if [ "$stat" = "PEND" ]; then
                epoch=$(date -d "$rest $(date +%Y)" +%s 2>/dev/null || echo 0)
                if [ "$epoch" -gt 0 ]; then
                    ages="$ages $((now_epoch - epoch))"
                fi
            fi
        done

        avg_age=0
        if [ -n "$ages" ]; then
            total=0
            for a in $ages; do
                total=$(expr $total + $a)
            done
            count=0
            for _ in $ages; do count=$(expr $count + 1); done
            avg_age=$(expr $total / $count)
        fi

        METRICS_PAYLOAD="$METRICS_PAYLOAD# TYPE avg_pending_age_seconds gauge
avg_pending_age_seconds0{user=\"$user\"} $avg_age
"

        # Push basic metrics (no range in URL)
        BASIC_METRICS=$(echo "$METRICS_PAYLOAD" | grep -E 'job_pending_total|job_running_total|avg_pending_age_seconds')
        if [ -n "$BASIC_METRICS" ]; then
            echo "$BASIC_METRICS" | curl -s -X POST --data-binary @- "$PUSHGATEWAY_URL/metrics/job/${JOB_NAME}/instance/${THISHOST}/user/${user}"
        fi

        # Throughput & success rate based on submit_time within range
        done_jobs=$(bjobs -d -u "$user" 2>/dev/null | awk -v since="$since" '
            BEGIN{c=0}
            $3=="DONE"{
                cmd="date -d \""$8" "$9" "$10" "strftime("%Y")"\" +%s"; cmd | getline t; close(cmd)
                if (t>=since) c++
            }
            END{print c+0}
        ')
        total_jobs=$(bjobs -d -u "$user" 2>/dev/null | awk -v since="$since" '
            BEGIN{c=0}
            $3=="DONE"||$3=="EXIT"{
                cmd="date -d \""$8" "$9" "$10" "strftime("%Y")"\" +%s"; cmd | getline t; close(cmd)
                if (t>=since) c++
            }
            END{print c+0}
        ')

        success_rate=0
        if [ "$total_jobs" -gt 0 ]; then
            success_rate=$(awk "BEGIN{printf \"%.2f\",100*$done_jobs/$total_jobs}")
        fi

        RANGED_METRICS="# TYPE job_throughput_total gauge
job_throughput_total0{user=\"$user\",range=\"$range\"} $done_jobs
# TYPE job_success_rate_percent gauge
job_success_rate_percent0{user=\"$user\",range=\"$range\"} $success_rate
"

        echo "$RANGED_METRICS" | curl -s -X POST --data-binary @- "$PUSHGATEWAY_URL/metrics/job/${JOB_NAME}/instance/${THISHOST}/user/${user}/range/${range}"
    done
done

# End of script
