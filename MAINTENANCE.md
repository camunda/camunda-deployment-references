# Maintenance of this repository

TODO: write the complete maintenance guide (https://github.com/camunda/camunda-deployment-references/issues/110)

## Branching Strategy for camunda-deployment-references

The repository [https://github.com/camunda/camunda-deployment-references](https://github.com/camunda/camunda-deployment-references) follows the logic of maintaining only the [next unreleased version of Camunda](https://docs.camunda.io/docs/8.7/reference/release-notes/) on the `main` branch.

=> Most of the time, we work on the next unreleased version, we should then merge into `main`.

For example, consider the following branches:

- `main/`
- `stable/8.6`
- `stable/8.5`

Where `8.6` is the latest stable version and `8.7` is the next one. The branch to target for merge requests should be `main` since it represents the upcoming version.

When `8.7` becomes the new stable version, we create the `stable/8.7` branch from `main` and then `main` will be used for the next unrelease version (`8.8`).
