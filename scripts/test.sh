#!/bin/bash

user=guttavisir-dev
time_window=6h
LOG_DIR="/work/cmcc/hl06625/dashboard/logs1"
now_epoch=$(date +%s)

#
ages=()
while read -r stat m d t; do
  [[ "$stat" != "PEND" ]] && continue
  epoch=$(date -d "$m $d $t $(date +%Y)" +%s 2>/dev/null)
  [[ $? -eq 0 ]] && ages+=( $((now_epoch - epoch)) )
done < <(bjobs -u "$user" -o "stat submit_time" -noheader)

avg_age=0
if [[ ${#ages[@]} -gt 0 ]]; then
  total=0
  for a in "${ages[@]}"; do total=$((total + a)); done
  avg_age=$((total / ${#ages[@]}))
fi
echo "$now_epoch avg_pending_age $avg_age" >> "$LOG_DIR/avg_pending_age_over_time11.log"
echo "avg_pending_age_seconds{user=\"$user\"} $avg_age" 