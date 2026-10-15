# Maintenance of this repository

TODO: write the complete maintenance guide (https://github.com/camunda/camunda-deployment-references/issues/110)

## Branching Strategy for camunda-deployment-references

The repository [https://github.com/camunda/camunda-deployment-references](https://github.com/camunda/camunda-deployment-references) follows the logic of maintaining only the [next unreleased version of Camunda](https://docs.camunda.io/docs/next/reference/announcements-release-notes/overview/#announcements--release-notes) on the `main` branch.

\=> Most of the time, we work on the next unreleased version, we should then merge into `main`.

For example, consider the following branches:

* `main`
* `stable/8.10`
* `stable/8.9`

Here, `8.10` is the latest stable version and `8.11` is the next version.
Target `main` for changes to the upcoming version.

When `8.11` becomes stable, create `stable/8.11` from `main`.
Then use `main` for the next unreleased version, `8.12`.

### Target branch tracking (`.target-branch`)

To avoid confusion, the repository contains a `.target-branch` file at its root.

* This file contains the **name of the branch that should be targeted for merge requests**.
* GitHub Actions and CI pipelines read this file to automatically detect the target branch.
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
     git branch stable/8.10 <cut-sha>
     git push origin stable/8.10
     git worktree add -b chore/prepare-stable-8.10 debug/wt-cut-810 stable/8.10
     git worktree add -b chore/prepare-main-8.11 debug/wt-main-811 origin/main
     ```

   * Create the `backport stable/8.x` label for the new stable branch.

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
     git grep -n -E 'gh-pages|workflow-scheduler|\.camunda-version|\.target-branch'
     ```

   * Inspect Helm source pins, image pins, installation scripts, test fixtures, generated READMEs, and topology examples.
   * Inspect release notes, documentation links, smoke-test releases, scheduler blocks, Renovate configuration, and artifact publishers.
   * Record each retained development dependency and the condition that permits its replacement.

3. **Set the stable branch metadata**

   * Set `.camunda-version` to the released minor, for example `8.10`.
   * Set `.target-branch` to `stable/8.x` on the stable branch only.
   * Change marked action branch defaults and lint push filters to `stable/8.x` on the cut branch.
   * Keep `c8-sm-checks` references on `main`. Do not add a cut-switch marker to that default.

4. **Maintain `RELEASE-NOTES.md` on both branches**

   * Add the released version section at the cut.
   * Group changes by reference architecture. Cite merged pull requests and state facts only.
   * Use the first-parent history from the previous branch point to the recorded cut commit.
   * Keep the released section identical on `main` and `stable/8.x`.
   * Keep one section per minor. Do not add a section for a patch or a rebuild.
   * Add backported user-visible fixes to that section on both branches, in the same pull request as the backport or right after it.
   * Add the next version's `(unreleased)` section on `main`.

5. **Prepare `main` for the next version**

   * Set `.camunda-version` to the next unreleased minor, for example `8.11`.
   * Keep `.target-branch` set to `main`.
   * Check the chart's `Chart.yaml` and application version in `camunda-platform-helm` before changing chart references.
   * Check that the registry publishes the next `dev-latest` tag.
   * Change `15-dev-latest` to `16-dev-latest` only when the 8.11 chart exists and the registry permits access.
   * Change each corresponding `camunda-platform` Renovate pattern from `versioning=regex:^15` to `versioning=regex:^16` at the same time.
   * After checkout, source builders select `charts/camunda-platform-$(cat .camunda-version)` when that directory exists.
   * Otherwise, they select the newest `charts/camunda-platform-8.*` directory with `sort -V`.
   * The fallback prints a warning to stderr that names the expected and selected directories.
   * Keep working chart pins until a verified replacement exists. Record remaining prerequisites in the pull-request description.
   * Check Docker Hub before selecting alpha or SNAPSHOT image tags. Components can publish different versions.
   * Keep working distribution versions if the next distribution does not exist.
   * Change EC2 previous versions together with `TESTS_CAMUNDA_VERSION` and `TESTS_CONNECTORS_VERSION` when the next minor's distributions exist.
   * Keep the previous versions on the preceding minor until then. This preserves a minor-version upgrade test.

6. **Update workflow schedules**

   * Add the released minor's blocks to `.github/workflows-config/workflow-scheduler.yml` on `main`.
   * Use the previous minor's blocks as a starting point.
   * Split weekly suites across hours. Use distinct names and a free weekday.
   * Stagger daily blocks by one hour between versions.
   * Check each listed workflow against the new stable branch. Do not copy workflows that no longer exist.
   * Every scheduled workflow needs `on.pull_request` on its target branch.
   * Include new architectures and their cleanup workflows. Exclude dev-only workflows from stable schedules.
   * Use the scheduler only for stable branches. Keep `main`'s native workflow schedules.

7. **Update Renovate branch patterns**

   Renovate reads this repository's configuration from the **default branch** only.
   A run against `stable/8.x` reuses `main`'s `.github/renovate.json5`.
   This repository does not set [`useBaseBranchConfig`](https://docs.renovatebot.com/configuration-options/#usebasebranchconfig).

   * On `main`, in `.github/renovate.json5`, update the `baseBranchPatterns` list:
     * Add the newly created `stable/8.x` branch.
     * Follow step 13 for branches whose maintenance period ended.
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

8. **Remove dev-only workflows and chart source builds from the cut branch**

   On `stable/8.x`, remove the five `gh-pages` publishers and the alpha availability watcher.
   Find all dev-only workflow markers with `git grep -l 'TODO: \[release-duty\] delete this workflow' -- .github/workflows`.
   Remove any additional workflow whose marker requires deletion at the cut.

   ```sh
   git rm .github/workflows/internal_openshift_artifact_rosa_versions.yml \
          .github/workflows/internal_openshift_artifact_acm_versions.yml \
          .github/workflows/internal_aws_artifact_aurora_versions.yml \
          .github/workflows/internal_aws_artifact_opensearch_versions.yml \
          .github/workflows/internal_bitnami_artifact_image_versions.yml \
          .github/workflows/internal_global_alpha_availability_check.yml
   ```

   The five publishers write version artifacts to this repository's single `gh-pages` branch.
   The shared Renovate preset reads one URL per artifact for every repository and branch.
   A later publication replaces the shared artifact. Keep `main` as the only producer.

   On 2026-08-20, copies on `stable/8.7`, `stable/8.8`, and `stable/8.9` lacked `main`'s ROSA `--hosted-cp` merge.
   Their ACM and OpenSearch publishers also lacked the guard against empty artifacts.
   Maintenance-branch runs replaced shared artifacts with incomplete data until `main` published them again the next night.
   Scheduled workflows run only on the default branch.
   Pull-request runs caused these replacements until #3145. Manual dispatch remained possible until #3153, #3154, and #3155.

   The alpha watcher checks development SNAPSHOT pins. Stable branches use published versions and do not need this watcher.

   * Remove both `build-camunda-chart.sh` helpers on the cut branch.
   * Replace their installation callers with the published chart and an explicit chart version.
   * Remove source checkout, commit pins, chart selection blocks, and local-chart environment variables from actions and workflows.
   * Remove the `local-chart-path` input, schema autodetection, and caller plumbing from the Helm deprecation action.
   * Preserve schema validation. Adapt test guards to inspect the published chart instead of requiring a source checkout.
   * Remove source-build Makefile hints, the chart selection self-test, and its local pre-commit hook.
   * Search for remaining source-build references:

     ```sh
     git grep -n -E 'build-camunda-chart|renovate-helm-main|CHART_CHECKOUT|LOCAL_CHART|local-chart-path|HELM_CHART_REF|\.camunda-platform-helm'
     ```

   * Record each retained match and its reason in the cut pull request.

9. **Update the versioned Camunda documentation**

   * Open a pull request in `camunda/camunda-docs` after the stable branch exists.
   * In `versioned_docs/version-8.x`, change this repository's `blob/main` and `tree/main` links to `blob/stable/8.x` and `tree/stable/8.x`.
   * Check that each target file exists on `stable/8.x`.
   * Keep links in `docs/`, the next-version documentation, on `main`.

10. **Release the smoke-test scripts**

    * Open a pull request in `camunda/c8-sm-checks` to update `ZEEBE_DEFAULT_VERSION` in `checks/zeebe/connectivity.sh` to the released minor.
    * Check the scripts, then tag a release in `camunda/c8-sm-checks`.
    * Keep this repository's `c8-sm-checks` references on `main`.

11. **Check and coordinate the release pull requests**

    * Run the repository checks on each preparation branch.
    * Check the released section of `RELEASE-NOTES.md` against both branches.
    * Record prerequisite pull requests and deferred version changes in the pull-request descriptions.
    * Let maintainers merge the checked pull requests. Do not merge automatically.

12. **Publish the repository tag and GitHub Release**

    * Wait for a maintainer to merge the cut pull request and required backports into `stable/8.x`.
    * For 8.10, wait for #3671 and #3669 to merge.
    * Record the release commit on `stable/8.x`. Use that commit, not the original unprepared branch point.
    * Check that the version section in `RELEASE-NOTES.md` is identical on both branches.
    * Copy only that section into a notes file under `debug/` in the release worktree.
    * Create an annotated tag named `8.x-YYwWWa`, like a Minecraft snapshot: `YY` is the two-digit year, `WW` the ISO week, and `a` the first release of that week. Use `b`, `c` for later releases in the same week. Get the week with `date +%gw%V`.
    * Publish that tag before creating the GitHub Release. Do not replace an existing tag or force-push a tag.
    * The first release of 8.10 used `8.10.0`, before this scheme. Do not create new `8.x.y` tags.
    * Example for an 8.10 release in ISO week 42 of 2026, using the recorded release commit:

      ```sh
      git tag -a 8.10-26w42a <release-sha> -m "Camunda Reference Architectures 8.10-26w42a"
      git push origin refs/tags/8.10-26w42a
      gh release create 8.10-26w42a --verify-tag --title "Camunda 8.10 (26w42a)" --notes-file debug/release-8.10.md
      ```

    * The notes file holds the full, current `8.x` section. Each release of a minor shows the cumulative section.
    * Publish a new tag and release after user-visible fixes reach `stable/8.x` and the section is amended on both branches.

13. **Retire a maintenance branch**

    * Record the retirement decision and the release-policy evidence.
    * Remove the branch from `baseBranchPatterns` in `main`'s `.github/renovate.json5`.
    * Remove all its weekly and daily blocks from `.github/workflows-config/workflow-scheduler.yml`.
    * Check the scheduler consumer for hardcoded branch lists and validation rules.
    * Search `.github`, `docs`, root Markdown files, `justfile`, and `scripts` for the retired branch and minor version.
    * Check backport configuration, Slack routing, matrices, labels, issue templates, and documentation examples.
    * Remove the branch from automatic maintained-version lists. Update examples that describe the current maintained set.
    * Keep historical facts and parser-test inputs. Record a decision for each remaining match.
    * Keep generic backport and Slack rules when they also serve historical or explicit manual operations.
    * Do not remove the Git branch or published history as part of this checklist.
    * Check that scheduler YAML parses. Test its matrix selection without creating or closing pull requests.
    * Record all remaining dependencies on the retired branch in the pull request.

---

## Modules

### AWS Modules

#### Dependencies

##### Upstream Dependencies: dependencies of this project

* **terraform-aws-modules**: This project relies on the official AWS modules available at [terraform-aws-modules](https://github.com/terraform-aws-modules).
