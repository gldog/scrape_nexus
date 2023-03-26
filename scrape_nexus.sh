#!/bin/bash

#--------------------------------------------------------------------------------------------------------------- 120 --#
# Collect Nexus metrics of different sources and assembles them as PROM-metrics in one single PROM-file.
#
# Sonatype Nexus Repository provides metrics in PROM-format. It provides metrics about Nexus application as well as the
# JVM. These metrics are collected calling the REST endpoint /service/metrics/prometheus.
#
# Prometheus could call this endpoint. But Nexus provides more than that, and it could make sense to collect all
# interesting metrics before delivering to Prometheus. But how to do that?
#
# A standard way of collecting server-metrics is using the node_exporter. If Prometheus is used it is most likely the
# node_exporter is installed on the server Nexus is running on, or it is recommended to do so.
# The node_exporter provides VM-metrics, and the node_exporter can deliver PROM-data from PROM-files.
# It makes sense to use the node_exporter to convey the Nexus-metrics:
#   - Prometheus needs only one scrape-config for the Nexus-server, instead of one config for node_exporter and another
#     one for Nexus.
#   - The Nexus-admin is free to add metrics of interest without contacting the Prometheus-admin. And this is what this
#     script is for.
#
# This script collects and writes to a PROM-file:
#   - reads /service/metrics/prometheus => creates service_metrics_prometheus.prom
#   - reads /service/rest/v1/blobstores => transforms useful data into PROM format and appends them to the .prom file
#   - reads /service/rest/v1/repositories => transforms useful data into PROM format and appends them to the .prom file
#   - parses nexus.log and extracts memory recommendations printed by the embedded Orient-DB
#
# Feel free to append metrics you interested in.

#
# Environment vars set from extern.
#
set +u
# Nexus-base-URL. Defaults to a local test instance http://localhost:8081.
# F.y.i., the context-path is configured in sonatype-work/nexus3/etc/nexus.properties. The default is "/".
[[ -z "$NXRMSCR_NEXUS_BASE_URL" ]] && NXRMSCR_NEXUS_BASE_URL="http://localhost:8081"
# Strip off trailing slash if present.
# Shell-check:
#   Recommended "See if you can use ${variable//search/replace} instead. See SC2001".
#   But this won't work here.
# shellcheck disable=SC2001
NXRMSCR_NEXUS_BASE_URL=$(echo $NXRMSCR_NEXUS_BASE_URL | sed 's#/*$##')
# Abs. path to Nexus logfile, defaults to /opt/nexus/sonatype-work/nexus3/log/nexus.log.
[[ -z "$NXRMSCR_NEXUS_LOGFILE_PATH" ]] && NXRMSCR_NEXUS_LOGFILE_PATH="/opt/nexus/sonatype-work/nexus3/log/nexus.log"
# Abs. path to Nexus tmp-file, defaults to /opt/nexus/sonatype-work/nexus3/tmp.
[[ -z "$NXRMSCR_NEXUS_TMP_PATH" ]] && NXRMSCR_NEXUS_TMP_PATH="/opt/nexus/sonatype-work/nexus3/tmp"
# Abs. path to the directory the PROM-metrics shall be saved to.
# Note, the files shared with node_exporter have to be readable by the user running node_exporter (the standard user
# for this is 'prometheus').
[[ -z "$NXRMSCR_PROM_FILES_DIR" ]] && NXRMSCR_PROM_FILES_DIR="/tmp/node_exporter_collector_textfiles"
[[ -z "$_IS_SCRIPT_UNDER_TEST" ]] && _IS_SCRIPT_UNDER_TEST=false
[[ -z "$NXRMSCR_DIRECTORY_SIZES_OF" ]] && NXRMSCR_DIRECTORY_SIZES_OF=""
set -u

# Log with common format.
# Note:
#   - The message is expected as one argument. Don't use:
#       log "message1" "message2"
#     or
#       log "message1" \
#         "message2"
#   - Starting the script with nohup later on redirects stdout and stderr to the given logfile. No redirection
#     is needed here.
function log() {
  echo "$(date +"%Y-%m-%d %H-%M-%S") $SCRIPT_NAME: $1"
}

#
# Internal vars.
#

