global:
  scrape_interval: 15s
  external_labels:
    cluster: ${prefix}
scrape_configs:
  - job_name: 'core'
    metrics_path: /actuator/prometheus
    dns_sd_configs:
      - names:
${names}
        type: A
        port: 9600
        refresh_interval: 30s
