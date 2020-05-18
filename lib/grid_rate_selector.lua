local VoiceSliderBank = include 'lib/grid_voice_slider_bank'

local RateSelector = setmetatable({}, VoiceSliderBank)
RateSelector.__index = RateSelector

function RateSelector.new(x, y, width, height, n_voices, voices, type)
	local selector = setmetatable(VoiceSliderBank.new(x, y, width, height, n_voices, voices, type, 5, 1, 8), RateSelector)
	selector.on_select = function(v, r)
		selector.voice_params[v].rate = r
	end
	return selector
end

function RateSelector:key(x, y, z)
	if held_keys.shift then
		if z == 1 then
			for v = 1, self.n_voices do
				local slider = self.sliders[v]
				if slider:should_handle_key(x, y) then
					local diff = math.abs(slider.selected - slider:get_key_option(x, y))
					self.voice_params[v].jitter = diff / 4
					return
				end
			end
		end
		return
	end
	VoiceSliderBank.key(self, x, y, z)
end

function RateSelector:draw(g)
	for v = 1, self.n_voices do
		local voice = self.voices[v]
		local slider = self.sliders[v]
		local x_center = self.x_center
		local x_rate, y = slider:get_option_coords(slider.selected)
		local x_jitter = x_rate + voice:get_step_length(0) - voice.ticks_per_shift
		for x = self.x, self.x2 do
			local level = (x >= slider.x and x <= slider.x2) and 2 or 0
			if x == x_jitter then
				level = get_voice_control_level(v, 3)
			elseif x <= x_rate and x >= x_center then
				level = get_voice_control_level(v, 1)
			elseif x >= x_rate and x <= x_center then
				level = get_voice_control_level(v, 1)
			end
			g:led(x, y, math.ceil(level))
		end
	end
end

function RateSelector:get_state()
	local state = {}
	for v = 1, self.n_voices do
		local voice_params = self.voice_params[v]
		local voice_state = {}
		voice_state.rate = voice_params.rate
		voice_state.jitter = voice_params.jitter
		state[v] = voice_state
	end
	return state
end

function RateSelector:set_state(state)
	for v = 1, self.n_voices do
		local voice_params = self.voice_params[v]
		local voice_state = state[v]
		voice_params.rate = voice_state.rate
		voice_params.jitter = voice_state.jitter
	end
end

return RateSelector
