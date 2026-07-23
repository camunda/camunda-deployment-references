[
  {
    "name": "management-identity",
    "image": "${image}",
    "cpu": ${cpu},
    "memory": ${memory},
    "essential": true,
    "healthCheck": {
      "command": [
        "CMD-SHELL",
        "wget -qO- http://localhost:8082/actuator/health/liveness || exit 1"
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
          "awslogs-stream-prefix": "management-identity",
          "awslogs-multiline-pattern": "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z"
        }
    },
    "environment": ${env_vars_json},
    %{ if has_secrets ~}
    "secrets": ${secrets_json},
    %{ endif ~}
    "portMappings": [
      {
        "name": "http",
        "containerPort": 8084,
        "hostPort": 8084,
        "protocol": "tcp"
      },
      {
        "name": "management",
        "containerPort": 8082,
        "hostPort": 8082,
        "protocol": "tcp"
      }
    ]
  }
]
