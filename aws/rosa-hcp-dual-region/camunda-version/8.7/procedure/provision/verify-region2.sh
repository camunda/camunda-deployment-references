[ "$(terraform console <<<local.rosa_cluster_2_region | jq -r)" != "$CLUSTER_2_REGION" ] && {
  echo "Error: The region value for rosa_cluster_2 in the file cluster_region_2.tf does not match the expected region ($CLUSTER_2_REGION)." && \
  echo "Please update the rosa_cluster_2_region variable in the file cluster_region_2.tf with the correct value."
} || echo "good! local.rosa_cluster_2_region is set correctly"
