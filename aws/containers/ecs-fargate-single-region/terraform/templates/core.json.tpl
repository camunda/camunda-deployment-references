[
  {
    "name": "${prefix}-core",
    "image": "${app_image}",
    "cpu": ${fargate_cpu},
    "memory": ${fargate_memory},
    "networkMode": "awsvpc",
    "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/${prefix}-core",
          "awslogs-region": "${aws_region}",
          "awslogs-stream-prefix": "ecs"
        }
    },
    "user": "root",
    "environment": [
      {
        "name": "CAMUNDA_OPERATE_DATABASE",
        "value": "opensearch"
      },
      {
        "name": "CAMUNDA_TASKLIST_DATABASE",
        "value": "opensearch"
      },
      {
        "name": "CAMUNDA_DATABASE_TYPE",
        "value": "opensearch"
      },
      {
        "name": "ZEEBE_BROKER_EXPORTERS_CAMUNDAEXPORTER_CLASSNAME",
        "value": "io.camunda.exporter.CamundaExporter"
      },
      {
        "name": "ZEEBE_BROKER_EXPORTERS_CAMUNDAEXPORTER_ARGS_CONNECT_TYPE",
        "value": "opensearch"
      },
      {
        "name": "ZEEBE_BROKER_EXPORTERS_CAMUNDAEXPORTER_ARGS_CONNECT_CLUSTERNAME",
        "value": "opensearch"
      },
      {
        "name": "ZEEBE_BROKER_EXPORTERS_CAMUNDAEXPORTER_ARGS_CREATESCHEMA",
        "value": "true"
      },
      {
        "name": "CAMUNDA_REST_QUERY_ENABLED",
        "value": "true"
      },
      {
        "name": "CAMUNDA_OPERATE_CSRFPREVENTIONENABLED",
        "value": "false"
      },
      {
        "name": "SPRING_PROFILES_ACTIVE",
        "value": "identity,operate,tasklist,broker,consolidated-auth"
      },
      {
        "name": "CAMUNDA_OPERATE_IMPORTERENABLED",
        "value": "false"
      },
      {
        "name": "CAMUNDA_OPERATE_ARCHIVERENABLED",
        "value": "false"
      },
      {
        "name": "CAMUNDA_TASKLIST_IMPORTERENABLED",
        "value": "false"
      },
      {
        "name": "CAMUNDA_TASKLIST_ARCHIVERENABLED",
        "value": "false"
      },

      {
        "name": "CAMUNDA_OPERATE_OPENSEARCH_URL",
        "value": "${opensearch_url}"
      },
      {
        "name": "CAMUNDA_OPERATE_ZEEBEOPENSEARCH_URL",
        "value": "${opensearch_url}"
      },
      {
        "name": "CAMUNDA_TASKLIST_OPENSEARCH_URL",
        "value": "${opensearch_url}"
      },
      {
        "name": "CAMUNDA_TASKLIST_ZEEBEOPENSEARCH_URL",
        "value": "${opensearch_url}"
      },
      {
        "name": "ZEEBE_BROKER_EXPORTERS_CAMUNDAEXPORTER_ARGS_CONNECT_URL",
        "value": "${opensearch_url}"
      },
      {
        "name": "CAMUNDA_DATABASE_URL",
        "value": "${opensearch_url}"
      }
    ],
    "portMappings": [
      {
        "containerPort": 8080,
        "hostPort": 8080
      },
      {
        "containerPort": 9600,
        "hostPort": 9600
      },
      {
        "containerPort": 26500,
        "hostPort": 26500
      },
      {
        "containerPort": 26501,
        "hostPort": 26501
      },
      {
        "containerPort": 26502,
        "hostPort": 26502
      }
    ],
    "mountPoints": [
      {
        "sourceVolume": "camunda-volume",
        "containerPath": "/usr/local/camunda/data"
      }
    ]
  }
]
