local Control = include 'lib/grid_control'

local X0XRoll = setmetatable({}, Control)
X0XRoll.__index = X0XRoll

function X0XRoll.new(x, y, width, height, voice)
	local roll = setmetatable(Control.new(x, y, width, height), X0XRoll)
	roll.voice = voice
	return roll
end

function X0XRoll:get_offset(x)
	return x - self.x_center
end

function X0XRoll:draw(g)
	for x = self.x, self.x2 do
		-- TODO: is it worth trying to generalize this type of grid control more, or is it fine for it to
		-- always just read mod values from a voice?
		local pitch, mod = self.voice:get(self:get_offset(x))
		local level = math.max(0, util.round(7 * (mod / 2)))
		if x == self.x_center then
			level = level + 3
		end
		-- TODO: map y to mod too?
		g:led(x, self.y, level)
	end
end

function X0XRoll:key(x, y, z)
	if z ~= 1 then
		return
	end
	if not self:should_handle_key(x, y) then
		return
	end
	local offset = self:get_offset(x)
	local pitch, mod = self.voice:get(offset)
	if mod > 0 then
		self.voice:set(offset, pitch, 0)
	else
		self.voice:set(offset, pitch, 1)
	end
end

return X0XRoll
