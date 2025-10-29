[
  {
    "name": "${prefix}-nginx-static",
    "image": "${core_image}",
    "cpu": ${core_cpu},
    "memory": ${core_memory},
    "essential": true,
    %{ if docker_hub_credentials_arn != "" ~}
    "repositoryCredentials": {
      "credentialsParameter": "${docker_hub_credentials_arn}"
    },
    %{ endif ~}
    "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/${prefix}-nginx",
          "awslogs-region": "${aws_region}",
          "awslogs-stream-prefix": "nginx",
          "awslogs-multiline-pattern": "^\\[\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}\\.\\d{3}\\]"
        }
    },
    "user": "root",
    "environment": ${env_vars_json},
    "mountPoints": [
      {
        "sourceVolume": "camunda-volume",
        "containerPath": "/data"
      }
    ],
    "portMappings": [
      {
        "containerPort": 4000,
        "hostPort": 4000,
        "protocol": "tcp"
      } 
      ]
  }
]
