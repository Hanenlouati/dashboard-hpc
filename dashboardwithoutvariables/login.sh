#!/usr/bin/env bash
source /cassandra/opt/ibm/lsfsuite/lsf/conf/profile.lsf
export PATH=/cassandra/opt/anaconda/3-2024.10-1/bin:/opt/ibm/lsfsuite/lsf/10.1/linux3.10-glibc2.17-x86_64/bin:/usr/bin:/bin:/usr/sbin:/sbin

set -euo pipefail
IFS=$'\n\t'

# -------------------------------
# Configuration
# -------------------------------
WHITELIST="/work/cmcc/hl06625/dashboard/users.txt"

PUSHGATEWAY_URL="http://192.168.96.42:9091"
JOB="online_users"
INSTANCE=$(hostname)
BASE_URL="${PUSHGATEWAY_URL}/metrics/job/${JOB}/instance/${INSTANCE}"

# -------------------------------
# Timestamps
# -------------------------------
now_epoch=$(date +%s)
date_human=$(date --iso-8601=seconds)

# -------------------------------
# Function to get current SSH sessions filtered by whitelist
# -------------------------------
get_sessions() {
  ssh login1 "ps -eo user,cmd --no-headers | awk '/sshd: .*@pts/ { print \$1 }'" \
    | grep -Fxf "$WHITELIST" || true
}

# -------------------------------
# Save unique users and counts
# -------------------------------
sessions=$(get_sessions | sort -u)
counts=$(get_sessions | sort | uniq -c | awk '{ printf("%s %d\n", $2, $1) }')

# -------------------------------
# Display
# -------------------------------
echo "[$date_human] Approved users currently logged in:"
echo "$sessions"
echo
echo "[$date_human] Session counts per user:"
echo "$counts"
echo

# -------------------------------
# Push to Prometheus Pushgateway
# -------------------------------
declare -A user_counts
while read -r line; do
  [[ -z "$line" ]] && continue
  user=$(echo "$line" | awk '{print $1}')
  count=$(echo "$line" | awk '{print $2}')
  user_counts["$user"]=$count
done <<< "$counts"

metrics=""
while read -r user; do
  [[ -z "$user" ]] && continue
  count="${user_counts[$user]:-0}"
  metrics+="online_user_sessions1{user=\"$user\"} $count"$'\n'
done < "$WHITELIST"

echo -e "$metrics" | curl -s --data-binary @- "$BASE_URL"

# -------------------------------
# Final message with exit check
# -------------------------------
if [[ $? -ne 0 ]]; then
  echo "[$(date)] ERROR: Failed to push metrics to Pushgateway at ${BASE_URL}" >&2
else
  echo "[$(date)] pushed"
fi
