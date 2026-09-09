#!/bin/bash

# -------------------------------
# Configuration
# -------------------------------
PUSHGATEWAY_URL="http://192.168.96.42:9091"
JOB="service_class"
INSTANCE=$(hostname)
BASE_URL="${PUSHGATEWAY_URL}/metrics/job/${JOB}/instance/${INSTANCE}"
# -------------------------------
# Service Class Filter
# -------------------------------
# For now, only process SC_climax; you can add more later.
ALLOWED_SC=("SC_climax")


# Create header for log file
echo -e "ServiceClass\tGuarantee\tExpiration\tUsers\tApps\tProject\tQueues" 

metrics=""

# -------------------------------
# Parse bsla output
# -------------------------------
current_sc=""
expiration="none"
users="none"
apps="none"
project="none"
queues="none"
guarantee=0

while read -r line; do
    # SERVICE CLASS NAME
    if [[ $line =~ ^SERVICE\ CLASS\ NAME:\ (.*) ]]; then
        # Push previous SC if exists
        if [[ -n "$current_sc" && " ${ALLOWED_SC[*]} " =~ " ${current_sc} " ]]; then
            users_clean=$(echo "$users" | tr -d '[]' | tr ' ' ',' | sed 's/,,*/,/g')
            apps_clean=$(echo "$apps" | tr -d '[]' | tr ' ' ',' | sed 's/,,*/,/g')
            project_clean=$(echo "$project" | tr -d '[]' | tr ' ' ',' | sed 's/,,*/,/g')
            queues_clean=$(echo "$queues" | tr -d '[]' | tr ' ' ',' | sed 's/,,*/,/g')
            expiration_clean=$(echo "$expiration" | tr -d '[]' | tr ' ' ',' | sed 's/,,*/,/g')
            metrics+="service_classes{service_class=\"$current_sc\",guarantee=\"$guarantee\",expiration=\"$expiration_clean\",queues=\"$queues_clean\",users=\"$users_clean\",apps=\"$apps_clean\",project=\"$project_clean\"} 1"$'\n'

            echo -e "$current_sc\t$guarantee\t$expiration\t$users\t$apps\t$project\t$queues" 
        fi

        # Reset for new SC
        current_sc="$(echo "${BASH_REMATCH[1]}" | xargs)"
        expiration="none"
        users="none"
        apps="none"
        project="none"
        queues="none"
        guarantee=0
        continue
    fi

    # Expiration
    if [[ $line =~ END\ DATE[[:space:]]+([0-9/]+) ]]; then
        expiration="${BASH_REMATCH[1]}"
    fi

    # ACCESS CONTROL parsing
    if [[ $line =~ QUEUES\[([^\]]*)\] ]]; then queues="${BASH_REMATCH[1]}"; fi
    if [[ $line =~ USERS\[([^\]]*)\] ]]; then users="${BASH_REMATCH[1]}"; fi
    if [[ $line =~ APPS\[([^\]]*)\] ]]; then apps="${BASH_REMATCH[1]}"; fi
    if [[ $line =~ PROJECTS\[([^\]]*)\] ]]; then project="${BASH_REMATCH[1]}"; fi

    # GUARANTEE line
    if [[ $line =~ guarantee_parallel|guarantee_serial|guarantee_gpu ]]; then
        guarantee=$(echo "$line" | awk '{print $3}')
    fi

done < <(bsla)

# Push last SC
if [[ -n "$current_sc" && " ${ALLOWED_SC[*]} " =~ " ${current_sc} " ]]; then
    users_clean=$(echo "$users" | tr -d '[]' | tr ' ' ',' | sed 's/,,*/,/g')
    apps_clean=$(echo "$apps" | tr -d '[]' | tr ' ' ',' | sed 's/,,*/,/g')
    project_clean=$(echo "$project" | tr -d '[]' | tr ' ' ',' | sed 's/,,*/,/g')
    queues_clean=$(echo "$queues" | tr -d '[]' | tr ' ' ',' | sed 's/,,*/,/g')
    expiration_clean=$(echo "$expiration" | tr -d '[]' | tr ' ' ',' | sed 's/,,*/,/g')

    metrics+="service_classes{service_class=\"$current_sc\",guarantee=\"$guarantee\",expiration=\"$expiration_clean\",queues=\"$queues_clean\",users=\"$users_clean\",apps=\"$apps_clean\",project=\"$project_clean\"} 1"$'\n'

    echo -e "$current_sc\t$guarantee\t$expiration\t$users\t$apps\t$project\t$queues" 
fi

# -------------------------------
# Push metrics
# -------------------------------
echo -e "$metrics" | curl -s --data-binary @- "$BASE_URL"

echo "Metrics pushed and logged to $LOG_FILE"

#second section for running nodes counting 
# -------------------------------
# Calculate number of nodes per job for SCs with guarantee > 0
# -------------------------------
# -------------------------------
# Second section: running nodes counting
# -------------------------------
echo "DEBUG: Starting node_per_job metric collection" 
all_metrics=""
declare -A job_nodes

