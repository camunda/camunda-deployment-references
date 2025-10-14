# Maintenance of this repository

TODO: write the complete maintenance guide (https://github.com/camunda/camunda-deployment-references/issues/110)

## Branching Strategy for camunda-deployment-references

The repository [https://github.com/camunda/camunda-deployment-references](https://github.com/camunda/camunda-deployment-references) follows the logic of maintaining only the [next unreleased version of Camunda](https://docs.camunda.io/docs/next/reference/announcements-release-notes/overview/#announcements--release-notes) on the `main` branch.

\=> Most of the time, we work on the next unreleased version, we should then merge into `main`.

For example, consider the following branches:

* `main/`
* `stable/8.6`
* `stable/8.5`

Where `8.6` is the latest stable version and `8.7` is the next one. The branch to target for merge requests should be `main` since it represents the upcoming version.

When `8.7` becomes the new stable version, we create the `stable/8.7` branch from `main` and then `main` will be used for the next unreleased version (`8.8`).

### Target branch tracking (`.target-branch`)

To avoid confusion, the repository contains a `.target-branch` file at its root.

* This file contains the **name of the branch that should be targeted for merge requests**.
* GitHub Actions and CI pipelines read this file to automatically detect the correct branch.
* Example content of `.target-branch`:

```
main
```

Whenever the branching strategy changes (for example when `main` is cut into a new `stable/8.x` branch), **update this file** to reflect the new target.

---

## Release duty

When a new version is ready for release, we need to cut the `main` branch to create a new stable branch (`stable/8.x`). Follow these steps:

1. **Create the stable branch**

   * From `main`, create a new branch `stable/8.x`.
   * Example: If the current stable version is `8.6` and we are preparing to release `8.7`, run:

     ```sh
     git checkout main
     git checkout -b stable/8.7
     git push origin stable/8.7
     ```

3. **Ensure all release tasks are completed**

   * Resolve all `TODO [release-duty]` items in the codebase.
   * Verify that documentation, configurations, and dependencies are up to date.

4. Update the value of the release in `.camunda-version` (e.g: `8.7`).

5. **Update `.target-branch`** so that it continues to point to `stable/8.x` (or whichever branch is the version target).

6. **Prepare `main` for the next version**

   * The `main` branch now represents the next unreleased version (`8.8`).
   * Add all the schedules for the version in `.github/workflows-config/workflow-scheduler.yml`.
   * Update version references in relevant files to reflect the new development cycle.
   * **Update `.target-branch`** so that it continues to point to `main` (or whichever branch is the new default target).

---

## Modules

### AWS Modules

#### Dependencies

##### Upstream Dependencies: dependencies of this project

* **terraform-aws-modules**: This project relies on the official AWS modules available at [terraform-aws-modules](https://github.com/terraform-aws-modules).
