local Scale = {}
Scale.__index = Scale

function Scale.new(length)
	local instance = {}
	setmetatable(instance, Scale)
	instance.length = length
	instance.mask = {}
	for n = 1, instance.length do
		instance.mask[n] = true
	end
	return instance
end

function Scale:set_mask(mask)
	self.mask = {}
	self.length = #mask
	for n = 1, self.length do
		self.mask[n] = mask[n]
	end
end

function Scale:get_mask()
	local mask = {}
	for n = 1, self.length do
		mask[n] = self.mask[n]
	end
	return mask
end

function Scale:get_pitch_class(pitch)
	return (pitch - 1 ) % self.length + 1
end

function Scale:contains(pitch)
	return self.mask[self:get_pitch_class(pitch)]
end

function Scale:set_class(pitch, enable)
	self.mask[self:get_pitch_class(pitch)] = enable
end

function Scale:toggle_class(pitch)
	local pitch_class = self:get_pitch_class(pitch)
	self.mask[pitch_class] = not self.mask[pitch_class]
end

return Scale
