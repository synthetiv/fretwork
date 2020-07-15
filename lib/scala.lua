-- scala file interpreter

local log2 = math.log(2)

local cf = {}
function continue_fraction(f, term)
	local i = math.floor(f) + 0.0
	if term == nil then
		term = 1
	else
		term = term + 1
	end
	-- convert int to float, otherwise goofy stuff happens later when we start multiplying large ints
	cf[term] = i + 0.0
	f = f - i
	-- TODO: find a sensible precision threshold that will keep rational approximations within, say,
	-- 1/100th of a cent of original cent values
	if f < 0.0001 or term > 16383 then
		return cf, term
	end
	return continue_fraction(1 / f, term)
end

function rationalize(f)
	local cf, term = continue_fraction(f, 0)
	local num = cf[term] + 0.0
	local den = 1.0
	term = term - 1
	while term > 0 do
		num, den = den, num
		num = num + cf[term] * den
		-- if we hit inf anywhere, consider this an irrational number
		if num == math.huge or den == math.huge then
			return f, 1.0
		end
		term = term - 1
	end
	local diff = f - (num / den)
	if math.abs(diff) ~= 0.0 then
		print(string.format('rationalization imperfect: %f - %f/%f = %f', f, num, den, diff))
		return f, 1.0
	end
	return num, den
end

local function parse_cents(value)
	value = tonumber(value)
	if value == nil then
		error('bad cent value: ' .. value)
	end
	value = value / 1200
	print(value)
	local num, den = rationalize(math.pow(2, value))
	return value, num, den
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
					ratios[length] = {
						num = num,
						den = den
					}
				end
			end
		end
	end
	-- if the stated length doesn't match the number of pitches, then something went wrong
	if length ~= expected_length then
		error('length mismatch', length, expected_length)
	end
	return pitches, ratios, desc
end

return read_scala_file
