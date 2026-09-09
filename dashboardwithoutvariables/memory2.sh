#!/usr/bin/env bash
set -euo pipefail
IFS=$' \t\n'

# ---------------- Configuration ----------------
USERS_FILE="/work/cmcc/hl06625/dashboard/users.txt"
TIME_RANGES=("24h" "3d")
PUSHGATEWAY_URL="http://192.168.96.42:9091"
JOB="memory_job"
INSTANCE=$(hostname)

BASE_URL="${PUSHGATEWAY_URL}/metrics/job/${JOB}/instance/${INSTANCE}"
curl -s -X DELETE "${BASE_URL}" >/dev/null 2>&1 || echo "Warning: could not clear old metrics from Pushgateway"

# Timestamps
now_epoch=$(date +%s)
date_human=$(date --iso-8601=seconds)

echo "=== Run started at $(date) ==="

# Verify users file exists and is readable
if [[ ! -r "$USERS_FILE" ]]; then
  echo "ERROR: Cannot read $USERS_FILE" >&2
  exit 1
fi

now_epoch=$(date +%s)
current_year=$(date +%Y)

# ---------------- Collect job efficiencies and push ----------------
while read -r user; do
    [[ -z "$user" || "$user" == \#* ]] && continue

    raw_jobs=$(bjobs -a -u "$user" -o "jobid stat submit_time" -noheader 2>/dev/null)
    [[ -z "$raw_jobs" || "$raw_jobs" == "No job found" ]] && continue

    jobs=$(grep -E '^[[:space:]]*[0-9]+' <<<"$raw_jobs" | sed -E 's/^[[:space:]]*//')

    for range in "${TIME_RANGES[@]}"; do
        if [[ $range =~ ^([0-9]+)h$ ]]; then
            delta=$((BASH_REMATCH[1]*3600))
        elif [[ $range =~ ^([0-9]+)d$ ]]; then
            delta=$((BASH_REMATCH[1]*86400))
        else
            echo "Warning: invalid range '$range'" >&2
            continue
        fi

        while read -r jobid stat month day hm; do
            [[ $jobid =~ ^[0-9]+$ ]] || continue

            submit_ts="$month $day $hm $current_year"
            submit_epoch=$(LC_ALL=C date -d "$submit_ts" +%s 2>/dev/null) || continue
            (( now_epoch - submit_epoch <= delta )) || continue

            detail=$(bjobs -l "$jobid" 2>/dev/null) || { 
                echo "ERROR: Failed to get details for job $jobid" >&2; 
                continue; 
            }

            memory_eff=$(grep -m1 -oE 'MEM Efficiency:[[:space:]]*([0-9]+(\.[0-9]+)?)' <<<"$detail" \
                        | sed -E 's/.*:[[:space:]]*([0-9]+(\.[0-9]+)?).*/\1/')
            [[ -z "$memory_eff" ]] && memory_eff="N/A"

            cpuu_eff=$(grep -m1 -oE 'CPU AVERAGE EFFICIENCY:[[:space:]]*([0-9]+(\.[0-9]+)?)' <<<"$detail" \
                        | sed -E 's/.*:[[:space:]]*([0-9]+(\.[0-9]+)?).*/\1/')
            [[ -z "$cpuu_eff" ]] && cpuu_eff="N/A"

            # Push Memory Efficiency
            if [[ $memory_eff != "N/A" ]]; then
                printf 'memory_efficiency{user="%s",job_id="%s",range="%s"} %s\n' \
                    "$user" "$jobid" "$range" "$memory_eff" \
                    | curl -s --data-binary @- "$BASE_URL/user/${user}/range/${range}/jobid/${jobid}"
                
                if [[ $? -eq 0 ]]; then
                    echo "[$date_human] Pushed memory efficiency for job $jobid user $user"
                else
                    echo "[$date_human] ERROR pushing memory efficiency for job $jobid user $user" >&2
                fi
            fi

            # Push CPU Efficiency
            if [[ $cpuu_eff != "N/A" ]]; then
                printf 'cpuu_efficiency{user="%s",job_id="%s",range="%s"} %s\n' \
                    "$user" "$jobid" "$range" "$cpuu_eff" \
                    | curl -s --data-binary @- "$BASE_URL/user/${user}/range/${range}/jobid/${jobid}"
                
                if [[ $? -eq 0 ]]; then
                    echo "[$date_human] Pushed CPU efficiency for job $jobid user $user"
                else
                    echo "[$date_human] ERROR pushing CPU efficiency for job $jobid user $user" >&2
                fi
            fi

        done <<< "$jobs"
    done
done < <(grep -Ev '^(#|$)' "$USERS_FILE")

echo "Push complete."
