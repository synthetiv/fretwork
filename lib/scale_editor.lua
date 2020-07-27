local read_scala_file = include 'lib/scala'
local Ratio = include 'lib/ratio'

local ScaleEditor = {}
ScaleEditor.__index = ScaleEditor

function ScaleEditor.new(scale)
	local editor = setmetatable({}, ScaleEditor)
	editor.scale = scale
	editor.ratios = {}
	editor.selected_ratio = 0
	editor.held_keys = {
		ctrl = false,
		lctrl = false,
		rctrl = false,
		shift = false,
		lshift = false,
		rshift = false,
		alt = false,
		lalt = false,
		ralt = false
	}
	editor.on_update = function() end
	return editor
end

function ScaleEditor:select_pitch(pitch_id)
	self.selected_ratio = self.scale:get_class(pitch_id) - 1
end

--- reduce a ratio to [1/1, span_ratio)
-- @param r a ratio table containing `num` and `den` properties; a `factors` property will be added
function ScaleEditor:reduce_ratio(r)
	local i = 1
	local s = self.span_ratio
	local span = s.num / s.den
	while r.num / r.den >= span do
		print('down', r.num .. '/' .. r.den)
		r.num = r.num * s.den
		r.den = r.den * s.num
		i = i + 1
		if i > 10 then
			print('too many loops down', r.num .. '/' .. r.den)
			return
		end
	end
	while r.den / r.num > span do
		print('up', r.num .. '/' .. r.den)
		r.num = r.num * s.num
		r.den = r.den * s.den
		i = i + 1
		if i > 10 then
			print('too many loops up', r.num .. '/' .. r.den)
			return
		end
	end
	r._dirty = true
end

function ScaleEditor:print_ratios()
	for r = 1, self.length do
		local ratio = (r == self.length and self.span_ratio or self.ratios[p])
		local marker = (self:is_class_active(r + 1) and '*' or ' ')
		print(string.format('%d. %s %s', r, marker, ratio))
	end
end

local function sort_ratios(a, b)
	if a == nil then
		return false
	elseif b == nil then
		return true
	end
	return a < b
end

--- reduce & sort ratios, update scale values to match them
function ScaleEditor:update()

	local ratios = self.ratios
	local count = #ratios
	local selected = self.ratios[self.selected_ratio]

	for i = 1, count do
		self:reduce_ratio(ratios[i])
	end
	table.sort(ratios, sort_ratios)

	self.selected_ratio = 0
	for r = 1, count do
		if ratios[r] == selected then
			self.selected_ratio = r
		end
	end

	self.span_ratio._dirty = true -- TODO: why did I think this was necessary...?
	self.length = #ratios + 1 -- include span ratio in length

	local class_values = {}
	for i, ratio in ipairs(ratios) do
		class_values[i] = ratio.value
	end
	class_values[self.length] = self.span_ratio.value
	self.scale:set_class_values(class_values)
	
	self:print_ratios()

	self:on_update()
end

function ScaleEditor:is_class_active(class)
	if class == nil then
		class = self.selected_ratio + 1
	end
	return self.scale:is_class_active(class)
end

function ScaleEditor:toggle_class(class)
	if class == nil then
		class = self.selected_ratio + 1
	end
	return self.scale:toggle_class(class)
end

function ScaleEditor:replace_class(class, num, den)
	if class == nil then
		class = self.selected_ratio + 1
	end
	if class < 2 or class > self.length then
		error('invalid ratio index: ' .. class)
		return
	end
	self.selected_ratio = class - 1
	self.ratios[self.selected_ratio] = Ratio.new(num, den)
	self:update()
end

function ScaleEditor:multiply_class(class, num, den)
	if class == nil then
		class = self.selected_ratio + 1
	end
	if class < 2 or class > self.length then
		error('invalid ratio index: ' .. class)
		return
	end
	self:replace_class(class, self.ratios[class] * Ratio.new(num, den))
end

function ScaleEditor:delete_class(class)
	if class == nil then
		class = self.selected_ratio + 1
	end
	if class < 2 or class > self.length then
		error('invalid ratio index: ' .. class)
		return
	end
	table.remove(self.ratios, class - 1)
	self:update()
end

function ScaleEditor:insert_ratio(num, den)
	self.ratios[self.length] = Ratio.new(num, den)
	self.selected_ratio = self.length
	self:update()
end

