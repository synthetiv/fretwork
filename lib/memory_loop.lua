local Memory = include 'lib/memory'

local LoopMemory = setmetatable({}, Memory)
LoopMemory.__index = LoopMemory

LoopMemory.new = function(prefix, shift_register, default_offset)
	local mem = setmetatable(Memory.new(), LoopMemory)
	mem.tap_key = prefix .. '_tap'
	mem.length_param = prefix .. '_loop_length'
	mem.scramble_param = 'voice_%d_' .. prefix .. '_scramble'
	mem.direction_param = 'voice_%d_' .. prefix .. '_direction'
	mem.shift_register = shift_register
	for s = 1, mem.n_slots do
		local loop = {
			values = {},
			voices = {}
		}
		for i = 1, 16 do
			loop.values[i] = 0
		end
		for v = 1, 4 do
			loop.voices[v] = {
				offset = v * default_offset,
				scramble = 0,
				direction = 1
			}
		end
		mem.slots[s] = loop
	end
	return mem
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
		voice.direction = new_voice.direction
	end
end

function LoopMemory:recall(loop)
	for v = 1, n_voices do
		voices[v][self.tap_key]:set_offset(loop.voices[v].offset)
		params:set(string.format(self.scramble_param, v), loop.voices[v].scramble)
		params:set(string.format(self.direction_param, v), loop.voices[v].direction)
	end
	if quantization_off() then
		self.shift_register:set_loop(0, loop.values)
		-- silently update the loop length
		params:set(self.length_param, self.shift_register.length, true)
		update_voices()
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
		loop_voice.offset = tap:get_offset()
		loop_voice.scramble = tap.scramble
		loop_voice.direction = tap.direction
	end
	self.shift_register.dirty = false
end

return LoopMemory
