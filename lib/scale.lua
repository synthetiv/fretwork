local Scale = {}
Scale.__index = Scale

function Scale.new(length)
	local instance = setmetatable({}, Scale)
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

function Scale:quantize(pitch)
	-- TODO: what about non-12TET scales? probably worth looking at Emilie's code for Braids
	return math.floor(pitch + 0.5)
end

function Scale:snap(pitch)
	local quantized = self:quantize(pitch)
	local low = quantized < pitch -- TODO: shouldn't this be the other way around?
	if self:contains(quantized) then
		return quantized
	end
	for i = 1, 96 do
		local up = math.min(96, quantized + i)
		local down = math.max(1, quantized - i)
		if low then
			if self:contains(down) then
				return down
			elseif self:contains(up) then
				return up
			end
		else
			if self:contains(up) then
				return up
			elseif self:contains(down) then
				return down
			end
		end
	end
	return 0
end

return Scale
