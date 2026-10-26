-- structures/oop: SimpleObject.luau
--!strict

local Widget = {}
Widget.__index = Widget

type Root = {
	Destroy: (self: Root) -> (),
}

type WidgetFields = {
	Root: Root,
}

export type Widget = setmetatable<WidgetFields, typeof(Widget)>

function Widget.new(root: Root): Widget
	local fields: WidgetFields = {
		Root = root,
	}

	return setmetatable(fields, Widget)
end

function Widget.Destroy(self: Widget)
	self.Root:Destroy()
end

return Widget
