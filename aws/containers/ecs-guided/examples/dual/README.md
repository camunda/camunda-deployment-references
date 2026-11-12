# Adding a second region

Variables for the steps of [`../../EVOLVE-DUAL.md`](../../EVOLVE-DUAL.md). Region A is the
deployment you already have (`examples/greenfield` or `examples/byo-vpc`); these files only
show what changes in it, and what the second region gets.

| Directory | Use |
|-----------|-----|
| `region-a/` | The variables that change in the existing deployment (`camunda-converged.tfvars` is the last step). |
| `region-b/` | The stages of the new region, run with `STATE_KEY_PREFIX=region-b/`. |
| `interconnect.tfvars`, `global-database.tfvars` | The two roots that span both regions. |
