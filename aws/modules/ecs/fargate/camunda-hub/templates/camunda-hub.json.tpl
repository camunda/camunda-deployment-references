[
  {
    "name": "camunda-hub-restapi",
    "image": "${restapi_image}",
    "cpu": ${restapi_cpu},
    "memory": ${restapi_memory},
    "essential": true,
    "healthCheck": {
      "command": [
        "CMD-SHELL",
        "wget -qO- http://localhost:8091${restapi_health_path} || exit 1"
      ],
      "interval": 30,
      "timeout": 5,
      "retries": 3,
      "startPeriod": 180
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
        "awslogs-stream-prefix": "camunda-hub-restapi",
        "awslogs-multiline-pattern": "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z"
      }
    },
    "environment": ${restapi_env_json},
    %{ if restapi_has_secrets ~}
    "secrets": ${restapi_secrets_json},
    %{ endif ~}
    "mountPoints": [
      {
        "sourceVolume": "tmp",
        "containerPath": "/tmp",
        "readOnly": false
      }
    ],
    "portMappings": [
      { "containerPort": 8081, "hostPort": 8081, "protocol": "tcp" },
      { "containerPort": 8091, "hostPort": 8091, "protocol": "tcp" }
    ]
  },
  {
    "name": "camunda-hub-websockets",
    "image": "${websockets_image}",
    "cpu": ${websockets_cpu},
    "memory": ${websockets_memory},
    "essential": true,
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
        "awslogs-stream-prefix": "camunda-hub-websockets"
      }
    },
    "environment": ${websockets_env_json},
    %{ if websockets_has_secrets ~}
    "secrets": ${websockets_secrets_json},
    %{ endif ~}
    "portMappings": [
      { "containerPort": 8060, "hostPort": 8060, "protocol": "tcp" }
    ]
  }
]
