
set -eu

export IS_SCRIPT_USED_AS_LIB_FOR_TESTING=1
export NXRMSCR_PROM_FILES_DIR=tmp
export CONTROL_LINE="# Control-line. With this line the test can check the generated PROM data is appended."

function set_up() {
  rm -f "$NXRMSCR_PROM_FILES_DIR"/*
}
