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
	self:update_mask_values()
end

function Scale:update_mask_values()
	local i = 1
	self.mask_values = {}
	for p = 1, n_values do
		if self.mask[(p - 1) % self.length + 1] then
			self.mask_values[i] = self.values[p]
			i = i + 1
		end
	end
	self.n_mask_values = #self.mask_values
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
	self:update_mask_values()
end

function Scale:toggle_class(pitch)
	local pitch_class = self:get_pitch_class(pitch)
	self.mask[pitch_class] = not self.mask[pitch_class]
	self:update_mask_values()
end

function Scale.ubound(t, v)
	local i = 1
	local next_i = 1
	local step = 0
	local count = #t - 1
	while count > 0 do
		next_i = i
		step = math.floor(count / 2)
		next_i = next_i + step
		print(string.format('count: %d; i: %d; step: %d; next: %d', count, i, step, next_i))
		if t[next_i] <= v then
			print('next <= v')
			i = next_i + 1
			count = count - step - 1
		else
			print('next > v')
			count = step
		end
	end
	return i
end

function Scale:snap(value)
	local pitch = 1
	local next_pitch = 1
	local step = 0
	local count = self.n_mask_values - 1
	while count > 0 do
		next_pitch = pitch
		step = math.floor(count / 2)
		next_pitch = next_pitch + step
		if self.mask_values[next_pitch] <= value then
			pitch = next_pitch + 1
			count = count - step - 1
		else
			count = step
		end
	end
	local upper_pitch = math.max(1, math.min(self.n_mask_values, pitch))
	local lower_pitch = math.max(1, math.min(self.n_mask_values, pitch - 2))
	local best_distance = 2 -- octaves; distances between pitch classes certainly ought to be smaller than this
	for p = lower_pitch, upper_pitch do
		local distance = math.abs(value - self.mask_values[p])
		if distance < best_distance then
			best_distance = distance
			pitch = p
		end
	end
	return self.mask_values[pitch]
end

function Scale:get(pitch)
	print('get ' .. pitch)
	return self.values[pitch]
end

return Scale
