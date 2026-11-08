# OOP Objects

This document applies to project-owned, metatable-backed objects with independently constructed instances.

It does not apply to return-function modules, plain table modules, ECS components, ECS systems, data modules, entry points, or objects owned by external APIs.

Use OOP when the file needs to preserve instance identity: a session owns a resource, a controller owns callbacks, or a runtime object needs a clear teardown path. Do not use it just to group functions under a nice name.

## Constructor Strategy

Constructor shape is a decision, not ceremony.

Use fields-first construction when all required fields are known before the instance needs to exist:

```luau
type Resource = {
	Close: (self: Resource) -> (),
}

const Session = {}
Session.__index = Session

type SessionFields = {
	Resource: Resource,
}

export type Session = setmetatable<SessionFields, typeof(Session)>

function Session.new(resource: Resource): Session
	const fields: SessionFields = {
		Resource = resource,
	}

	return setmetatable(fields, Session)
end
```

Use incremental `self` when setup is staged, conditional, cyclic, or callback/helper driven:

```luau
type Resource = {
	Close: (self: Resource) -> (),
}

const Session = {}
Session.__index = Session

type SessionFields = {
	Resource: Resource,
	Hooks: { () -> () },
}

export type Session = setmetatable<SessionFields, typeof(Session)>

function Session.new(factory: () -> Resource): Session
	const self = setmetatable({}, Session) :: Session

	self.Hooks = {}
	self.Resource = factory()

	return self
end
```

Use one constructor-boundary cast only when construction order genuinely needs it. Do not use call-site casts to compensate for constructor typing.

Prefer fields-first construction when possible. Use empty-table incremental construction when the instance is built out step by step.

Do not inline a populated field table inside `setmetatable`. Use one of the established construction shapes. The [instance-construction validator](../../../../../rules/luau/design/objects/README.md) checks this for named fields and a local metatable binding.

Fields-first:

```luau
const fields: SessionFields = {
	Resource = resource,
	Hooks = {},
}

const self = setmetatable(fields, Session)
```

Empty-table staged:

```luau
const self = setmetatable({}, Session) :: Session
self.Hooks = {}
self.Resource = factory()
```

The empty-table staged form is less type-safe. Keep the cast at the constructor boundary and do not spread it to callers.

## Method Declarations

Declare project-owned receiver methods with dot syntax and explicit `self`:

```luau
function Session.Close(self: Session): ()
	self.Resource:Close()
end
```

Call concrete receiver methods with colon syntax:

```luau
session:Close()
```

This keeps receiver typing explicit while preserving normal call ergonomics.

External APIs keep their documented call conventions even when they differ from project-owned methods.

Do not use a metatable-derived concrete instance type as a shared cross-implementation interface. Shared abstractions should use an explicit structural contract.
