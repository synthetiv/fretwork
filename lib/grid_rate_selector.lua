local VoiceSliderBank = include 'lib/grid_voice_slider_bank'

local RateSelector = setmetatable({}, VoiceSliderBank)
RateSelector.__index = RateSelector

function RateSelector.new(x, y, width, height, n_voices, voices, type)
	local selector = setmetatable(VoiceSliderBank.new(x, y, width, height, n_voices, voices, type, 1, 1, 15), RateSelector)
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
	local x_center = self.x_center
	for v = 1, self.n_voices do
		local slider = self.sliders[v]
		local x_rate, y = slider:get_option_coords(slider.selected)
		local x_jitter = self.taps[v]:get_step_length(0)
		if x_rate == x_center then
			x_jitter = 0
		elseif x_rate > x_center then
			x_jitter = math.max(x_center, self.x2 + 1 - x_jitter)
		else
			x_jitter = math.min(x_center, self.x - 1 + x_jitter)
		end
		for x = self.x, self.x2 do
			local level = 1
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

return RateSelector
