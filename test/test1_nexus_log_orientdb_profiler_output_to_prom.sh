#!/bin/bash

source lib.sh
set -e

is_any_test_failed=0

#
#
echo "Test-1, Test-Case-1: No recommendation lines present."
#
export NXRMSCR_NEXUS_LOGFILE_PATH=resources/test1/log/nexus.t1.tc1.log
export PROM_FILE=tmp/out.t1.tc1.prom
source ../scrape_nexus.sh
set_up
printf "%s\n\n" "$CONTROL_LINE" >"${PROM_FILE}.$$"
nexus_log_orientdb_profiler_output_to_prom
rename_prom

expected_filecontent=$(
  cat <<'EOF'
# Control-line. With this line the test can check the generated PROM data is appended.

# HELP sonatype_nexus_recommended_maximum_jvm_heap_megabytes Recommendation for the JVM heap size in MB read from nexus.log.
# TYPE sonatype_nexus_recommended_maximum_jvm_heap_megabytes gauge
sonatype_nexus_recommended_maximum_jvm_heap_megabytes 0
# HELP sonatype_nexus_recommended_maximum_direct_memory_megabytes Recommendation for the maximum direct memory size in MB read from nexus.log.
# TYPE sonatype_nexus_recommended_maximum_direct_memory_megabytes gauge
sonatype_nexus_recommended_maximum_direct_memory_megabytes 0
EOF
)

message=$(compare "$PROM_FILE" "$expected_filecontent")
echo "$message"
if [[ "$message" == *"FAILED"* ]]; then
  is_any_test_failed=1
fi

#
#
echo "Test-1, Test-Case-2: Recommendation lines present, all recommendations lines with same values."
#
export NXRMSCR_NEXUS_LOGFILE_PATH=resources/test1/log/nexus.t1.tc2.log
export PROM_FILE=tmp/out.t1.tc2.prom
source ../scrape_nexus.sh
set_up
printf "%s\n\n" "$CONTROL_LINE" >"${PROM_FILE}.$$"
nexus_log_orientdb_profiler_output_to_prom
rename_prom

expected_filecontent=$(
  cat <<'EOF'
# Control-line. With this line the test can check the generated PROM data is appended.

# HELP sonatype_nexus_recommended_maximum_jvm_heap_megabytes Recommendation for the JVM heap size in MB read from nexus.log.
# TYPE sonatype_nexus_recommended_maximum_jvm_heap_megabytes gauge
sonatype_nexus_recommended_maximum_jvm_heap_megabytes 2652
# HELP sonatype_nexus_recommended_maximum_direct_memory_megabytes Recommendation for the maximum direct memory size in MB read from nexus.log.
# TYPE sonatype_nexus_recommended_maximum_direct_memory_megabytes gauge
sonatype_nexus_recommended_maximum_direct_memory_megabytes 3036
EOF
)

compare "$PROM_FILE" "$expected_filecontent"

#
#
echo "Test-1, Test-Case-3: Recommendation lines present, last recommendations line with different values."
#
export NXRMSCR_NEXUS_LOGFILE_PATH=resources/test1/log/nexus.t1.tc3.log
export PROM_FILE=tmp/out.t1.tc3.prom
source ../scrape_nexus.sh
set_up
printf "%s\n\n" "$CONTROL_LINE" >"${PROM_FILE}.$$"
nexus_log_orientdb_profiler_output_to_prom
rename_prom

expected_filecontent=$(
  cat <<'EOF'
# Control-line. With this line the test can check the generated PROM data is appended.

# HELP sonatype_nexus_recommended_maximum_jvm_heap_megabytes Recommendation for the JVM heap size in MB read from nexus.log.
# TYPE sonatype_nexus_recommended_maximum_jvm_heap_megabytes gauge
sonatype_nexus_recommended_maximum_jvm_heap_megabytes 2000
# HELP sonatype_nexus_recommended_maximum_direct_memory_megabytes Recommendation for the maximum direct memory size in MB read from nexus.log.
# TYPE sonatype_nexus_recommended_maximum_direct_memory_megabytes gauge
sonatype_nexus_recommended_maximum_direct_memory_megabytes 3000
EOF
)

message=$(compare "$PROM_FILE" "$expected_filecontent")
echo "$message"
if [[ "$message" == *"FAILED"* ]]; then
  is_any_test_failed=1
fi

if [[ "$is_any_test_failed" == 1 ]]; then
  echo "Test-1 FAILED: At lest one test failed."
else
  echo "Test-1 OK: All tests passed."
fi
