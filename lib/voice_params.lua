-------
-- magic param setter/getter.
-- because typing `params:get(string.format(...))` over and over is annoying.
local VoiceParamGroup = {}

--- create a new param group
-- @param voice voice index
-- @param names table of { short names = string.format patterns }
-- @return new param group
function VoiceParamGroup.new(voice, names)
	local group = {}
	local map = {}
	for short_name, long_name_format in pairs(names) do
		map[short_name] = string.format(long_name_format, voice)
	end
	group.map = map
	group.get_full_param = function(self, param)
		if param == 'loop_length' then
			return string.format(self.map[param], self.register)
		end
		return self.map[param]
	end
	setmetatable(group, VoiceParamGroup)
	return group
end

--- get param value
-- @param param parameter short name
function VoiceParamGroup:__index(param)
	param = self:get_full_param(param)
	if param ~= nil then
		return params:get(param)
	end
	return nil
end

--- set param value
-- @param param parameter short name
-- @param value new value
function VoiceParamGroup:__newindex(param, value)
	param = self:get_full_param(param)
	if param ~= nil then
		params:set(param, value)
	end
end

--- a set of param groups
local VoiceParams = {}

--- create a new pair of param groups
-- @param voice voice index
-- @param names table of { short names = string.format patterns }
-- @return table containing pitch and mod param groups
function VoiceParams.new(voice, param_names)
	local params = setmetatable({}, VoiceParams)
	for type, names in pairs(param_names) do
		params[type] = VoiceParamGroup.new(voice, names)
	end
	return params
end

return VoiceParams
