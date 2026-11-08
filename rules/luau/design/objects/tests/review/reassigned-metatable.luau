type SessionState = {
	closed: boolean,
	Close: ((SessionState) -> ())?,
}

local function getExternalSession(): SessionState
	return { closed = false }
end

local Session: SessionState = { closed = false }
Session = getExternalSession()

function Session:Close()
	self.closed = true
end

return setmetatable({}, Session)