# The directory this script is located in (not: the directory this script is called from).
SCRIPT_LOCATION_DIR=$(dirname "$0")
# The script name without path.
SCRIPT_NAME=$(basename "$0")
# The PID-file is the script name without script-extension but suffix .pid.
PID_FILE="$SCRIPT_LOCATION_DIR/${SCRIPT_NAME%.*}.pid"
# The logfile is the script name without script-extension but suffix .log.
LOG_FILE="$SCRIPT_LOCATION_DIR/${SCRIPT_NAME%.*}.log"
INTERVAL=10
SERVICE_METRICS_PROMETHEUS_URL="$NXRMSCR_NEXUS_BASE_URL/service/metrics/prometheus"
SERVICE_METRICS_PROMETHEUS_PROM_FILE="service_metrics_prometheus.prom"
PROM_FILE="$NXRMSCR_PROM_FILES_DIR/$SERVICE_METRICS_PROMETHEUS_PROM_FILE"

function control() {
  case "$1" in
  start)
    if [[ -f $PID_FILE ]]; then
      log "ERROR: Called with parameter start, but found PID-file $PID_FILE with PID $(cat "$PID_FILE")." |
        tee -a "$LOG_FILE"
      exit 1
    else
      mkdir -p "$NXRMSCR_PROM_FILES_DIR"
      # Redirect stdout and stderr to the given logfile.
      nohup "$0" >>"$LOG_FILE" 2>&1 &
      # $? is the exit status of nohup.
      # shellcheck disable=SC2181
      if [[ $? -eq 0 ]]; then
        echo $! >"$PID_FILE"
        log "Started, PID is $!, PID-file is $PID_FILE."
      else
        log "ERROR: nohup returned $?"
        exit 1
      fi
    fi
    ;;

  stop)
    if [[ -f $PID_FILE ]]; then
      if kill "$(cat "$PID_FILE")"; then
        log "Stopped, PID was $(cat "$PID_FILE"), PID-file was $PID_FILE."
        rm -f "$PID_FILE"
      else
        log "ERROR: Could not kill PID $(cat "$PID_FILE") from  PID-file was $PID_FILE."
      fi
    else
      log "ERROR: Could not find PID-file $PID_FILE."
      exit 1
    fi
    # Signal no data to Prometheus instead sticking to the latest scrape.
    # -f: Do not moan in case the directory is empty.
    rm -f "$NXRMSCR_PROM_FILES_DIR/*"
    ;;

  *)
    log "Unsupported parameter $1. Supported parameters are: <none> (foregroud call); start, stop (nohup)."
    exit 1
    ;;
  esac

}

function scrape_nexus_prometheus_url() {

  # curls exits with a non-zero value in case the server can't be reached. Don't abort this script in those cases.
  set +e
  is_connection_failed=false
  # Wait until Nexus is up.
  # 4xx and 5xx counts to 'not available' (because '-f').
  if [[ "$_IS_SCRIPT_UNDER_TEST" == false ]]; then
    until curl -fIks "$NXRMSCR_NEXUS_BASE_URL" -o /dev/null; do
      log "ERROR: Failed to connect to $NXRMSCR_NEXUS_BASE_URL. Waiting $INTERVAL seconds until retry."
      rm -f "${PROM_FILE}.$$"
      rm -f "${PROM_FILE}"
      is_connection_failed=true
      sleep $INTERVAL
    done
  fi
  if [[ $is_connection_failed == true ]]; then
    log "Connection to $NXRMSCR_NEXUS_BASE_URL successful."
  fi

  out=$(curl -fksS "$SERVICE_METRICS_PROMETHEUS_URL" -o "${PROM_FILE}.$$" 2>&1)
  # Because of '%{http_code}' the output starts with the HTTP status code. This is expected to be 200. But on errors
  # this could be 4xx or 5xx as well. If Nexus can't be reached it is 000. At 4xx and 5xx it is followed by an
  # error message from curl. It is:
  #   curl: (22) The requested URL returned error: 400
  #   curl: (22) The requested URL returned error: 500
  #   url: (7) Failed to connect to localhost port 8081 after 2 ms: Couldn't connect to server
  # SC2181: "Check exit code directly with e.g. if mycmd;, not indirectly with $?":
  # shellcheck disable=SC2181
  if [[ $? -ne 0 ]]; then
    log "ERROR: Failed to connect to $SERVICE_METRICS_PROMETHEUS_URL. $out"
    rm -f "${PROM_FILE}.$$"
    rm -f "${PROM_FILE}"
  fi

  set -e
}

