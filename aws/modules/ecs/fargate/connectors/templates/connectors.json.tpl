[
  {
    "name": "connectors",
    "image": "${image}",
    "cpu": ${cpu},
    "memory": ${memory},
    "essential": true,
    %{ if init_container_enabled ~}
    "dependsOn": [
      {
        "containerName": "${init_container_name}",
        "condition": "SUCCESS"
      }
    ],
    %{ endif ~}
    "healthCheck": {
      "command": [
        "CMD-SHELL",
        "wget --spider --quiet http://localhost:8080/connectors/actuator/health/readiness || exit 1"
      ],
      "interval": 30,
      "timeout": 5,
      "retries": 3,
      "startPeriod": 120
    },
    "stopTimeout": 30,
    %{ if registry_credentials_arn != "" ~}
    "repositoryCredentials": {
      "credentialsParameter": "${registry_credentials_arn}"
    },
    %{ endif ~}
    "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "${log_group_name}",
          "awslogs-region": "${aws_region}",
          "awslogs-stream-prefix": "connectors",
          "awslogs-multiline-pattern": "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z"
        }
    },
    "environment": ${env_vars_json},
    %{ if has_secrets ~}
    "secrets": ${secrets_json},
    %{ endif ~}
    %{ if init_container_enabled ~}
    "mountPoints": [
      {
        "sourceVolume": "init-config",
        "containerPath": "/config",
        "readOnly": true
      }
    ],
    %{ endif ~}
    "portMappings": [
      {
        "containerPort": 8080,
        "hostPort": 8080,
        "protocol": "tcp"
      }
    ]
  }
  %{ if init_container_enabled ~}
  ,
  ${init_container_json}
  %{ endif ~}
]
