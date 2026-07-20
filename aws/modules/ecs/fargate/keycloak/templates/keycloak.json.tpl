[
  {
    "name": "keycloak",
    "image": "${image}",
    "cpu": ${cpu},
    "memory": ${memory},
    "essential": true,
    "command": ["start"],
    "healthCheck": {
      "command": [
        "CMD-SHELL",
        "exec 3<>/dev/tcp/127.0.0.1/9000 && echo -e 'GET /auth/health/ready HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n' >&3 && timeout 5 cat <&3 | grep -q '200 OK'"
      ],
      "interval": 15,
      "timeout": 15,
      "retries": 15,
      "startPeriod": 90
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
          "awslogs-stream-prefix": "keycloak"
        }
    },
    "environment": ${env_vars_json},
    %{ if has_secrets ~}
    "secrets": ${secrets_json},
    %{ endif ~}
    "portMappings": [
      { "name": "http", "containerPort": 18080, "hostPort": 18080, "protocol": "tcp" },
      { "name": "management", "containerPort": 9000, "hostPort": 9000, "protocol": "tcp" }
    ]
  }
]
