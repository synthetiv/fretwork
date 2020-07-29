-- primes well beyond what anyone's likely to care about (127-limit)
local primes = { 2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83, 89, 97, 101, 103, 107, 109, 113, 127 }
local n_primes = #primes

-- used for converting ratios to CV-friendly values
local log2 = math.log(2)

-- allocate one table for continue_fraction() to store data in
local cf = {}

--- run the continued fraction algorithm on a number
-- @param f the initial number, usually a float
-- @param term the number of terms in the continued fraction expression (n1 + 1/(n2 + 1/(n3 + 1/(n4 + 1/(...)))))
-- @return a table of {n1, n2, n3 ...} as described above, and the total number of terms
local function continued_fraction(f, term)
	local i = math.floor(f) + 0.0
	if term == nil then
		term = 1
	else
		term = term + 1
	end
	-- convert int to float, otherwise goofy stuff happens later when we start multiplying large ints
	cf[term] = i + 0.0
	f = f - i
	-- TODO: find a sensible precision threshold that will keep rational approximations within, say,
	-- 1/100th of a cent of original cent values
	if f < 0.0001 or term > 16383 then
		return cf, term
	end
	return continued_fraction(1 / f, term)
end

--- attempt to translate a number to a ratio of whole numbers
-- @param f the initial number, usually a float
-- @return numerator, denominator
local function rationalize(f)
	if f == 1 then -- short circuit for efficiency
		return 1, 1
	end
	local cf, term = continued_fraction(f, 0)
	local num = cf[term] + 0.0
	local den = 1.0
	term = term - 1
	while term > 0 do
		num, den = den, num
		num = num + cf[term] * den
		-- if we hit inf anywhere, consider this an irrational number
		if num == math.huge or den == math.huge then
			return f, 1.0
		end
		term = term - 1
	end
	local diff = f - (num / den)
	if math.abs(diff) ~= 0.0 then
		print(string.format('rationalization imperfect: %f - %f/%f = %f', f, num, den, diff))
		return f, 1.0
	end
	return num, den
end

--- get prime factors of a number
-- @param n any number
-- @return table of factors with indices corresponding to the `primes` table (i.e. factors of 5 at index 3)
local function factorize(n)
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
			print('failed to factorize', n)
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

Ratio = {}

--- create a new Ratio
-- @param num numerator, float, table of factors, or a Ratio
-- @param den denominator or nil
-- @return a new Ratio or, if num is a Ratio, num, unmodified
function Ratio.new(num, den)
	local factors_arg = nil
	if type(num) == 'table' then
		if getmetatable(num) == Ratio then
			return num
		else
			factors_arg = num
			num = 1
			den = 1
		end
	elseif type(num) == 'string' then
		return Ratio.dejohnstonize(num)
	elseif type(num) ~= 'number' then
		num = 1
	end
	if type(den) ~= 'number' then
		num, den = rationalize(num)
	end
	local r = {
		_num = num,
		_den = den,
		_factors = factors_arg or {},
		_dirty = factors_arg == nil,
		_name = ''
	}
	setmetatable(r, Ratio)
	-- calculate factors or num/den, whichever we don't already have
	r:simplify()
	return r
end

--- (re)calculate factors based on num/den
function Ratio:factorize()
	local factors = factorize(self.num)
	local den_factors = factorize(self.den)
	-- if we couldn't factorize either the numerator or the denominator, set factors to nil to
	-- indicate that this ratio is irrational
	if factors == nil or den_factors == nil then
		print('missing factors for num or den')
		self._factors = nil
		self._dirty = false
		return
	end
	for p = 1, n_primes do
		factors[p] = factors[p] - den_factors[p]
	end
	self._factors = factors
	self._dirty = false
end

--- simplify num/den based on factors
function Ratio:simplify()
	if self._dirty then
		self:factorize()
	end
	local factors = self._factors
	local num = 1
	local den = 1
	for p = 1, n_primes do
		if factors[p] > 0 then
			num = num * math.pow(primes[p], factors[p])
		elseif factors[p] < 0 then
			den = den * math.pow(primes[p], -factors[p])
		end
	end
	self.num = num
	self.den = den
end

--- reduce a ratio to [1/1, span)
-- @param span a maximum ratio (usually an octave)
function Ratio:reduce(span)
	if getmetatable(span) ~= Ratio then
		span = Ratio.new(span)
	end
	local i = 1
	while self >= span do
		self.num = self.num * span.den
		self.den = self.den * span.num
		i = i + 1
		if i > 10 then
			print('too many loops down', self.num .. '/' .. self.den)
			return
		end
	end
	while self < 1 do
		self.num = self.num * span.num
		self.den = self.den * span.den
		i = i + 1
		if i > 10 then
			print('too many loops up', self.num .. '/' .. self.den)
			return
		end
	end
	self:simplify()
