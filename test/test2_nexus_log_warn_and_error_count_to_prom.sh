#!/bin/bash

source lib.sh
set -e

is_any_test_failed=0

#
#
echo "Test-2, Test-Case-1: 0 WARN, 0 ERROR"
#
export NXRMSCR_NEXUS_LOGFILE_PATH=resources/test2/log/nexus.t2.tc1.log
export PROM_FILE=tmp/out.t2.tc1.prom
source ../scrape_nexus.sh
set_up
printf "%s\n\n" "$CONTROL_LINE" >"${PROM_FILE}.$$"
nexus_log_warn_and_error_count_to_prom
rename_prom

expected_filecontent=$(
  cat <<'EOF'
# Control-line. With this line the test can check the generated PROM data is appended.

# HELP sonatype_nexus_num_warn_lines_in_nexus_log_total Number of WARN lines in nexus.log.
# TYPE sonatype_nexus_num_warn_lines_in_nexus_log_total counter
sonatype_nexus_num_warn_lines_in_nexus_log_total 0
# HELP sonatype_nexus_num_error_lines_in_nexus_log_total Number of ERROR lines in nexus.log.
# TYPE sonatype_nexus_num_error_lines_in_nexus_log_total counter
sonatype_nexus_num_error_lines_in_nexus_log_total 0
EOF
)

message=$(compare "$PROM_FILE" "$expected_filecontent")
echo "$message"
if [[ "$message" == *"FAILED"* ]]; then
  is_any_test_failed=1
fi

#
#
echo "Test-2, Test-Case-2: 2 WARN, 1 ERROR"
#
export NXRMSCR_NEXUS_LOGFILE_PATH=resources/test2/log/nexus.t2.tc2.log
export PROM_FILE=tmp/out.t2.tc2.prom
source ../scrape_nexus.sh
set_up
printf "%s\n\n" "$CONTROL_LINE" >"${PROM_FILE}.$$"
nexus_log_warn_and_error_count_to_prom
rename_prom

expected_filecontent=$(
  cat <<'EOF'
# Control-line. With this line the test can check the generated PROM data is appended.

# HELP sonatype_nexus_num_warn_lines_in_nexus_log_total Number of WARN lines in nexus.log.
# TYPE sonatype_nexus_num_warn_lines_in_nexus_log_total counter
sonatype_nexus_num_warn_lines_in_nexus_log_total 2
# HELP sonatype_nexus_num_error_lines_in_nexus_log_total Number of ERROR lines in nexus.log.
# TYPE sonatype_nexus_num_error_lines_in_nexus_log_total counter
sonatype_nexus_num_error_lines_in_nexus_log_total 1
EOF
)

message=$(compare "$PROM_FILE" "$expected_filecontent")
echo "$message"
if [[ "$message" == *"FAILED"* ]]; then
  is_any_test_failed=1
fi

if [[ "$is_any_test_failed" == 1 ]]; then
  echo "Test-2 FAILED: At lest one test failed."
else
  echo "Test-2 OK: All tests passed."
fi
