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
   * Update the Helm chart major version: bump the `dev-latest` tag (e.g. `14-dev-latest` → `15-dev-latest`) and the Renovate `versioning=regex:^N` pattern in all files containing a `# renovate:` comment for `camunda-platform`. Search for `TODO: [release-duty]` markers to find all locations.
   * **Update `.target-branch`** so that it continues to point to `main` (or whichever branch is the new default target).

7. **Update Renovate branch patterns**

   Renovate reads its configuration from the **default branch** only. A run against `stable/8.x` reuses `main`'s `.github/renovate.json5` rather than the copy sitting on the branch, because [`useBaseBranchConfig`](https://docs.renovatebot.com/configuration-options/#usebasebranchconfig) is not set. Both steps below follow from that.

   * On `main`, in `.github/renovate.json5`, update the `baseBranchPatterns` list:
     * Add the newly created `stable/8.x` branch.
     * Remove any branches whose maintenance period has ended.
   * This ensures Renovate only creates dependency update PRs for actively maintained branches.
   * On the newly created `stable/8.x` branch, replace the inherited `.github/renovate.json5` with the pointer stub already used by the other maintenance branches:

     ```json5
     {
       // Renovate does not read this file.
       //
       // A base branch run reuses the configuration of the repository default branch
       // unless `useBaseBranchConfig` is set, and it is not set here. Anything that
       // must apply to this maintenance branch belongs in `.github/renovate.json5` on
       // `main`, scoped with `matchBaseBranches`.
       //
       // This stub is kept so that a rule added here is not silently ignored.
       $schema: "https://docs.renovatebot.com/renovate-schema.json",
       extends: ["github>camunda/infraex-common-config:default.json5"],
     }
     ```

     Skipping this leaves the branch carrying a `baseBranchPatterns` list frozen on the day of the cut, and invites the next person to add a rule there that Renovate will never apply. Anything genuinely specific to a maintenance branch goes on `main`, scoped with `matchBaseBranches`.

8. **Delete the `gh-pages` publishers from the new branch**

   On the freshly cut `stable/8.x`, delete the five workflows carrying a `TODO: [release-duty]` marker that says so — `git grep -l 'TODO: \[release-duty\] delete this workflow'` lists them:

   ```sh
   git rm .github/workflows/internal_openshift_artifact_rosa_versions.yml \
          .github/workflows/internal_openshift_artifact_acm_versions.yml \
          .github/workflows/internal_aws_artifact_aurora_versions.yml \
          .github/workflows/internal_aws_artifact_opensearch_versions.yml \
          .github/workflows/internal_bitnami_artifact_image_versions.yml
   ```

   These workflows publish version artifacts to this repository's single `gh-pages` branch, and the shared Renovate preset reads one URL per artifact for every repository and every branch. Whatever runs last wins, everywhere, so `main` is the only legitimate producer.

   A copy left behind does not sit idle, it ages. By the time it was found on 2026-08-20, the `stable/8.7`, `stable/8.8` and `stable/8.9` copies published the ROSA classic list without the `--hosted-cp` merge `main` had since added, and the ACM and OpenSearch ones predated the guard that refuses to publish an empty artifact — so a run from a maintenance branch replaced the global artifact with a degraded one until `main` republished it the following night. Scheduled workflows only run on the default branch, so none of that was ever on purpose: a `pull_request` run did it until #3145, and a `workflow_dispatch` still could until #3153, #3154 and #3155.

---

## Modules

### AWS Modules

#### Dependencies

##### Upstream Dependencies: dependencies of this project

* **terraform-aws-modules**: This project relies on the official AWS modules available at [terraform-aws-modules](https://github.com/terraform-aws-modules).
