local function consume(values: { number }, publish: (number) -> ()): ()
	local total = 0
	for _, value in values do
		if value > 0 then
			total += value
			publish(total)
		else
			break
		end
	end
end

return consume
