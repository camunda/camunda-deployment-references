[
  {
    "name": "orchestration-cluster",
    "image": "${image}",
    "cpu": ${cpu},
    "memory": ${memory},
    "essential": true,
    %{ if init_container_enabled || restore_container_enabled ~}
    "dependsOn": [
      %{ if restore_container_enabled ~}
      {
        "containerName": "${restore_container_name}",
        "condition": "SUCCESS"
      }%{ if init_container_enabled ~},%{ endif ~}
      %{ endif ~}
      %{ if init_container_enabled ~}
      {
        "containerName": "${init_container_name}",
        "condition": "SUCCESS"
      }
      %{ endif ~}
    ],
    %{ endif ~}
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
          "awslogs-group": "${log_group_name}",
          "awslogs-region": "${aws_region}",
          "awslogs-stream-prefix": "orchestration-cluster",
          "awslogs-multiline-pattern": "^\\[\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}\\.\\d{3}\\]"
        }
    },
    "environment": ${env_vars_json},
    %{ if has_secrets ~}
    "secrets": ${secrets_json},
    %{ endif ~}
    "mountPoints": [
      {
        "sourceVolume": "camunda-volume",
        "containerPath": "/usr/local/camunda/data"
      }
      %{ if init_container_enabled ~}
      ,
      {
        "sourceVolume": "init-config",
        "containerPath": "/config",
        "readOnly": true
      }
      %{ endif ~}
    ],
    "portMappings": [
      {
        "containerPort": 26500,
        "hostPort": 26500,
        "protocol": "tcp",
        "name": "grpc"
      },
      {
        "containerPort": 26501,
        "hostPort": 26501,
        "protocol": "tcp"
      },
      {
        "containerPort": 26502,
        "hostPort": 26502,
        "protocol": "tcp",
        "name": "internal-api"
      },
      {
        "containerPort": 9600,
        "hostPort": 9600,
        "protocol": "tcp",
        "name": "management"
      },
      {
        "containerPort": 8080,
        "hostPort": 8080,
        "protocol": "tcp",
        "name": "rest"
      }
    ]
  }
  %{ if restore_container_enabled ~}
  ,
  ${restore_container_json}
  %{ endif ~}
  %{ if init_container_enabled ~}
  ,
  ${init_container_json}
  %{ endif ~}
]
