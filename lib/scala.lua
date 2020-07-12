-- scala file interpreter

local log2 = math.log(2)

local function parse_cents(value)
	value = tonumber(value)
	if value == nil then
		error('bad cent value: ' .. value)
	end
	value = value / 1200
	return value, math.pow(2, value), 1
end

local function parse_ratio(value)
	-- get numerator
	local num, den = string.match(value, '^(.+)/(.+)$')
	if num == nil then
		-- no /? read whole value as a number
		num = tonumber(value)
		if value == nil then
			error('bad ratio value: ' .. value)
		end
		den = 1
	else
		num = tonumber(num)
		den = tonumber(den)
		if den == nil or num == nil then
			error('bad ratio value: ' .. value)
		end
	end
	return math.log(num / den) / log2, num, den
end

function read_scala_file(path)
	if not util.file_exists(path) then
		error('missing file')
	end
	local desc = nil
	local length = 0
	local expected_length = 0
	local pitches = {}
	local ratios = {}
	for line in io.lines(path) do
		line = string.gsub(line, '\r', '') -- trim pesky CR characters that make debugging a pain
		if string.sub(line, 1, 1) ~= '!' then -- ignore comments
			if desc == nil then
				-- first line is a description of the scale
				desc = line
			else
				local value = string.match(line, '(%S+)')
				local num = 1
				local den = 1
				if expected_length == 0 then
					-- second line is the number of pitches
					expected_length = tonumber(value)
					if expected_length == nil then
						error('bad length: ' .. value)
					end
				else
					-- everything else is a pitch
					length = length + 1
					if string.find(value, '%.') ~= nil then
						value, num, den = parse_cents(value)
					else
						value, num, den = parse_ratio(value)
					end
					pitches[length] = value
					ratios[length] = { num, den }
				end
			end
		end
	end
	-- if the stated length doesn't match the number of pitches, then something went wrong
	if length ~= expected_length then
		error('length mismatch', length, expected_length)
	end
	-- enforce low -> high pitch order, or scale.lua's quantization won't work
	table.sort(pitches)
	return pitches, ratios, length, desc
end

return read_scala_file
