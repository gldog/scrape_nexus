README
=

# The script

This script collects Nexus-related data, converts them to PROM format, and writes the PROM-data to a file where the
tool [`node_exporter`](https://github.com/prometheus/node_exporter) can read it with its
feature `--collector.textfile.directory`.
`node_exporter` is used as the conveyor for all Nexus-metrics.

The advantage using `node_exporter` are:

* You (or the Promethus admin) have only one scrape-config in Prometheus.
* Once the scrape-config is set up by the Prometheus admin, the Nexus admin controls what data is scraped.
* There is a chance your Nexus-VM is already scraped by `nnode_exporter`.
* You don't need an additional network-rule for the Nexus-PROM endpoint.

# Collected data

This script

* reads Nexus `/service/metrics/prometheus` REST end-point and writes the output to a PROM-file,
* counts WARN and ERROR occurrences in nexus.log, converts them to PROM-data, and appends them to the PROM-file.
* reads OrientDB-profiler recommendations from nexus.log, converts them to PROM-data, and append them to the PROM-file.
* Reads blobstore- and repository-sizes from a Nexus-task's output as described
  in [Investigating Blob Store and Repository Size and Space Usage](https://support.sonatype.com/hc/en-us/articles/115009519847-Investigating-Blob-Store-and-Repository-Size-and-Space-Usage)
  , converts them to PROM-data, and appends them to the PROM-file.
* measures sizes of directories, converts them to PROM-data, and append them to the PROM file.

# Parameters

## `NXRMSCR_NEXUS_BASE_URL`

Mandatory.
Nexus base-url.

The current implementation of this script uses anonymous access to Nexus.
The Nexus-user `anonymous` needs the privilege `nx-metrics-all`.

## `NXRMSCR_NEXUS_LOGFILE_PATH`

Optional.

Path to Nexus `nexus.log`.

E.g. `/opt/nexus/sonatype-work/nexus3/log/nexus.log`.

If given, the script transforms the WARN and ERROR count, and the OrientDB-profiler recommendations.

WARN and ERROR count:

    # HELP sonatype_nexus_num_warn_lines_in_nexus_log_total Number of WARN lines in nexus.log.
    # TYPE sonatype_nexus_num_warn_lines_in_nexus_log_total counter
    sonatype_nexus_num_warn_lines_in_nexus_log_total 0

    # HELP sonatype_nexus_num_error_lines_in_nexus_log_total Number of ERROR lines in nexus.log.
    # TYPE sonatype_nexus_num_error_lines_in_nexus_log_total counter
    sonatype_nexus_num_error_lines_in_nexus_log_total 0

OrientDB-profiler recommendations, output only if recommendation is present in `nexus.log`.

An entry in the `nexus.log` could be something like:

    2017-05-05 22:57:18,268-0400 INFO  [Timer-1] *SYSTEM com.orientechnologies.common.profiler.OAbstractProfiler$MemoryChecker - Database 'analytics' uses 1,726MB/2,048MB of DISKCACHE memory, while Heap is not completely used (usedHeap=2210MB maxHeap=3641MB). To improve performance set maxHeap to 2652MB and DISKCACHE to 3036MB

The transformed PROM is:

    # HELP sonatype_nexus_recommended_maximum_jvm_heap_megabytes Recommendation for the JVM heap size in MB read from nexus.log.
    # TYPE sonatype_nexus_recommended_maximum_jvm_heap_megabytes gauge
    sonatype_nexus_recommended_maximum_jvm_heap_megabytes 2652

    # HELP sonatype_nexus_recommended_maximum_direct_memory_megabytese Recommendation for the maximum direct memory size in MB read from nexus.log.
    # TYPE sonatype_nexus_recommended_maximum_direct_memory_megabytes gauge
    sonatype_nexus_recommended_maximum_direct_memory_megabytes 3036

See also links:

Sonatype: [Optimizing OrientDB Database Memory](https://support.sonatype.com/hc/en-us/articles/115007093447-Optimizing-OrientDB-Database-Memory-)

OrientDB: [OAbstractProfiler.java](https://github.com/orientechnologies/orientdb/blob/develop/core/src/main/java/com/orientechnologies/common/profiler/OAbstractProfiler.java:)

## `NXRMSCR_NEXUS_TMP_PATH`

Optional.

Path to Nexus `tmp` directory.

E.g. `/opt/nexus/sonatype-work/nexus3/tmp`.

This is the directory a Nexus-task calling the Groovy script
`nx-blob-repo-space-report-20220510.groovy` as described
in [Investigating Blob Store and Repository Size and Space Usage](https://support.sonatype.com/hc/en-us/articles/115009519847-Investigating-Blob-Store-and-Repository-Size-and-Space-Usage)
writes its report-files to.
If given, the script transforms that blobstore- and repo-sizes, and information about reclaimable-sizes.
F.y.i., the files have the prefix `repoSizes-`.

Given the output of a fresh Nexus instance:

repoSizes-20230327-010000.json:

    {
        "default": {
            "repositories": {
                "nuget-group": {
                    "reclaimableBytes": 0,
                    "totalBytes": 0
                },
                "maven-snapshots": {
                    "reclaimableBytes": 0,
                    "totalBytes": 0
                },
                "maven-central": {
                    "reclaimableBytes": 0,
                    "totalBytes": 0
                },
                "nuget.org-proxy": {
                    "reclaimableBytes": 0,
                    "totalBytes": 6934
                },
                "maven-releases": {
                    "reclaimableBytes": 0,
                    "totalBytes": 0
                },
                "nuget-hosted": {
                    "reclaimableBytes": 0,
                    "totalBytes": 0
                },
                "maven-public": {
                    "reclaimableBytes": 0,
                    "totalBytes": 0
                }
            },
            "totalBlobStoreBytes": 6934,
            "totalReclaimableBytes": 0,
            "totalRepoNameMissingCount": 0
        }
    }

The Resulting PROM-data is:

    # HELP sonatype_nexus_repoSizes_blobstore_totalBlobStoreBytes
    # TYPE sonatype_nexus_repoSizes_blobstore_totalBlobStoreBytes gauge
    sonatype_nexus_repoSizes_blobstore_totalBlobStoreBytes{blobstore="default"} 6934

    # HELP sonatype_nexus_repoSizes_blobstore_totalReclaimableBytes
    # TYPE sonatype_nexus_repoSizes_blobstore_totalReclaimableBytes gauge
    sonatype_nexus_repoSizes_blobstore_totalReclaimableBytes 0

    # HELP sonatype_nexus_repoSizes_blobstore_totalRepoNameMissingCount
    # TYPE sonatype_nexus_repoSizes_blobstore_totalRepoNameMissingCount gauge
    sonatype_nexus_repoSizes_blobstore_totalRepoNameMissingCount 0

    # HELP sonatype_nexus_repoSizes_repo_totalBytes
    # TYPE sonatype_nexus_repoSizes_repo_totalBytes
    sonatype_nexus_repoSizes_repo_totalBytes{blobstore="default",repo="nuget-group"}
    sonatype_nexus_repoSizes_repo_totalBytes{blobstore="default",repo="maven-snapshots"}
    sonatype_nexus_repoSizes_repo_totalBytes{blobstore="default",repo="maven-central"}
    sonatype_nexus_repoSizes_repo_totalBytes{blobstore="default",repo="nuget.org-proxy"}
    sonatype_nexus_repoSizes_repo_totalBytes{blobstore="default",repo="maven-releases"}
    sonatype_nexus_repoSizes_repo_totalBytes{blobstore="default",repo="nuget-hosted"}
    sonatype_nexus_repoSizes_repo_totalBytes{blobstore="default",repo="maven-public"}

    # HELP sonatype_nexus_repoSizes_repo_reclaimableBytes
    # TYPE sonatype_nexus_repoSizes_repo_reclaimableBytes gauge
    sonatype_nexus_repoSizes_repo_reclaimableBytes{blobstore="default",repo="nuget-group"}
    sonatype_nexus_repoSizes_repo_reclaimableBytes{blobstore="default",repo="maven-snapshots"}
    sonatype_nexus_repoSizes_repo_reclaimableBytes{blobstore="default",repo="maven-central"}
    sonatype_nexus_repoSizes_repo_reclaimableBytes{blobstore="default",repo="nuget.org-proxy"}
    sonatype_nexus_repoSizes_repo_reclaimableBytes{blobstore="default",repo="maven-releases"}
    sonatype_nexus_repoSizes_repo_reclaimableBytes{blobstore="default",repo="nuget-hosted"}
    sonatype_nexus_repoSizes_repo_reclaimableBytes{blobstore="default",repo="maven-public"}

Link:

Sonatype: [Investigating Blob Store and Repository Size and Space Usage](https://support.sonatype.com/hc/en-us/articles/115009519847-Investigating-Blob-Store-and-Repository-Size-and-Space-Usage)

## `NXRMSCR_DIRECTORY_SIZES_OF`

Optional.

E.g.

1. `/opt/nexus/sonatype-work/nexus3/tmp/db:/opt/nexus/sonatype-work/nexus3/log`
2. `/opt/nexus/sonatype-work/nexus3/{db,elasticsearch,log,tmp}`

If given, the sizes of the directories are transformed.
You can give multiple paths separated by colon `:` (example 1).
You can also use bash-expansion (example 2), or both.

The metrics are transformed to (example 1):

    node_directory_size_bytes{directory="/opt/nexus/sonatype-work/nexus3/tmp/db") 21782238764
    node_directory_size_bytes{directory="/opt/nexus/sonatype-work/nexus3/tmp/log") 187656273

Or (example 2)

    node_directory_size_bytes{directory="/opt/nexus/sonatype-work/nexus3/db") 21782238764
    node_directory_size_bytes{directory="/opt/nexus/sonatype-work/nexus3/elasticsearch") 172384766
    node_directory_size_bytes{directory="/opt/nexus/sonatype-work/nexus3/log") 187656273
    node_directory_size_bytes{directory="/opt/nexus/sonatype-work/nexus3/tmp") 8277654

The sizes are calculated by `du`. Its execution-duration is also measured.
The output is (0s is an example):

    # HELP The duration the du-command took for all directories in NXRMSCR_DIRECTORY_SIZES_OF.
    # TYPE node_directory_size_du_exec_duration_seconds gauge
    node_directory_size_du_exec_duration_seconds 0

By this you can control the `du` doesn't take longer than the script's scrape interval.

Link:

5robustperception.io: [Monitoring directory sizes with the Textfile Collector](https://www.robustperception.io/monitoring-directory-sizes-with-the-textfile-collector/)

## `NXRMSCR_PROM_FILE_DIR`

The directory thsi script writes its PROM-file to.
E.g. `/tmp/nodeexporter_collector_textfile_directory`

# Start, Stop, Logging

The scirpt makes itself a daemon:

    scrape_nexus.sh start

To stop it:

    scrape_nexus.sh stop

The script creates a pid-file and a log-file in its directory.

# systemd

Use `Type=forking`.

Here is an example comprising 3 configs:

* nexus.service, pseudo-service controlling nexus-app and nexus-scraper.
* nexus-app.service, controls the Nexus application
* nexus-scraper.service, controls the scrape_nexus.sh

Normally you use just the `nexus.service`.
You can use `nexus-app.service` and `nexus-scraper` as well and independently.
But `nexus.service` assures the scraper starts up after Nexus, and shuts down before Nexus.

Credits
to [Controlling a Multi-Service Application with systemd](https://alesnosek.com/blog/2016/12/04/controlling-a-multi-service-application-with-systemd/)
.

nexus.service:

    [Unit]
    Description=Sonatype Nexus Application
    PartOf=nexus.service
    After=nexus.service
    
    [Service]
    Type=forking
    LimitNOFILE=65536
    ExecStart=/opt/nexus/nexus3/bin/nexus start
    ExecStop=/opt/nexus/nexus3/bin/nexus stop
    User=nexus
    Restart=on-abort
    
    [Install]
    WantedBy=nexus.service

nexus-app.service:

    [Unit]
    Description=Sonatype Nexus Repository service-group
    # This is to control Nexus Repo application and it scraper-script.
    # Starting and stopping this controls also the dependent services nexus-app and nexus-scraper.
    # But that services can be controled on its own. This allows e.g. separate restarts of Nexus Repo or the scraper.
    After=network.target
    
    [Service]
    Type=oneshot
    # Execute a dummy program.
    ExecStart=/bin/true
    # This service shall be considered active after start.
    RemainAfterExit=yes
    
    [Install]
    WantedBy=multi-user.target

nexus-scraper.service:

    [Unit]
    Description=Sonatype Nexus Repository scraper
    PartOf=nexus.service
    After=nexus.service
    After=nexus-app.service
    
    [Service]
    Type=forking
    User=nexus
    
    # This service controls the scrape_nexus.sh. That script has two operation modes:
    #   1. Controlling scrape_nexus.sh itself (start, stop)
    #   2. Run the scraping (no parameter).
    Environment=NXRMSCR_NEXUS_BASE_URL=https://localhost
    Environment=NXRMSCR_NEXUS_LOGFILE_PATH=/opt/nexus/sonatype-work/nexus3/log/nexus.log
    Environment=NXRMSCR_NEXUS_TMP_PATH=/opt/nexus/sonatype-work/nexus3/tmp
    Environment=NXRMSCR_PROM_FILES_DIR=/tmp/node_exporter_collector_textfile_directory
    Environment=NXRMSCR_DIRECTORY_SIZES_OF=/opt/nexus/sonatype-work/nexus3/{blobs,cache,db,elasticsearch,log,orient,task_export_databases_for_backup,tmp}
    ExecStart=/opt/cdtools/scrape_nexus.sh start
    ExecStop=/opt/cdtools/scrape_nexus.sh stop
    # Ending the scraping, signal "no data" to Prometheus rather than sticking to the most recent scraped data.
    #   -r: Delete the directory rather than the files: systmd runs without shell, so here is no
    #       shell-expansion. Deleting something with rm -r dir/* results in "No such file or directory".
    #   -f: Do not moan in case the directory is not present.
    ExecStopPost=/usr/bin/rm -rf /tmp/node_exporter_collector_textfiles/
    
    [Install]
    WantedBy=nexus.service
