
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

regenerate-golden-file module_dir backend_bucket_region backend_bucket_name backend_bucket_key relative_output_path="./test/golden/":
  #!/bin/bash
  cd {{ justfile_directory() }}/{{ module_dir }}
  terraform init \
    -backend-config="bucket={{ backend_bucket_name }}" \
    -backend-config="key={{ backend_bucket_key }}" \
    -backend-config="region={{ backend_bucket_region }}"
  RHCS_TOKEN="" AWS_REGION="eu-west-2" terraform plan -out=tfplan
  terraform show -json tfplan | jq > tfplan.json
  mkdir -p {{ relative_output_path }}
  jq --sort-keys '.planned_values.root_module' tfplan.json > {{ relative_output_path }}tfplan.json
  rm -rf tfplan tfplan.json


# Install all the tooling
install-tooling: asdf-install

# Install asdf plugins
asdf-plugins tool_versions_dir="./":
    #!/bin/sh
    echo "Installing asdf plugins"
    for plugin in $(awk '{print $1}' {{tool_versions_dir}}.tool-versions); do \
      asdf plugin add ${plugin} 2>&1 | (grep "already added" && exit 0); \
    done

    echo "Update all asdf plugins"
    asdf plugin update --all

# Install tools using asdf
asdf-install: asdf-plugins
    asdf install

# Install tooling of the current dir (https://just.systems/man/en/working-directory.html)
[no-cd]
install-tooling-current-dir: asdf-install-current-dir

[no-cd]
asdf-install-current-dir:
    #!/bin/sh

    just asdf-plugins "$(pwd)/"
    asdf install
