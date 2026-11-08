-- global-rules/languages/luau/structures/oop/examples/StagedObject.luau
--!strict

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

function Session.Close(self: Session): ()
	for _, hook in self.Hooks do
		hook()
	end

	self.Resource:Close()
end

return Session
