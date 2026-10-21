# Typed testing

Tests return a metatable-backed suite from `require("@testing")`. The shared
library owns case validation, execution, comparison, failure collection, and
reporting. Requiring a test never executes it.

```luau
--!strict

local Test = require("@testing")

local definition: Test.Definition<number, number> = {
	Name = "Example",
	Execute = function(input: number): number
		return input * 2
	end,
	Cases = {
		{ Name = "Double", Input = 2, Expected = 4, Compare = Test.Equal },
	},
}

return Test.new(definition)
```

`Execute` binds declarations to the function under test. `Equal` is the default
comparison; `DeepEqual` compares nested values. A case can choose another typed
comparison. Cases must have distinct, nonempty names. `suite:Report()` runs every
case and returns structured results, including failures and exceptions.
`suite:Run()` additionally fails the stage if any case failed. Output belongs to
the caller, so tests do not print success messages.

Run an individual suite with
`bash ci/integration/run.sh ci/validation/tests/testing.luau`.
The hosted workflow calls `ci/validation/run.luau` to collect stage evidence.

The existing fixture helpers remain available for tests still being migrated.
Frozen canonical-byte and signature vectors remain explicit security evidence;
do not regenerate their expected values from the implementation under test.
