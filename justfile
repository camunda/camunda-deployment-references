
regenerate-aws-ec2-golden-file:
  #!/bin/bash
  cd {{justfile_directory()}}/aws/ec2/terraform
  cp {{justfile_directory()}}/aws/ec2/test/fixtures/provider_override.tf .
  export AWS_REGION="eu-west-2"
  terraform init -upgrade
  terraform plan -var aws_ami="ami" -var generate_ssh_key_pair="true" -out=tfplan
  terraform show -json tfplan | jq > tfplan.json
  jq --sort-keys '.planned_values.root_module' tfplan.json > ../test/golden/tfplan.json
  rm -rf tfplan tfplan.json
  rm -rf provider_override.tf
