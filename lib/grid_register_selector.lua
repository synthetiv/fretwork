local VoiceSliderBank = include 'lib/grid_voice_slider_bank'

local RegisterSelector = setmetatable({}, VoiceSliderBank)
RegisterSelector.__index = RegisterSelector

function RegisterSelector.new(x, y, width, height, n_voices, voices, n_registers, registers, type)
	local selector = setmetatable(VoiceSliderBank.new(x, y, width, height, n_voices, voices, type, 4, 1, n_registers), RegisterSelector)
	selector.n_registers = n_registers
	selector.registers = registers
	selector.x_retrograde = selector.x
	selector.x_inversion = selector.x + 1
	selector.x_half = selector.sliders[1].x2 + 2
	selector.x_dec = selector.sliders[1].x2 + 3
	selector.x_inc = selector.sliders[1].x2 + 4
	selector.x_double = selector.sliders[1].x2 + 5
	selector.on_select = function(v, r)
		selector.voice_params[v].register = r
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
	local slider = self.sliders[v]
	local r = slider.selected
	local tap = self.taps[v]
	local voice_params = self.voice_params[v]
	local held_loop_keys = self.held_keys[v]
	if x == self.x_retrograde then
		if z == 1 then
			voice_params.retrograde = tap.direction < 0 and 0 or 1
		end
	elseif x == self.x_inversion then
		if z == 1 then
			voice_params.inversion = tap.next_multiply < 0 and 0 or 1
		end
	elseif x == self.x_half then
		held_loop_keys.half = z == 1
		if z == 1 then
			voice_params.loop_length = math.ceil(tap.shift_register.loop_length / 2)
		end
	elseif x == self.x_double then
		held_loop_keys.double = z == 1
		if z == 1 then
			voice_params.loop_length = tap.shift_register.loop_length * 2
		end
	elseif x == self.x_dec then
		held_loop_keys.dec = z == 1
		if z == 1 then
			voice_params.loop_length = tap.shift_register.loop_length - 1
		end
	elseif x == self.x_inc then
		held_loop_keys.inc = z == 1
		if z == 1 then
			voice_params.loop_length = tap.shift_register.loop_length + 1
		end
	elseif held_keys.shift then
		local pos = tap:get_step_pos(0)
		local r2 = slider:get_key_option(x, y)
		local loop = tap.shift_register:get_loop(pos)
		slider:key(x, y, z) -- changes tap's shift register
		tap.shift_register:set_loop(pos, loop)
	else
		slider:key(x, y, z)
	end
end

function RegisterSelector:draw(g)
	VoiceSliderBank.draw(self, g)
	for v = 1, self.n_voices do
		local y = self.voice_ys[v]
		local tap = self.taps[v]
		local register = tap.shift_register
		local held_keys = self.held_keys[v]
		g:led(self.x_retrograde, y, tap.direction < 0 and 7 or 2)
		g:led(self.x_inversion, y, tap.next_multiply < 0 and 7 or 2)
		g:led(self.x_half, y, held_keys.half and 7 or 2)
		g:led(self.x_dec, y, held_keys.dec and 4 or 1)
		g:led(self.x_inc, y, held_keys.inc and 4 or 1)
		g:led(self.x_double, y, held_keys.double and 7 or 2)
	end
end

function RegisterSelector:get_state()
	local state = {
		voices = {},
		loops = {}
	}
	for v = 1, self.n_voices do
		local tap = self.taps[v]
		local voice_params = self.voice_params[v]
		local voice_state = {}
		local r = voice_params.register
		voice_state.register = r
		voice_state.retrograde = voice_params.retrograde
		voice_state.inversion = voice_params.inversion
		state.voices[v] = voice_state
	end
	for r = 1, self.n_registers do
		state.loops[r] = self.registers[r]:get_loop(1)
	end
	return state
end

function RegisterSelector:set_state(state)
	for v = 1, self.n_voices do
		local tap = self.taps[v]
		local voice_params = self.voice_params[v]
		local voice_state = state.voices[v]
		voice_params.register = voice_state.register
		voice_params.retrograde = voice_state.retrograde
		voice_params.inversion = voice_state.inversion
	end
	for r = 1, self.n_registers do
		self.registers[r]:set_loop(1, state.loops[r])
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
