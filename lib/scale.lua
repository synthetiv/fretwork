-- quantization code owes a lot to Emilie Gillet's code for Braids:
-- https://github.com/pichenettes/eurorack/blob/master/braids/quantizer.cc

local read_scala_file = include 'lib/scala'

local Scale = {}
Scale.__index = Scale

local n_values = 128
local center_pitch_id = n_values / 2

local log2 = math.log(2)

function Scale.new(pitch_class_values, length)
	local instance = setmetatable({}, Scale)
	instance.values = {}
	instance.pitch_class_values = pitch_class_values
	instance.length = length
	instance:init()
	instance:update_mask_pitch_ids()
	return instance
end

function Scale:init()
	-- precalculate all pitch values across all octaves
	local pitch_class_values = self.pitch_class_values
	local length = self.length
	local values = self.values
	local span = pitch_class_values[length]
	local pitch_class = 1
	local current_span = 0
	for p = 0, center_pitch_id do
		values[center_pitch_id + p + 1] = pitch_class_values[pitch_class] + current_span * span
		values[center_pitch_id - p] = pitch_class_values[length - pitch_class + 1] - (current_span + 1) * span
		pitch_class = pitch_class + 1
		if pitch_class > length then
			pitch_class = 1
			current_span = current_span + 1
		end
	end
	-- reinitialize masks, since scale length may have changed
	local mask = {}
	local next_mask = {}
	local p = 1, length do
		mask[p] = false
		next_mask[p] = false
	end
	self.length = length
	self.span = span
	self.mask = mask
	self.next_mask = next_mask
end

function Scale:set_mask(new_mask)
	local mask = self.mask
	for i = 1, self.length do
		mask[i] = new_mask[i]
	end
	self:update_mask_pitch_ids()
end

function Scale:apply_edits()
	self:set_mask(self.next_mask)
end

function Scale:update_mask_pitch_ids()
	local i = 1
	local mask_pitch_ids = {}
	for p = 1, n_values do
		if self:mask_contains(p) then
			mask_pitch_ids[i] = p
			i = i + 1
		end
	end
	self.mask_pitch_ids = mask_pitch_ids
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