function nexus_log_warn_and_error_count_to_prom() {

  if [[ -f $NXRMSCR_NEXUS_LOGFILE_PATH ]]; then
    {
      echo "# HELP sonatype_nexus_num_warn_lines_in_nexus_log_total Number of WARN lines in nexus.log."
      echo "# TYPE sonatype_nexus_num_warn_lines_in_nexus_log_total counter"
      echo "sonatype_nexus_num_warn_lines_in_nexus_log_total $(grep -cE " WARN " "$NXRMSCR_NEXUS_LOGFILE_PATH")"
    } >>"${PROM_FILE}.$$"

    {
      echo "# HELP sonatype_nexus_num_error_lines_in_nexus_log_total Number of ERROR lines in nexus.log."
      echo "# TYPE sonatype_nexus_num_error_lines_in_nexus_log_total counter"
      echo "sonatype_nexus_num_error_lines_in_nexus_log_total $(grep -cE " ERROR " "$NXRMSCR_NEXUS_LOGFILE_PATH")"
    } >>"${PROM_FILE}.$$"
  fi
}

# Build Prometheus metrics for recommended_maximum_jvm_heap_megabytes and and recommended_maximum_direct_memory_megabytes
# and print them to the PROM-file.
function nexus_log_orientdb_profiler_output_to_prom() {

  if [[ -f $NXRMSCR_NEXUS_LOGFILE_PATH ]]; then

    # Prepare Prometheus metric text for max. heap size.
    max_heap_metric="# HELP sonatype_nexus_recommended_maximum_jvm_heap_megabytes"
    max_heap_metric+=" Recommendation for the JVM heap size in MB read from nexus.log.\n"
    max_heap_metric+="# TYPE sonatype_nexus_recommended_maximum_jvm_heap_megabytes gauge\n"
    max_heap_metric+="sonatype_nexus_recommended_maximum_jvm_heap_megabytes"

    # Prepare Prometheus metric text for direct memory size.
    max_direct_metric="# HELP sonatype_nexus_recommended_maximum_direct_memory_megabytes"
    max_direct_metric+=" Recommendation for the maximum direct memory size in MB read from nexus.log.\n"
    max_direct_metric+="# TYPE sonatype_nexus_recommended_maximum_direct_memory_megabytes gauge\n"
    max_direct_metric+="sonatype_nexus_recommended_maximum_direct_memory_megabytes"

    # Make the newlines effective in awk. Without this, awk prints them as literal '\n'.
    # The format '%b' really prints the newline ('%s' would print the literal '\n').
    max_heap_metric=$(printf "%b" "$max_heap_metric")
    max_direct_metric=$(printf "%b" "$max_direct_metric")

    # The lines of interest can be found by the following pattern. It is printed from the OAbstractProfiler. This class
    # is part of the OrientDB code, not the Nexus code.
    # From OrientDB https://github.com/orientechnologies/orientdb/blob/develop/core/src/main/java/com/orientechnologies/common/profiler/OAbstractProfiler.java:
    #     "To improve performance set maxHeap to %dMB and DISKCACHE to %dMB"
    pattern="OAbstractProfiler.+To improve performance set maxHeap to"

    # tac starts reading the logfile from the end. This is to get the latest recommended values.
    # Extend grep with 'true': grep exits with a non-zero value in case the pattern can't be found. Don't abort this
    # script in those cases.
    last_matching_line=$(tac "$NXRMSCR_NEXUS_LOGFILE_PATH" | grep -m 1 -E "$pattern" || true)
    if [[ -n "$last_matching_line" ]]; then

      # This is a version using -v to define awk-vars. But it doesn't run on MacOS. It is moaning:
      #   awk: newline in string # HELP recommended_m... at source line 1
      #
      #tac -s "$pattern" -r "$NXRMSCR_NEXUS_LOGFILE_PATH" | head -n 1 |
      #  awk -v max_heap_metric="$max_heap_metric" -v max_direct_metric="$max_direct_metric" \
      #    '{printf "%s %d\n%s %d\n", max_heap_metric, $1, max_direct_metric, $5; }'>>"${PROM_FILE}.$$"

      # This is a portable version.
      # The delete ARGV is to prevent awk treating the ARGs as argument-filenames.
      # A matching line ends with the following sentence:
      #   Index:                                                    -4  -3        -2 -1      0
      #   Log-text:   ... To improve performance set maxHeap to 2652MB and DISKCACHE to 3036MB
      # awk can print fields counting from right to left using the awk-variable NF (number of fields in current row).
      # To get the '3036MB' the $NF is used, and to get the '2652MB' the $(NF-4) is used. Both are printed as int
      # to strip off the 'MB'.
      echo "$last_matching_line" |
        awk 'BEGIN {max_heap_metric=ARGV[1]; max_direct_metric=ARGV[2]; delete ARGV[1]; delete ARGV[2]}
          {printf "%s %d\n%s %d\n", max_heap_metric, $(NF-4), max_direct_metric, $NF }' \
          "$max_heap_metric" "$max_direct_metric" >>"${PROM_FILE}.$$"
    else
      # Set recommended values to 0 signalling the log-scrape is alive but no profiler-recommendations has been found.
      printf "%b 0\n%b 0\n" "$max_heap_metric" "$max_direct_metric" >>"${PROM_FILE}.$$"
    fi
    # Without logfile no recommendations are written to signal the absent logfile.
  fi
}

