-- quantization code owes a lot to Emilie Gillet's code for Braids:
-- https://github.com/pichenettes/eurorack/blob/master/braids/quantizer.cc

local read_scala_file = include 'lib/scala'

local Scale = {}
Scale.__index = Scale

local n_values = 128
local center_pitch_id = n_values / 2

function Scale.new(pitch_class_values, length)
	local instance = setmetatable({}, Scale)
	instance.values = {}
	instance:init(pitch_class_values, length)
	instance:update_mask_pitch_ids()
	return instance
end

function Scale:init(pitch_class_values, length)
	-- precalculate all pitch values across all octaves
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

function Scale:mask_to_pitches()
	local pitches = {}
	local mask = self.next_mask
	for class = 1, self.length do
		if mask[class] then
			table.insert(pitches, self.values[self.center_pitch_id + class - 1])
		end
	end
	return pitches
end

function Scale:mask_from_pitches(pitches)
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

function Scale:read_scala_file(path)
	-- read the file
	local pitch_class_values, length, desc = read_scala_file(path)
	-- save current mask pitches
	local mask_pitches = self:mask_to_pitches(self.mask)
	-- set scale values
	self:init(pitch_class_values, length)
	-- reset mask to match old pitches as closely as possible
	self:mask_from_pitches(mask_pitches)
	-- announce ourselves
	print(desc)
end

Scale.n_values = n_values
Scale.center_pitch_id = center_pitch_id
return Scale
