#!/bin/bash

hive --database tpcds_bin_partitioned_orc_1000 -f ${PMH}/workload/hive/test_case/resource/tpcds_hive_nowhere2_queue2.sql > /dev/null 2>&1
hive --database tpcds_bin_partitioned_orc_1000 -f ${PMH}/workload/hive/test_case/resource/tpcds_hive_nowhere3_queue2.sql > /dev/null 2>&1
hive --database tpcds_bin_partitioned_orc_1000 -f ${PMH}/workload/hive/test_case/resource/tpcds_hive_where3_queue2.sql > /dev/null 2>&1
hive --database tpcds_bin_partitioned_orc_1000 -f ${PMH}/workload/hive/test_case/resource/tpcds_hive_where2_queue2.sql > /dev/null 2>&1
hive --database tpcds_bin_partitioned_orc_1000 -f ${PMH}/workload/hive/test_case/resource/tpcds_hive_nowhere1_queue2.sql > /dev/null 2>&1
hive --database tpcds_bin_partitioned_orc_1000 -f ${PMH}/workload/hive/test_case/resource/tpcds_hive_where1_queue2.sql > /dev/null 2>&1
hive --database tpcds_bin_partitioned_orc_1000 -f ${PMH}/workload/hive/test_case/resource/tpcds_hive_nowhere3_queue2.sql > /dev/null 2>&1
hive --database tpcds_bin_partitioned_orc_1000 -f ${PMH}/workload/hive/test_case/resource/tpcds_hive_nowhere1_queue2.sql > /dev/null 2>&1
hive --database tpcds_bin_partitioned_orc_1000 -f ${PMH}/workload/hive/test_case/resource/tpcds_hive_nowhere2_queue2.sql > /dev/null 2>&1
hive --database tpcds_bin_partitioned_orc_1000 -f ${PMH}/workload/hive/test_case/resource/tpcds_hive_nowhere3_queue2.sql > /dev/null 2>&1
hive --database tpcds_bin_partitioned_orc_1000 -f ${PMH}/workload/hive/test_case/resource/tpcds_hive_nowhere3_queue2.sql > /dev/null 2>&1
hive --database tpcds_bin_partitioned_orc_1000 -f ${PMH}/workload/hive/test_case/resource/tpcds_hive_nowhere1_queue2.sql > /dev/null 2>&1
hive --database tpcds_bin_partitioned_orc_1000 -f ${PMH}/workload/hive/test_case/resource/tpcds_hive_nowhere2_queue2.sql > /dev/null 2>&1
hive --database tpcds_bin_partitioned_orc_1000 -f ${PMH}/workload/hive/test_case/resource/tpcds_hive_nowhere2_queue2.sql > /dev/null 2>&1
hive --database tpcds_bin_partitioned_orc_1000 -f ${PMH}/workload/hive/test_case/resource/tpcds_hive_nowhere3_queue2.sql > /dev/null 2>&1