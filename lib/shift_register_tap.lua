local RandomQueue = include 'lib/random_queue'

local ShiftRegisterTap = {}
ShiftRegisterTap.__index = ShiftRegisterTap

ShiftRegisterTap.new = function(offset, shift_register, voice)
	local tap = setmetatable({}, ShiftRegisterTap)
	tap.pos = shift_register:get_loop_offset_pos(offset)
	tap.shift_register = shift_register
	tap.voice = voice -- TODO: does this let me simplify anything that's been annoying?
	tap.direction = 1
	tap.scramble = 0
	-- TODO: is there another way to handle noise/scramble that would:
	-- 1. handle loop length changes better? i.e. if you change the SR length and a note moves from
	-- point A on the screen to point B, the corresponding scramble/noise values move with it so that
	-- the voice path doesn't twitch & jump around?
	-- 2. really never repeat?
	tap.scramble_values = RandomQueue.new(131) -- prime length, so SR loop and random queues are rarely in phase
	tap.noise = 0
	tap.noise_values = RandomQueue.new(137)
	tap.next_bias = 0
	tap.bias = 0
	tap.tick = 0
	tap.ticks_per_step = 2
	return tap
end

function ShiftRegisterTap:set_rate(direction, ticks_per_step)
	-- retain current position as best you can
	local tick = self.tick / self.ticks_per_step
	self.tick = math.floor(tick * ticks_per_step) -- TODO: util.round() here sometimes rounds up so that tick == ticks_per_step, and that screws up sync with register... I think
	self.ticks_per_step = ticks_per_step
	self.direction = direction
end
	
function ShiftRegisterTap:get_offset(t)
	-- 9 ticks/step won't be shifted by clock, so future == past == present
	if self.ticks_per_step == 9 then
		return 0
	end
	return math.floor((t + self.tick) / self.ticks_per_step) * self.direction
end

function ShiftRegisterTap:get_pos(t)
	t = self:get_offset(t)
	local scramble_offset = util.round(self.scramble_values:get(t) * self.scramble)
	return t + self.pos + scramble_offset
end

function ShiftRegisterTap:get(t)
	local pos = self:get_pos(t)
	local noise_value = self.noise_values:get(self:get_offset(t)) * self.noise
	return self.shift_register:read(pos) + noise_value + self.bias
end

function ShiftRegisterTap:apply_edits()
	self.bias = self.next_bias
	if self.next_offset ~= nil then
		self.pos = self.shift_register:clamp_loop_pos(self.shift_register.start + self.next_offset)
		self.next_offset = nil
	end
end

function ShiftRegisterTap:shift(d, manual)
	-- don't shift automatically if 9 ticks/step
	if not manual and self.ticks_per_step == 9 then
		return
	end
	local ticks_per_step = self.ticks_per_step
	local tick = self.tick
	tick = tick + d
	d = math.floor(tick / ticks_per_step) * self.direction
	if d ~= 0 then
		if self.voice.sync then
			self.shift_register:shift(d * self.direction) -- TODO: argh
		end
		self.scramble_values:shift(d)
		self.noise_values:shift(d)
		self.pos = self.shift_register:clamp_loop_pos(self.pos + d)
		self:apply_edits()
	end
	self.tick = tick % ticks_per_step
end

function ShiftRegisterTap:set(t, value)
	local pos = self:get_pos(t)
	local noise_value = self.noise_values:get(self:get_offset(t)) * self.noise
	self.shift_register:write(pos, value - self.bias - noise_value)
end

return ShiftRegisterTap