# Loop over SCs from previous metrics
while read -r line; do
    # Extract service class name and guarantee
    if [[ $line =~ service_classes\{service_class=\"([^\"]+)\",guarantee=\"([0-9]+)\" ]]; then
        sc_name="$(echo "${BASH_REMATCH[1]}" | xargs)"   # trim spaces
        sc_guarantee="${BASH_REMATCH[2]}"

        # Only process allowed SCs
        if [[ " ${ALLOWED_SC[*]} " =~ " ${sc_name} " ]]; then
            echo "DEBUG: Processing allowed service class: $sc_name (guarantee=$sc_guarantee)" 

            # Only for SCs with guarantee > 0
            if (( sc_guarantee > 0 )); then
                echo "DEBUG: Guarantee > 0 for $sc_name, collecting node metrics" 

                # Get running jobs for this SC
                jobs_output=$(bjobs -r -u all -sla "$sc_name" 2>/dev/null | tail -n +2)

                # Skip if no running job
                if [[ "$jobs_output" == "No running job found" || -z "$jobs_output" ]]; then
                    echo "DEBUG: No running jobs for $sc_name, pushing placeholder metric" 
                    metric_line="nodesc{service_class=\"$sc_name\",job_id=\"none\",user=\"none\",nb_nodes=\"0\",status=\"ok\"} 1"
                    echo "$metric_line" 
                    all_metrics+="$metric_line"$'\n'
                    continue
                fi

                current_job=""
                current_user=""
                current_nodes=()

                while read -r jobline; do
                    [[ -z "$jobline" ]] && continue
                    first_col=$(echo "$jobline" | awk '{print $1}')
                    if [[ "$first_col" =~ ^[0-9]+$ ]]; then
                        # Push previous job if exists
                        if [[ -n "$current_job" ]]; then
                            unique_nodes=$(printf "%s\n" "${current_nodes[@]}" | sort -u | wc -l)
                            if (( unique_nodes > 0 && sc_guarantee % unique_nodes == 0 )); then
                                status="ok"
                            else
                                status="no"
                            fi
                            metric_line="nodesc{service_class=\"$sc_name\",job_id=\"$current_job\",user=\"$current_user\",nb_nodes=\"$unique_nodes\",status=\"$status\"} 1"
                            echo "$metric_line" 
                            all_metrics+="$metric_line"$'\n'
                            echo "DEBUG: Job $current_job user $current_user has $unique_nodes running nodes (status=$status)" 
                        fi

                        # Start new job
                        current_job=$(echo "$jobline" | awk '{print $1}')
                        current_user=$(echo "$jobline" | awk '{print $2}')
                        exec_host_field=$(echo "$jobline" | awk '{print $6}')
                        current_nodes=()

                        # Parse EXEC_HOST field
                        if [[ "$exec_host_field" == *\** ]]; then
                            for part in $exec_host_field; do
                                node=$(echo "$part" | awk -F'*' '{print $2}')
                                [[ -n "$node" ]] && current_nodes+=("$node")
                            done
                        else
                            [[ -n "$exec_host_field" ]] && current_nodes+=("$exec_host_field")
                        fi
                    else
                        # Continuation line (additional EXEC_HOST entries)
                        exec_host_line=$(echo "$jobline" | xargs)
                        for part in $exec_host_line; do
                            if [[ "$part" == *\** ]]; then
                                node=$(echo "$part" | awk -F'*' '{print $2}')
                                [[ -n "$node" ]] && current_nodes+=("$node")
                            else
                                [[ -n "$part" ]] && current_nodes+=("$part")
                            fi
                        done
                    fi
                done <<< "$jobs_output"

                # Push last job
                if [[ -n "$current_job" ]]; then
                    unique_nodes=$(printf "%s\n" "${current_nodes[@]}" | sort -u | wc -l)
                    if (( unique_nodes > 0 && sc_guarantee % unique_nodes == 0 )); then
                        status="ok"
                    else
                        status="no"
                    fi
                    metric_line="nodesc{service_class=\"$sc_name\",job_id=\"$current_job\",user=\"$current_user\",nb_nodes=\"$unique_nodes\",status=\"$status\"} 1"
                    echo "$metric_line" 
                    all_metrics+="$metric_line"$'\n'
                    echo "DEBUG: Job $current_job user $current_user has $unique_nodes running nodes (status=$status)" 
                fi
            fi
        else
            echo "DEBUG: Skipping disallowed service class: $sc_name" 
        fi
    fi
done <<< "$metrics"

# Push all collected metrics to Pushgateway
echo -e "$all_metrics" | curl -s --data-binary @- "$BASE_URL"
if [[ $? -eq 0 ]]; then
    echo "[$(date --iso-8601=seconds)] Pushed CPU efficiency / node_per_job metrics successfully"
else
    echo "[$(date --iso-8601=seconds)] ERROR pushing CPU efficiency / node_per_job metrics" >&2
fi
echo "DEBUG: node_per_job metrics collection completed" 