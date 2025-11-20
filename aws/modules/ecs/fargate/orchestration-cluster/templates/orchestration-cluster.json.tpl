[
  {
    "name": "orchestration-cluster",
    "family": "${prefix}-orchestration-cluster",
    "image": "${image}",
    "cpu": ${cpu},
    "memory": ${memory},
    "essential": true,
    "healthCheck": {
      "command": [
        "CMD-SHELL",
        "wget --spider --quiet http://localhost:9600/actuator/health/readiness || exit 1"
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
          "awslogs-group": "/ecs/${prefix}-camunda",
          "awslogs-region": "${aws_region}",
          "awslogs-stream-prefix": "orchestration-cluster",
          "awslogs-multiline-pattern": "^\\[\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}\\.\\d{3}\\]"
        }
    },
    "command": [
      "bash",
      "-c",
      "export ZEEBE_BROKER_NETWORK_HOST=$(hostname -I | awk '{print $2}'); /usr/local/camunda/bin/camunda"
    ],
    "environment": ${env_vars_json},
    "mountPoints": [
      {
        "sourceVolume": "camunda-volume",
        "containerPath": "/usr/local/camunda/data"
      }
    ],
    "portMappings": [
      {
        "containerPort": 26500,
        "hostPort": 26500,
        "protocol": "tcp"
      },
      {
        "containerPort": 26501,
        "hostPort": 26501,
        "protocol": "tcp"
      },
      {
        "containerPort": 26502,
        "hostPort": 26502,
        "protocol": "tcp"
      },
      {
        "containerPort": 9600,
        "hostPort": 9600,
        "protocol": "tcp"
      },
      {
        "containerPort": 8080,
        "hostPort": 8080,
        "protocol": "tcp"
      }
    ]
  }
]
