#!/usr/bin/perl
use strict;
use warnings;
use lib qw(..);
use JSON qw( );
use File::Basename;

if ($#ARGV + 1 != 1) {
    die "Usage: ./generate_scripts.pl <TEST_PLAN_JSON>";
}

my $test_plan_fn = $ARGV[0];
my %tags = ();
########## Load JSON definition from above two files ############
my $scenario_text = do {
    open(my $json_fh, "<:encoding(UTF-8)", $test_plan_fn) or die "Cannot open $test_plan_fn for read!";
    local $/;
    <$json_fh>
};
my $json = JSON->new;
my $scenario = $json->decode($scenario_text);
my $conf_fn = "";
foreach my $step (@{$scenario}) {
    if (exists $step->{"USE"}) {
        $conf_fn = $step->{"USE"};
    }
}
if ($conf_fn eq "") {
    die "Please reference conf.json using \"USE\" in your $test_plan_fn"
}
my $conf_text = do {
    open(my $json_fh, "<:encoding(UTF-8)", $conf_fn) or die "Cannot open $conf_fn for read!";
    local $/;
    <$json_fh>
};
my $conf = $json->decode($conf_text);
# Sanity check
if (($conf->{"SCHEDULER"} ne "YARN") and ($conf->{"SCHEDULER"} ne "STANDALONE")) {
    die "Does not support ".$conf->{"SCHEDULER"}.", only YARN/STANDALONE supported";
}

########### Verify the environment as defined in the JSON files ############
# Check MASTE is current node
my $ping_result = `ping $conf->{"MASTER"} -c 1`;
if ($? != 0) {
    die "Please make sure to run the script from ".$conf->{"MASTER"};
}
`ping $conf->{"MASTER"} -c 1 | head -n 1 | awk -F\\( '{print \$2}' | awk -F\\) '{print \$1}' | xargs -i sh -c "ifconfig | grep {}"`;
my $master_ip = `ping $conf->{"MASTER"} -c 1 | head -n 1 | awk -F\\( '{print \$2}' | awk -F\\) '{print \$1}'`;
chomp($master_ip);
if ($? != 0) {
    die "Please make sure to run the script from ".$conf->{"MASTER"};
}

# Get all nodes and check ssh/dstat etc
if (not (-e $conf->{"HADOOP_HOME"}."/etc/hadoop/slaves")) {
    die "slaves file not found under ".$conf->{"HADOOP_HOME"}."/etc/hadoop/ folder";
}
my $slaves_str = `grep -v \\# $conf->{"HADOOP_HOME"}/etc/hadoop/slaves`;
my @nodes = split(/\n/, $slaves_str);
my $all_slaves = "";
my $first_slave = "";
my $slave_count = $#nodes + 1;
foreach my $node (@nodes) {
    chomp($node);
    if ($all_slaves eq "") {
        $all_slaves = $node;
    } else {
        $all_slaves = $all_slaves." ".$node;
    }
    if ($first_slave eq "") {
        $first_slave = $node;
    }
}

my $cores_online = "";
my $cores = 0;
my $total_cores_online = 0;

push (@nodes, $conf->{"MASTER"});
if ($#nodes == 0) {
    die "Slave nodes not defined in ".$conf->{"HADOOP_HOME"}."/etc/hadoop/slaves";
}
my $need_install_tools = 0;
my $ssh_problem = 0;
foreach my $node (@nodes) {
    `ssh $node date`;
    if ($? != 0) {
        $ssh_problem = 1;
        print "$node not reachable or passwordless not set\n";
    } else {
        `ssh $node which dstat`;
        if ($? != 0) {
            $need_install_tools = 1;
            print "Please install dstat on $node\n";
        }
    }
}
if ($ssh_problem != 0) {
    die "Please resolve ssh passwordless access first";
}
if ($need_install_tools != 0) {
    die "Install tools and try again";
}

# Upload lpcpu to the first slave node
if (not (-e "../../../lpcpu.tar.bz2")) {
    die "lpcpu.tar.bz2 not found in repository";
}
`scp ../../../lpcpu.tar.bz2 $nodes[0]:/root/`;
`ssh $nodes[0] "cd /root && tar xjf lpcpu.tar.bz2"`;

########### Generate the test scripts ############
# Header
my $date_str = `date +"%Y%m%d%H%M%S"`;
chomp($date_str);
my $case_tag = $test_plan_fn;
if ($case_tag =~ /(.*).json/) {
    $case_tag = $1;
}
my $script_dir = $case_tag."-".$date_str;
`mkdir $script_dir`;
my $current_dir = `pwd`;
chomp($current_dir);
my $script_dir_full = $current_dir."/".$script_dir;
open my $script_fh, "> $script_dir/run.sh" or die "Cannot open file ".$script_dir."/run.sh for write";

