// The path deliberately says `skills/`, not `.github/skills/`, where this module
// actually lives: a module path element may not begin with a dot once the module
// is fetched as a dependency. Nothing imports this module -- it is a local CLI
// run via `go run .` -- so the path only has to be stable and legal.
module github.com/camunda/camunda-deployment-references/skills/ci-feedback-loop

go 1.23.0

require github.com/spf13/cobra v1.9.1

require (
	github.com/inconshreveable/mousetrap v1.1.0 // indirect
	github.com/spf13/pflag v1.0.6 // indirect
)