function ScaleEditor:read_scala_file(path)
	-- read the file
	local ratios, description = read_scala_file(path)
	-- the final ratio is a special one, because it's the scale span; it shouldn't be editable with
	-- the same functions as other pitches, so we move it to a separate property
	self.length = #ratios
	for i = 1, self.length do
		setmetatable(ratios[i], Ratio)
	end
	self.span_ratio = ratios[self.length]
	ratios[self.length] = nil
	-- sort, reduce, and update scale ratios
	self.ratios = ratios
	self:update()
	-- announce ourselves
	print(description)
end

function ScaleEditor:redraw()
	screen.clear()

	screen.font_face(1)
	screen.font_size(8)
	-- large: 29/13 (mono), 27/10 (contrasty mono), 30/13 (italic), 32/13 (same, light), 34/16 (italic), 36/16 (same, light)
	-- tiny: 25/6
	--
	local selected_ratio = self.selected_ratio
	local class = selected_ratio + 1
	local active = self:is_class_active()
	local ratio = self.ratios[selected_ratio]
	if class == 1 then
		ratio = self.span_ratio
	end

	screen.level(active and 10 or 3)
	screen.move(3, 14)
	if class == 1 then
		screen.text('span')
	else
		screen.text(string.format('%d.', class))
	end

	screen.level(active and 15 or 7)
	screen.font_face(27)
	screen.font_size(10)

	screen.move(61, 12)
	screen.text_right(string.format('%.0f', ratio.num))

	screen.level(active and 4 or 1)
	screen.move(58, 21)
	screen.line(68, 1)
	screen.stroke()

	screen.level(active and 15 or 7)
	screen.move(66, 17)
	screen.text(string.format('%.0f', ratio.den))

	screen.level(active and 10 or 3)
	screen.font_face(1)
	screen.font_size(8)
	
	local x = 3
	local name = ratio.name
	local char = string.sub(name, 1, 1)
	name = string.sub(name, 2)
	screen.move(x, 23)
	screen.text(char)
	x = x + screen.text_extents(char) + 1
	while string.len(name) > 0 do
		char = string.sub(name, 1, 1)
		name = string.sub(name, 2)
		screen.move(x, 23)
		if char == 'b' then
			screen.move_rel(0.5, -5)
			screen.line_rel(0, 5)
			screen.move_rel(0.5, -0.5)
			screen.line_rel(1, 0)
			screen.move_rel(0.5, -0.5)
			screen.line_rel(0, -2)
			screen.move_rel(-0.5, 0.5)
			screen.line_rel(-1, 0)
			screen.stroke()
			x = x + 4
		elseif char == '^' then
			screen.move_rel(0, -2.5)
			screen.line_rel(1, 0)
			screen.move_rel(0, -1)
			screen.line_rel(1, 0)
			screen.move_rel(0.5, -1.5)
			screen.line_rel(0, 5)
			screen.move_rel(0.5, -3.5)
			screen.line_rel(1, 0)
			screen.move_rel(0, 1)
			screen.line_rel(1, 0)
			screen.stroke()
			x = x + 6
		elseif char == 'v' then
			screen.move_rel(0, -2.5)
			screen.line_rel(1, 0)
			screen.move_rel(0, 1)
			screen.line_rel(1, 0)
			screen.move_rel(0.5, 1.5)
			screen.line_rel(0, -5)
			screen.move_rel(0.5, 3.5)
			screen.line_rel(1, 0)
			screen.move_rel(0, -1)
			screen.line_rel(1, 0)
			screen.stroke()
			x = x + 6
		elseif char == 'E' then
			screen.move_rel(1, -4.5)
			screen.line_rel(3, 0)
			screen.move_rel(-4, 1)
			screen.line_rel(1, 0)
			screen.move_rel(0, 1)
			screen.line_rel(2, 0)
			screen.move_rel(-3, 1)
			screen.line_rel(1, 0)
			screen.move_rel(0, 1)
			screen.line_rel(3, 0)
			screen.stroke()
			x = x + 5
		elseif char == 'l' then
			screen.move_rel(0.5, -5)
			screen.line_rel(0, 5)
			screen.move_rel(0.5, -0.5)
			screen.line_rel(1, 0)
			screen.stroke()
			x = x + 3
		elseif char == 'L' then
			screen.move_rel(0, -0.5)
			screen.line_rel(4, 0)
			screen.move_rel(-4, -0.5)
			screen.line_rel(1, 0)
			screen.move_rel(0, -1)
			screen.line_rel(1, 0)
			screen.move_rel(0.5, -0.5)
			screen.line_rel(0, -2)
			screen.stroke()
			x = x + 5
		elseif char == 'Z' then
			screen.move_rel(0, -4.5)
			screen.line_rel(4, 0)
			screen.move_rel(0, 1)
			screen.line_rel(-1, 0)
			screen.move_rel(0, 1)
			screen.line_rel(-2, 0)
			screen.move_rel(0, 1)
			screen.line_rel(-1, 0)
			screen.move_rel(1, 1)
			screen.line_rel(3, 0)
			screen.stroke()
			x = x + 5
		else
			screen.text(char)
			x = x + screen.text_extents(char) + 1
		end
	end

	screen.move(3, 42)
	if ratio.factors ~= nil then
		local is_first = true
		for p, e in ipairs(ratio.factors) do
			if e ~= 0 then

				screen.font_face(1)
				screen.font_size(8)
				if not is_first then
					screen.move_rel(1, 1)
					screen.level(1)
					screen.text('*')
					screen.level(active and 10 or 3)
					screen.move_rel(1, -1)
				end
				screen.text(Ratio.primes[p])

				if e ~= 1 then
					screen.move_rel(0, -4)
					screen.font_face(25)
					screen.font_size(6)
					screen.text(e)
					screen.move_rel(0, 4)
				end

				is_first = false
			end
		end
	end

	local span_value = self.span_ratio.value
	local level = 1
	local len = 1
	if self.selected_ratio == 0 and self:is_class_active(1) then
		level = 15
		len = 5
	elseif self:is_class_active(1) then
		level = 7
		len = 4
	elseif self.selected_ratio == 0 then
		level = 5
	end
	screen.level(level)
	screen.move(0.5, 64)
	screen.line_rel(0, -len)
	screen.stroke()
	screen.move(127.5, 64)
	screen.line_rel(0, -len)
	screen.stroke()
	for r = 1, self.length - 1 do
		local x = math.floor(127 * self.ratios[r].value / span_value) + 0.5
		level = 1
		len = 1
		if self.selected_ratio == r and self:is_class_active(r + 1) then
			level = 15
			len = 5
		elseif self:is_class_active(r + 1) then
			level = 7
			len = 4
		elseif self.selected_ratio == r then
			level = 5
		end
		screen.move(x, 64)
		screen.line_rel(0, -len)
		screen.level(level)
		screen.stroke()
	end

	screen.update()
