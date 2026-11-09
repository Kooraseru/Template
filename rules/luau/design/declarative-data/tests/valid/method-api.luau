-- global-rules/languages/luau/declarative-data/tests/valid/method-api.luau
--!strict

const Metrics = {}

function Metrics.Record(name: string): ()
	print(name)
end

return Metrics
