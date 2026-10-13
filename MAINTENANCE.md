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

Create `stable/8.x` from `main` when Camunda releases a new minor version.
Use separate worktrees for the stable branch and the next development cycle.
Submit each change through a pull request. A maintainer merges the pull requests after the required checks pass.

1. **Create the stable branch**

   * Record the commit on `origin/main` that defines the cut.
   * Create `stable/8.x` from that commit.
   * Create a worktree for each preparation branch. Do not change the shared checkout.
   * Example for the `8.10` cut:

     ```sh
      git branch stable/8.10 origin/main
      git push origin stable/8.10
      git worktree add -b chore/prepare-stable-8.10 debug/wt-cut-810 stable/8.10
      git worktree add -b chore/prepare-main-8.11 debug/wt-main-811 origin/main
     ```

2. **Check release tasks and unmarked moving parts**

   * Check every `release-duty` marker on both preparation branches.
   * On `stable/8.x`, replace development versions with verified release versions.
   * On `main`, keep only markers that apply to the next release.
   * Check moving parts that have no `release-duty` marker. Use these searches:

     ```sh
     git grep -n 'release-duty'
     git grep -n -E 'dev-latest|SNAPSHOT|renovate-helm-main|camunda-platform-8\.'
     git grep -n -E 'baseBranchPatterns|TESTS_.*PREVIOUS_VERSION|camunda_hub_cluster_version'
     git grep -n -E 'c8-sm-checks|blob/main|tree/main|docs/next' -- .github aws azure generic local docs
     git grep -n -E 'gh-pages|workflow-scheduler|\.camunda-version|\.camunda-chart-version|\.target-branch'
     ```

   * Inspect Helm source pins, image pins, installation scripts, test fixtures, generated READMEs, and topology examples.
   * Inspect release notes, documentation links, smoke-test tags, scheduler blocks, Renovate configuration, and artifact publishers.
   * Record each retained development dependency and the condition that permits its replacement.

3. **Set the stable branch metadata**

   * Set `.camunda-version` to the released minor, for example `8.10`.
   * Set `.target-branch` to `stable/8.x` on the stable branch only.
   * If `.camunda-chart-version` exists, set it to the chart source directory's minor version.

4. **Maintain `RELEASE-NOTES.md` on both branches**

   * Add the released version section at the cut.
   * Group changes by reference architecture. Cite merged pull requests and state facts only.
   * Use the first-parent history from the previous branch point to the recorded cut commit.
   * Keep the released section in sync on `main` and `stable/8.x`.
   * Add the next version's `(unreleased)` section on `main`.

5. **Prepare `main` for the next version**

   * Set `.camunda-version` to the next unreleased minor, for example `8.11`.
   * Keep `.target-branch` set to `main`.
   * Check the chart's `Chart.yaml` and application version in `camunda-platform-helm` before changing chart references.
   * Check that the registry publishes the next `dev-latest` tag.
   * Change `15-dev-latest` to `16-dev-latest` only when the 8.11 chart exists and the registry permits access.
   * Change each corresponding `camunda-platform` Renovate pattern from `versioning=regex:^15` to `versioning=regex:^16` at the same time.
   * Keep `.camunda-chart-version` on the available source directory if upstream does not yet provide the next minor.
   * Keep working chart pins until a verified replacement exists. Record the remaining prerequisite below.
   * Check Docker Hub before selecting alpha or SNAPSHOT image tags. Components can publish different versions.
   * Keep working distribution versions if the next distribution does not exist.
   * Set the EC2 upgrade-test previous versions to the latest stable minor.

6. **Update workflow schedules**

   * Add the released minor's blocks to `.github/workflows-config/workflow-scheduler.yml` on `main`.
   * Use the previous minor's blocks as a starting point.
   * Split weekly suites across hours. Use distinct names and a free weekday.
   * Stagger daily blocks by one hour between versions.
   * Update the `main` block for the next development version.
   * Check each listed workflow against the new stable branch. Do not copy workflows that no longer exist.
   * Include new architectures and their cleanup workflows. Exclude the five artifact publishers from stable schedules.
   * Keep `main`'s native workflow schedules unless a separate change requires their removal.

