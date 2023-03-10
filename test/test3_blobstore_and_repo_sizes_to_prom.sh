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
    #diff --side-by-side --suppress-common-lines <(cat "$promfile") <(printf '%s\n' "$expected_filecontent")
  fi
}

#
#
echo "Test-3, Test-Case-1: No repoSizes-JSON file present."
#
export NXRMSCR_NEXUS_TMP_PATH="resources/test3/tmp-no-repoSizes-files"
export PROM_FILE="tmp/out.t3.tc1.prom"
set_up
printf "%s\n\n" "$CONTROL_LINE" >"${PROM_FILE}.$$"
blobstore_and_repo_sizes_to_prom
rename_prom

# No PROM-data.
expected_filecontent="$(printf "%s\n\n" "$CONTROL_LINE")"

compare "$PROM_FILE" "$expected_filecontent"

#
#
echo "Test-3, Test-Case-2: Empty repoSizes-JSON file."
#
export NXRMSCR_NEXUS_TMP_PATH="resources/test3/tmp/repoSizes-20230308-230000.json"
export PROM_FILE="tmp/out.t3.tc2.prom"
set_up
printf "%s\n\n" "$CONTROL_LINE" >"${PROM_FILE}.$$"
blobstore_and_repo_sizes_to_prom
rename_prom

# No PROM-data.
expected_filecontent="$(printf "%s\n\n" "$CONTROL_LINE")"

compare "$PROM_FILE" "$expected_filecontent"

#
#
echo "Test-3, Test-Case-3: repoSizes-JSON file with 2 blobstores and 2 repos each."
#
export NXRMSCR_NEXUS_TMP_PATH="resources/test3/tmp/repoSizes-20230308-230001.json"
export PROM_FILE="tmp/out.t3.tc3.prom"
printf "%s\n\n" "$CONTROL_LINE" >"${PROM_FILE}.$$"
blobstore_and_repo_sizes_to_prom
rename_prom

expected_filecontent=$(
  cat <<'EOF'
# Control-line. With this line the test can check the generated PROM data is appended.

# HELP sonatype_nexus_repoSizes_blobstore_totalBlobStoreBytes
# TYPE sonatype_nexus_repoSizes_blobstore_totalBlobStoreBytes gauge
sonatype_nexus_repoSizes_blobstore_totalBlobStoreBytes{blobstore="default"} 101
sonatype_nexus_repoSizes_blobstore_totalBlobStoreBytes{blobstore="blobstore2"} 201
# HELP sonatype_nexus_repoSizes_blobstore_totalReclaimableBytes
# TYPE sonatype_nexus_repoSizes_blobstore_totalReclaimableBytes gauge
sonatype_nexus_repoSizes_blobstore_totalReclaimableBytes{blobstore="default"} 102
sonatype_nexus_repoSizes_blobstore_totalReclaimableBytes{blobstore="blobstore2"} 202
# HELP sonatype_nexus_repoSizes_blobstore_totalRepoNameMissingCount
# TYPE sonatype_nexus_repoSizes_blobstore_totalRepoNameMissingCount gauge
sonatype_nexus_repoSizes_blobstore_totalRepoNameMissingCount{blobstore="default"} 103
sonatype_nexus_repoSizes_blobstore_totalRepoNameMissingCount{blobstore="blobstore2"} 203
# HELP sonatype_nexus_repoSizes_repo_totalBytes
# TYPE sonatype_nexus_repoSizes_repo_totalBytes gauge
sonatype_nexus_repoSizes_repo_totalBytes{blobstore="default",repo="bs-default-repo-1"} 12
sonatype_nexus_repoSizes_repo_totalBytes{blobstore="default",repo="bs-default-repo-2"} 14
sonatype_nexus_repoSizes_repo_totalBytes{blobstore="blobstore2",repo="bs-blobstore2-repo-1"} 22
sonatype_nexus_repoSizes_repo_totalBytes{blobstore="blobstore2",repo="bs-blobstore2-repo-2"} 24
# HELP sonatype_nexus_repoSizes_repo_reclaimableBytes
# TYPE sonatype_nexus_repoSizes_repo_reclaimableBytes gauge
sonatype_nexus_repoSizes_repo_reclaimableBytes{blobstore="default",repo="bs-default-repo-1"} 11
sonatype_nexus_repoSizes_repo_reclaimableBytes{blobstore="default",repo="bs-default-repo-2"} 13
sonatype_nexus_repoSizes_repo_reclaimableBytes{blobstore="blobstore2",repo="bs-blobstore2-repo-1"} 21
sonatype_nexus_repoSizes_repo_reclaimableBytes{blobstore="blobstore2",repo="bs-blobstore2-repo-2"} 23
EOF
)

compare "$PROM_FILE" "$expected_filecontent"

if [[ "$is_any_test_failed" == 1 ]]; then
  echo "Test-3 FAILED: At lest one test failed."
else
  echo "Test-3 OK: All tests passed."
fi
