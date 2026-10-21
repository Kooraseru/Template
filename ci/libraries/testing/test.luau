-- libraries/testing/test.luau
--!strict

local Test = {}
Test.__index = Test

--# Types

export type Case<Input, Output> = {
	Name: string,
	Input: Input,
	Expected: Output,
	Compare: ((Output, Output) -> boolean)?,
}

export type Definition<Input, Output> = {
	Name: string,
	Execute: (Input) -> Output,
	Cases: { Case<Input, Output> },
}

export type Result = { Name: string, Success: boolean, Error: string? }
export type Report = { Name: string, Success: boolean, Results: { Result } }
export type Suite<Input, Output> = setmetatable<Definition<Input, Output>, typeof(Test)>

--# Helpers

local function equal(actual: unknown, expected: unknown, seen: { [unknown]: unknown }): boolean
	if type(actual) ~= "table" or type(expected) ~= "table" then
		return actual == expected
	end

	if seen[actual] then
		return seen[actual] == expected
	end

	seen[actual] = expected
	local actualEntries = actual :: { [unknown]: unknown }
	local expectedEntries = expected :: { [unknown]: unknown }

	for key, value in actualEntries do
		if not equal(value, expectedEntries[key], seen) then
			return false
		end
	end

	for key in expectedEntries do
		if actualEntries[key] == nil then
			return false
		end
	end

	return true
end

--# Functions

function Test.Equal<Output>(actual: Output, expected: Output): boolean
	return actual == expected
end

function Test.DeepEqual<Output>(actual: Output, expected: Output): boolean
	return equal(actual, expected, {})
end

function Test.new<Input, Output>(definition: Definition<Input, Output>): Suite<Input, Output>
	assert(definition.Name ~= "", "test suite needs a name")
	assert(type(definition.Execute) == "function", "test suite needs its function under test")
	assert(#definition.Cases > 0, "test suite needs at least one case")
	local names: { [string]: boolean } = {}
	local cases: { Case<Input, Output> } = {}

	for _, case in definition.Cases do
		assert(case.Name ~= "" and not names[case.Name], "empty or duplicate test case name: " .. case.Name)
		assert(case.Compare == nil or type(case.Compare) == "function", "invalid comparison: " .. case.Name)
		names[case.Name] = true
		table.insert(cases, table.clone(case))
	end

	local fields: Definition<Input, Output> = {
		Name = definition.Name,
		Execute = definition.Execute,
		Cases = cases,
	}

	return setmetatable(fields, Test)
end

function Test.Report<Input, Output>(self: Suite<Input, Output>): Report
	local results: { Result } = {}
	local success = true

	for _, case in self.Cases do
		local passed, failure = pcall(function()
			local actual = self.Execute(case.Input)
			local compare = case.Compare or Test.Equal
			assert(compare(actual, case.Expected), "comparison failed")
		end)

		success = success and passed
		table.insert(results, {
			Name = case.Name,
			Success = passed,
			Error = if passed then nil else tostring(failure),
		})
	end

	return { Name = self.Name, Success = success, Results = results }
end

function Test.Run<Input, Output>(self: Suite<Input, Output>, onReport: ((Report) -> ())?): Report
	local report = self:Report()
	local failures = {}

	if onReport then
		onReport(report)
	end

	for _, result in report.Results do
		if not result.Success then
			table.insert(failures, result.Name .. ": " .. (result.Error or "failed"))
		end
	end

	assert(report.Success, report.Name .. "\n" .. table.concat(failures, "\n"))

	return report
end

return Test
