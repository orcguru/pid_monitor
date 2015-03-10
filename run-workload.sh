#!/bin/bash

# To run a custom workload, define the following 4 variables and run this script

[ -z "$WORKLOAD_NAME" ]  && WORKLOAD_NAME=dd && echo "dd workload"
[ -z "$PROCESS_NAME_TO_WATCH" ]  && PROCESS_NAME_TO_WATCH="dd"
[ -z "$PROCESS_NAME_TO_GREP" ]  && PROCESS_NAME_TO_GREP="dd"
[ -z "$WORKLOAD_CMD" ]  && WORKLOAD_CMD="dd if=/dev/zero of=/tmp/tmpfile bs=128k count=16384"
[ -z "$WORKLOAD_DIR" ]  && WORKLOAD_DIR='.'
[ -z "$ESTIMATED_RUN_TIME_MIN" ]  && ESTIMATED_RUN_TIME_MIN=1
[ -z "$RUNDIR" ]  && RUNDIR=$(./setup-run.sh $WORKLOAD_NAME)
[ -z "$RUN_ID" ]  && RUN_ID="RUN1"

if [ -z "$SWEEP_FLAG" ]
then
    echo workload:\"$WORKLOAD_NAME\" >> $RUNDIR/html/config.txt
    echo date:\"$(date)\" >> $RUNDIR/html/config.txt
fi
echo run_id:\"$RUN_ID\" >> $RUNDIR/html/config.txt

DELAY_SEC=$ESTIMATED_RUN_TIME_MIN  # For 20min total run time, record data every 20 seconds

echo Running this workload:
echo \"$WORKLOAD_CMD\"

echo Putting results in $RUNDIR
cp $0 $RUNDIR/scripts
cp *py $RUNDIR/scripts
cp *R $RUNDIR/scripts

# STEP 1: CREATE OUTPUT FILENAMES BASED ON TIMESTAMP
TIMESTAMP=$(date +"%Y-%m-%d_%H:%M:%S")
TIME_FN=$RUNDIR/data/raw/$RUN_ID.time.stdout
CONFIG_FN=$RUNDIR/data/raw/$RUN_ID.config.txt
WORKLOAD_STDOUT=$RUNDIR/data/raw/$RUN_ID.workload.stdout
WORKLOAD_STDERR=$RUNDIR/data/raw/$RUN_ID.workload.stderr
STAT_STDOUT=$RUNDIR/data/raw/$RUN_ID.pwatch.stdout
DSTAT_CSV=$RUNDIR/data/final/dstat.csv

# STEP 2: DEFINE COMMANDS FOR ALL SYSTEM MONITORS
STAT_CMD="./watch-process.sh $PROCESS_NAME_TO_WATCH $DELAY_SEC" 
DSTAT_CMD="dstat -v --output $DSTAT_CSV $DELAY_SEC"

# STEP 3: COPY CONFIG FILES TO RAW DIRECTORY
CONFIG=$CONFIG,timestamp,$TIMESTAMP
CONFIG=$CONFIG,run_id,$RUN_ID
CONFIG=$CONFIG,kernel,$(uname -r)
CONFIG=$CONFIG,hostname,$(hostname -s)
CONFIG=$CONFIG,workload_name,$WORKLOAD_NAME
CONFIG=$CONFIG,stat_command,$STAT_CMD
CONFIG=$CONFIG,workload_command,$WORKLOAD_CMD
CONFIG=$CONFIG,workload_dir,$WORKLOAD_DIR
CONFIG=$CONFIG,  # Add trailiing comma
echo $CONFIG > $CONFIG_FN

# STEP 4: START SYSTEM MONITORS
$STAT_CMD > $STAT_STDOUT &

STAT_PID=$!

CWD=$(pwd)
echo Working directory: $WORKLOAD_DIR
cd $WORKLOAD_DIR

# STEP 5: RUN WORKLOAD
/usr/bin/time --verbose --output=$TIME_FN bash -c \
    "$WORKLOAD_CMD 1> $WORKLOAD_STDOUT 2> $WORKLOAD_STDERR"

cd $CWD
#STEP 6: KILL STAT MONITOR
sleep 5
kill -9 $STAT_PID 2> /dev/null 1>/dev/null
sleep 1

#STEP 7: ANALYZE DATA
echo Now tidying raw data into CSV files
./tidy-pwatch.py $STAT_STDOUT $PROCESS_NAME_TO_GREP $RUN_ID > $RUNDIR/data/final/$RUN_ID.pwatch.csv
./tidy-time.py $TIME_FN $RUN_ID >> $RUNDIR/data/final/$RUN_ID.time.csv

# Combine CSV files from all runs into summaries
./summarize-csv.sh .time.csv > $RUNDIR/data/final/summary.time.csv
./summarize-csv.sh .pwatch.csv > $RUNDIR/data/final/summary.pwatch.csv

#STEP 8: PARSE FINAL CSV DATA INTO CSV DATA FOR CHARTS/JAVASCRIPT
echo Creating html charts
cp -R html $RUNDIR/.
cd $RUNDIR/html
../scripts/split-chartdata.R ../data/final/$RUN_ID.pwatch.csv pid elapsed_time_sec cpu_pct  $RUN_ID # Parse CPU data
../scripts/split-chartdata.R ../data/final/$RUN_ID.pwatch.csv pid elapsed_time_sec mem_pct  $RUN_ID # Parse memory data
cd $CWD
