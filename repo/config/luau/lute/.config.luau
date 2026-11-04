-- Share the same custom rules between Mandolin diagnostics and local/CI Lute runs.
return {
	lute = {
		lint = {
			rulepaths = { "rules" },
			ignores = {
				"build/**",
				"dependencies/**",
			},
			ruleconfigs = {
				declarative_data = {
					severity = "warning",
				},
			},
		},
	},
}
