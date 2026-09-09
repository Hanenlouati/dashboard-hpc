#!/bin/bash

#BSUB -P F000
#BSUB -J dashboard          # Job name
#BSUB -o /work/cmcc/hl06625/dashboard/errorandlogs/output.%J.log
#BSUB -e /work/cmcc/hl06625/dashboard/errorandlogs/error.%J.log
#BSUB -R "rusage[mem=200M]" 
#BSUB -q  s_short



# Activate conda environment
# Add this line before activating the environment
#source /work/cmcc/hl06625/.bashrc
#conda activate satbat

# Navigate to the working directory
#cd /work/cmcc/hl06625/SaBaTo

# Execute the Python script
#python libs/parallelsat2.py rhone_request.json 2022-09-11 2022-09-11 --workers 4
#python libs/bandratiocbash
#bash /work/cmcc/hl06625/dashboard/job_status_summary.sh
#bash  /work/cmcc/hl06625/dashboard/metricsjobs.sh
#bash /work/cmcc/hl06625/dashboard/disk_state.sh
#bash /work/cmcc/hl06625/dashboard/queues.sh
#bash /work/cmcc/hl06625/dashboard/hosts.sh
bash  /work/cmcc/hl06625/dashboard/memory2.sh 
#bash /work/cmcc/hl06625/dashboard/sc.sh
#bash /work/cmcc/hl06625/dashboard/service_class.sh
#bash /work/cmcc/hl06625/dashboard/serviceclass2.sh
#bash /work/cmcc/hl06625/dashboard/sc2.sh
#bash /work/cmcc/hl06625/dashboard/sc3.sh


#bash /work/cmcc/hl06625/dashboard/login.sh


#bash /work/cmcc/hl06625/dashboardwithoutvariables/job_status_summary.sh
#bash /work/cmcc/hl06625/dashboardwithoutvariables/metricsjobs.sh
#bash /work/cmcc/hl06625/dashboardwithoutvariables/disk_state.sh
#bash /work/cmcc/hl06625/dashboardwithoutvariables/queues.sh
#bash /work/cmcc/hl06625/dashboardwithoutvariables/hosts.sh
#bash /work/cmcc/hl06625/dashboardwithoutvariables/memory2.sh 
#bash /work/cmcc/hl06625/dashboardwithoutvariables/sc.sh
#bash /work/cmcc/hl06625/dashboardwithoutvariables/login.sh




#bash  /work/cmcc/hl06625/dashboard/test.sh
#bash  /work/cmcc/hl06625/dashboard/memory2.sh 
#bash  /work/cmcc/hl06625/dashboard/login.sh
#bash  /work/cmcc/hl06625/dashboard/serviceclass1/test.sh
#bash  /work/cmcc/hl06625/dashboard/sc.sh



