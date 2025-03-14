# Developer's Guide

Welcome to the development reference for Camunda's Terraform EKS module! This document provides guidance on setting up a testing environment, running tests, and managing releases.

## Setting up Development Environment

To start developing or testing the EKS module, follow these steps:

1. **Clone the Repository:**
   - Clone the repository from [camunda/camunda-deployment-references](https://github.com/camunda/camunda-deployment-references) to your local machine.

2. **Navigate to Test Suite:**
   - Go to the `aws/modules/.test/src` directory to access the test suite.

3. **Test-Driven Development (TDD):**
   - Use the Test-Driven Development approach to iterate on the module.
   - Add or modify test cases in the test suite to match the desired functionality.
   - Run tests frequently to ensure changes meet requirements.

4. **Local Development:**
   - Utilize environment variables like `SKIP_XXX` to control certain behaviors during local development.
   - Ensure to use a unique identifier for the cluster to avoid conflicts with existing resources.

5. **Testing Tools:**
   - Refer to `.test/README.md` for instructions on setting up and using testing tools.
   - Add fixtures and test cases using Terratest and Testify to validate module functionality.

6. **Cluster Cleanup:**
   - Set `CLEAN_CLUSTER_AT_THE_END=false` to prevent automatic cluster deletion in case of errors.
   - Optionally, manually clean up the cluster after testing by reversing this setting.

## Tests in the CI

The tests in the CI can be triggered automatically by modifying terraform or test files.
It will be labeled either `test` or `terraform` automatically by the labeler.

You can skip specific tests in the CI by listing them in the commit description with the prefix `skip-tests:` (e.g.: `skip-tests:Test1,Test2`).
If you want to skip all tests, use `skip-tests:all`.
Remember, if all tests are skipped, the workflow will intentionally result in a `failed` status.
To skip tests without triggering an error, add the label `testing-ci-not-necessary` to the PR.

## Adding new GH actions

Please pin GitHub actions, if you need you can use [pin-github-action](https://github.com/mheap/pin-github-action) cli tool.

---

By following these guidelines, we ensure smooth development iterations, robust testing practices, and clear version management for the Terraform EKS module. Happy coding!
