set -eu

export _IS_SCRIPT_UNDER_TEST=true
export NXRMSCR_PROM_FILE_DIR=tmp
export CONTROL_LINE="# Control-line. With this line the test can check the generated PROM data is appended."

function set_up() {
  rm -f "$NXRMSCR_PROM_FILE_DIR"/*
}

function compare() {
  local promfile=$1
  local expected_filecontent=$2

  if [[ "$(cat "$promfile")" == "$expected_filecontent" ]]; then
    echo "  ok"
  else
    echo "  FAILED"
    echo "  Comaprison got / expected:"
    # scrape_nexus.sh sets 'set -e'. But the test-functions uses the diff-command which exits with 1 in case of a diff.
    # That would lead to an abortion and no subsequent tests would be executed.
    set +e
    #diff <(cat "$promfile") <(printf '%s\n' "$expected_filecontent")
    diff --side-by-side --suppress-common-lines <(cat "$promfile") <(printf '%s\n' "$expected_filecontent")
    set -e
  fi
}
