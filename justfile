# this file is a recipe file for the project

# renovate: datasource=github-releases depName=gotestyourself/gotestsum
gotestsum_version := "v1.12.1"

# Generate the AWS golden file for the EC2 tf files
aws-compute-ec2-single-region-golden:
  #!/bin/bash
  set -euxo pipefail
  cd {{justfile_directory()}}/aws/compute/ec2-single-region/terraform
  cp {{justfile_directory()}}/aws/compute/ec2-single-region/test/fixtures/provider_override.tf .
  export AWS_REGION="eu-west-2"
  terraform init -upgrade
  terraform plan -var aws_ami="ami" -var generate_ssh_key_pair="true" -out=tfplan
  terraform show -json tfplan | jq > tfplan.json
  jq --sort-keys '.planned_values.root_module' tfplan.json > ../test/golden/tfplan.json
  rm -rf tfplan tfplan.json
  rm -rf provider_override.tf

# Launch a single test using go test in verbose mode
aws-tf-modules-test-verbose testname: aws-tf-modules-install-tests-go-mod
    cd aws/modules/.test/src/ && go test -v --timeout=120m -p 1 -run {{testname}}

# Launch a single test using gotestsum
aws-tf-modules-test testname gts_options="": aws-tf-modules-install-tests-go-mod
    cd aws/modules/.test/src/ && go run gotest.tools/gotestsum@{{gotestsum_version}} {{gts_options}} -- --timeout=120m -p 1 -run {{testname}}

# Launch the tests in parallel using go test in verbose mode
aws-tf-modules-tests-verbose: aws-tf-modules-install-tests-go-mod
    cd aws/modules/.test/src/ && go test -v --timeout=120m -p 1 .

# Launch the tests in parallel using gotestsum
aws-tf-modules-tests gts_options="": aws-tf-modules-install-tests-go-mod
    cd aws/modules/.test/src/ && go run gotest.tools/gotestsum@{{gotestsum_version}} {{gts_options}} -- --timeout=120m -p 1 .

# Install go dependencies from test/src/go.mod
aws-tf-modules-install-tests-go-mod:
    cd aws/modules/.test/src/ && go mod download

regenerate-golden-file module_dir backend_bucket_region backend_bucket_name backend_bucket_key relative_output_path="./test/golden/":
  #!/bin/bash
  set -euxo pipefail

  cd {{ justfile_directory() }}/{{ module_dir }}
  terraform init \
    -backend-config="bucket={{ backend_bucket_name }}" \
    -backend-config="key={{ backend_bucket_key }}" \
    -backend-config="region={{ backend_bucket_region }}"

  # we always use the same region and fake rhcs token to have a pre-defined output
  RHCS_TOKEN="" AWS_REGION="eu-west-2" terraform plan -out=tfplan
  terraform show -json tfplan | jq > tfplan.json
  rm -f tfplan
  mkdir -p {{ relative_output_path }}

  # redact sensible/specific values
  sed 's/"arn:[^\"]*\"/"ARN_REDACTED"/g' tfplan.json > tfplan-redacted.json
  rm -f tfplan.json
  sed -E '
  s/"arn:([^"\\]|\\.)*"/"ARN_REDACTED"/g;
  s/'\''arn:([^'\''\\]|\\.)*'\''/'\''ARN_REDACTED'\''/g;
  s/\"[0-9]+\.[0-9]+\.[0-9]+\",/"GOLDEN",/g;;
  ' tfplan-redacted.json > tfplan.json

  rm -f tfplan-redacted.json

  # bring order
  jq --sort-keys '.planned_values.root_module' tfplan.json > tfplan-redacted.json
  rm -f tfplan.json

  # transform the tfoutput to deal only with keys to keep simple ordering
  jq 'def transform:
      if type == "array" then
        . as $arr |
        if $arr | length > 0 and (.[0] | type == "object" and has("address")) then
          # Transform array elements into an object with address as the key
          map({ (.address): with_entries(select(.key != "address")) | map_values(transform) }) | add
        else
          .
        end
      elif type == "object" then
        if has("address") and .address != null then
          { (.address): with_entries(select(.key != "address")) | map_values(transform) }
        elif has("resources") then
          { "resources": map(transform) | add }
        elif has("child_modules") then
          { "child_modules": map(transform) | add }
        else
          with_entries(.value |= transform)
        end
      else
        .
      end;
    transform' tfplan-redacted.json > tfplan.json
  rm -f tfplan-redacted.json

  # final sort
  jq --sort-keys '.' tfplan.json >  {{ relative_output_path }}tfplan-golden.json
  rm -f tfplan.json

  if grep -E -q '\b@camunda\.[A-Za-z]{2,}\b' {{ relative_output_path }}tfplan-golden.json; then
    echo "ERROR: The golden file {{ relative_output_path }}tfplan-golden.json file contains user-specific information."
    exit 1
  fi


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
