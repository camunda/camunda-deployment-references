[
  {
    "name": "${prefix}-core",
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
          "awslogs-group": "/ecs/${prefix}-core",
          "awslogs-region": "${aws_region}",
          "awslogs-stream-prefix": "core"
        }
    },
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
        "containerPort": 9605,
        "hostPort": 9605,
        "protocol": "tcp"
      },
      {
        "containerPort": 8080,
        "hostPort": 8080,
        "protocol": "tcp"
      }
    ]
  },
  {
    "name": "${prefix}-opensearch",
    "image": "opensearchproject/opensearch:2.11.1",
    "cpu": ${opensearch_cpu},
    "memory": ${opensearch_memory},
    "essential": true,
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
          "awslogs-stream-prefix": "opensearch"
        }
    },
    "environment": [
      {
        "name": "discovery.type",
        "value": "single-node"
      },
      {
        "name": "plugins.security.disabled",
        "value": "true"
      }
    ],
    "portMappings": [
      {
        "containerPort": 9200,
        "hostPort": 9200,
        "protocol": "tcp"
      }
    ]
  }
]
