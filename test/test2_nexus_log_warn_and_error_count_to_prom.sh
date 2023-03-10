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
    diff <(cat "$promfile") <(printf '%s\n' "$expected_filecontent")
  fi
}

nexus_log_warn_and_error_count_to_prom

#
#
echo "Test-2, Test-Case-1: 0 WARN, 0 ERROR"
#
export NXRMSCR_NEXUS_LOGFILE_PATH=resources/test2/log/nexus.t2.tc1.log
export PROM_FILE=tmp/out.t2.tc1.prom
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

compare "$PROM_FILE" "$expected_filecontent"

#
#
echo "Test-2, Test-Case-2: 2 WARN, 1 ERROR"
#
export NXRMSCR_NEXUS_LOGFILE_PATH=resources/test2/log/nexus.t2.tc2.log
export PROM_FILE=tmp/out.t2.tc2.prom
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

compare "$PROM_FILE" "$expected_filecontent"

if [[ "$is_any_test_failed" == 1 ]]; then
  echo "Test-2 FAILED: At lest one test failed."
else
  echo "Test-2 OK: All tests passed."
fi