my $pmh = dirname(dirname(dirname(`pwd`)));
print $script_fh <<EOF;
#!/bin/bash
# This script is generated by generate_scripts.pl
ctrl_c_exit() {
    echo "Cleanup environment before exit now"
    if [ \$CMD_TO_KILL != "" ]
    then
        echo "Got command to kill \$CMD_TO_KILL"
        `ps -ef | grep "\$CMD_TO_KILL" | grep -v grep | awk '{print \$2}' | xargs -i kill -9 {}`
        #FIXME
EOF
}

print $script_fh <<EOF;
        \$PMH/workload/hive/scripts/create_summary_table.pl \$PMH/workload/hive/test_case/$test_plan_fn \$RUNDIR

EOF

print $script_fh <<EOF;
    fi
    exit 1
}

EOF

print $script_fh <<EOF;
CMD_TO_KILL=""
SMT_NEED_RESET=0
trap ctrl_c_exit INT

export PMH=$pmh
export WORKLOAD_NAME=$script_dir
export DESCRIPTION="$script_dir"
export WORKLOAD_DIR="."      # The workload working directory
export MEAS_DELAY_SEC=1      # Delay between each measurement
export RUNDIR=\$(\${PMH}/setup-run.sh \$WORKLOAD_NAME)
INFO=\$PMH/workload/hive/test_case/$script_dir/info
APPID=\$PMH/workload/hive/test_case/$script_dir/appid
DEBUG=\$PMH/workload/hive/test_case/$script_dir/debug.log
rm -f \$INFO

# SLAVES config required by run-workload.sh
unset SLAVES
SLAVES="$all_slaves"
export SLAVES

cd \$PMH
cp -R html \$RUNDIR/html

EOF

