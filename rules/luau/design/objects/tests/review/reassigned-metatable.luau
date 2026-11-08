local Session = {}
Session = getExternalSession()

function Session:Close()
	self.closed = true
end

return setmetatable({}, Session)
