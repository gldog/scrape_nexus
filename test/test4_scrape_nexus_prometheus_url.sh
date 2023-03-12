#!/bin/bash

source lib.sh

# scrape_nexus.sh sets set -e. But the test-functions uses the diff-command which exits with 1 in case of a diff.
# That would lead to an abortion and no subsequent tests would be executed.
set +e

is_any_test_failed=0

export PROM_FILE="tmp/out.t3.tc1.prom"

# Get free port:
while
  port=$(shuf -n 1 -i 49152-65535)
  netstat -atun | grep -q "$port"
do
  continue
done

#echo "$port"

# 'Random' port.
port="55185"

export NXRMSCR_NEXUS_BASE_URL="http://localhost:$port"
source ../scrape_nexus.sh

#
#
echo "Test-4, Test-Case-1: Service returns 200"
#
set_up
echo -e "HTTP/1.1 200 OK\n\n" | nc -l "$port" 2>&2 >/dev/null &
out=$(scrape_nexus_prometheus_url)
#echo "OUT: $out"
if [[ -n "$out" ]]; then
  echo "ERROR: Unexpected error message."
  is_any_test_failed=1
fi
if [[ ! $(find "$NXRMSCR_PROM_FILES_DIR" -type f | wc -l) -eq 1 ]]; then
  echo "ERROR: Missing PROM file in NXRMSCR_PROM_FILES_DIR $NXRMSCR_PROM_FILES_DIR"
  is_any_test_failed=1
fi

#
#
echo "Test-4, Test-Case-2: Service returns 400"
#
set_up
echo -e "HTTP/1.1 400 OK\n\n" | nc -l "$port" 2>&2 >/dev/null &
out=$(scrape_nexus_prometheus_url)
#echo "OUT: $out"
if [[ ! "$out" == *"curl: (22) The requested URL returned error: 400"* ]]; then
  echo "ERROR: Missing error message."
  is_any_test_failed=1
fi
if [[ $(find "$NXRMSCR_PROM_FILES_DIR" -type f | wc -l) -gt 0 ]]; then
  echo "ERROR: Found file in NXRMSCR_PROM_FILES_DIR $NXRMSCR_PROM_FILES_DIR"
  is_any_test_failed=1
fi

#
#
echo "Test-4, Test-Case-3: Service returns 500"
#
set_up
echo -e "HTTP/1.1 500 OK\n\n" | nc -l "$port" 2>&2 >/dev/null &
out=$(scrape_nexus_prometheus_url)
#echo "OUT: $out"
if [[ ! "$out" == *"curl: (22) The requested URL returned error: 500"* ]]; then
  echo "ERROR: Missing error message."
  is_any_test_failed=1
fi
if [[ $(find "$NXRMSCR_PROM_FILES_DIR" -type f | wc -l) -gt 0 ]]; then
  echo "ERROR: Found file in NXRMSCR_PROM_FILES_DIR $NXRMSCR_PROM_FILES_DIR"
  is_any_test_failed=1
fi

#
#
echo "Test-4, Test-Case-4: Service isn't available."
#
# No netcat. Means: Nexus isn't available.
out=$(scrape_nexus_prometheus_url)
#echo "OUT: $out"
if [[ ! "$out" == *"url: (7) Failed to connect to localhost port"* ]]; then
  echo "ERROR: Missing error message."
  is_any_test_failed=1
fi
if [[ $(find "$NXRMSCR_PROM_FILES_DIR" -type f | wc -l) -gt 0 ]]; then
  echo "ERROR: Found file in NXRMSCR_PROM_FILES_DIR $NXRMSCR_PROM_FILES_DIR"
  is_any_test_failed=1
fi

if [[ "$is_any_test_failed" == 1 ]]; then
  echo "Test-4 FAILED: At lest one test failed."
else
  echo "Test-4 OK: All tests passed."
fi
