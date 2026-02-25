module github.com/observability-platform/terraform-tests

go 1.21

require github.com/stretchr/testify v1.9.0

// NOTE: Run `go mod tidy` after first `go test` to resolve the full dependency tree.
// The indirect dependencies below are a subset; `go mod tidy` will complete them.

require (
	github.com/davecgh/go-spew v1.1.1 // indirect
	github.com/kr/pretty v0.2.1 // indirect
	github.com/kr/text v0.2.0 // indirect
	github.com/pmezard/go-difflib v1.0.0 // indirect
	gopkg.in/check.v1 v1.0.0-20180628173108-788fd7840127 // indirect
	gopkg.in/yaml.v3 v3.0.1 // indirect
)
