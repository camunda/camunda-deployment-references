if [ "$(terraform console <<<local.rosa_cluster_1_region | jq -r)" != "$CLUSTER_1_REGION" ]; then
  echo "Error: The region value for rosa_cluster_1 in the file cluster_region_1.tf does not match the expected region ($CLUSTER_1_REGION)."
  echo "Please update the rosa_cluster_1_region variable in the file cluster_region_1.tf with the correct value."
else
  if [ "$CLUSTER_1_REGION" != "$AWS_REGION" ]; then
    echo "Error: The CLUSTER_1_REGION ($CLUSTER_1_REGION) does not match the AWS_REGION ($AWS_REGION)."
    echo "Please ensure both regions are aligned."
  else
    echo "good! local.rosa_cluster_1_region and AWS_REGION are set correctly"
  fi
fi
