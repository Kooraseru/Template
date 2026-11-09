local Session = {}
Session.__index = Session

function Session.Close(self)
	self.closed = true
end

function Session.new()
	return setmetatable({}, Session)
end

return Session
