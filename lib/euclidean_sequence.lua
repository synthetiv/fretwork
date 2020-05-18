local function euclidean_sequence(fill, length)
	local pattern = {}
	-- initialize pattern with all 1s at start
	for i = 1, length do
		pattern[i] = { i <= fill and 1 or -1 }
	end
	-- distribute sequences from end of pattern to beginning
	while fill > 1 do
		local cut = math.min(fill, #pattern - fill)
		for i = 1, cut do
			-- append last sequence to an earlier sequence
			for j, v in ipairs(pattern[#pattern]) do
				pattern[i][#pattern[i] + 1] = v
			end
			-- remove last sequence
			pattern[#pattern] = nil
		end
		fill = cut
	end
	-- flatten 
	local flat = {}
	local j = 1
	local k = 0
	for i = 1, length do
		k = k + 1
		if pattern[j][k] == nil then
			j = j + 1
			k = 1
		end
		flat[#flat + 1] = pattern[j][k]
	end
	return flat
end

return euclidean_sequence
