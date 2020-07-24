-- scala file interpreter

local Ratio = include 'lib/ratio'

local function parse_cents(value)
	value = tonumber(value)
	if value == nil then
		error('bad cent value: ' .. value)
	end
	value = value / 1200
	return Ratio.new(math.pow(2, value))
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
	return Ratio.new(num, den)
end

function read_scala_file(path)
	if not util.file_exists(path) then
		error('missing file')
	end
	local desc = nil
	local length = 0
	local expected_length = 0
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
						ratio = parse_cents(value)
					else
						ratio = parse_ratio(value)
					end
					ratios[length] = ratio
				end
			end
		end
	end
	-- if the stated length doesn't match the number of pitches, then something went wrong
	if length ~= expected_length then
		error('length mismatch', length, expected_length)
	end
	return ratios, desc
end

return read_scala_file
