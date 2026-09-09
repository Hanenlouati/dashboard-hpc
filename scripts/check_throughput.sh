#!/usr/bin/env bash
# check_throughput.sh
# Simple script to count DONE jobs for multiple users in given ranges

set -euo pipefail

# Users to check
USERS=(
aa11823
ad07521
cg05222
fv08620
gv29119
jk12824
ls15122
lw12924
resm-dev
re35220
rf01924
vr25423
vs15521
wrf_cmcc-dev
hl06625
)

# Time ranges
RANGES=("6h" "24h" "7d")

now_epoch=$(date +%s)

for user in "${USERS[@]}"; do
  echo "====== User: $user ======"
  for range in "${RANGES[@]}"; do
    # Compute cutoff
    case "$range" in
      *h) delta=$(( ${range%h} * 3600 )) ;;
      *d) delta=$(( ${range%d} * 86400 )) ;;
      *) echo "Unsupported range $range" >&2; continue ;;
    esac
    since=$(( now_epoch - delta ))

    # Count DONE jobs after cutoff
    done_jobs=$(bjobs -d -u "$user" 2>/dev/null | awk -v since="$since" '
      $3=="DONE" {
        cmd="date -d \""$8" "$9" "$10" $(date +%Y)\" +%s"
        cmd | getline t
        close(cmd)
        if (t>=since) c++
      }
      END{print c+0}
    ')

    echo "  Range $range → DONE jobs: $done_jobs"
  done
  echo
done
