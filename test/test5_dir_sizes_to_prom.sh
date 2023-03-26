#!/bin/bash

source lib.sh
set -e

is_any_test_failed=0

#
#
echo "Test-5, Test-Case-1: No dirs set."
#
export PROM_FILE=tmp/out.t5.tc1.prom
source ../scrape_nexus.sh
set_up
printf "%s\n\n" "$CONTROL_LINE" >"${PROM_FILE}.$$"
directory_sizes_to_prom
rename_prom

expected_filecontent=$(
  cat <<'EOF'
# Control-line. With this line the test can check the generated PROM data is appended.

EOF
)

message=$(compare "$PROM_FILE" "$expected_filecontent")
echo "$message"
if [[ "$message" == *"FAILED"* ]]; then
  is_any_test_failed=1
fi

#
#
echo "Test-5, Test-Case-2: 2 existing dirs set."
#
export NXRMSCR_DIRECTORY_SIZES_OF="resources/test5/a:resources/test5/b"
export PROM_FILE=tmp/out.t5.tc1.prom
source ../scrape_nexus.sh
set_up
printf "%s\n\n" "$CONTROL_LINE" >"${PROM_FILE}.$$"
directory_sizes_to_prom
rename_prom

expected_filecontent=$(
  cat <<'EOF'
# Control-line. With this line the test can check the generated PROM data is appended.

node_directory_size_bytes{directory="resources/test5/a"} 12288
node_directory_size_bytes{directory="resources/test5/b"} 20480
# HELP The duration the du-command took for all directories in NXRMSCR_DIRECTORY_SIZES_OF.
# TYPE node_directory_size_du_exec_duration_seconds gauge
node_directory_size_du_exec_duration_seconds 0
EOF
)

message=$(compare "$PROM_FILE" "$expected_filecontent")
echo "$message"
if [[ "$message" == *"FAILED"* ]]; then
  is_any_test_failed=1
fi

#
#
echo "Test-5, Test-Case-3: Expanded dirs."
#
export NXRMSCR_DIRECTORY_SIZES_OF="resources/test5/{a,b}"
export PROM_FILE=tmp/out.t5.tc1.prom
source ../scrape_nexus.sh
set_up
printf "%s\n\n" "$CONTROL_LINE" >"${PROM_FILE}.$$"
directory_sizes_to_prom
rename_prom

expected_filecontent=$(
  cat <<'EOF'
# Control-line. With this line the test can check the generated PROM data is appended.

node_directory_size_bytes{directory="resources/test5/a"} 12288
node_directory_size_bytes{directory="resources/test5/b"} 20480
# HELP The duration the du-command took for all directories in NXRMSCR_DIRECTORY_SIZES_OF.
# TYPE node_directory_size_du_exec_duration_seconds gauge
node_directory_size_du_exec_duration_seconds 0
EOF
)

message=$(compare "$PROM_FILE" "$expected_filecontent")
echo "$message"
if [[ "$message" == *"FAILED"* ]]; then
  is_any_test_failed=1
fi

#
#
echo "Test-5, Test-Case-4: 1 existing dir and 2 not existing dirs set."
#
export NXRMSCR_DIRECTORY_SIZES_OF="a/b/not-existing-dir1:a/b/not-existing-dir2:resources/test5/b"
export PROM_FILE=tmp/out.t5.tc1.prom
source ../scrape_nexus.sh
set_up
printf "%s\n\n" "$CONTROL_LINE" >"${PROM_FILE}.$$"
out=$(directory_sizes_to_prom)
rename_prom

expected_error_message="ERROR: NXRMSCR_DIRECTORY_SIZES_OF: a/b/not-existing-dir1: No such file or directory;\
 a/b/not-existing-dir2: No such file or directory"
if [[ ! "$out" == *"$expected_error_message" ]]; then
  echo "ERROR: Missing error message: '$expected_error_message'"
  is_any_test_failed=1
fi

expected_filecontent=$(
  cat <<'EOF'
# Control-line. With this line the test can check the generated PROM data is appended.

EOF
)

message=$(compare "$PROM_FILE" "$expected_filecontent")
echo "$message"
if [[ "$message" == *"FAILED"* ]]; then
  is_any_test_failed=1
fi

if [[ "$is_any_test_failed" == 1 ]]; then
  echo "Test-5 FAILED: At lest one test failed."
else
  echo "Test-5 OK: All tests passed."
fi
