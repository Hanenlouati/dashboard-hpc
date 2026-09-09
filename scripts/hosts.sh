#!/bin/bash
source /cassandra/opt/ibm/lsfsuite/lsf/conf/profile.lsf

# Script: hosts.sh
# Description: Collects host status, slot & CPU usage metrics,
#              scatter data, and pushes them to Pushgateway.

# — Pushgateway configuration —
PUSHGATEWAY_URL="http://192.168.96.42:9091"
JOB="cesmc_host_monitor"
INSTANCE=$(hostname)
BASE_URL="${PUSHGATEWAY_URL}/metrics/job/${JOB}/instance/${INSTANCE}"

# Timestamps
now_epoch=$(date +%s)
date_human=$(date --iso-8601=seconds)

# Build metrics payload
metrics=""

#
# 1) Host status counts (donut chart)
while read -r count status; do
  metrics+="host_status_count{status=\"${status}\",instance=\"${INSTANCE}\"} ${count}"$'\n'
done < <(bhosts -noheader -o "STATUS" | sort | uniq -c | awk '{print $1, $2}')

#
# 2) Slot usage (heatmap & timeseries)
while IFS= read -r line; do
  metrics+="${line}"$'\n'
done < <(
  bhosts -noheader -o "HOST_NAME MAX NJOBS" | \
  awk -v inst="$INSTANCE" '
    {
      host=$1; max=$2; njobs=$3;
      pct = (max > 0 ? njobs/max*100 : 0);
      printf("host_slots_used_pct{host=\"%s\",instance=\"%s\"} %.1f\n", host, inst, pct);
      printf("host_slots_used{host=\"%s\",instance=\"%s\"} %d\n", host, inst, njobs);
    }
  '
)

#
# 3a) CPU utilization % and alert (stdout)
while IFS= read -r line; do
  metrics+="${line}"$'\n'
done < <(
  lsload -I ut | awk -v inst="$INSTANCE" -v ts="$date_human" '
    NR>1 {
      host=$1; ut=$3;
      printf("host_cpu_util_pct{host=\"%s\",instance=\"%s\"} %.1f\n", host, inst, ut);
      if (ut > 95.0) {
        # ALERT output to stdout instead of log file
        printf("[%s] ALERT: Host %s CPU >95%% (%.1f%%)\n", ts, host, ut) > "/dev/stderr";
      }
    }
  '
)

# 3b) r15s load timeseries
while IFS= read -r line; do
  metrics+="${line}"$'\n'
done < <(
  lsload -I r15s | awk -v inst="$INSTANCE" '
    NR>1 {
      host=$1; load=$3;
      printf("host_cpu_load{host=\"%s\",instance=\"%s\"} %.2f\n", host, inst, load);
    }
  '
)

#
# 4) Scatter: CPU% vs slots% per host
# Grafana can join on {host}, no additional metrics needed.

# — Push to Pushgateway —
echo -n "$metrics" | curl -s --data-binary @- "${BASE_URL}"

# — Log success/failure to stdout —
if [[ $? -eq 0 ]]; then
  echo "[$date_human] Pushed host metrics successfully"
else
  echo "[$date_human] ERROR pushing host metrics" >&2
fi