7. **Update Renovate branch patterns**

   Renovate reads this repository's configuration from the **default branch** only.
   A run against `stable/8.x` reuses `main`'s `.github/renovate.json5`.
   This repository does not set [`useBaseBranchConfig`](https://docs.renovatebot.com/configuration-options/#usebasebranchconfig).

   * On `main`, in `.github/renovate.json5`, update the `baseBranchPatterns` list:
     * Add the newly created `stable/8.x` branch.
      * Remove branches whose maintenance period ended. Check the [release policy](https://camunda.com/release-policy/) and the version's release announcements.
   * Remove those branches from the scheduler configuration too.
   * Inspect [infraex-common-config](https://github.com/camunda/infraex-common-config/blob/main/default.json5) for branch-specific rules.
   * Its current preset uses generic `/^stable\/8\..*/` rules, not a rule for each minor.
   * No per-version preset change is necessary unless that configuration changes.
   * On `stable/8.x`, replace the inherited `.github/renovate.json5` with the pointer stub used by the other maintenance branches:

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

      The inherited list cannot control Renovate on the stable branch.
      Put maintenance-branch rules on `main`, scoped with `matchBaseBranches`.

8. **Remove the `gh-pages` publishers from the new branch**

   On `stable/8.x`, remove the five artifact publishers.
   Find their markers with `git grep -l 'TODO: \[release-duty\] delete this workflow'`.

   ```sh
   git rm .github/workflows/internal_openshift_artifact_rosa_versions.yml \
          .github/workflows/internal_openshift_artifact_acm_versions.yml \
          .github/workflows/internal_aws_artifact_aurora_versions.yml \
          .github/workflows/internal_aws_artifact_opensearch_versions.yml \
          .github/workflows/internal_bitnami_artifact_image_versions.yml
   ```

   These workflows publish version artifacts to this repository's single `gh-pages` branch.
   The shared Renovate preset reads one URL per artifact for every repository and branch.
   A later publication replaces the shared artifact. Keep `main` as the only producer.

   On 2026-08-20, copies on `stable/8.7`, `stable/8.8`, and `stable/8.9` lacked `main`'s ROSA `--hosted-cp` merge.
   Their ACM and OpenSearch publishers also lacked the guard against empty artifacts.
   Maintenance-branch runs replaced shared artifacts with incomplete data until `main` published them again the next night.
   Scheduled workflows run only on the default branch.
   Pull-request runs caused these replacements until #3145. Manual dispatch remained possible until #3153, #3154, and #3155.

9. **Update the versioned Camunda documentation**

   * Open a pull request in `camunda/camunda-docs` after the stable branch exists.
   * In `versioned_docs/version-8.x`, change this repository's `blob/main` and `tree/main` links to `blob/stable/8.x` and `tree/stable/8.x`.
   * Check that each target file exists on `stable/8.x`.
   * Keep links in `docs/`, the next-version documentation, on `main`.

10. **Release the smoke-test scripts**

    * Open a pull request in `camunda/c8-sm-checks` to update `ZEEBE_DEFAULT_VERSION` in `checks/zeebe/connectivity.sh` to the released minor.
    * Check the scripts before publishing a new tag. This repository uses tags, not maintenance branches.
    * Update the `c8-sm-checks` tag references here after that tag exists.
    * Do not invent the next tag or change references before publication.

11. **Check and coordinate the release pull requests**

    * Run the repository checks on each preparation branch.
    * Check the released section of `RELEASE-NOTES.md` against both branches.
    * Record prerequisite pull requests and deferred version changes in the pull-request descriptions.
    * Let maintainers merge the checked pull requests. Do not merge automatically.

### 8.11 development prerequisites

Checked on 2026-10-13:

* `.camunda-version` targets `8.11`. `.camunda-chart-version` remains `8.10` so source builds select an existing directory.
* [Upstream Chart.yaml](https://github.com/camunda/camunda-platform-helm/blob/main/charts/camunda-platform-8.10/Chart.yaml) declares chart `15.1.0` and application `8.10.x`.
* Upstream `main` has no `charts/camunda-platform-8.11` directory. Keep the verified source commit and `15-dev-latest` fallback references.
* An anonymous manifest request for `16-dev-latest` returned HTTP 401, including after the registry's token exchange.
* The [public Helm index](https://helm.camunda.io/index.yaml) lists `15.0.0` from 2026-10-08 and `15.1.0` from 2026-10-12.
* Keep source builds on development `main`. Remove them on the stable preparation branch when the published chart meets each architecture's requirements.
* Recheck upstream and the registry before changing the chart directory, `dev-latest` tags, or Renovate chart-major patterns.
* Docker Hub publishes `8.11-SNAPSHOT` for [Camunda](https://hub.docker.com/r/camunda/camunda/tags?name=8.11), [Connectors](https://hub.docker.com/r/camunda/connectors-bundle/tags?name=8.11), and [Optimize](https://hub.docker.com/r/camunda/optimize/tags?name=8.11).
* No 8.11 alpha tag appeared in those lists. Identity and Hub had no 8.11 tags.
* ECS dual-region uses the verified 8.11 SNAPSHOT images. Other working GA defaults remain until their next-version configuration is available.
* EC2 and Debian retain Camunda `8.10.3` and Connectors `8.10.0`. No `8.11.0-alpha1` GitHub release exists for either distribution.
* [8.7 release announcements](https://unsupported.docs.camunda.io/8.7/docs/reference/announcements-release-notes/870/870-announcements/) give 2026-10-13 as the end of standard maintenance.
* The documentation now marks 8.7 unmaintained. Remove `stable/8.7` from Renovate and scheduler targets.
* `c8-sm-checks` still defaults to Zeebe `8.9` and its latest tag is `v1.4.0`. Complete step 10 separately.

---

## Modules

### AWS Modules

#### Dependencies

##### Upstream Dependencies: dependencies of this project

* **terraform-aws-modules**: This project relies on the official AWS modules available at [terraform-aws-modules](https://github.com/terraform-aws-modules).
