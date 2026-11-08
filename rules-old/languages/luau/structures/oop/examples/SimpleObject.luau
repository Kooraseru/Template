-- global-rules/languages/luau/structures/oop/examples/SimpleObject.luau
--!strict

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

function Session.Close(self: Session): ()
	self.Resource:Close()
end

return Session
