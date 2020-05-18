local function sine_sequence(length, amp)
	local amp = amp * length / 24
	local step = math.pi * 2 / length
	local pattern = {}
	for i = 1, length do
		pattern[i] = math.sin(i * step) * amp
	end
	return pattern
end

return sine_sequence
