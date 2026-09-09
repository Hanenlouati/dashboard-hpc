#!/bin/bash

SC_NAME="SC_GPU_grins"
LOG_DIR="./debug_logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/node_per_job_debug_$(date +%Y%m%d_%H%M%S).log"

echo "DEBUG: Starting node_per_job calculation for $SC_NAME" >> "$LOG_FILE"

jobs=$(bjobs -r -u all -sla "$SC_NAME" 2>/dev/null | tail -n +2)

if [[ "$jobs" == "No running job found" || -z "$jobs" ]]; then
    echo "DEBUG: No running jobs for $SC_NAME" | tee -a "$LOG_FILE"
    exit 0
fi

current_job_id=""
current_user=""
nodes=()

while read -r line; do
    # Skip empty lines
    [[ -z "$line" ]] && continue

    first_col=$(echo "$line" | awk '{print $1}')

    if [[ "$first_col" =~ ^[0-9]+$ ]]; then
        # New job detected → process previous job
        if [[ -n "$current_job_id" ]]; then
            unique_nodes=$(printf "%s\n" "${nodes[@]}" | sort -u | wc -l)
            metric_line="node_per_job{job_id=\"$current_job_id\",user=\"$current_user\",nb_nodes=\"$unique_nodes\"} 1"
            echo "DEBUG: Job $current_job_id user $current_user has $unique_nodes running nodes" | tee -a "$LOG_FILE"
            echo "$metric_line"
        fi

        # Reset for new job
        current_job_id="$first_col"
        current_user=$(echo "$line" | awk '{print $2}')
        exec_host=$(echo "$line" | awk '{print $6}')

        nodes=()
        if [[ "$exec_host" == *\** ]]; then
            for part in $exec_host; do
                node=$(echo "$part" | awk -F'*' '{print $2}')
                [[ -n "$node" ]] && nodes+=("$node")
            done
        else
            [[ -n "$exec_host" ]] && nodes+=("$exec_host")
        fi
    else
        # Continuation line → additional EXEC_HOST entries
        exec_host=$(echo "$line" | xargs )
        if [[ "$exec_host" == *\** ]]; then
            for part in $exec_host; do
                node=$(echo "$part" | awk -F'*' '{print $2}')
                [[ -n "$node" ]] && nodes+=("$node")
            done
        else
            [[ -n "$exec_host" ]] && nodes+=("$exec_host")
        fi
    fi
done <<< "$jobs"

# Process last job
if [[ -n "$current_job_id" ]]; then
    unique_nodes=$(printf "%s\n" "${nodes[@]}" | sort -u | wc -l)
    metric_line="node_per_job{job_id=\"$current_job_id\",user=\"$current_user\",nb_nodes=\"$unique_nodes\"} 1"
    echo "DEBUG: Job $current_job_id user $current_user has $unique_nodes running nodes" | tee -a "$LOG_FILE"
    echo "$metric_line"
fi

echo "DEBUG: Finished processing $SC_NAME" >> "$LOG_FILE"
