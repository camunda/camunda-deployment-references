global:
  scrape_interval: ${scrape_interval}
  external_labels:
    cluster: ${prefix}
scrape_configs:
  - job_name: 'core'
    metrics_path: ${metrics_path}
    # Targets are discovered dynamically: the sidecar container queries AWS
    # Cloud Map for the orchestration clusters and rewrites this file, which
    # Prometheus hot-reloads. Nothing here is pinned to a task IP.
    file_sd_configs:
      - files:
          - ${targets_file}
        refresh_interval: ${refresh_interval}s
    # The target is a task IP. Name the series after the task id instead, so
    # exported series carry nothing about the VPC they were scraped in.
    relabel_configs:
      - source_labels: [pod]
        target_label: instance
