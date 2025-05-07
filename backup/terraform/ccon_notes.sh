# context terraform folder

export S3_BUCKET_NAME=$(terraform output -raw s3_bucket_name)
export S3_ACCESS_KEY=$(terraform output -raw s3_aws_access_key)
export S3_SECRET_ACCESS_KEY=$(terraform output -raw s3_aws_secret_access_key)

kind create cluster
kubectl create namespace camunda

kubectl create secret generic s3-credentials \
  --from-literal=S3_ACCESS_KEY=$S3_ACCESS_KEY \
  --from-literal=S3_SECRET_ACCESS_KEY=$S3_SECRET_ACCESS_KEY

helm upgrade --install camunda camunda/camunda-platform --version 12.0.1 -f ~/helm-values.yml

# register Elastic backup repo

curl -XPUT 'http://localhost:9200/_snapshot/camunda' -H 'Content-Type: application/json' -d'
{
"type": "s3",
"settings": {
   "bucket": "'$S3_BUCKET_NAME'",
   "client": "camunda",
   "base_path": "backups"
}
}
'

# deploy some dummy stuff and showcase

kubectl port-forward services/camunda-zeebe-gateway 8080:8080

curl localhost:8080/v2/deployments -H 'Content-Type: multipart/form-data' -F 'resources=@single-task.bpmn'

kubectl port-forward services/camunda-operate 8040:80

# Start and complete some dummy instances

kubectl port-forward services/camunda-tasklist 8090:80

# Backup Process

# Now doing the backup - Operate

kubectl port-forward services/camunda-operate 9640:9600

curl --request POST 'http://localhost:9640/actuator/backups' \
-H 'Content-Type: application/json' \
-d '{ "backupId": 1 }'

# verify done

curl http://localhost:9640/actuator/backups/1 | jq

# Now doing the backup - Tasklist

kubectl port-forward services/camunda-tasklist 9680:9600

curl --request POST 'http://localhost:9680/actuator/backups' \
-H 'Content-Type: application/json' \
-d '{ "backupId": 1 }'

# verify done

curl http://localhost:9680/actuator/backups/1 | jq

# Take a backup of Zeebe
# Soft Pause Zeebe

kubectl port-forward services/camunda-zeebe-gateway 9600:9600

curl -XPOST http://localhost:9600/actuator/exporting/pause\?soft\=true
# curl -XPOST http://localhost:9600/actuator/exporting/resume

curl -XPUT 'http://localhost:9200/_snapshot/camunda/camunda_zeebe_records_backup_1?wait_for_completion=true' -H 'Content-Type: application/json' -d'
{
   "indices": "zeebe-record*",
   "feature_states": ["none"]
}
'

# Now doing the backup - Zeebe

kubectl port-forward services/camunda-zeebe-gateway 9600:9600

curl --request POST 'http://localhost:9600/actuator/backups' \
-H 'Content-Type: application/json' \
-d '{ "backupId": 1 }'

# verify done

curl http://localhost:9600/actuator/backups/1 | jq

# Backup completed

---

# Restore Process

helm uninstall camunda
kubectl delete pvc --all
kubectl delete pv --all

# Disable in the helm-values everything but elasticsearch

helm upgrade --install camunda camunda/camunda-platform --version 12.0.1 -f ~/helm-values.yml

# Restore all Elastic indices

# Init the snapshot repo again
curl -XPUT 'http://localhost:9200/_snapshot/camunda' -H 'Content-Type: application/json' -d'
{
"type": "s3",
"settings": {
   "bucket": "'$S3_BUCKET_NAME'",
   "client": "camunda",
   "base_path": "backups"
}
}
'

# List available backups, since you won't know what is available

curl -XPOST 'localhost:9200/_snapshot/camunda/camunda_operate_1_8.7.1_part_1_of_6/_restore?wait_for_completion=true'
curl -XPOST 'localhost:9200/_snapshot/camunda/camunda_operate_1_8.7.1_part_2_of_6/_restore?wait_for_completion=true'
curl -XPOST 'localhost:9200/_snapshot/camunda/camunda_operate_1_8.7.1_part_3_of_6/_restore?wait_for_completion=true'
curl -XPOST 'localhost:9200/_snapshot/camunda/camunda_operate_1_8.7.1_part_4_of_6/_restore?wait_for_completion=true'
curl -XPOST 'localhost:9200/_snapshot/camunda/camunda_operate_1_8.7.1_part_5_of_6/_restore?wait_for_completion=true'
curl -XPOST 'localhost:9200/_snapshot/camunda/camunda_operate_1_8.7.1_part_6_of_6/_restore?wait_for_completion=true'

curl -XPOST 'localhost:9200/_snapshot/camunda/camunda_tasklist_1_8.7.1_part_1_of_6/_restore?wait_for_completion=true'
curl -XPOST 'localhost:9200/_snapshot/camunda/camunda_tasklist_1_8.7.1_part_2_of_6/_restore?wait_for_completion=true'
curl -XPOST 'localhost:9200/_snapshot/camunda/camunda_tasklist_1_8.7.1_part_3_of_6/_restore?wait_for_completion=true'
curl -XPOST 'localhost:9200/_snapshot/camunda/camunda_tasklist_1_8.7.1_part_4_of_6/_restore?wait_for_completion=true'
curl -XPOST 'localhost:9200/_snapshot/camunda/camunda_tasklist_1_8.7.1_part_5_of_6/_restore?wait_for_completion=true'
curl -XPOST 'localhost:9200/_snapshot/camunda/camunda_tasklist_1_8.7.1_part_6_of_6/_restore?wait_for_completion=true'

curl -XPOST 'localhost:9200/_snapshot/camunda/camunda_zeebe_records_backup_1/_restore?wait_for_completion=true'

curl -s "localhost:9200/_cat/indices?v"

# Restore Zeebe

# Overwrite with

```
command: ["/usr/local/zeebe/bin/restore", "--backupId=1"]
```

Redeploy afterwards without it again to work.

# Complete started tasks in Tasklist
