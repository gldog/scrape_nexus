#!/bin/bash

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

# Exit script on failure.
set -e

#
# Environment vars set from extern.
#
# Nexus-base-URL. Defaults to a local test instance http://localhost:8081.
# F.y.i., the context-path is configured in sonatype-work/nexus3/etc/nexus.properties. The default is "/".
[[ -z $NEXUS_BASE_URL ]] && NEXUS_BASE_URL="http://localhost:8081"
# Strip off trailing slash if present.
# Shell-check:
#   Recommended "See if you can use ${variable//search/replace} instead. See SC2001".
#   But this won't work here.
# shellcheck disable=SC2001
NEXUS_BASE_URL=$(echo $NEXUS_BASE_URL | sed 's#/*$##')

# Abs. path to Nexus logfile, defaults to /opt/nexus/sonatype-work/nexus3/log/nexus.log.
[[ -z $NEXUS_LOGFILE_PATH ]] && NEXUS_LOGFILE_PATH="/opt/nexus/sonatype-work/nexus3/log/nexus.log"

[[ -z $NEXUS_TMP_PATH ]] && NEXUS_TMP_PATH="/opt/nexus/sonatype-work/nexus3/tmp"

# Abs. path to the directory the PROM-metrics shall be saved to.
# Note, the files shared with node_exporter have to be readable by the user running node_exporter (the standard user
# for this is 'prometheus').
[[ -z $PROM_FILES_DIR ]] && PROM_FILES_DIR="/tmp/node_exporter_collector_textfiles"

# Log with common format.
# Note, starting the script with nohup later on redirects stdout and stderr to the given logfile.
function log() {
  # Print each argument separately:
  # Given a long string to be printed. This string is split into two lines:
  #
  #   log "Strings if split into lines" \"
  #     ", result in multiple arguments."
  #
  # Using echo "$@" would result in:
  #
  #   Strings if split into lines , result in multiple arguments.
  #
  # Note the space before the comma.
  # Printing each argument as a separate string without the newline character avoids that.
  echo -n "$(date +"%Y-%m-%d %H-%M-%S") $SCRIPT_NAME: "
  for arg in "$@"; do
    echo -n "$arg"
  done
  # Print final newline.
  echo
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
SERVICE_METRICS_PROMETHEUS_URL="$NEXUS_BASE_URL/service/metrics/prometheus"
SERVICE_METRICS_PROMETHEUS_PROM_FILE="service_metrics_prometheus.prom"
PROM_FILE="$PROM_FILES_DIR/$SERVICE_METRICS_PROMETHEUS_PROM_FILE"

function control() {
  case "$1" in
  start)
    if [[ -f $PID_FILE ]]; then
      log "ERROR: Called with parameter start, but found PID-file $PID_FILE with PID $(cat "$PID_FILE")." | tee -a "$LOG_FILE"
      exit 1
    else
      mkdir -p "$PROM_FILES_DIR"
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
    rm -f "$PROM_FILES_DIR/*"
    ;;

  *)
    log "Unsupported parameter $1. Supported parameters are: <none> (foregroud call); start, stop (nohup)."
    exit 1
    ;;
  esac

}

function scrape_nexus_prometheus_url() {

  # Wait until Nexus is up.
  until curl --insecure --output /dev/null --silent --head --fail "$NEXUS_BASE_URL"; do
    log "ERROR: Failed to connect to Nexus $NEXUS_BASE_URL. Waiting $INTERVAL seconds until retry."
    sleep $INTERVAL
  done

  curl -s --insecure "$SERVICE_METRICS_PROMETHEUS_URL" -o "${PROM_FILE}.$$"
}