function blobstore_and_repo_sizes_to_prom() {

  blobstore_and_repo_sizes_jsonfile=$(find $NXRMSCR_NEXUS_TMP_PATH -name "repoSizes-*" | tail -1)
  if [[ ! -f "$blobstore_and_repo_sizes_jsonfile" ]]; then
    # Can't write PROM metric without the JSON file.
    return
  fi

  is_any_metric=false
  # Blobstore: totalBlobStoreBytes
  totalBlobStoreBytes_prom="# HELP sonatype_nexus_repoSizes_blobstore_totalBlobStoreBytes\n"
  totalBlobStoreBytes_prom+="# TYPE sonatype_nexus_repoSizes_blobstore_totalBlobStoreBytes gauge\n"
  # Blobstore: totalReclaimableBytes
  totalReclaimableBytes_prom="# HELP sonatype_nexus_repoSizes_blobstore_totalReclaimableBytes\n"
  totalReclaimableBytes_prom+="# TYPE sonatype_nexus_repoSizes_blobstore_totalReclaimableBytes gauge\n"
  # Blobstore: totalRepoNameMissingCount
  totalRepoNameMissingCount_prom="# HELP sonatype_nexus_repoSizes_blobstore_totalRepoNameMissingCount\n"
  totalRepoNameMissingCount_prom+="# TYPE sonatype_nexus_repoSizes_blobstore_totalRepoNameMissingCount gauge\n"
  # Repo: totalBytes
  totalBytes_prom="# HELP sonatype_nexus_repoSizes_repo_totalBytes\n"
  totalBytes_prom+="# TYPE sonatype_nexus_repoSizes_repo_totalBytes gauge\n"
  # Repo: reclaimableBytes
  reclaimableBytes_prom="# HELP sonatype_nexus_repoSizes_repo_reclaimableBytes\n"
  reclaimableBytes_prom+="# TYPE sonatype_nexus_repoSizes_repo_reclaimableBytes gauge\n"

  # By using jq --compact-output (or -c) we can get each object on a newline.
  # jq is robust against an completely empty file.
  for blobstore_obj in $(jq -c '. | to_entries | .[]' "$blobstore_and_repo_sizes_jsonfile"); do
    is_any_metric=true
    # jq -r (raw) prints the blobstore-names without surrounding quotes..
    blobstore_name=$(echo "$blobstore_obj" | jq -r '.key')
    # Blobstore: totalBlobStoreBytes
    totalBlobStoreBytes=$(echo "$blobstore_obj" | jq '.value.totalBlobStoreBytes')
    totalBlobStoreBytes_prom+="sonatype_nexus_repoSizes_blobstore_totalBlobStoreBytes"
    totalBlobStoreBytes_prom+="{blobstore=\"$blobstore_name\"} $totalBlobStoreBytes\n"
    # Blobstore: totalReclaimableBytes
    totalReclaimableBytes=$(echo "$blobstore_obj" | jq '.value.totalReclaimableBytes')
    totalReclaimableBytes_prom+="sonatype_nexus_repoSizes_blobstore_totalReclaimableBytes"
    totalReclaimableBytes_prom+="{blobstore=\"$blobstore_name\"} $totalReclaimableBytes\n"
    # Blobstore: totalRepoNameMissingCount
    totalRepoNameMissingCount=$(echo "$blobstore_obj" | jq '.value.totalRepoNameMissingCount')
    totalRepoNameMissingCount_prom+="sonatype_nexus_repoSizes_blobstore_totalRepoNameMissingCount"
    totalRepoNameMissingCount_prom+="{blobstore=\"$blobstore_name\"} $totalRepoNameMissingCount\n"
    for repo_obj in $(echo "$blobstore_obj" | jq -c '.value.repositories | to_entries | .[]'); do
      repo_name=$(echo "$repo_obj" | jq -r '.key')
      totalBytes=$(echo "$repo_obj" | jq -r '.value.totalBytes')
      reclaimableBytes=$(echo "$repo_obj" | jq -r '.value.reclaimableBytes')
      # Repo: totalBytes
      totalBytes_prom+="sonatype_nexus_repoSizes_repo_totalBytes"
      totalBytes_prom+="{blobstore=\"$blobstore_name\",repo=\"$repo_name\"} $totalBytes\n"
      # Repo: reclaimableBytes
      reclaimableBytes_prom+="sonatype_nexus_repoSizes_repo_reclaimableBytes"
      reclaimableBytes_prom+="{blobstore=\"$blobstore_name\",repo=\"$repo_name\"} $reclaimableBytes\n"
    done
  done

  if [[ "$is_any_metric" == true ]]; then
    printf "%b%b%b%b%b" \
      "$totalBlobStoreBytes_prom" "$totalReclaimableBytes_prom" "$totalRepoNameMissingCount_prom" \
      "$totalBytes_prom" "$reclaimableBytes_prom" \
      >>"${PROM_FILE}.$$"
  fi
}

