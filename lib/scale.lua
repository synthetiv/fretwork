-- quantization code owes a lot to Emilie Gillet's code for Braids:
-- https://github.com/pichenettes/eurorack/blob/master/braids/quantizer.cc

local Scale = {}
Scale.__index = Scale

local n_values = 128
local center_pitch_id = n_values / 2

--- create a new Scale
-- @param class_values table of pitch class values (1.0 = 1200 cents)
function Scale.new(class_values)
	local scale = setmetatable({}, Scale)
	scale.values = {}
	scale.classes_active = {}
	scale.next_classes_active = {}
	scale.active_values = { 0 } -- just the root note
	scale:set_class_values(class_values)
	return scale
end

--- update scale to a new set of pitch class values, and calculate values across all spans
-- @param class_values table of pitch class values
function Scale:set_class_values(class_values)
	local length = #class_values
	local span = class_values[length]
	local values = self.values
	local class = 1
	local current_span = 0
	for p = 0, center_pitch_id do
		values[center_pitch_id + p + 1] = class_values[class] + current_span * span
		values[center_pitch_id - p] = class_values[length - class + 1] - (current_span + 1) * span
		class = class + 1
		if class > length then
			class = 1
			current_span = current_span + 1
		end
	end
	self.class_values = class_values
	self.length = length
	self.span = span
	self:set_active_values()
	self:apply_edits()
end

--- set next active pitch classes to match a table of values
-- values not found in the scale will be quantized, so this function can be used to find a scale's
-- closest approximation of any chord or set of pitches
-- @param active_values table of active values (current active values table will be used if omitted)
function Scale:set_active_values(active_values)
	if active_values == nil then
		active_values = self.active_values
	else
		self.active_values = active_values
	end
	local classes_active = self.next_classes_active
	-- first, reset all classes to inactive
	-- (note: if scale length has previously been greater than it is now, there may be junk values at
	-- the end of this table at indexes > self.length, but that doesn't matter)
	for class = 1, self.length do
		classes_active[class] = false
	end
	-- loop over provided values and set nearest pitch classes to active
	for i, value in ipairs(active_values) do
		local pitch_id = self:get_nearest_pitch_id(value)
		local class = self:get_class(pitch_id)
		classes_active[class] = true
	end
end

--- get a table of active pitch class values to match next_classes_active
-- @return table of pitch class values
function Scale:get_active_values()
	local active_values = {}
	local i = 1
	for class, is_active in ipairs(self.next_classes_active) do
		if is_active then
			active_values[i] = self.class_values[(class - 2) % self.length + 1]
			i = i + 1
		end
	end
	return active_values
end

--- update currently active pitch classes to match next_classes_active
function Scale:apply_edits()
	-- match classes_active to next_classes_active
	local next_classes_active = self.next_classes_active
	local classes_active = self.classes_active
	for i = 1, self.length do
		classes_active[i] = next_classes_active[i]
	end
	-- update table of all active pitch ids
	local active_pitch_ids = {}
	local i = 1
	for p = 1, n_values do
		if self:is_pitch_id_active(p) then
			active_pitch_ids[i] = p
			i = i + 1
		end
	end
	self.active_pitch_ids = active_pitch_ids
	-- update count of active pitch ids
	self.n_active_pitch_ids = i - 1
end

--- get the pitch class of a pitch id
-- @param pitch_id pitch id from 1 to n_values
-- @return pitch class from 1 to self.length
function Scale:get_class(pitch_id)
	return (pitch_id - self.center_pitch_id) % self.length + 1
end

--- check whether a pitch id is currently active
-- @param pitch_id pitch id from 1 to n_values
-- @return true if active, false if not
function Scale:is_pitch_id_active(pitch_id)
	return self.classes_active[self:get_class(pitch_id)]
end

--- check whether a pitch id will be active after apply_edits() is called
-- @param pitch_id pitch id from 1 to n_values
-- @return true if pitch will be active, false if not
function Scale:is_pitch_id_next_active(pitch_id)
	return self.next_classes_active[self:get_class(pitch_id)]
end

--- activate/deactivate a pitch id (and all pitches in its pitch class)
-- @param pitch_id a pitch id from 1 to n_values
-- @enable true to activate, false to deactivate
function Scale:set_class_active(pitch_id, enable)
	self.next_classes_active[self:get_class(pitch_id)] = enable
	self.active_values = self:get_active_values()
end

--- toggle active status of a pitch id (and all pitches in its pitch class)
-- @param pitch_id a pitch id from 1 to n_values
function Scale:toggle_class(pitch_id)
	local class = self:get_class(pitch_id)
	self.next_classes_active[class] = not self.next_classes_active[class]
	self.active_values = self:get_active_values()
end

--- find the closest pitch id to a given value, ignoring active/inactive status of pitches
-- @param value pitch value (1.0 = 1200 cents)
-- @return pitch id from 1 to n_values
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
	end
	return upper_id
end

--- find the closest active pitch id to a given value
-- @param value pitch value (1.0 = 1200 cents)
-- @return pitch id from 1 to n_values
function Scale:get_nearest_active_pitch_id(value)
	if self.n_active_pitch_ids == 0 then
		return -1
	end
	local values = self.values
	local active_pitch_ids = self.active_pitch_ids
	local upper_id = 2
	local next_id = 2
	local jump_size = 0
	local n_remaining = self.n_active_pitch_ids - 2
	while n_remaining > 0 do
		jump_size = math.floor(n_remaining / 2)
		next_id = upper_id + jump_size
		if values[active_pitch_ids[next_id]] > value then
			n_remaining = jump_size
		else
			upper_id = next_id + 1
			n_remaining = n_remaining - jump_size - 1
		end
	end
	local lower_id = active_pitch_ids[upper_id - 1]
	upper_id = active_pitch_ids[upper_id]
	if math.abs(value - values[lower_id]) < math.abs(value - values[upper_id]) then
		return lower_id
	end
	return upper_id
end

--- quantize a pitch value to the nearest active pitch
-- note: if no pitches are active, no quantization is applied
-- @param value pitch value (1.0 = 1200 cents)
-- @return quantized pitch value (1.0 = 1200 cents)
function Scale:snap(value)
	local pitch_id = self:get_nearest_active_pitch_id(value)
	if pitch_id == -1 then
		return value
	end
	return self.values[pitch_id]
end

Scale.n_values = n_values
Scale.center_pitch_id = center_pitch_id
return Scale
