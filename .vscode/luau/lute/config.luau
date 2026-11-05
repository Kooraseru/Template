-- .vscode/luau/lute/config.luau
--!strict

-- Share the same custom rules between Mandolin diagnostics and local/CI Lute runs.
return {
	lute = {
		lint = {
			rulepaths = { "../../../rules/languages/luau/declarative-data" },
			ignores = {
				"build/**",
				"build/run/dependencies/**",
				"../../../rules/**/tests/**",
			},
			ruleconfigs = {
				-- This Lute version crashes on `const`; Luau LSP reports unused locals.
				unused_variable = { off = true },
				declarative_data = {
					severity = "warning",
				},
			},
		},
	},
}