function nexus_log_warn_and_error_count_to_prom() {

  if [[ -f $NEXUS_LOGFILE_PATH ]]; then

    cat <<EOF >>"${PROM_FILE}.$$"
# HELP sonatype_nexus_num_warn_lines_in_nexus_log_total Number of WARN lines in nexus.log.
# TYPE sonatype_nexus_num_warn_lines_in_nexus_log_total counter
sonatype_nexus_num_warn_lines_in_nexus_log_total $(grep -cE " WARN " "$NEXUS_LOGFILE_PATH")
EOF

    cat <<EOF >>"${PROM_FILE}.$$"
# HELP sonatype_nexus_num_error_lines_in_nexus_log_total Number of ERROR lines in nexus.log.
# TYPE sonatype_nexus_num_error_lines_in_nexus_log_total counter
sonatype_nexus_num_error_lines_in_nexus_log_total $(grep -cE " ERROR " "$NEXUS_LOGFILE_PATH")
EOF

  fi
}

function nexus_log_orientdb_profiler_output_to_prom() {

  # The lines of interest can be found by the following pattern. It is printed from the OAbstractProfiler. This class is
  # part of the OrientDB code, not the Nexus code.
  # In OrientDB https://github.com/orientechnologies/orientdb/blob/develop/core/src/main/java/com/orientechnologies/common/profiler/OAbstractProfiler.java:
  #     "To improve performance set maxHeap to %dMB and DISKCACHE to %dMB"
  pattern="OAbstractProfiler.+To improve performance set maxHeap to"

  # Prepare Prometheus metric text for max. heap size.
  max_heap_metric=$(
    cat <<'EOF'
# HELP sonatype_nexus_recommended_maximum_jvm_heap_megabytes Recommendation for the JVM heap size in MB read from nexus.log.
# TYPE sonatype_nexus_recommended_maximum_jvm_heap_megabytes gauge
sonatype_nexus_recommended_maximum_jvm_heap_megabytes
EOF
  )

  # Prepare Prometheus metric text for direct memory size.
  max_direct_metric=$(
    cat <<'EOF'
# HELP sonatype_nexus_recommended_maximum_direct_memory_megabytes Recommendation for the maximum direct memory size in MB read from nexus.log.
# TYPE sonatype_nexus_recommended_maximum_direct_memory_megabytes gauge
sonatype_nexus_recommended_maximum_direct_memory_megabytes
EOF
  )

  # Build both Prometheus metrics and print them to the temporary PROM-file already created.
  # tac starts reading the logfile from the end. This is to get the latest recommended values.
  # After the commands
  #   tac -s "$pattern" -r "$nexus_log" | head -n 1
  # the output is
  #   "2652MB and DISKCACHE to 3036MB"
  # Then awk assembles the prepared texts and the recommended values. It prints the values 2652MB and 3036MB as integers
  # to strip off the "MB".
  if [[ -f $NEXUS_LOGFILE_PATH ]]; then
    if grep -E -q "$pattern" "$NEXUS_LOGFILE_PATH"; then

      # This is a version using -v to define awk-vars. But it doesn't run on MacOS. It is moaning:
      #   awk: newline in string # HELP recommended_m... at source line 1
      #
      #tac -s "$pattern" -r "$nexus_log" | head -n 1 |
      #  awk -v max_heap_metric="$max_heap_metric" -v max_direct_metric="$max_direct_metric" \
      #    '{printf "%s %d\n%s %d\n", max_heap_metric, $1, max_direct_metric, $5; }'

      # This is a portable version.
      # The delete ARGV is to prevent awk treating the ARGs as argument-filenames.
      tac -s "$pattern" -r "$NEXUS_LOGFILE_PATH" | head -n 1 |
        awk 'BEGIN {max_heap_metric=ARGV[1]; max_direct_metric=ARGV[2]; delete ARGV[1]; delete ARGV[2]}
          {printf "%s %d\n%s %d\n", max_heap_metric, $1, max_direct_metric, $5; }' \
          "$max_heap_metric" "$max_direct_metric" >>"${PROM_FILE}.$$"
    else
      # Set recommended values to 0 signalling the log-scrape is alive if no profiler-recommendations has been found.
      echo -e "$max_heap_metric 0\n" >>"${PROM_FILE}.$$"
      echo -e "$max_direct_metric 0\n" >>"${PROM_FILE}.$$"
    fi
    # Without logfile no recommendations are written to signal the absent logfile.
  fi
}

