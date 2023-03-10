#!/bin/bash

source lib.sh
./test1_nexus_log_orientdb_profiler_output_to_prom.sh
./test2_nexus_log_warn_and_error_count_to_prom.sh
./test3_blobstore_and_repo_sizes_to_prom.sh

rm "$NXRMSCR_PROM_FILES_DIR"/*
