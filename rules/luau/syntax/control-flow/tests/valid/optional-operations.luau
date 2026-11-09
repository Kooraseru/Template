local function publishIfReady(ready: boolean, publish: (string) -> ()): ()
	if ready then
		publish("ready")
		publish("finished")
	end
end

return publishIfReady