end

function ScaleEditor:keyboard_event(type, code, value)
	if type == 1 then
		if code == hid.codes.KEY_LEFTCTRL then
			self.held_keys.lctrl = value ~= 0
			self.held_keys.ctrl = self.held_keys.lctrl or self.held_keys.rctrl
		elseif code == hid.codes.KEY_RIGHTCTRL then
			self.held_keys.rctrl = value ~= 0
			self.held_keys.ctrl = self.held_keys.lctrl or self.held_keys.rctrl
		elseif code == hid.codes.KEY_LEFTSHIFT then
			self.held_keys.lshift = value ~= 0
			self.held_keys.shift = self.held_keys.lshift or self.held_keys.rshift
		elseif code == hid.codes.KEY_RIGHTSHIFT then
			self.held_keys.rshift = value ~= 0
			self.held_keys.shift = self.held_keys.lshift or self.held_keys.rshift
		elseif code == hid.codes.KEY_LEFTALT then
			self.held_keys.lalt = value ~= 0
			self.held_keys.alt = self.held_keys.lalt or self.held_keys.ralt
		elseif code == hid.codes.KEY_RIGHTALT then
			self.held_keys.ralt = value ~= 0
			self.held_keys.alt = self.held_keys.lalt or self.held_keys.ralt
		elseif value == 1 then
			if self.held_keys.alt and not (self.held_keys.ctrl or self.held_keys.shift) then
			elseif not (self.held_keys.ctrl or self.held_keys.alt or self.held_keys.shift) then
				if code == hid.codes.KEY_RIGHTBRACE then
					self.selected_ratio = (self.selected_ratio + 1) % self.scale.length
					dirty = true
					return
				elseif code == hid.codes.KEY_LEFTBRACE then
					self.selected_ratio = (self.selected_ratio - 1) % self.scale.length
					dirty = true
					return
				end
			end
		end
	end
	print('editor key', type, code, value)
end

return ScaleEditor
