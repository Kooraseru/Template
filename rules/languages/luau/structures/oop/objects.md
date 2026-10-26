# OOP Objects

This document applies to project-owned, metatable-backed objects with
independently constructed instances.

It does not apply to return-function modules, plain table modules, ECS
components, ECS systems, data modules, entry points, or engine-owned Roblox
objects.

Use OOP when the file needs to preserve instance identity: a widget owns a root
frame, a controller owns connections, or a runtime object needs a clear destroy
path. Do not use it just to group functions under a nice name.

## Constructor Strategy

Constructor shape is a decision, not ceremony.

Use fields-first construction when all required fields are known before the instance needs to exist:

```luau
type LoadingScreenFields = {
	Gui: ScreenGui,
}

export type LoadingScreen = setmetatable<LoadingScreenFields, typeof(LoadingScreen)>

function LoadingScreen.new(playerGui: PlayerGui): LoadingScreen
	local fields: LoadingScreenFields = {
		Gui = findExistingGui(playerGui) or createGui(playerGui),
	}

	return setmetatable(fields, LoadingScreen)
end
```

For staged setup, create a complete typed fields record with optional fields or
an explicit lifecycle state. Do not cast an empty table to the final object
type.

```luau
local Widget = {}
Widget.__index = Widget

type WidgetFields = {
	Root: Frame,
	Connections: { RBXScriptConnection },
}

export type Widget = setmetatable<WidgetFields, typeof(Widget)>

function Widget.new(): Widget
	local fields: WidgetFields = {
		Root = Instance.new("Frame"),
		Connections = {},
	}
	return setmetatable(fields, Widget)
end
```

Prefer fields-first construction. Represent values that become available later
with optional fields or explicit lifecycle state.

Do not inline a populated field table inside `setmetatable`. Use one of the
established construction shapes.

Fields-first:

```luau
local fields: WidgetFields = {
	Root = createRoot(),
	Connections = {},
}

local self = setmetatable(fields, Widget)
```


## Method Declarations

Declare project-owned receiver methods with dot syntax and explicit `self`:

```luau
function Widget.Destroy(self: Widget)
	self.Root:Destroy()
end
```

Call concrete receiver methods with colon syntax:

```luau
widget:Destroy()
```

This keeps receiver typing explicit while preserving normal call ergonomics.

Roblox APIs and engine objects keep their native colon-call shape.

Do not use a metatable-derived concrete instance type as a shared
cross-implementation interface. Shared abstractions should use an explicit
structural contract.
