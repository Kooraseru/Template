-- validation/tests/testing.luau
--!strict

local Test = require("@testing")

--# Types

type Operation = () -> boolean

--# Declaration

local definition: Test.Definition<Operation, boolean> = {
	Name = "Shared typed testing",
	Execute = function(operation: Operation): boolean
		return operation()
	end,
	Cases = {
		{
			Name = "Comparison methods are inherited",
			Input = function(): boolean
				local suite = Test.new({
					Name = "Equality",
					Execute = function(value: number): number
						return value * 2
					end,
					Cases = { { Name = "Double", Input = 2, Expected = 4, Compare = Test.Equal } },
				})

				return suite.Equal(4, 4) and suite:Report().Success
			end,
			Expected = true,
		},
		{
			Name = "Failures and exceptions are reported without stopping later cases",
			Input = function(): boolean
				local count = 0
				local suite = Test.new({
					Name = "Failures",
					Execute = function(value: number): number
						count += 1
						assert(value ~= 0, "execution failed")
						return value
					end,
					Cases = {
						{ Name = "Mismatch", Input = 1, Expected = 2 },
						{ Name = "Exception", Input = 0, Expected = 0 },
						{ Name = "Later success", Input = 3, Expected = 3 },
					},
				})
				local report = suite:Report()

				return count == 3
					and not report.Success
					and not report.Results[1].Success
					and not report.Results[2].Success
					and report.Results[3].Success
			end,
			Expected = true,
		},
		{
			Name = "Duplicate names are rejected",
			Input = function(): boolean
				return not pcall(function()
					Test.new({
						Name = "Duplicate",
						Execute = function(value: boolean): boolean
							return value
						end,
						Cases = {
							{ Name = "Same", Input = true, Expected = true },
							{ Name = "Same", Input = false, Expected = false },
						},
					})
				end)
			end,
			Expected = true,
		},
		{
			Name = "Nested comparisons detect extra and mismatched fields",
			Input = function(): boolean
				return Test.DeepEqual({ data = { 1, 2 } }, { data = { 1, 2 } })
					and not Test.DeepEqual({ data = { 1, 2 } }, { data = { 1, 3 } })
					and not Test.DeepEqual({ data = { 1 } }, { data = { 1, 2 } })
			end,
			Expected = true,
		},
	},
}

return Test.new(definition)
