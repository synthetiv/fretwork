local VoiceSliderBank = include 'lib/grid_voice_slider_bank'

local RegisterSelector = setmetatable({}, VoiceSliderBank)
RegisterSelector.__index = RegisterSelector

function RegisterSelector.new(x, y, width, height, n_voices, voices, type)
	local selector = setmetatable(VoiceSliderBank.new(x, y, width, height, n_voices, voices, 4, 1, n_registers), RegisterSelector)
	local register_param = 'voice_%d_' .. type .. '_register'
	selector.register_param = register_param
	selector.multiply_param = 'voice_%d_' .. type .. '_multiply'
	selector.loop_length_param = type .. '_loop_%d_length'
	selector.tap_key = type .. '_tap'
	selector.x_inversion = selector.x + 1
	selector.x_half = selector.sliders[1].x2 + 2
	selector.x_dec = selector.sliders[1].x2 + 3
	selector.x_inc = selector.sliders[1].x2 + 4
	selector.x_double = selector.sliders[1].x2 + 5
	selector.on_select = function(v, r)
		params:set(string.format(register_param, v), r)
	end
	selector.held_keys = {}
	for v = 1, n_voices do
		selector.held_keys[v] = {
			half = false,
			dec = false,
			inc = false,
			double = false
		}
	end
	return selector
end

function RegisterSelector:key(x, y, z)
	local v = self.y_voices[y]
	if v == nil then
		return
	end
	local r = self.sliders[v].selected
	local tap = voices[v][self.tap_key]
	local held_keys = self.held_keys[v]
	if x == self.x_inversion then
		if z == 1 then
			params:set(string.format(self.multiply_param, v), tap.next_multiply < 0 and 2 or 1)
		end
	elseif x == self.x_half then
		held_keys.half = z == 1
		if z == 1 then
			params:set(string.format(self.loop_length_param, r), math.ceil(tap.shift_register.loop_length / 2))
		end
	elseif x == self.x_double then
		held_keys.double = z == 1
		if z == 1 then
			params:set(string.format(self.loop_length_param, r), tap.shift_register.loop_length * 2)
		end
	elseif x == self.x_dec then
		held_keys.dec = z == 1
		if z == 1 then
			params:set(string.format(self.loop_length_param, r), tap.shift_register.loop_length - 1)
		end
	elseif x == self.x_inc then
		held_keys.inc = z == 1
		if z == 1 then
			params:set(string.format(self.loop_length_param, r), tap.shift_register.loop_length + 1)
		end
	else
		VoiceSliderBank.key(self, x, y, z)
	end
end

-- TODO: shift to copy loop
function RegisterSelector:draw(g)
	VoiceSliderBank.draw(self, g)
	for v = 1, self.n_voices do
		local y = self.voice_ys[v]
		local tap = voices[v][self.tap_key]
		local register = tap.shift_register
		local held_keys = self.held_keys[v]
		g:led(self.x_inversion, y, tap.next_multiply < 0 and 7 or 2)
		g:led(self.x_half, y, held_keys.half and 7 or 2)
		g:led(self.x_dec, y, held_keys.dec and 4 or 1)
		g:led(self.x_inc, y, held_keys.inc and 4 or 1)
		g:led(self.x_double, y, held_keys.double and 7 or 2)
	end
end

function RegisterSelector:reset()
	for v = 1, self.n_voices do
		self.held_keys[v].half = false
		self.held_keys[v].dec = false
		self.held_keys[v].inc = false
		self.held_keys[v].double = false
	end
end

return RegisterSelector
