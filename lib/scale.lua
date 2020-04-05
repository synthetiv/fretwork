-- quantization code owes a lot to Emilie Gillet's code for Braids:
-- https://github.com/pichenettes/eurorack/blob/master/braids/quantizer.cc

local Scale = {}
Scale.__index = Scale

local n_values = 128

function Scale.new(pitch_class_values)
	local instance = setmetatable({}, Scale)
	instance:init(pitch_class_values)
	-- enable all notes
	local mask = {}
	for p = 1, instance.length do
		mask[p] = true
	end
	instance:set_mask(mask)
	return instance
end

function Scale:init(pitch_class_values)
	self.length = #pitch_class_values
	self.span = pitch_class_values[#pitch_class_values]
	-- precalculate all pitch values across all octaves
	self.center_pitch_id = n_values / 2
	self.values = {}
	local pitch_class = 1
	local span = 0
	for p = 0, self.center_pitch_id do
		self.values[self.center_pitch_id + p + 1] = pitch_class_values[pitch_class] + span * self.span
		self.values[self.center_pitch_id - p] = pitch_class_values[self.length - pitch_class + 1] - (span + 1) * self.span
		pitch_class = pitch_class + 1
		if pitch_class > self.length then
			pitch_class = 1
			span = span + 1
		end
	end
end

function Scale:copy_mask(mask)
	local copy = {}
	for p = 1, self.length do
		copy[p] = mask[p] or false
	end
	return copy
end

function Scale:set_mask(mask)
	self.next_mask = self:copy_mask(mask)
	self.mask = self:copy_mask(mask)
	self:update_mask_pitch_ids()
end

function Scale:get_next_mask()
	return self:copy_mask(self.next_mask)
end

function Scale:set_next_mask(mask)
	self.next_mask = self:copy_mask(mask)
end

function Scale:apply_edits()
	self:set_mask(self.next_mask)
end

function Scale:update_mask_pitch_ids()
	local i = 1
	self.mask_pitch_ids = {}
	for p = 1, n_values do
		if self:mask_contains(p) then
			self.mask_pitch_ids[i] = p
			i = i + 1
		end
	end
	self.n_mask_pitches = i - 1
end

function Scale:get_pitch_class(pitch_id)
	return (pitch_id - self.center_pitch_id) % self.length + 1
end

function Scale:mask_contains(pitch_id)
	return self.mask[self:get_pitch_class(pitch_id)]
end

function Scale:next_mask_contains(pitch_id)
	return self.next_mask[self:get_pitch_class(pitch_id)]
end

function Scale:set_class(pitch_id, enable)
	self.next_mask[self:get_pitch_class(pitch_id)] = enable
end

function Scale:toggle_class(pitch_id)
	local pitch_class = self:get_pitch_class(pitch_id)
	self.next_mask[pitch_class] = not self.next_mask[pitch_class]
end

local function binary_search(first, last, v, predicate)
	local i = 1
	local j = 1
	local step = 0
	local count = last - first
	while count > 0 do
		step = math.floor(count / 2)
		i = j + step
		if predicate(i, v) then
			count = step
		else
			j = i + 1
			count = count - step - 1
		end
	end
	return j
end

local function get_nearest(last, v, predicate)
	local first = last - 2
	local best_distance = 2 -- octaves; distances between pitch classes certainly ought to be smaller than this
	local j = first
	for i = first, last do
		local distance = math.abs(v - predicate(i))
		if distance < best_distance then
			best_distance = distance
			j = i
		end
	end
	return j
end

function Scale:get_nearest_pitch_id(value)
	local pitch_id = binary_search(1, n_values, value, function(i, v)
		return self.values[i] > value
	end)
	pitch_id = get_nearest(pitch_id, value, function(i)
		return self.values[i] or 2
	end)
	return pitch_id
end

function Scale:get_nearest_mask_pitch_id(value)
	if self.n_mask_pitches == 0 then
		return -1
	end
	local mask_pitch_id = binary_search(1, self.n_mask_pitches, value, function(i, v)
		return self.values[self.mask_pitch_ids[i]] > value
	end)
	mask_pitch_id = get_nearest(mask_pitch_id, value, function(i)
		return self.mask_pitch_ids[i] ~= nil and self.values[self.mask_pitch_ids[i]] or 2
	end)
	return self.mask_pitch_ids[mask_pitch_id]
end

function Scale:get(pitch_id)
	return self.values[pitch_id]
end

function Scale:snap(value)
	local nearest_mask_pitch_id = self:get_nearest_mask_pitch_id(value)
	if nearest_mask_pitch_id == -1 then
		return value
	end
	return self:get(nearest_mask_pitch_id)
end

function Scale:mask_to_pitches(mask)
	local pitches = {}
	for class = 1, self.length do
		if mask[class] then
			table.insert(pitches, self:get(self.center_pitch_id + class - 1))
		end
	end
	return pitches
end

function Scale:pitches_to_mask(pitches)
	local mask = {}
	for class = 1, self.length do
		mask[class] = false
	end
	for i, pitch in ipairs(pitches) do
		local pitch_id = self:get_nearest_pitch_id(pitch)
		local class = self:get_pitch_class(pitch_id)
		mask[class] = true
	end
	return mask
end

function Scale.parse_cents(value)
	value = tonumber(value)
	if not value then
		return nil
	end
	return value / 1200
end

function Scale.parse_ratio(value)
	-- get numerator
	local num, den = string.match(value, '^(.+)/(.+)$')
	if num == nil then
		-- no /? read whole value as a number
		num = tonumber(value)
		if value == nil then
			return nil
		end
		den = 1
	else
		num = tonumber(num)
		den = tonumber(den)
		if den == nil or num == nil then
			return nil
		end
	end
	return math.log(num / den) / math.log(2)
end

-- switch to new scale values, preserving the current mask as much as possible
function Scale:reinit(pitches)
	local mask_pitches = self:mask_to_pitches(self.mask)
	self:init(pitches)
	self:set_mask(self:pitches_to_mask(mask_pitches))
end

function Scale:read_scala_file(path)
	print('reading scala file', path)
	local file = io.open(path, 'r')
	if file == nil then
		print('missing file')
		return
	end
	local desc = nil
	local length = 0
	local pitches = {}
	for line in io.lines(path) do
		line = string.gsub(line, '\r', '') -- trim pesky CR characters that make debugging a pain
		if string.sub(line, 1, 1) == '!' then
			print('comment', string.sub(line, 1, -1))
		else
			if desc == nil then
				desc = line
				print('set desc', desc)
			else
				local value = string.match(line, '(%S+)')
				if length == 0 then
					length = tonumber(value)
					print('set length', length)
					if length == nil then
						print('bad length', value)
						return
					end
				else
					if string.find(value, '%.') ~= nil then
						value = self.parse_cents(value)
					else
						value = self.parse_ratio(value)
					end
					if value == nil then
						print('bad value', value)
						return
					end
					if #pitches > 0 and value <= pitches[#pitches] then
						print('non-ascending value')
						return
					end
					table.insert(pitches, value)
				end
			end
		end
	end
	if #pitches ~= length then
		print('length mismatch')
		return
	end
	print('ok')
	tab.print(pitches)
	self:reinit(pitches)
end

return Scale
