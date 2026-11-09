const Session = {}
function Session:Close()
	print(self)
end
function Session.new()
	return setmetatable({}, Session)
end
return Session
