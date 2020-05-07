local Memory = include 'lib/memory'

local LoopMemory = setmetatable({}, Memory)
LoopMemory.__index = LoopMemory

LoopMemory.new = function(type, shift_register, default_offset)
	local mem = setmetatable(Memory.new(), LoopMemory)
	mem.tap_key = type .. '_tap'
	mem.length_param = type .. '_loop_length'
	mem.scramble_param = 'voice_%d_' .. type .. '_scramble'
	mem.rate_param = 'voice_%d_' .. type .. '_rate'
	mem.shift_register = shift_register
	mem.default_offset = default_offset
	return mem
end

function LoopMemory:get_slot_default(s)
	local loop = {
		values = self:get_slot_default_values(s),
		voices = {}
	}
	-- TODO: no. move this out, either into transpose memory or somewhere else
	for v = 1, n_voices do
		loop.voices[v] = {
			offset = (v - 1) * self.default_offset,
			scramble = 0,
			rate = 2
		}
	end
	return loop
end

function LoopMemory:set(loop, new_loop)
	loop.values = {}
	for i, v in ipairs(new_loop.values) do
		loop.values[i] = v
	end
	for v = 1, n_voices do
		local voice = loop.voices[v]
		local new_voice = new_loop.voices[v]
		voice.offset = new_voice.offset
		voice.scramble = new_voice.scramble
		voice.rate = new_voice.rate
	end
end

function LoopMemory:recall(loop)
	for v = 1, n_voices do
		-- TODO: when tap rates differ, loop contents and tap offsets may change at different times,
		-- which looks and sounds confusing (NOTE: this should be fixed-ish by moving offset data to a
		-- different memory bank)
		voices[v][self.tap_key].next_offset = loop.voices[v].offset
		params:set(string.format(self.scramble_param, v), loop.voices[v].scramble)
		-- params:set(string.format(self.rate_param, v), loop.voices[v].direction) -- TODO
	end
	if quantization_off() then
		self.shift_register:set_loop(0, loop.values)
		-- silently update the loop length
		-- TODO: set length params for all registers, or something
		-- params:set(self.length_param, self.shift_register.loop_length, true)
		-- force values + paths to update
		for v = 1, n_voices do
			local voice = voices[v]
			voice[self.tap_key].dirty = true
			voice:update()
		end
	else
		self.shift_register:set_next_loop(1, loop.values)
	end
end

function LoopMemory:save(loop)
	local offset = quantization_off() and 0 or 1 -- if quantizing, save the future loop state (on the next tick)
	loop.values = self.shift_register:get_loop(offset)
	for v = 1, n_voices do
		local loop_voice = loop.voices[v]
		local tap = voices[v][self.tap_key]
		-- loop_voice.offset = tap:get_offset() -- TODO: undefined method (!)
		loop_voice.scramble = tap.scramble
		-- loop_voice.direction = tap.direction -- TODO
	end
	self.shift_register.dirty = false
end

return LoopMemory