end

function Ratio:__index(key)
	if 'num' == key then
		return self._num
	elseif 'den' == key then
		return self._den
	elseif 'value' == key then
		return math.log(self._num / self._den) / log2
	elseif 'quotient' == key then
		return self._num / self._den
	elseif 'factors' == key then
		if not self._dirty then
			return self._factors
		end
		self:factorize()
		return self._factors
	elseif 'name' == key then
		if not self._dirty and self._name ~= '' then
			return self._name
		end
		self:johnstonize()
		return self._name
	end
	return Ratio[key]
end

function Ratio:__newindex(key, value)
	-- mark ratios as needing factorization after setting num or den by hand
	if 'num' == key then
		self._num = value
		self._dirty = true
	elseif 'den' == key then
		self._den = value
		self._dirty = true
	end
end

function Ratio:__mul(other)
	if getmetatable(self) ~= Ratio then
		self = Ratio.new(self)
	end
	if getmetatable(other) ~= Ratio then
		other = Ratio.new(other)
	end
	if self.factors == nil or other.factors == nil then
		-- one or both ratios is irrational, so just multiply num + den
		return Ratio.new(self.num * other.num, self.den * other.den)
	end
	local factors = self.factors
	local other_factors = other.factors
	local product_factors = {}
	for p = 1, n_primes do
		product_factors[p] = factors[p] + other_factors[p]
	end
	return Ratio.new(product_factors)
end

function Ratio:__div(other)
	if getmetatable(self) ~= Ratio then
		self = Ratio.new(self)
	end
	if getmetatable(other) ~= Ratio then
		other = Ratio.new(other)
	end
	if self.factors == nil or other.factors == nil then
		-- one or both ratios is irrational, so just multiply num*den + den*num
		return Ratio.new(self.num * other.den, self.den * other.num)
	end
	local quotient_factors = {}
	for p = 1, n_primes do
		quotient_factors[p] = self.factors[p] - other.factors[p]
	end
	return Ratio.new(quotient_factors)
end

function Ratio:__lt(other)
	if type(self) == 'number' then
		return self < other.quotient
	elseif type(other) == 'number' then
		return self.quotient < other
	elseif getmetatable(other) ~= Ratio then
		other = Ratio.new(other)
	end
	return self.quotient < other.quotient
end

function Ratio:__lte(other)
	if type(self) == 'number' then
		return self <= other.quotient
	elseif type(other) == 'number' then
		return self.quotient <= other
	elseif getmetatable(other) ~= Ratio then
		other = Ratio.new(other)
	end
	return self.quotient <= other.quotient
end

function Ratio:__gt(other)
	if type(self) == 'number' then
		return self > other.quotient
	elseif type(other) == 'number' then
		return self.quotient > other
	elseif getmetatable(other) ~= Ratio then
		other = Ratio.new(other)
	end
	return self.quotient > other.quotient
end

function Ratio:__gte(other)
	if type(self) == 'number' then
		return self >= other.quotient
	elseif type(other) == 'number' then
		return self.quotient >= other
	elseif getmetatable(other) ~= Ratio then
		other = Ratio.new(other)
	end
	return self.quotient >= other.quotient
end

function Ratio:__tostring()
	if self.factors ~= nil then
		return string.format('%.0f/%.0f', self.num, self.den)
	end
	return string.format('%f', self.num / self.den)
end

function Ratio:print_factors()
	local factors = self.factors
	if factors == nil then
		print('irrational')
		return
	end
	local string = string.format('%s = ', self)
	local first = true
	for p = 1, n_primes do
		if factors[p] ~= 0 then
			if not first then
				string = string .. ' * '
			end
			if factors[p] == 1 then
				string = string .. string.format('%d', primes[p])
			else
				string = string .. string.format('%d^%d', primes[p], factors[p])
			end
			first = false
		end
	end
	print(string)
end

