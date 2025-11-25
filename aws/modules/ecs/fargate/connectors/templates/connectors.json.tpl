[
  {
    "name": "connectors",
    "image": "${image}",
    "cpu": ${cpu},
    "memory": ${memory},
    "essential": true,
    "healthCheck": {
      "command": [
        "CMD-SHELL",
        "wget --spider --quiet http://localhost:8080/actuator/health/readiness || exit 1"
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
          "awslogs-multiline-pattern": "^\\[\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}\\.\\d{3}\\]"
        }
    },
    "environment": ${env_vars_json},
    "portMappings": [
      {
        "containerPort": 8080,
        "hostPort": 8080,
        "protocol": "tcp"
      }
    ]
  }
]
