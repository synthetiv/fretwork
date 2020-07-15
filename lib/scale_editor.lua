local read_scala_file = include 'lib/scala'

local primes = { 2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83, 89, 97, 101, 103, 107, 109, 113, 127 }
local n_primes = #primes

local log2 = math.log(2)

local ScaleEditor = {}
ScaleEditor.__index = ScaleEditor

function ScaleEditor.new(scale)
	local editor = setmetatable({}, ScaleEditor)
	editor.pitch = 1
	editor.scale = scale
	editor.ratios = {}
	editor.prime_scroll = 1
	return editor
end

--- get prime factors of a number
-- @param n any number
function factorize(n)
	local p = 1
	local prime = primes[p]
	local factors = {}
	for p = 1, n_primes do
		factors[p] = 0
	end
	while n > 1 and p <= n_primes do
		if n % prime == 0 then
			-- divide by prime, keep going
			factors[p] = factors[p] + 1
			n = n / prime
		elseif p >= n_primes then
			-- if we've tried the last prime and we aren't done factoring, give up
			return nil
		else
			-- next prime
			p = p + 1
			prime = primes[p]
			factors[p] = 0
		end
	end
	return factors
end

--- factorize and simplify a ratio
-- @param r a ratio table containing `num` and `den` properties; a `factors` property will be added
function factorize_ratio(r)
	local factors = factorize(r.num)
	local den_factors = factorize(r.den)
	-- if we couldn't factorize either the numerator or the denominator, set factors to nil to
	-- indicate that `r` is irrational
	if factors == nil or den_factors == nil then
		r.factors = nil
		return
	end
	r.num = 1
	r.den = 1
	for p = 1, n_primes do
		factors[p] = factors[p] - den_factors[p]
		if factors[p] > 0 then
			r.num = r.num * math.pow(primes[p], factors[p])
		elseif factors[p] < 0 then
			r.den = r.den * math.pow(primes[p], -factors[p])
		end
	end
	r.factors = factors
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
	factorize_ratio(r)
end

function ScaleEditor:print_ratios()
	local classes_active = self.scale.classes_active
	for p = 1, self.length do
		local r = (p == self.length and self.span_ratio or self.ratios[p])
		local marker = (classes_active[p % self.length + 1] and '*' or ' ')
		if r.factors ~= nil then
			print(string.format('%d. %s %.0f/%.0f', p, marker, r.num, r.den))
		else
			print(string.format('%d. %s %f', p, marker, r.num))
		end
	end
end

local function sort_ratios(a, b)
	if a == nil then
		return false
	elseif b == nil then
		return true
	end
	return a.num / a.den < b.num / b.den
end

--- reduce & sort ratios, update scale values to match them
function ScaleEditor:update()
	local ratios = self.ratios
	self.length = #ratios + 1 -- include span ratio in length
	for i = 1, self.length - 1 do
		self:reduce_ratio(ratios[i])
	end
	table.sort(ratios, sort_ratios)
	local class_values = {}
	for i, r in ipairs(ratios) do
		class_values[i] = math.log(r.num / r.den) / log2
	end
	class_values[self.length] = math.log(self.span_ratio.num / self.span_ratio.den) / log2
	self.scale:set_class_values(class_values)
	self:print_ratios()
end

function ScaleEditor:replace_ratio(class, num, den)
	if num == nil or den == nil then
		error('missing num or den')
	end
	local r = self.ratios[class]
	r.num = num
	r.den = den
	self:update()
end

function ScaleEditor:multiply_ratio(class, num, den)
	if num == nil or den == nil then
		error('missing num or den')
	end
	local ratio = self.ratios[class]
	self:replace_ratio(class, ratio[1] * num, ratio[2] * den)
end

function ScaleEditor:delete_ratio(class)
	table.remove(self.ratios, class)
	self:update()
end

function ScaleEditor:insert_ratio(num, den)
	if num == nil or den == nil then
		error('missing num or den')
	end
	self.ratios[self.length] = {
		num = num,
		den = den
	}
	self:update()
end

function ScaleEditor:read_scala_file(path)
	-- read the file
	local _, ratios, description = read_scala_file(path)
	-- the final ratio is a special one, because it's the scale span; it shouldn't be editable with
	-- the same functions as other pitches, so we move it to a separate property
	self.length = #ratios
	self.span_ratio = ratios[self.length]
	factorize_ratio(self.span_ratio) -- simplify, if necessary
	ratios[self.length] = nil
	-- sort, reduce, and update scale ratios
	self.ratios = ratios
	self:update()
	-- announce ourselves
	print(description)
end

function ScaleEditor:draw_screen()
	screen.clear()

	screen.font_face(1)
	screen.font_size(8)

	screen.level(15)
	screen.move(3, 12)
	screen.text(self.pitch)

	screen.update()
end

return ScaleEditor
