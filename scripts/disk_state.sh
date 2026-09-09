#!/bin/bash

# Export necessary paths
export PATH=/cassandra/opt/tools/bin:/cassandra/opt/anaconda/3-2024.10-1/bin:/opt/ibm/lsfsuite/lsf/10.1/linux3.10-glibc2.17-x86_64/bin:/usr/bin:/bin:/usr/sbin:/sbin

# Debug: print PATH inside script
echo "PATH inside script: $PATH"

# Source LSF environment
source /cassandra/opt/ibm/lsfsuite/lsf/conf/profile.lsf

# ——— Pushgateway configuration ———
PUSHGATEWAY_URL="http://192.168.96.42:9091"
THISHOST=$(hostname)
job="cesmc_disk_monitor"
instance="${THISHOST}"
BASE_URL="${PUSHGATEWAY_URL}/metrics/job/${job}"

# ——— Clean any existing data for the job ———
echo "" | curl -s --data-binary @- "${BASE_URL}"

# ——— Allowed users ———
mapfile -t allowed_users < <(grep -Ev '^(#|$)' '/work/cmcc/hl06625/dashboard/users.txt')

is_allowed_user() {
    local u="$1"
    for au in "${allowed_users[@]}"; do
        [[ "$u" == "$au" ]] && return 0
    done
    return 1
}

collect_quota_data() {
    local mount_point="$1"
    local label="$2"
    local metrics=""

    # Use absolute path to gpfsrepquota
    /cassandra/opt/tools/bin/gpfsrepquota -f "$mount_point" > "/tmp/repquota_${label}_$$.tmp"

    while read -r _ group user fileset used soft hard grace; do
        is_allowed_user "$user" || continue

        local used_b=$(echo "$used" | numfmt --from=iec 2>/dev/null)
        local soft_b=$(echo "$soft" | numfmt --from=iec 2>/dev/null)

        if [[ "$soft" != "n.d" && -n "$soft_b" && $soft_b -gt 0 ]]; then
            pct=$((100 * used_b / soft_b))
        else
            pct=0
        fi
      
        # ——— UPDATED: Grace status logic ———
        if [[ "$grace" == "expired" ]]; then           # <-- UPDATED
            grace_status="expired"                     # <-- UPDATED
        elif [[ "$grace" =~ ^[0-9]+$ ]]; then         # <-- UPDATED
            grace_status="warning"                     # <-- UPDATED
        else                                           # <-- UPDATED
            grace_status="ok"                          # <-- UPDATED
        fi

        metrics+="disk_usage_meta{user=\"${user}\",partition=\"${label}\",used=\"${used}\",soft=\"${soft}\",hard=\"${hard}\",percent=\"${pct}%\",grace=\"${grace_status}\"} 1"$'\n'
        metrics+="disk_usage_percent{user=\"${user}\",partition=\"${label}\"} ${pct}"$'\n'
    done < <(grep -E '^USER[[:space:]]+goco' "/tmp/repquota_${label}_$$.tmp")


    rm -f "/tmp/repquota_${label}_$$.tmp"

    # Push metrics
    echo -n "$metrics" | curl -s -X POST --data-binary @- "${BASE_URL}/partition/${label}/instance/${instance}"

    if [[ $? -ne 0 ]]; then
        echo "[$(date)] ERROR: Failed to push metrics to Pushgateway at ${BASE_URL}/partition/${label}/instance/${instance}"
    else
        echo "pushed"
    fi
}

# Collect data
collect_quota_data "/work/cmcc" "work"
collect_quota_data "/data/cmcc" "data"
collect_quota_data "/users_home/cmcc" "home"
