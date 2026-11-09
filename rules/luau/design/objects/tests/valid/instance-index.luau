const Session = {}
Session.__index = Session
function Session.new()
	return setmetatable({}, Session)
end
return Session
