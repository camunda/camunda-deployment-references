# Maintenance of this repository

TODO: write the complete maintenance guide (https://github.com/camunda/camunda-deployment-references/issues/110)

## Branching Strategy for camunda-deployment-references

The repository [https://github.com/camunda/camunda-deployment-references](https://github.com/camunda/camunda-deployment-references) follows the logic of maintaining only the [latest released version of Camunda](https://docs.camunda.io/docs/8.7/reference/release-notes/) on the `main` branch.

=> Most of the time, we work on the next unreleased version.

We should not merge into `main` directly but into the respective Camunda version branch we are working on.

The `main` branch will be updated automatically when we push to the latest stable version branch, thanks to the workflow `.github/workflows/internal_global_sync_main.yml`.

For example, consider the following branches:

- `main/`
- `stable/8.7`
- `stable/8.6`
- `stable/8.5`

Where `8.6` is the latest stable version and `8.7` is the next one. The branch to target for merge requests should be `8.7` since it represents the upcoming version.

When `8.7` becomes the new stable version, we will update the `internal_global_sync_main` workflow to merge it into `main`.
