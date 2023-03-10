#!/bin/bash

source lib.sh
source ../scrape_nexus.sh

# scrape_nexus.sh sets set -e. But the test-functions uses the diff-command which exits with 1 in case of a diff.
# That would lead to an abortion and no subsequent tests would be executed.
set +e

is_any_test_failed=0

function compare() {
  local promfile=$1
  local expected_filecontent=$2

  if [[ "$(cat "$promfile")" == "$expected_filecontent" ]]; then
    echo "  ok"
  else
    echo "  FAILED"
    is_any_test_failed=1
    echo "  Comaprison got / expected:"
    #diff <(cat "$promfile") <(printf '%s\n' "$expected_filecontent")
    diff --side-by-side --suppress-common-lines <(cat "$promfile") <(printf '%s\n' "$expected_filecontent")
  fi
}

#
#
echo "Test-1, Test-Case-1: No recommendation lines present."
#
export NXRMSCR_NEXUS_LOGFILE_PATH=resources/test1/log/nexus.t1.tc1.log
export PROM_FILE=tmp/out.t1.tc1.prom
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

compare "$PROM_FILE" "$expected_filecontent"

#
#
echo "Test-1, Test-Case-2: Recommendation lines present, all recommendations lines with same values."
#
export NXRMSCR_NEXUS_LOGFILE_PATH=resources/test1/log/nexus.t1.tc2.log
export PROM_FILE=tmp/out.t1.tc2.prom
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

compare "$PROM_FILE" "$expected_filecontent"

#
# END
#
if [[ "$is_any_test_failed" == 1 ]]; then
  echo "Test-1 FAILED: At lest one test failed."
else
  echo "Test-1 OK: All tests passed."
fi
