-- repo/ci/preflight/providers/lune/graph.luau
--!strict

-- A directed graph of imports and planned component execution edges.
local Graph = {}
Graph.__index = Graph

type Edge = { target: string, kind: string }
type Fields = { edges: { [string]: { Edge } } }

export type Graph = setmetatable<Fields, typeof(Graph)>

function Graph.new(): Graph
	local fields: Fields = { edges = {} }
	return setmetatable(fields, Graph)
end

function Graph.AddNode(self: Graph, path: string): ()
	if not self.edges[path] then
		self.edges[path] = {}
	end
end

function Graph.AddEdge(self: Graph, source: string, target: string, kind: string): ()
	self:AddNode(source)
	self:AddNode(target)
	for _, edge in self.edges[source] do
		if edge.target == target and edge.kind == kind then
			return
		end
	end
	table.insert(self.edges[source], { target = target, kind = kind })
end

function Graph.Reachable(self: Graph, roots: { string }): { [string]: { string } }
	local paths: { [string]: { string } } = {}
	local queue: { string } = {}
	for _, root in roots do
		if not paths[root] then
			paths[root] = { root }
			table.insert(queue, root)
		end
	end

	local cursor = 1
	while cursor <= #queue do
		local source = queue[cursor]
		cursor += 1
		for _, edge in self.edges[source] or {} do
			if not paths[edge.target] then
				local trace: { string } = {}
				for _, path in paths[source] do
					table.insert(trace, path)
				end
				table.insert(trace, edge.target)
				paths[edge.target] = trace
				table.insert(queue, edge.target)
			end
		end
	end
	return paths
end

return Graph
