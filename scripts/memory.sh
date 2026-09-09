#!/usr/bin/env bash
set -euo pipefail
IFS=$' \t\n'

# ---------------- Configuration ----------------
USERS_FILE="/work/cmcc/hl06625/dashboard/users.txt"
TIME_RANGES=("3d")
PUSHGATEWAY_URL="http://192.168.96.42:9091"
JOB="memory_job"
INSTANCE=$(hostname)
BASE_URL="${PUSHGATEWAY_URL}/metrics/job/${JOB}/instance/${INSTANCE}"

# Clear previous metrics for this instance
echo "" | curl -s --data-binary @- "$BASE_URL" >/dev/null 2>&1

# ---------------- Start run ----------------
now_epoch=$(date +%s)
current_year=$(date +%Y)
date_human=$(date --iso-8601=seconds)
echo "=== Run started at $(date) ==="

# Verify users file
if [[ ! -r "$USERS_FILE" ]]; then
    echo "ERROR: Cannot read $USERS_FILE" >&2
    exit 1
fi

# ---------------- Loop over users ----------------
while read -r user; do
    [[ -z "$user" || "$user" == \#* ]] && continue

    raw_jobs=$(bjobs -a -u "$user" -o "jobid stat submit_time" -noheader 2>/dev/null || true)

    # If no jobs at all, push zeros for all ranges immediately
    if [[ -z "$raw_jobs" || "$raw_jobs" =~ ^[[:space:]]*No[[:space:]]+job ]]; then
        for range in "${TIME_RANGES[@]}"; do
            printf 'mem_efficiency{user="%s",range="%s"} 0\n' "$user" "$range" \
                | curl -s --data-binary @- "$BASE_URL/user/${user}/range/${range}"
            printf 'cpu_efficiency{user="%s",range="%s"} 0\n' "$user" "$range" \
                | curl -s --data-binary @- "$BASE_URL/user/${user}/range/${range}"
            echo "[$date_human] No jobs for user $user, pushed zeros for range $range"
        done
        continue
    fi

    jobs=$(grep -E '^[[:space:]]*[0-9]+' <<<"$raw_jobs" | sed -E 's/^[[:space:]]*//')

    for range in "${TIME_RANGES[@]}"; do
        # Determine seconds for the range
        if [[ $range =~ ^([0-9]+)h$ ]]; then
            delta=$((BASH_REMATCH[1]*3600))
        elif [[ $range =~ ^([0-9]+)d$ ]]; then
            delta=$((BASH_REMATCH[1]*86400))
        else
            echo "Warning: invalid range '$range'" >&2
            continue
        fi

        # Collect job metrics within this range
        mem_values=()
        cpu_values=()
        while read -r jobid stat month day hm; do
            [[ $jobid =~ ^[0-9]+$ ]] || continue
            submit_ts="$month $day $hm $current_year"
            submit_epoch=$(LC_ALL=C date -d "$submit_ts" +%s 2>/dev/null) || continue
            (( now_epoch - submit_epoch <= delta )) || continue

            detail=$(bjobs -l "$jobid" 2>/dev/null || true)
            [[ -z "$detail" ]] && continue

            mem_eff=$(grep -m1 -oE 'MEM Efficiency:[[:space:]]*([0-9]+(\.[0-9]+)?)' <<<"$detail" \
                        | sed -E 's/.*:[[:space:]]*([0-9]+(\.[0-9]+)?).*/\1/')
            cpu_eff=$(grep -m1 -oE 'CPU PEAK EFFICIENCY:[[:space:]]*([0-9]+(\.[0-9]+)?)' <<<"$detail" \
                        | sed -E 's/.*:[[:space:]]*([0-9]+(\.[0-9]+)?).*/\1/')

            [[ -n "$mem_eff" ]] && mem_values+=("$mem_eff")
            [[ -n "$cpu_eff" ]] && cpu_values+=("$cpu_eff")
        done <<< "$jobs"

        # Aggregate (average) or zero if no jobs
        if [[ ${#mem_values[@]} -eq 0 ]]; then
            mem_avg=0
        else
            mem_avg=$(printf "%s\n" "${mem_values[@]}" | awk '{sum+=$1} END{print sum/NR}')
        fi

        if [[ ${#cpu_values[@]} -eq 0 ]]; then
            cpu_avg=0
        else
            cpu_avg=$(printf "%s\n" "${cpu_values[@]}" | awk '{sum+=$1} END{print sum/NR}')
        fi

        # Push the aggregated metric
        printf 'mem_efficiency{user="%s",range="%s"} %.2f\n' "$user" "$range" "$mem_avg" \
            | curl -s --data-binary @- "$BASE_URL/user/${user}/range/${range}"
        printf 'cpu_efficiency{user="%s",range="%s"} %.2f\n' "$user" "$range" "$cpu_avg" \
            | curl -s --data-binary @- "$BASE_URL/user/${user}/range/${range}"

        echo "[$date_human] Pushed aggregated metrics for user $user, range $range (MEM=$mem_avg, CPU=$cpu_avg)"
    done
done < <(grep -Ev '^(#|$)' "$USERS_FILE")

echo "Push complete."
