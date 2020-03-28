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
	instance.edit_mask = mask
	instance:apply_edit_mask()
	return instance
end

function Scale:init(pitch_class_values)
	self.length = #pitch_class_values
	self.pitch_class_values = pitch_class_values
	-- precalculate all pitch values across all octaves
	self.center_pitch_id = n_values / 2
	self.values = {}
	local pitch_class = 1
	local octave = 0
	for p = 0, self.center_pitch_id do
		self.values[p + self.center_pitch_id + 1] = self.pitch_class_values[pitch_class] + octave
		self.values[self.center_pitch_id - p] = self.pitch_class_values[self.length - pitch_class + 1] - octave - 1
		pitch_class = pitch_class + 1
		if pitch_class > self.length then
			pitch_class = 1
			octave = octave + 1
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
	self.mask = self:copy_mask(mask)
	self:update_mask_pitch_ids()
end

function Scale:get_edit_mask()
	return self:copy_mask(self.edit_mask)
end

function Scale:set_edit_mask(mask)
	self.edit_mask = self:copy_mask(mask)
end

function Scale:apply_edit_mask()
	self:set_mask(self.edit_mask)
end

function Scale:update_mask_pitch_ids()
	local i = 1
	self.mask_pitch_ids = {}
	for p = 1, n_values do
		if self.mask[(p - 1) % self.length + 1] then
			self.mask_pitch_ids[i] = p
			i = i + 1
		end
	end
	self.n_mask_pitches = i - 1
end

function Scale:get_pitch_class(pitch_id)
	return (pitch_id - 1) % self.length + 1
end

function Scale:mask_contains(pitch_id)
	return self.mask[self:get_pitch_class(pitch_id)]
end

function Scale:edit_mask_contains(pitch_id)
	return self.edit_mask[self:get_pitch_class(pitch_id)]
end

function Scale:set_class(pitch_id, enable)
	self.edit_mask[self:get_pitch_class(pitch_id)] = enable
end

function Scale:toggle_class(pitch_id)
	local pitch_class = self:get_pitch_class(pitch_id)
	self.edit_mask[pitch_class] = not self.edit_mask[pitch_class]
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
		return self.mask_pitch_ids[i] ~= null and self.values[self.mask_pitch_ids[i]] or 2
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

return Scale
