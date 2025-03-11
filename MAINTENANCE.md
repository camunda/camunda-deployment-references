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

## Release duty

When a new version is ready for release, we need to cut the `main` branch to create a new stable branch (`stable/8.x`). Follow these steps:

1. **Create the stable branch**
   - From `main`, create a new branch `stable/8.x`.
   - Example: If the current stable version is `8.6` and we are preparing to release `8.7`, run:
     ```sh
     git checkout main
     git checkout -b stable/8.7
     git push origin stable/8.7
     ```

1. **Ensure all release tasks are completed**
   - Resolve all `TODO [release-duty]` items in the codebase.
   - Verify that documentation, configurations, and dependencies are up to date.

1. **Prepare `main` for the next version**
   - The `main` branch now represents the next unreleased version (`8.8`).
   - Update version references in relevant files to reflect the new development cycle.
