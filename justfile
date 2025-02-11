
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


# Install all the tooling
install-tooling: asdf-install

# Install asdf plugins
asdf-plugins:
    #!/bin/sh
    echo "Installing asdf plugins"
    for plugin in $(awk '{print $1}' .tool-versions); do \
      asdf plugin add ${plugin} 2>&1 | (grep "already added" && exit 0); \
    done

    echo "Update all asdf plugins"
    asdf plugin update --all

# Install tools using asdf
asdf-install: asdf-plugins
    asdf install
