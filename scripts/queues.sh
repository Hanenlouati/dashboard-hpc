#!/bin/bash
source /cassandra/opt/ibm/lsfsuite/lsf/conf/profile.lsf

# Script: queues.sh
# Description: Collects LSF queue metrics and pushes to Pushgateway

# Ensure your environment (e.g., LSF) is loaded
if [ -f /work/cmcc/hl06625/.bashrc ]; then
  source /work/cmcc/hl06625/.bashrc
fi

# ——— Pushgateway configuration ———
PUSHGATEWAY_URL="http://192.168.96.42:9091"
THISHOST=$(hostname)
job="cesmc_queue_monitor"
instance="${THISHOST}"
BASE_URL="${PUSHGATEWAY_URL}/metrics/job/${job}"

# ——— Clean any existing data for this job ———
echo "" | curl -s --data-binary @- "${BASE_URL}"

# ——— Timestamps ———
now_epoch=$(date +%s)
date_human=$(date --iso-8601=seconds)

# ——— 1) Dump raw queue state via bqueues ———
bqueues -w | awk -v ts="$date_human" '
NR==1 {
  print "# Timestamp: " ts
  print "QUEUE\tPEND\tRUN\tMAX\tCAPACITY%\tLOAD%\tSTATUS\tPJOBS"
  next
}
{
  queue=$1; status=$3; max=$4; pend=$9; run=$10; pjobs=$13;
  cap="0"; load="0";
  if (max != "-" && max > 0) {
    cap = int((run / max) * 100);
    load = int(((run + pend) / max) * 100);
  } else {
    cap = "N/A"; load = "N/A";
  }
  printf("%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
    queue, pend, run, max, cap, load, status, pjobs);
}'

# ——— 2) Build all metrics payload ———
metrics=""
while IFS=$'\t' read -r queue pend run max cap load status pjobs; do
  [[ "$queue" == \#* || "$queue" == "QUEUE" ]] && continue

  metrics+="queue_state_meta{\
queue=\"${queue}\",\
status=\"${status}\",\
pend=\"${pend}\",\
run=\"${run}\",\
max=\"${max}\",\
capacity_percent=\"${cap}\",\
load_percent=\"${load}\",\
pending_eligible=\"${pjobs}\"\
} 1"$'\n'

  metrics+="queue_pending_jobs{queue=\"${queue}\"} ${pend}"$'\n'
  metrics+="queue_running_jobs{queue=\"${queue}\"} ${run}"$'\n'
done < <(bqueues -w | tail -n +3)

# ——— 3) Push all metrics to Pushgateway ———
echo -n "$metrics" | curl -s -X POST --data-binary @- "${BASE_URL}/instance/${instance}"

# ——— 4) Log success or failure to stdout/stderr ———
if [[ $? -ne 0 ]]; then
  echo "[$date_human] ERROR pushing queue metrics" >&2
else
  echo "[$date_human] Pushed queue metrics successfully"
fi
