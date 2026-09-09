
#!/bin/bash
source /cassandra/opt/ibm/lsfsuite/lsf/conf/profile.lsf

# -------------------------------
# Configuration
# -------------------------------
PUSHGATEWAY_URL="http://192.168.96.42:9091"
JOB="service_class"
INSTANCE=$(hostname)
BASE_URL="${PUSHGATEWAY_URL}/metrics/job/${JOB}/instance/${INSTANCE}"


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
    if [[ $line =~ ^SERVICE\ CLASS\ NAME:\ (.*) ]]; then
        if [[ -n "$current_sc" ]]; then
            users_clean=$(echo "$users" | tr ' []' '_' | tr -s '_')
            apps_clean=$(echo "$apps" | tr ' []' '_' | tr -s '_')
            project_clean=$(echo "$project" | tr ' []' '_' | tr -s '_')
            queues_clean=$(echo "$queues" | tr ' []' '_' | tr -s '_')
            expiration_clean=$(echo "$expiration" | tr ' /' '_' | tr -s '_')

            metrics+="serviceclasses{service_class=\"$current_sc\",guarantee=\"$guarantee\",expiration=\"$expiration_clean\",queues=\"$queues_clean\",users=\"$users_clean\",apps=\"$apps_clean\",project=\"$project_clean\"} 1"$'\n'

            echo -e "$current_sc\t$guarantee\t$expiration\t$users\t$apps\t$project\t$queues"
        fi

        current_sc="${BASH_REMATCH[1]}"
        expiration="none"
        users="none"
        apps="none"
        project="none"
        queues="none"
        guarantee=0
        continue
    fi

    if [[ $line =~ END\ DATE[[:space:]]+([0-9/]+) ]]; then
        expiration="${BASH_REMATCH[1]}"
    fi

    if [[ $line =~ QUEUES\[([^\]]*)\] ]]; then queues="${BASH_REMATCH[1]}"; fi
    if [[ $line =~ USERS\[([^\]]*)\] ]]; then users="${BASH_REMATCH[1]}"; fi
    if [[ $line =~ APPS\[([^\]]*)\] ]]; then apps="${BASH_REMATCH[1]}"; fi
    if [[ $line =~ PROJECTS\[([^\]]*)\] ]]; then project="${BASH_REMATCH[1]}"; fi

    if [[ $line =~ guarantee_parallel|guarantee_serial|guarantee_gpu ]]; then
        guarantee=$(echo "$line" | awk '{print $3}')
    fi

done < <(bsla)

# Push last SC
if [[ -n "$current_sc" ]]; then
    users_clean=$(echo "$users" | tr ' []' '_' | tr -s '_')
    apps_clean=$(echo "$apps" | tr ' []' '_' | tr -s '_')
    project_clean=$(echo "$project" | tr ' []' '_' | tr -s '_')
    queues_clean=$(echo "$queues" | tr ' []' '_' | tr -s '_')
    expiration_clean=$(echo "$expiration" | tr ' /' '_' | tr -s '_')

    metrics+="serviceclasses{service_class=\"$current_sc\",guarantee=\"$guarantee\",expiration=\"$expiration_clean\",queues=\"$queues_clean\",users=\"$users_clean\",apps=\"$apps_clean\",project=\"$project_clean\"} 1"$'\n'

    echo -e "$current_sc\t$guarantee\t$expiration\t$users\t$apps\t$project\t$queues"
fi

# -------------------------------
# Push metrics
# -------------------------------
echo -e "$metrics" | curl -s --data-binary @- "$BASE_URL"
if [[ $? -ne 0 ]]; then
    echo "[$(date)] ERROR: Failed to push metrics to Pushgateway at ${BASE_URL}"
else
    echo "[$(date)] Metrics pushed successfully"
fi
