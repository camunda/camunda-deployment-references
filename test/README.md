# Testing

## Requirements

To gather all specifics versions of this project, we use:
- [asdf](https://asdf-vm.com/) version manager (see [installation](https://asdf-vm.com/guide/getting-started.html)).
- [just](https://github.com/casey/just) as a command runner
  - install it using asdf: `asdf plugin add just && asdf install just`

Then we will install all the tooling listed in the `.tool-versions` of this root project using just:
```bash
just install-tooling

# list available recipes
just --list
```

## Configure AWSCli

You should now have `awscli` installed, verify it with: `aws --version`

Make sure that your aws cli is configured with a proper AWS Profile and a region:

**Aws Cli Auth**: https://docs.aws.amazon.com/cli/latest/userguide/cli-authentication-user.html#cli-authentication-user-configure.title

```bash
export AWS_DEFAULT_PROFILE=<profile-name>
# you can also use
# export AWS_PROFILE=<profile-name>

export AWS_REGION=eu-central-1

# if you are using sso
aws sso login --profile "$AWS_DEFAULT_PROFILE"

# verify that you are correctly authenticated
aws eks list-clusters
```

## Configure the tests

The tests will create resources on AWS using the provided account

By default, a random uuid is assigned and prepended to the end of each object created.

If you want to specify a non-random cluster UID:
```bash
export TESTS_CLUSTER_ID="myTest"
```

If you don't want to delete the resources at the end of the test:
```bash
export CLEAN_CLUSTER_AT_THE_END=false
```

The tf states are stored by default in a S3 bucket, if you want to configure the bucket name and the bucket region:
```bash
export TF_STATE_BUCKET="myBucket"
export TF_STATE_BUCKET_REGION="eu-central-1"
```

You can change the default deployment region:
```bash
export TESTS_CLUSTER_REGION="eu-west-1"
```

You can change the terraform binary (default is `terraform`):
```bash
export TESTS_TF_BINARY_NAME="tofu"
```

### Run the tests

Test with:

```bash
# Launch all the tests
just test

# if you want the live output
just tests-verbose

# or just test one case
just test-verbose TestUpgradeEKSTestSuite
```

When you run the test, terratest will create a copy of the module to be tested in the `tests/states` directory.
You can later navigate to the directory and use its content to manipulate the cluster.

**Local development note:**
You can set the `SKIP_XXX` variable to prevent unique IDs of tests from being generated each time, thus using the same resources instead of deploying new resources with terraform.

### Just Reference

May not be up-to-date, please verify with `just --list`:
```text
╰─λ just --list                                                                                                            130 (10.968s) < 15:28:36
Available recipes:
    asdf-install      # Install tools using asdf
    asdf-plugins      # Install asdf plugins
    install-tooling   # Install all the tooling
    test TEST         # Launch a single test using gotestsum
    test-verbose TEST # Launch a single test using go test in verbose mode
    tests             # Launch the tests in parallel using gotestsum
    tests-verbose     # Launch the tests in parallel using go test in verbose mode
```

## Troubleshooting

Ensure you don't have test clusters running for a while:

```bash
eksctl get clusters
```
