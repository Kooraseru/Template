-- structures/oop: StagedObject.luau
--!strict

local Widget = {}
Widget.__index = Widget

type Root = {
	Destroy: (self: Root) -> (),
}

type Connection = {
	Disconnect: (self: Connection) -> (),
}

type WidgetFields = {
	Root: Root,
	Connections: { Connection },
}

export type Widget = setmetatable<WidgetFields, typeof(Widget)>

function Widget.new(root: Root, connections: { Connection }): Widget
	local fields: WidgetFields = {
		Root = root,
		Connections = connections,
	}
	return setmetatable(fields, Widget)
end

function Widget.Destroy(self: Widget)
	for _, connection in self.Connections do
		connection:Disconnect()
	end

	self.Root:Destroy()
end

return Widget
