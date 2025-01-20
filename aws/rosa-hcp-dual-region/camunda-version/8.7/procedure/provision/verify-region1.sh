[ "$(terraform console <<<local.rosa_cluster_1_region | jq -r)" != "$CLUSTER_1_REGION" ] && {
  echo "Error: The region value for rosa_cluster_1 in the file cluster_region_1.tf does not match the expected region ($CLUSTER_1_REGION)." && \
  echo "Please update the rosa_cluster_1_region variable in the file cluster_region_1.tf with the correct value."
} || echo "good! local.rosa_cluster_1_region is set correctly"