# See also https://www.robustperception.io/monitoring-directory-sizes-with-the-textfile-collector/
function directory_sizes_to_prom() {

  if [[ -n "$NXRMSCR_DIRECTORY_SIZES_OF" ]]; then
    # Check if dir(s) exist.
    dirs=$(echo "$NXRMSCR_DIRECTORY_SIZES_OF" | tr ":" " ")
    unixtime_before_ls=$(date +%s)
    set +e
    # ls: Prints information of existing dirs to stdout and information about non-existing dirs to stderr. We are only
    # interested in stderr here (and the exit status).
    # Redirect stderr to ls_out, but not stdout. The order of '2>&1' and '>/dev/null' matters.
    ls_out=$(eval ls "$dirs" 2>&1 >/dev/null)
    ls_exit_code=$?
    set -e
    unixtime_after_ls=$(date +%s)
    if [[ $ls_exit_code == 0 ]]; then
      # eval is needed in case $dirs contains parameters to be expanded. E.g. path/to{a,b}. Without eval, the _string_
      # 'path/to{a,b}' is passed to ls, not the expanded 'path/to/a path/to/b'. Same with du later on.
      prom="$(eval du -sk "$dirs" | awk '{ print "node_directory_size_bytes{directory=\"" $2 "\"" "}" " " $1*1024}')\n"
      prom+="# HELP The duration the du-command took for all directories in NXRMSCR_DIRECTORY_SIZES_OF.\n"
      prom+="# TYPE node_directory_size_du_exec_duration_seconds gauge\n"
      prom+="$(echo "$unixtime_before_ls $unixtime_after_ls" |
        awk '{print "node_directory_size_du_exec_duration_seconds " $2-$1"\\n"}')\n"
      printf "%b" "$prom" >>"${PROM_FILE}.$$"
    else
      # Write an error message.
      # The check for dir-existence with ls outputs something like
      #   ls: the-dir: No such file or directory
      # But using the ls as check for existence is an internal implementation. The user should not see the output of ls.
      # The two sed prettifies the error message from ls. The first call replaces the "ls: " with ";". The second one
      # removed the first ";".
      log "ERROR: NXRMSCR_DIRECTORY_SIZES_OF: $(echo "$ls_out" | tr -d '\n' | sed 's#ls: #; #g' | sed 's#; ##1')"
    fi
  fi
}

# Provide the PROM-file atomically.
function rename_prom() {
  mv "${PROM_FILE}.$$" "$PROM_FILE"
}

function run() {

  message="Start scraping. Settings: NXRMSCR_NEXUS_BASE_URL: $NXRMSCR_NEXUS_BASE_URL"
  message+=", NXRMSCR_NEXUS_LOGFILE_PATH: $NXRMSCR_NEXUS_LOGFILE_PATH"
  message+=", NXRMSCR_PROM_FILES_DIR: $NXRMSCR_PROM_FILES_DIR"
  log "$message"

  # If the umask would be a typical default of 0027, the user reading these files (usually 'prometheus' running the
  # node_exporter) could got into no read-access.
  umask 0022

  while true; do
    mkdir -p "$NXRMSCR_PROM_FILES_DIR"
    # -f: Files might not yet there, avoid rm-error.
    rm -f "$NXRMSCR_PROM_FILES_DIR/*"
    # Inform some reader what is the directory-content for.
    echo "These files were written by $0." >$NXRMSCR_PROM_FILES_DIR/readme.txt
    scrape_nexus_prometheus_url
    nexus_log_warn_and_error_count_to_prom
    nexus_log_orientdb_profiler_output_to_prom
    blobstore_and_repo_sizes_to_prom
    directory_sizes_to_prom
    rename_prom
    sleep $INTERVAL
  done
}

if [[ "$_IS_SCRIPT_UNDER_TEST" == false ]]; then
  set +u # Because $1 is empty at 'run'.
  if [[ -n "$1" ]]; then
    control "$1"
  else
    run
  fi
  set -u
fi

#--------------------------------------------------------------------------------------------------------------- 120 --#
