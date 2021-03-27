-- All little endian

--+ Reads doubles (f64) or floats (f32)
--: double reads an f64 if true, f32 otherwise
function read_float(read_byte, double)
	-- First read the mantissa
	local mantissa = 0
	for _ = 1, double and 6 or 2 do
		mantissa = (mantissa + read_byte()) / 0x100
	end
	-- Second and first byte in big endian: last bit of exponent + 7 bits of mantissa, sign bit + 7 bits of exponent
	local byte_2, byte_1 = read_byte(), read_byte()
	local sign = 1
	if byte_1 >= 0x80 then
		sign = -1
		byte_1 = byte_1 - 0x80
	end
	local exponent = byte_1 * 2
	if byte_2 >= 0x80 then
		exponent = exponent + 1
		byte_2 = byte_2 - 0x80
	end
	mantissa = (mantissa + byte_2) / 0x80
	if exponent == 0xFF then
		if mantissa == 0 then
			return sign * math.huge
		end
		-- Differentiating quiet and signalling nan is not possible in Lua, hence we don't have to do it
		-- HACK ((0/0)^1) yields nan, 0/0 yields -nan
		return sign == 1 and ((0/0)^1) or 0/0
	end
	assert(mantissa < 1)
	if exponent == 0 then
		-- subnormal value
		return sign * 2^-126 * mantissa
	end
	return sign * 2 ^ (exponent - 127) * (1 + mantissa)
end

--+ Reads a single floating point number (f32)
function read_single(read_byte)
	return read_float(read_byte)
end

--+ Reads a double (f64)
function read_double(read_byte)
	return read_float(read_byte, true)
end

function read_uint(read_byte, bytes)
	local factor = 1
	local uint = 0
	for _ = 1, bytes do
		uint = uint + read_byte() * factor
		factor = factor * 0x100
	end
	return uint
end

function write_uint(write_byte, uint, bytes)
	for _ = 1, bytes do
		write_byte(uint % 0x100)
		uint = math.floor(uint / 0x100)
	end
	assert(uint == 0)
end

--: on_write function(double)
--: double set to true to force f64, false for f32, nil for auto
function write_float(write_byte, number, on_write, double)
	local sign = 0
	if number < 0 then
		number = -number
		sign = 0x80
	end
	local mantissa, exponent = math.frexp(number)
	exponent = exponent + 127
	if exponent > 1 then
		-- TODO ensure this deals properly with subnormal numbers
		mantissa = mantissa * 2 - 1
		exponent = exponent - 1
	end
	local sign_byte = sign + math.floor(exponent / 2)
	mantissa = mantissa * 0x80
	local exponent_byte = (exponent % 2) * 0x80 + math.floor(mantissa)
	mantissa = mantissa % 1
	local mantissa_bytes = {}
	-- TODO ensure this check is proper
	if double == nil then
		double = mantissa % 2^-23 > 0
	end
	if on_write then
		on_write(double)
	end
	local len = double and 6 or 2
	for index = len, 1, -1 do
		mantissa = mantissa * 0x100
		mantissa_bytes[index] = math.floor(mantissa)
		mantissa = mantissa % 1
	end
	assert(mantissa == 0)
	for index = 1, len do
		write_byte(mantissa_bytes[index])
	end
	write_byte(exponent_byte)
	write_byte(sign_byte)
end

function write_single(write_byte, number)
	return write_float(write_byte, number, nil, false)
end

function write_double(write_byte, number)
	return write_float(write_byte, number, nil, true)
end