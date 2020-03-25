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
	self.pitch_class_values = pitch_class_values
	-- precalculate all pitch values across all octaves
	self.center_pitch = n_values / 2
	self.values = {}
	local pitch_class = 1
	local octave = 0
	for p = 0, self.center_pitch do
		self.values[p + self.center_pitch + 1] = self.pitch_class_values[pitch_class] + octave
		self.values[self.center_pitch - p] = self.pitch_class_values[self.length - pitch_class + 1] - octave - 1
		pitch_class = pitch_class + 1
		if pitch_class > self.length then
			pitch_class = 1
			octave = octave + 1
		end
	end
end

function Scale:set_mask(mask)
	self.mask = {}
	for p = 1, self.length do
		self.mask[p] = mask[p] or false
	end
	self:update_mask_pitches()
end

function Scale:update_mask_pitches()
	local i = 1
	self.mask_pitches = {}
	for p = 1, n_values do
		if self.mask[(p - 1) % self.length + 1] then
			self.mask_pitches[i] = p
			i = i + 1
		end
	end
	self.n_mask_pitches = i - 1
	local enabled_pitches = 0
	for p = 1, self.length do
		if self.mask[p] then
			enabled_pitches = enabled_pitches + 1
		end
	end
	self.n_enabled_pitches = enabled_pitches
end

function Scale:get_mask()
	local mask = {}
	for n = 1, self.length do
		mask[n] = self.mask[n]
	end
	return mask
end

function Scale:get_pitch_class(pitch)
	return (pitch - 1) % self.length + 1
end

function Scale:contains(pitch)
	return self.mask[self:get_pitch_class(pitch)]
end

function Scale:set_class(pitch, enable)
	self.mask[self:get_pitch_class(pitch)] = enable
	self:update_mask_pitches()
end

function Scale:toggle_class(pitch)
	local pitch_class = self:get_pitch_class(pitch)
	-- don't let the user disable the last remaining pitch
	-- TODO: if we were using z/gates, then this wouldn't have to cause errors -- could just silence all voices
	print(self.n_mask_pitches)
	if self.n_enabled_pitches <= 1 and self.mask[pitch_class] then
		return
	end
	self.mask[pitch_class] = not self.mask[pitch_class]
	self:update_mask_pitches()
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

function Scale:get_nearest_pitch(value)
	local pitch = binary_search(1, n_values, value, function(i, v)
		return self.values[i] > value
	end)
	pitch = get_nearest(pitch, value, function(i)
		return self.values[i] or 2
	end)
	return pitch
end

function Scale:get_nearest_mask_pitch(value)
	local mask_pitch = binary_search(1, self.n_mask_pitches, value, function(i, v)
		return self.values[self.mask_pitches[i]] > value
	end)
	mask_pitch = get_nearest(mask_pitch, value, function(i)
		return self.mask_pitches[i] ~= null and self.values[self.mask_pitches[i]] or 2
	end)
	return self.mask_pitches[mask_pitch]
end

function Scale:get(pitch)
	return self.values[pitch]
end

function Scale:snap_raw(value)
	return self:get(self:get_nearest_pitch(value))
end

function Scale:snap(value)
	return self:get(self:get_nearest_mask_pitch(value))
end

return Scale