function Scale:get_nearest_pitch_id(value)
	local values = self.values
	-- binary search to find the first pitch ID whose value is higher than the one we want
	local upper_id = 2
	local next_id = 2 -- next ID to check (start at 2 because we'll also check one lower value)
	local jump_size = 0 -- size of binary search jump
	local n_remaining = n_values - 2 -- number of IDs left to check
	while n_remaining > 0 do
		jump_size = math.floor(n_remaining / 2)
		next_id = upper_id + jump_size
		if values[next_id] > value then
			n_remaining = jump_size
		else
			upper_id = next_id + 1
			n_remaining = n_remaining - jump_size - 1
		end
	end
	-- check the value below it to see if it's closer than upper_id is
	local lower_id = upper_id - 1
	if math.abs(value - values[lower_id]) < math.abs(value - values[upper_id]) then
		return lower_id
	else
		return upper_id
	end
end

function Scale:get_nearest_mask_pitch_id(value)
	if self.n_mask_pitches == 0 then
		return -1
	end
	local values = self.values
	local mask_pitch_ids = self.mask_pitch_ids
	local upper_id = 2
	local next_id = 2
	local jump_size = 0
	local n_remaining = self.n_mask_pitches - 2
	while n_remaining > 0 do
		jump_size = math.floor(n_remaining / 2)
		next_id = upper_id + jump_size
		if values[mask_pitch_ids[next_id]] > value then
			n_remaining = jump_size
		else
			upper_id = next_id + 1
			n_remaining = n_remaining - jump_size - 1
		end
	end
	local lower_id = mask_pitch_ids[upper_id - 1]
	upper_id = mask_pitch_ids[upper_id]
	if math.abs(value - values[lower_id]) < math.abs(value - values[upper_id]) then
		return lower_id
	else
		return upper_id
	end
end

function Scale:snap(value)
	local nearest_mask_pitch_id = self:get_nearest_mask_pitch_id(value)
	if nearest_mask_pitch_id == -1 then
		return value
	end
	return self.values[nearest_mask_pitch_id]
end

function Scale:get_mask_pitches()
	local pitches = {}
	local mask = self.next_mask
	for class = 1, self.length do
		if mask[class] then
			table.insert(pitches, self.values[self.center_pitch_id + class - 1])
		end
	end
	return pitches
end

function Scale:set_mask_to_pitches(pitches)
	local mask = self.next_mask
	for class = 1, self.length do
		mask[class] = false
	end
	for i, pitch in ipairs(pitches) do
		local pitch_id = self:get_nearest_pitch_id(pitch)
		local class = self:get_pitch_class(pitch_id)
		mask[class] = true
	end
end

local function sort_ratios(a, b)
	if a == nil then
		return false
	elseif b == nil then
		return true
	end
	return a[1] / a[2] < b[1] / b[2]
end

function Scale:sort_ratios()
	table.sort(self.ratios, sort_ratios)
end

function Scale:update_from_ratios()
	local mask_pitches = self:get_mask_pitches()
	local length = 0
	self:sort_ratios()
	for i, r in ipairs(self.ratios) do
		if r ~= nil then
			length = length + 1
		end
		self.pitch_class_values[i] = math.log(r[1] / r[2]) / log2
	end
	self.length = length
	self.span_ratio = self.ratios[self.length]
	self:init()
	self:set_mask_to_pitches(mask_pitches)
end

function Scale:reduce_ratio(ratio)
	local bumper = 1
	local span = self.span_ratio[1] / self.span_ratio[2]
	while ratio[1] / ratio[2] > span do
		print('down', ratio[1], ratio[2])
		ratio[1] = ratio[1] * self.span_ratio[2]
		ratio[2] = ratio[2] * self.span_ratio[1]
		bumper = bumper + 1
		if bumper > 10 then
			print('too many loops down', ratio[1], ratio[2])
			return
		end
	end
	while ratio[2] / ratio[1] > span do
		print('up', ratio[1], ratio[2])
		ratio[1] = ratio[1] * self.span_ratio[1]
		ratio[2] = ratio[2] * self.span_ratio[2]
		bumper = bumper + 1
		if bumper > 10 then
			print('too many loops up', ratio[1], ratio[2])
			return
		end
	end
end

function Scale:set_ratio(pitch_class, num, den)
	local ratio = self.ratios[pitch_class]
	ratio[1] = num
	ratio[2] = den
	self:reduce_ratio(ratio)
	self:update_from_ratios()
end

function Scale:alter_ratio(pitch_class, num, den)
	local ratio = self.ratios[pitch_class]
	self:set_ratio(pitch_class, ratio[1] * num, ratio[2] * den)
end

function Scale:remove_ratio(pitch_class)
	self.ratios[pitch_class] = nil
	-- self.length = self.length - 1
	self:update_from_ratios()
end

function Scale:add_ratio(num, den)
	-- self.length = self.length + 1
	self.ratios[self.length + 1] = { num, den }
	self:update_from_ratios()
end

function Scale:print_ratios()
	for p = 1, self.length do
		local r = self.ratios[p]
		print((self.mask[p] and '* ' or '  ') .. r[1] .. '/' .. r[2])
	end
end

function Scale:read_scala_file(path)
	-- save current mask pitches
	local mask_pitches = self:get_mask_pitches()
	-- read the file
	self.pitch_class_values, self.ratios, self.length, self.desc = read_scala_file(path)
	self:update_from_ratios()
	-- set scale values
	self:init()
	-- reset mask to match old pitches as closely as possible
	self:set_mask_to_pitches(mask_pitches)
	-- announce ourselves
	print(desc)
end

Scale.n_values = n_values
Scale.center_pitch_id = center_pitch_id
return Scale
