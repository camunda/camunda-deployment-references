[
  {
    "name": "${prefix}-core",
    "image": "${core_image}",
    "cpu": ${core_cpu},
    "memory": ${core_memory},
    "essential": true,
    "stopTimeout": 30,
    %{ if docker_hub_credentials_arn != "" ~}
    "repositoryCredentials": {
      "credentialsParameter": "${docker_hub_credentials_arn}"
    },
    %{ endif ~}
    "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/${prefix}-core",
          "awslogs-region": "${aws_region}",
          "awslogs-stream-prefix": "core",
          "awslogs-multiline-pattern": "^\\[\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}\\.\\d{3}\\]"
        }
    },
    "command": [
      "bash",
      "-c",
      "export ZEEBE_BROKER_NETWORK_HOST=$(hostname -I | awk '{print $2}'); /usr/local/camunda/bin/camunda"
    ],
    "user": "root",
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
