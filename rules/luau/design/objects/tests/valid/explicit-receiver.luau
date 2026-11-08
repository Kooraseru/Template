const Session = {}
type Session = setmetatable<{}, typeof(Session)>
function Session.Close(self: Session)
	print(self)
end
function Session.new()
	return setmetatable({}, Session)
end
return Session
