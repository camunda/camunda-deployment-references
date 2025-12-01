# this file is a recipe file for the project

# renovate: datasource=github-releases depName=gotestyourself/gotestsum
gotestsum_version := "v1.13.0"

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
  set -euo pipefail

  cd {{ justfile_directory() }}/{{ module_dir }}

  rm -Rf {{ justfile_directory() }}/{{ module_dir }}/.terraform*

  # Copy *.tf files from test/fixtures/golden to the current directory before running the plan
  if ls test/fixtures/golden/fixture_*.tf 1> /dev/null 2>&1; then
    cp test/fixtures/golden/fixture_*.tf ./
  fi

  terraform init \
    -backend-config="bucket={{ backend_bucket_name }}" \
    -backend-config="key={{ backend_bucket_key }}" \
    -backend-config="region={{ backend_bucket_region }}"

  # we always use the same region and fake rhcs token to have a pre-defined output
  RHCS_TOKEN="" AWS_REGION="eu-west-2" terraform plan -var-file=test/golden/golden.tfvars -out=tfplan

  # Clean up copied .tf files (those prefixed with fixture_)
  rm -f fixture_*.tf

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
          if (.resources | length == 0) then
            { "resources": {} }
          else
            { "resources": map(transform) | add }
          end
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

  # normalize release_version: replace the date (and any suffix) with "SUFFIX"
  jq 'walk(
        if type == "object" and has("release_version") and (.release_version | test("^[0-9]+\\.[0-9]+\\.[0-9]+-[0-9]{8}.*$")) then
          .release_version |= sub("-[0-9]{8}.*$"; "-SUFFIX")
        else .
        end
      )' tfplan.json > tfplan-redacted.json
  rm -f tfplan.json

  # transform, as our users don’t have permission to see ipam_pools but CI does
  jq 'walk(if type == "object" then del(.ipam_pools) else . end)' tfplan-redacted.json > tfplan.json
  rm -f tfplan-redacted.json

  # final sort
  jq --sort-keys '.' tfplan.json >  {{ relative_output_path }}tfplan-golden.json
  rm -f tfplan.json

  if grep -E -q '\b@camunda\.[A-Za-z]{2,}\b' {{ relative_output_path }}tfplan-golden.json; then
    echo "ERROR: The golden file {{ relative_output_path }}tfplan-golden.json contains user-specific information."
    exit 1
  fi

# Discover all environments and regenerate golden files for each
# Usage:
#   just regenerate-golden-file-all
regenerate-golden-file-all:
  #!/usr/bin/env bash
  set -euo pipefail
  REPO_ROOT="{{ justfile_directory() }}"
  BUCKET="${TFSTATE_BUCKET:-tests-ra-aws-rosa-hcp-tf-state-eu-central-1}"
  REGION="${TFSTATE_REGION:-eu-central-1}"
  IGNORE_WORDS="${IGNORE_WORDS:-peering}"

  if [[ -z "$BUCKET" || -z "$REGION" ]]; then
    echo "ERROR: TFSTATE_BUCKET and TFSTATE_REGION environment variables are required." >&2
    exit 1
  fi

  # Find all directories that contain a config.tf file
  echo "Discovering environments (looking for */config.tf)..."
  echo "Ignoring any path containing: ${IGNORE_WORDS}"

  count=0
  while IFS= read -r tfvars; do
    module_dir_abs="$(dirname "$tfvars")"
    module_dir_rel="${module_dir_abs#"$REPO_ROOT/"}"

    # Skip if module_dir_rel contains any ignored word
    skip=""
    matched=""
    IFS=' ' read -ra words <<< "$IGNORE_WORDS"
    for w in "${words[@]}"; do
      if [[ "$module_dir_rel" == *"$w"* ]]; then
        skip="yes"
        matched="$w"
        break
      fi
    done
    if [[ -n "$skip" ]]; then
      echo "Skipping: ${module_dir_rel} (matched ignore word: ${matched})"
      continue
    fi

    backend_key="golden.tfstate"

    echo "[${count}] Regenerating golden for: ${module_dir_rel}"
    echo "      Backend: bucket=${BUCKET}, region=${REGION}, key=${backend_key}"
    if just regenerate-golden-file "${module_dir_rel}" "${REGION}" "${BUCKET}" "${backend_key}"; then
      count=$((count + 1))
    else
      echo "❌ Failed for ${module_dir_rel}" >&2
      exit 1
    fi
  done < <(find "$REPO_ROOT" -type f -name "config.tf" | LC_ALL=C sort)

  echo "Processed ${count} environment(s)."


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
