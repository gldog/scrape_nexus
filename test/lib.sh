
set -eu

export _IS_SCRIPT_UNDER_TEST=true
export NXRMSCR_PROM_FILES_DIR=tmp
export CONTROL_LINE="# Control-line. With this line the test can check the generated PROM data is appended."

function set_up() {
  rm -f "$NXRMSCR_PROM_FILES_DIR"/*
}
