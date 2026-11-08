const Session = {}
Session.__index = Session

function Session.Close(session)
	session.closed = true
end

function Session.new()
	return setmetatable({}, Session)
end

return Session