-- allocate a table for tallying up accidentals
local ac = {
	{ '#',  0 },
	{ 'b',  0 },
	{ '7',  0 },
	{ 'L',  0 },
	{ '^',  0 },
	{ 'v',  0 },
	{ '13', 0 },
	{ 'El', 0 },
	{ '17', 0 },
	{ 'Ll', 0 },
	{ '19', 0 },
	{ '6l', 0 },
	{ '+',  0 },
	{ '-',  0 }
}
function Ratio:johnstonize()

	if self.factors == nil then
		self._name = '?'
		return
	end

	local factors = self.factors
	local note = 1 -- C
	local class = 1
	local sharps = 0
	local pluses = 0
	local sevens = 0
	local arrows = 0
	local thirteens = 0
	local seventeens = 0
	local nineteens = 0
	--[[ TODO:
	local twentythrees = 0
	local twentynines = 0
	local thirtyones = 0
	--]]

	-- For every 3 in the numerator:
	-- Ascend one perfect fifth. (Add a plus to the perfect fifth note if starting on any kind of B or
	-- D, including Bb, D#, B-, whatever. If the original note had a minus, the plus will merely cancel
	-- it out on the new note.)
	local f3 = factors[2]
	while f3 > 0 do
		note = note + 4
		if class == 7 then -- B
			sharps = sharps + 1
		end
		if class == 7 or class == 2 then -- B or D
			pluses = pluses + 1
		end
		f3 = f3 - 1
		class = (note - 1) % 7 + 1
	end
	-- For every 3 in the denominator:
	-- Descend one perfect fifth. (Add minus if starting on an A or F.)
	while f3 < 0 do
		note = note - 4
		if class == 4 then -- F
			sharps = sharps - 1
		end
		if class == 4 or class == 6 then
			pluses = pluses - 1
		end
		f3 = f3 + 1
		class = (note - 1) % 7 + 1
	end

	-- For every 5 in the numerator:
	-- Ascend one major 3rd. (Add plus if starting on a D.)
	local f5 = factors[3]
	while f5 > 0 do
		note = note + 2
		if class == 2 or class == 3 or class == 6 or class == 7 then
			sharps = sharps + 1
		end
		if class == 2 then
			pluses = pluses + 1
		end
		f5 = f5 - 1
		class = (note - 1) % 7 + 1
	end
	-- For every 5 in the denominator:
	-- Descend one major 3rd. (Add minus if starting on an F.)
	while f5 < 0 do
		note = note - 2
		if class == 1 or class == 2 or class == 4 or class == 5 then
			sharps = sharps - 1
		end
		if class == 4 then
			pluses = pluses - 1
		end
		f5 = f5 + 1
		class = (note - 1) % 7 + 1
	end

	-- For every 7 in the numerator:
	-- Ascend one minor seventh and add a 7. (Add plus if starting on a G, B, or D.)
	local f7 = factors[4]
	while f7 > 0 do
		note = note + 6
		if class == 1 or class == 4 then
			sharps = sharps - 1
		end
		if class == 2 or class == 5 or class == 7 then
			pluses = pluses + 1
		end
		sevens = sevens + 1
		f7 = f7 - 1
		class = (note - 1) % 7 + 1
	end
	-- For every 7 in the denominator:
	-- Descend one minor seventh and add a L (sub-7). (Add minus if starting on an F, A, or C.)
	while f7 < 0 do
		note = note - 6
		if class == 3 or class == 7 then
			sharps = sharps + 1
		end
		if class == 1 or class == 4 or class == 6 then
			pluses = pluses - 1
		end
		sevens = sevens - 1
		f7 = f7 + 1
		class = (note - 1) % 7 + 1
	end

	-- For every 11 in the numerator:
	-- Ascend one perfect fourth and add ^ (up-arrow). (Add minus if starting on an A or F.)
	local f11 = factors[5]
	while f11 > 0 do
		note = note + 3
		if class == 4 then
			sharps = sharps - 1
		end
		if class == 4 or class == 6 then
			pluses = pluses - 1
		end
		arrows = arrows + 1
		f11 = f11 - 1
		class = (note - 1) % 7 + 1
	end
	-- For every 11 in the denominator:
	-- Descend one perfect fourth and add v (down-arrow). (Add plus if starting on a B or D.)
	while f11 < 0 do
		note = note - 3
		if class == 7 then
			sharps = sharps + 1
		end
		if class == 2 or class == 7 then
			pluses = pluses + 1
		end
		arrows = arrows - 1
		f11 = f11 + 1
		class = (note - 1) % 7 + 1
	end

	-- For every 13 in the numerator:
	-- Ascend one minor sixth and add a 13. (Add minus if starting on an F.)
	local f13 = factors[6]
	while f13 > 0 do
		note = note + 5
		if class == 1 or class == 2 or class == 4 or class == 5 then
			sharps = sharps - 1
		end
		if class == 4 then
			pluses = pluses - 1
		end
		thirteens = thirteens + 1
		f13 = f13 - 1
		class = (note - 1) % 7 + 1
	end
	-- For every 13 in the denominator:
	-- Descend one minor sixth and add an upside-down 13. (Add plus if starting on a D.)
	while f13 < 0 do
		note = note - 5
		if class == 2 or class == 3 or class == 6 or class == 7 then
			sharps = sharps + 1
		end
		if class == 2 then
			pluses = pluses + 1
		end
		thirteens = thirteens - 1
		f13 = f13 + 1
		class = (note - 1) % 7 + 1
	end

	-- For every 17 in the numerator:
	-- Add a sharp and a 17.
	-- For every 17 in the denominator:
	-- Add a flat and an upside-down 17.
	sharps = sharps + factors[7]
	seventeens = factors[7]

	-- For every 19 in the numerator:
	-- Ascend a minor third and add a 19. (Add plus if starting on a D.)
	local f19 = factors[8]
	while f19 > 0 do
		note = note + 2
		if class == 1 or class == 4 or class == 5 then
			sharps = sharps - 1
		end
		if class == 2 then
			pluses = pluses + 1
		end
		nineteens = nineteens + 1
		f19 = f19 - 1
		class = (note - 1) % 7 + 1
	end
	-- For every 19 in the denominator:
	-- Descend a minor third and add an upside-down 19. (Add minus if starting on an F.) 
	while f19 < 0 do
		note = note - 2
		if class == 3 or class == 6 or class == 7 then
			sharps = sharps + 1
		end
		if class == 4 then
			pluses = pluses - 1
		end
		nineteens = nineteens - 1
		f19 = f19 + 1
		class = (note - 1) % 7 + 1
	end

	local name = Ratio.notes[class].name
	ac[1][2] = sharps
	ac[2][2] = -sharps
	ac[3][2] = sevens
	ac[4][2] = -sevens
	ac[5][2] = arrows
	ac[6][2] = -arrows
	ac[7][2] = thirteens
	ac[8][2] = -thirteens
	ac[9][2] = seventeens
	ac[10][2] = -seventeens
	ac[11][2] = nineteens
	ac[12][2] = -nineteens
	ac[13][2] = pluses
	ac[14][2] = -pluses

	for i, a in ipairs(ac) do
		local accidental, count = a[1], a[2]
		while count > 0 do
			name = name .. accidental
			count = count - 1
		end
	end

	local check = Ratio.dejohnstonize(name)
	for p = 2, n_primes do -- ignore factors of 2
		if check.factors[p] ~= factors[p] then
			print('can\'t fully johnstonize')
			print(debug.traceback())
			self._name = self:__tostring()
			return
		end
	end
	
	self._name = name
