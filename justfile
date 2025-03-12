# this file is a recipe file for the project

# renovate: datasource=github-releases depName=gotestyourself/gotestsum
gotestsum_version := "v1.12.0"

# Generate the AWS golden file for the EC2 tf files
aws-compute-ec2-single-region-golden:
  #!/bin/bash
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
