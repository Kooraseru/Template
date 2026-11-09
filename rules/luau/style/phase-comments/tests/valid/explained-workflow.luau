local function summarize(entries: { number }): number
	local total = 0
	local positive = 0
	local negative = 0
	local minimum = math.huge
	local maximum = -math.huge
	local squares = 0
	local zeros = 0
	local count = #entries
	local offset = entries[1] or 0
	local adjustedTotal = 0

	--[=[
	Accumulate all metrics in one pass because the caller may supply a large list.
	]=]
	for _, entry in entries do
		total += entry
		minimum = math.min(minimum, entry)
		maximum = math.max(maximum, entry)
		squares += entry * entry
		adjustedTotal += entry - offset
		if entry > 0 then
			positive += 1
		elseif entry < 0 then
			negative += 1
		else
			zeros += 1
		end
	end

	-- Report a neutral spread for an empty input instead of subtracting infinities.
	local spread = if count == 0 then 0 else maximum - minimum
	local balance = positive - negative
	return total + adjustedTotal + squares + spread + zeros + balance
end

return summarize
