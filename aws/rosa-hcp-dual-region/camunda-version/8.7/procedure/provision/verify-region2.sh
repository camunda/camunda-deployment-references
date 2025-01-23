if [ "$(terraform console <<<local.rosa_cluster_2_region | jq -r)" != "$CLUSTER_2_REGION" ]; then
  echo "Error: The region value for rosa_cluster_2 in the file cluster_region_2.tf does not match the expected region ($CLUSTER_2_REGION)."
  echo "Please update the rosa_cluster_2_region variable in the file cluster_region_2.tf with the correct value."
else
  if [ "$CLUSTER_2_REGION" != "$AWS_REGION" ]; then
    echo "Error: The CLUSTER_2_REGION ($CLUSTER_2_REGION) does not match the AWS_REGION ($AWS_REGION)."
    echo "Please ensure both regions are aligned."
  else
    echo "good! local.rosa_cluster_2_region and AWS_REGION are set correctly"
  fi
fi