# *-scenario.json steps
foreach my $step (@{$scenario}) {
    if (exists $step->{"ACTION"}) {
        if ($step->{"ACTION"} eq "CLEAR_SWAPPINESS") {
            print $script_fh <<EOF;
# ACTION $step->{"ACTION"}
echo 0 > /proc/sys/vm/swappiness
grep -v \\# $conf->{"HADOOP_HOME"}/etc/hadoop/slaves | xargs -i ssh {} "echo 0 > /proc/sys/vm/swappiness"

EOF
        } elsif (($step->{"ACTION"} eq "HDFS") or ($step->{"ACTION"} eq "YARN")) {
            my $script_name = "dfs";
            if ($step->{"ACTION"} eq "YARN") {
                $script_name = "yarn";
            }
            my $script_action = "";
            if (not (exists $step->{"PARAM"})) {
                close $script_fh;
                `rm -rf $script_dir_full`;
                die "ACTION:".$step->{"ACTION"}." require PARAM START or STOP";
            } elsif ($step->{"PARAM"} eq "START") {
                $script_action = "start";
            } elsif ($step->{"PARAM"} eq "STOP") {
                $script_action = "stop"; 
            } else {
                close $script_fh;
                `rm -rf $script_dir_full`;
                die "ACTION:".$step->{"ACTION"}." invalid PARAM ".$step->{"PARAM"}.", require PARAM START or STOP";
            }
            print $script_fh <<EOF;
# ACTION $step->{"ACTION"}:$step->{"PARAM"}
$conf->{"HADOOP_HOME"}/sbin/$script_action-$script_name.sh

EOF
        } elsif ($step->{"ACTION"} eq "DROP_CACHE") {
            print $script_fh <<EOF;
# ACTION $step->{"ACTION"}
sync && echo 3 > /proc/sys/vm/drop_caches
grep -v \\# $conf->{"HADOOP_HOME"}/etc/hadoop/slaves | xargs -i ssh {} "sync && echo 3 > /proc/sys/vm/drop_caches"

EOF
        } elsif ($step->{"ACTION"} eq "WAIT") {
            my $sec = 5;
            if (exists $step->{"PARAM"}) {
                $sec = $step->{"PARAM"};
            }
            print $script_fh <<EOF;
# ACTION $step->{"ACTION"}:$sec
sleep $sec

EOF
        } else {
            close $script_fh;
            `rm -rf $script_dir_full`;
            die "ACTION:".$step->{"ACTION"}." is not supported!";
        }
    } elsif (exists $step->{"TAG"}) {
        my $smt_changed = 0;
        my $tag_idx = 0;
        if (exists $tags{$step->{"TAG"}}) {
            $tags{$step->{"TAG"}} = $tags{$step->{"TAG"}} + 1;
            $step->{"TAG"} = $step->{"TAG"}."_".$tags{$step->{"TAG"}};
        } else {
            $tags{$step->{"TAG"}} = 1;
        }
        if (not (exists $step->{"CMD"})) {
            close $script_fh;
            `rm -rf $script_dir_full`;
            die "Please define CMD section in TAG ".$step->{"TAG"};
        }
        my $repeat = 1;
        if (exists $step->{"REPEAT"}) {
            $repeat = $step->{"REPEAT"};
        }
        # Default do drop cache between runs
        my $drop_cache_between_run = 1;
        if ((exists $step->{"DROP_CACHE_BETWEEN_REPEAT"}) and ($step->{"DROP_CACHE_BETWEEN_REPEAT"} eq "FALSE")) {
            $drop_cache_between_run = 0;
        }
        if (not ((exists $step->{"CMD"}->{"EXECUTOR_PER_DN"}) and (exists $step->{"CMD"}->{"EXECUTOR_VCORES"}))) {
            close $script_fh;
            `rm -rf $script_dir_full`;
            die "TAG ".$step->{"TAG"}." please configure EXECUTOR_PER_DN/EXECUTOR_VCORES in CMD section";
        }
        # Update HIVE_HOME
        my $cmd = "";
        if ($step->{"CMD"}->{"COMMAND"} =~ /\<HIVE_HOME\>/) {
            $step->{"CMD"}->{"COMMAND"} =~ s/\<HIVE_HOME\>/$conf->{"HIVE_HOME"}/;
        }
        print $script_fh <<EOF;
CMD_TO_KILL="$step->{"CMD"}->{"COMMAND"}"
EOF
        $cmd = $cmd.$step->{"CMD"}->{"COMMAND"};
        if (exists $step->{"CMD"}->{"PARAM"}) {
            foreach my $element (@{$step->{"CMD"}->{"PARAM"}}) {
                if (ref($element) eq "HASH") {
                    if (exists $element->{"--conf"}) {
                        foreach my $conf (@{$element->{"--conf"}}) {
                            $cmd = $cmd." --conf ".$conf;
                        }
                        if (exists $conf->{"SPARK_DEFAULTS"}) {
                            foreach my $key (keys %{$conf->{"SPARK_DEFAULTS"}}) {
                                $cmd = $cmd." --conf ".$key."=".$conf->{"SPARK_DEFAULTS"}->{$key};
                            }
                        }
                    }
                } else {
                    if ($element =~ /\<SPARK_HOME\>/) {
                        $element =~ s/\<SPARK_HOME\>/$conf->{"SPARK_HOME"}/;
                    }
                    if ($element =~ /\<SPARK_MASTER_IP\>/) {
                        $element =~ s/\<SPARK_MASTER_IP\>/$master_ip/;
                    }
                    $cmd = $cmd." ".$element;
                }
            }
        }
        print $script_fh <<EOF;
echo \"TAG:$step->{"TAG"} COUNT:$repeat\" >> \$INFO
for ITER in \$(seq $repeat)
do
EOF
        if ($drop_cache_between_run == 1) {
            print $script_fh <<EOF;
    if [ \$ITER -ne 1 ] 
    then
        sync && echo 3 > /proc/sys/vm/drop_caches
        grep -v \\# $conf->{"HADOOP_HOME"}/etc/hadoop/slaves | xargs -i ssh {} "sync && echo 3 > /proc/sys/vm/drop_caches"
    fi
EOF
        }
        print $script_fh <<EOF;
    export RUN_ID=\"$step->{"TAG"}-ITER\$ITER\"
    CMD=\"${cmd}\"
    CMD=\"\${CMD} > \$PMH/workload/spark/test_case/$script_dir/$step->{"TAG"}-ITER\$ITER.log 2>&1\"
    export WORKLOAD_CMD=\${CMD}
EOF
        # For YARN scheduler, get the latest FINISHED/FAILED/KILLED application-id
        if ($conf->{"SCHEDULER"} eq "YARN") {
            print $script_fh <<EOF;
    # Get existing application-id infos
    $conf->{"HADOOP_HOME"}/bin/yarn application -appStates RUNNING -list 2>&1 | tail -n 1 | grep -v Application-Id > /dev/null 2>&1
    if [ \$? -eq 0 ]
    then
        echo "There should be no running task at this momenet, please check and run again!"
        exit 1
    fi
    echo "FINISHED" > \$APPID
    `\$PMH/workload/spark/scripts/query_yarn_app_id_in_some_state.pl $conf->{"HADOOP_HOME"} FINISHED \$DEBUG >> \$APPID`;
    echo "FAILED" >> \$APPID
    `\$PMH/workload/spark/scripts/query_yarn_app_id_in_some_state.pl $conf->{"HADOOP_HOME"} FAILED \$DEBUG >> \$APPID`;
    echo "KILLED" >> \$APPID
    `\$PMH/workload/spark/scripts/query_yarn_app_id_in_some_state.pl $conf->{"HADOOP_HOME"} KILLED \$DEBUG >> \$APPID`;
    \$PMH/workload/spark/scripts/query_yarn_app_id.pl \$APPID \$INFO $step->{"TAG"} \$ITER $conf->{"HADOOP_HOME"} \$PMH/workload/spark/scripts \$DEBUG &
EOF
        }
        print $script_fh <<EOF;
    \${PMH}/run-workload.sh
    DURATION=`grep "Elapsed (wall clock) time" \$RUNDIR/data/raw/$step->{"TAG"}-ITER\${ITER}_time_stdout.txt | awk -F"m:ss): " '{print \$2}' | awk -F: 'END { if (NF == 2) {sum=\$1*60+\$2} else {sum=\$1*3600+\$2*60+\$3} print sum}'`
    echo \"TAG:$step->{"TAG"} ITER:\$ITER DURATION:\$DURATION\" >> \$INFO
EOF
        if ($conf->{"SCHEDULER"} eq "STANDALONE") {
            print $script_fh <<EOF;
    grep "EventLoggingListener: Logging events to" \$PMH/workload/spark/test_case/$script_dir/$step->{"TAG"}-ITER\$ITER.log > /dev/null 2>&1
    if [ \$? -eq 0 ]
    then
        TGT_EVENT_LOG_FN=`grep "EventLoggingListener: Logging events to" \$PMH/workload/spark/test_case/$script_dir/$step->{"TAG"}-ITER\$ITER.log | awk -F"file:" '{print \$2}'`;
        DST_EVENT_LOG_FN=`grep "EventLoggingListener: Logging events to" \$PMH/workload/spark/test_case/$script_dir/$step->{"TAG"}-ITER\$ITER.log | awk -F"file:" '{print \$2}' | awk -F/ '{print \$NF}'`;
        echo \"TAG:$step->{"TAG"} ITER:\$ITER APPID:\$DST_EVENT_LOG_FN\" >> \$INFO
        echo \"TAG:$step->{"TAG"} ITER:\$ITER EVENTLOG:\$RUNDIR/spark_events/\${DST_EVENT_LOG_FN}-$step->{"TAG"}-ITER\$ITER\" >> \$INFO
        for SLAVE in \$SLAVES
        do
            scp \$SLAVE:\$TGT_EVENT_LOG_FN \$RUNDIR/spark_events/\${DST_EVENT_LOG_FN}-$step->{"TAG"}-ITER\$ITER > /dev/null 2>&1
        done
        scp $conf->{"MASTER"}:\$TGT_EVENT_LOG_FN \$RUNDIR/spark_events/\${DST_EVENT_LOG_FN}-$step->{"TAG"}-ITER\$ITER > /dev/null 2>&1
    else
        grep "Submitted application" \$PMH/workload/spark/test_case/$script_dir/$step->{"TAG"}-ITER\$ITER.log > /dev/null 2>&1
        if [ \$? -eq 0 ]
        then
            DST_EVENT_LOG_FN=`grep "Submitted application" \$PMH/workload/spark/test_case/$script_dir/$step->{"TAG"}-ITER\$ITER.log | awk '{print \$NF}'`;
            for SLAVE in \$SLAVES
            do
                scp \$SLAVE:$current_spark_event_dir/\$DST_EVENT_LOG_FN \$RUNDIR/spark_events/\${DST_EVENT_LOG_FN}-$step->{"TAG"}-ITER\$ITER > /dev/null 2>&1
            done
            scp $conf->{"MASTER"}:$current_spark_event_dir/\$DST_EVENT_LOG_FN \$RUNDIR/spark_events/\${DST_EVENT_LOG_FN}-$step->{"TAG"}-ITER\$ITER > /dev/null 2>&1
            echo \"TAG:$step->{"TAG"} ITER:\$ITER APPID:\$DST_EVENT_LOG_FN\" >> \$INFO
            echo \"TAG:$step->{"TAG"} ITER:\$ITER EVENTLOG:\$RUNDIR/spark_events/\${DST_EVENT_LOG_FN}-$step->{"TAG"}-ITER\$ITER\" >> \$INFO
        else
            echo "Cannot find app-ID, please enable console INFO log level when using STANDALONE scheduler!"
        fi
    fi
EOF
        } else {
            print $script_fh <<EOF;
    grep "TAG:$step->{"TAG"} ITER:\$ITER APPID:" \$INFO > /dev/null 2>&1
    while [ \$? -ne 0 ]
    do
        sleep 1
        grep "TAG:$step->{"TAG"} ITER:\$ITER APPID:" \$INFO > /dev/null 2>&1
    done
    grep "TAG:$step->{"TAG"} ITER:\$ITER APPID:TIMEOUT" \$INFO > /dev/null 2>&1
    if [ \$? -ne 0 ]
    then
        DST_EVENT_LOG_FN=`grep "TAG:$step->{"TAG"} ITER:\$ITER APPID:" \$INFO | awk -F\"APPID:\" '{print \$2}'`;
        for SLAVE in \$SLAVES
        do
            scp \$SLAVE:$current_spark_event_dir/\$DST_EVENT_LOG_FN \$RUNDIR/spark_events/\${DST_EVENT_LOG_FN}-$step->{"TAG"}-ITER\$ITER > /dev/null 2>&1
        done
        scp $conf->{"MASTER"}:$current_spark_event_dir/\$DST_EVENT_LOG_FN \$RUNDIR/spark_events/\${DST_EVENT_LOG_FN}-$step->{"TAG"}-ITER\$ITER > /dev/null 2>&1
        echo \"TAG:$step->{"TAG"} ITER:\$ITER EVENTLOG:\$RUNDIR/spark_events/\${DST_EVENT_LOG_FN}-$step->{"TAG"}-ITER\$ITER\" >> \$INFO
        $conf->{"HADOOP_HOME"}/bin/yarn application -appStates FINISHED -list 2>&1 | grep \$DST_EVENT_LOG_FN > /dev/null 2>&1
        if [ \$? -eq 0 ]
        then
            echo \"TAG:$step->{"TAG"} ITER:\$ITER STATUS:0\" >> \$INFO
        else
            echo \"TAG:$step->{"TAG"} ITER:\$ITER STATUS:1\" >> \$INFO
        fi
        # FIXME: put time result into INFO
    else
        echo "Application ID not found for TAG:$step->{"TAG"} ITER:\$ITER"
    fi
EOF
        }
        if (exists $step->{"AFTER"}) {
            if ($step->{"AFTER"} =~ /\<HADOOP_HOME\>/) {
                $step->{"AFTER"} =~ s/\<HADOOP_HOME\>/$conf->{"HADOOP_HOME"}/;
            }
            if ($step->{"AFTER"} =~ /\<SPARK_HOME\>/) {
                $step->{"AFTER"} =~ s/\<SPARK_HOME\>/$conf->{"SPARK_HOME"}/;
            }
            print $script_fh <<EOF;
    # AFTER command
    $step->{"AFTER"}
done

EOF
        } else {
            print $script_fh <<EOF;
done

EOF
        }
    } elsif (exists $step->{"SHELL"}) {
        if ($step->{"SHELL"} =~ /\<HADOOP_HOME\>/) {
            $step->{"SHELL"} =~ s/\<HADOOP_HOME\>/$conf->{"HADOOP_HOME"}/;
        }
        if ($step->{"SHELL"} =~ /\<SPARK_HOME\>/) {
            $step->{"SHELL"} =~ s/\<SPARK_HOME\>/$conf->{"SPARK_HOME"}/;
        }
        print $script_fh <<EOF;
# SHELL command
$step->{"SHELL"}

EOF
    }
}

print $script_fh <<EOF;
\$PMH/workload/spark/scripts/create_summary_table.pl \$PMH/workload/spark/test_case/$test_plan_fn \$RUNDIR

EOF

# Restore spark-env.sh if we are running in STANDALONE mode
if ($conf->{"SCHEDULER"} eq "STANDALONE") {
    print $script_fh <<EOF;
$conf->{"SPARK_HOME"}/sbin/stop-all.sh
\\cp \$RUNDIR/.spark-env.sh.backup.master $conf->{"SPARK_HOME"}/conf/spark-env.sh
for SLAVE in \$SLAVES
do
    scp \$RUNDIR/.spark-env.sh.backup.\$SLAVE \$SLAVE:$conf->{"SPARK_HOME"}/conf/spark-env.sh
done

EOF
}

close $script_fh;
`chmod +x $script_dir/run.sh`;