function blobstore_and_repo_sizes_to_prom() {
  #set -x

  blobstore_and_repo_sizes_jsonfile=$(find $NEXUS_TMP_PATH -name "repoSizes-*" | tail -1)
  # Can't write PROM metric without the JSON file.
  if [[ ! -f "$blobstore_and_repo_sizes_jsonfile" ]]; then
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

  if [[ -f "$blobstore_and_repo_sizes_jsonfile" ]]; then
    # By using jq --compact-output (or -c) we can get each object on a newline.
    # jq is robust against an completely empty file.
    for blobstore_obj in $(jq -c '. | to_entries | .[]' "$blobstore_and_repo_sizes_jsonfile"); do
      is_any_metric=true
      # jq -r (raw) prints the blobstore-names without surrounding quotes..
      blobstore_name=$(echo $blobstore_obj | jq -r '.key')
      #echo "BS-NAME: $blobstore_name"
      # Blobstore: totalBlobStoreBytes
      totalBlobStoreBytes=$(echo $blobstore_obj | jq '.value.totalBlobStoreBytes')
      totalBlobStoreBytes_prom+="sonatype_nexus_repoSizes_blobstore_totalBlobStoreBytes"
      totalBlobStoreBytes_prom+="{blobstore=\"$blobstore_name\"} $totalBlobStoreBytes\n"
      # Blobstore: totalReclaimableBytes
      totalReclaimableBytes=$(echo $blobstore_obj | jq '.value.totalReclaimableBytes')
      totalReclaimableBytes_prom+="sonatype_nexus_repoSizes_blobstore_totalReclaimableBytes"
      totalReclaimableBytes_prom+="{blobstore=\"$blobstore_name\"} $totalReclaimableBytes\n"
      # Blobstore: totalRepoNameMissingCount
      totalRepoNameMissingCount=$(echo $blobstore_obj | jq '.value.totalRepoNameMissingCount')
      totalRepoNameMissingCount_prom+="sonatype_nexus_repoSizes_blobstore_totalRepoNameMissingCount"
      totalRepoNameMissingCount_prom+="{blobstore=\"$blobstore_name\"} $totalRepoNameMissingCount\n"
      for repo_obj in $(echo "$blobstore_obj" | jq -c '.value.repositories | to_entries | .[]'); do
        #echo "REPO-OBJ: $repo_obj"
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

    [[ "$is_any_metric" = true ]] &&
      printf "%b%b%b%b%b" \
        "$totalBlobStoreBytes_prom" "$totalReclaimableBytes_prom" "$totalRepoNameMissingCount_prom" \
        "$totalBytes_prom" "$reclaimableBytes_prom" \
        >>"${PROM_FILE}.$$"
  fi
}

function rename_prom() {
  # Provide the PROM-file atomically.
  mv "${PROM_FILE}.$$" "$PROM_FILE"
}

function run() {

  set -u
  log "Start scraping. Settings: NEXUS_BASE_URL: $NEXUS_BASE_URL, NEXUS_LOGFILE_PATH: $NEXUS_LOGFILE_PATH" \
    ", PROM_FILES_DIR: $PROM_FILES_DIR"

  # If the umask would be a typical default of 0027, the user reading these files (usually 'prometheus' running the
  # node_exporter) could have no read-access.
  umask 0022

  while true; do
    mkdir -p "$PROM_FILES_DIR"
    # -f: Files might not yet there, avoid rm-error.
    rm -f "$PROM_FILES_DIR/*"
    # Inform some reader what is the directory-content for.
    echo "These files were written by $0." >$PROM_FILES_DIR/readme.txt
    scrape_nexus_prometheus_url
    nexus_log_warn_and_error_count_to_prom
    nexus_log_orientdb_profiler_output_to_prom
    blobstore_and_repo_sizes_to_prom
    rename_prom
    sleep $INTERVAL
  done
}

if [[ -z "$IS_SCRIPT_USED_AS_LIB_FOR_TESTING" ]]; then
  if [[ -n "$1" ]]; then
    control "$1"
  else
    run
  fi
fi

