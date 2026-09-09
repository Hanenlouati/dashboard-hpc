#!/bin/bash

#BSUB -P F000
#BSUB -J dashboard         # Job name
#BSUB -o /work/cmcc/hl06625/dashboard/errorandlogs/output.%J.log
#BSUB -e /work/cmcc/hl06625/dashboard/errorandlogs/error.%J.log
#BSUB -R "rusage[mem=1G]" 
#BSUB -q  s_short
#BSUB -W 30

# Activate conda environment
# Add this line before activating the environment
source /work/cmcc/hl06625/.bashrc


*/5 * * * * /bin/bash /path/to/run_job_status_summary.sh