end

function Ratio.dejohnstonize(name)
	local ratio = Ratio.new()
	local accidentals = Ratio.accidentals
	while string.len(name) > 0 do
		local char = string.sub(name, -1, -1)
		local pair = string.sub(name, -2, -1)
		if accidentals[pair] ~= nil then
			ratio = ratio * accidentals[pair]
			name = string.sub(name, 1, -3)
		elseif accidentals[char] ~= nil then
			ratio = ratio * accidentals[char]
			name = string.sub(name, 1, -2)
		elseif string.len(name) == 1 and Ratio.notes[name] ~= nil then
			ratio = ratio * Ratio.notes[name]
			name = string.sub(name, 1, -2)
		else
			print(name)
			error('can\'t dejohnstonize')
			return nil
		end
	end
	return ratio
end

-- base notes in Ben Johnston's notation (look up by name or number)
Ratio.notes = {
	Ratio.new(1, 1),
	Ratio.new(9, 8),
	Ratio.new(5, 4),
	Ratio.new(4, 3),
	Ratio.new(3, 2),
	Ratio.new(5, 3),
	Ratio.new(15, 8)
}
Ratio.notes.C = Ratio.notes[1]
Ratio.notes.D = Ratio.notes[2]
Ratio.notes.E = Ratio.notes[3]
Ratio.notes.F = Ratio.notes[4]
Ratio.notes.G = Ratio.notes[5]
Ratio.notes.A = Ratio.notes[6]
Ratio.notes.B = Ratio.notes[7]
-- set `name` directly to bypass __newindex and __index
for name, ratio in pairs(Ratio.notes) do
	if type(name) == 'string' then
		rawset(ratio, 'name', name)
	end
end

Ratio.accidentals = {
	['+']  = Ratio.new(81, 80),
	['-']  = Ratio.new(80, 81),
	['#']  = Ratio.new(25, 24),
	['b']  = Ratio.new(24, 25),
	['7']  = Ratio.new(35, 36),
	['L']  = Ratio.new(36, 35),
	['^']  = Ratio.new(33, 32),
	['v']  = Ratio.new(32, 33),
	['13'] = Ratio.new(65, 64),
	['El'] = Ratio.new(64, 65),
	['17'] = Ratio.new(51, 50),
	['Ll'] = Ratio.new(50, 51),
	['19'] = Ratio.new(95, 96),
	['6l'] = Ratio.new(96, 95),
	['23'] = Ratio.new(46, 45),
	['EZ'] = Ratio.new(45, 46),
	['29'] = Ratio.new(145, 144),
	['6Z'] = Ratio.new(144, 145),
	['31'] = Ratio.new(31, 30),
	['lE'] = Ratio.new(30, 31)
}

Ratio.primes = primes
Ratio.n_primes = n_primes

return Ratio