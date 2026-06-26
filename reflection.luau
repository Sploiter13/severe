--!strict
--!optimize 2

local descoff = 0x18
local propsoff = 0x40
local stride = 0x10
local nameoff = 0x8
local gsoff = 0x90
local getoff = 0x8
local gvoff = 0x18

--this part is made by ai

local function ptr(a: number): number?
	if a <= 0x10000 or a >= 0x7FFFFFFFFFFF then
		return nil
	end
	local ok, v = pcall(memory.readu64, a)
	return if ok and v ~= nil and v > 0x10000 and v < 0x7FFFFFFFFFFF then v else nil
end

local function code(a: number?, n: number): { number }?
	if a == nil or a <= 0x10000 or a >= 0x7FFFFFFFFFFF then
		return nil
	end
	local ok, buf = pcall(memory.readbuffer, a, n)
	if not ok or buf == nil then
		return nil
	end
	local out = table.create(n)
	for i = 0, n - 1 do
		out[i + 1] = buffer.readu8(buf, i)
	end
	return out
end

local function sx(v: number): number
	return if v >= 0x80000000 then v - 0x100000000 else v
end

local function dw(b: { number }, i: number): number
	return b[i] + b[i + 1] * 0x100 + b[i + 2] * 0x10000 + b[i + 3] * 0x1000000
end

local function grabdelta(b: { number }): number?
	for i = 1, 56 do
		if b[i + 1] == 0x8D and (b[i + 2] // 0x8) % 0x8 == 1 then
			local rm = b[i + 2] % 0x8
			local mod = b[i + 2] // 0x40
			if (b[i] == 0x48 and rm == 2) or (b[i] == 0x49 and rm == 0) then
				if mod == 1 then
					return b[i + 3]
				elseif mod == 2 then
					return dw(b, i + 3)
				end
			end
		end
	end
	local d1: number? = nil
	for i = 1, 56 do
		if
			(b[i] == 0x48 and b[i + 1] == 0x8D and b[i + 2] == 0x82)
			or (b[i] == 0x49 and b[i + 1] == 0x8D and b[i + 2] == 0x80)
		then
			d1 = sx(dw(b, i + 3))
		elseif b[i] == 0x48 and b[i + 1] == 0x8D and b[i + 2] == 0x88 and d1 ~= nil then
			return d1 + sx(dw(b, i + 3))
		end
	end
	return nil
end

local function getdelta(getset: number): number?
	local vtable = ptr(getset)
	if vtable == nil then
		return nil
	end
	local b = code(ptr(vtable + gvoff), 72)
	if b == nil then
		return nil
	end
	return grabdelta(b)
end

local function nogv(getset: number): boolean
	local vtable = ptr(getset)
	if vtable == nil then
		return false
	end
	local a = ptr(vtable + gvoff)
	if a == nil then
		return true
	end
	local b = code(a, 16)
	if b == nil then
		return true
	end
	for i = 1, 16 do
		if b[i] ~= 0 then
			return false
		end
	end
	return true
end

local function grabgv(getset: number): (number?, number?, { number }?)
	local vtable = ptr(getset)
	if vtable == nil then
		return nil, nil, nil
	end
	local a = ptr(vtable + gvoff)
	if a == nil then
		return nil, nil, nil
	end
	local b = code(a, 72)
	if b == nil then
		return nil, a, nil
	end
	return grabdelta(b), a, b
end

local function chase(a: number, b: { number }): { number }?
	for i = 1, 60 do
		if b[i] == 0xFF and (b[i + 1] == 0x25 or b[i + 1] == 0x15) then
			local p = ptr(a + i + 5 + sx(dw(b, i + 2)))
			return if p ~= nil then code(p, 48) else nil
		end
	end
	for i = 1, 60 do
		if b[i] == 0xE9 or b[i] == 0xE8 then
			return code(a + i + 4 + sx(dw(b, i + 1)), 48)
		end
	end
	return nil
end

local function indleaf(b: { number }, want: string): (number?, number?)
	for i = 1, 24 do
		local prim: number? = nil
		local at: number? = nil
		if b[i] == 0x48 and b[i + 1] == 0x8B and b[i + 2] == 0x81 then
			prim, at = dw(b, i + 3), i + 7
		elseif b[i] == 0x48 and b[i + 1] == 0x8B and b[i + 2] == 0x41 then
			prim, at = b[i + 3], i + 4
		end
		if prim ~= nil and at ~= nil then
			for s = at, at + 26 do
				local p: number? = nil
				if want == "f32" and b[s] == 0xF3 and b[s + 1] == 0x0F and b[s + 2] == 0x10 then
					p = s + 3
				elseif want == "f64" and b[s] == 0xF2 and b[s + 1] == 0x0F and b[s + 2] == 0x10 then
					p = s + 3
				elseif want == "u8" and b[s] == 0x0F and b[s + 1] == 0xB6 then
					p = s + 2
				elseif want == "i32" and b[s] == 0x8B then
					p = s + 1
				elseif want == "i64" and b[s] == 0x48 and b[s + 1] == 0x8B then
					p = s + 2
				end
				if p ~= nil and b[p] ~= nil and b[p] % 0x8 == 0 and (b[p] // 0x8) % 0x8 == 0 then
					local mod = b[p] // 0x40
					if mod == 1 then
						return prim, b[p + 1]
					elseif mod == 2 then
						return prim, dw(b, p + 1)
					end
				end
			end
		end
	end
	return nil, nil
end

--reader copies a struct straight outta rcx+disp
local function strdir(b: { number }): number?
	for i = 1, 40 do
		local at: number? = nil
		if b[i] == 0x0F and b[i + 1] == 0x10 then
			at = i + 2
		elseif (b[i] == 0xF2 or b[i] == 0xF3) and b[i + 1] == 0x0F and b[i + 2] == 0x10 then
			at = i + 3
		end
		if at ~= nil and b[at] ~= nil and b[at] % 0x8 == 1 then
			local mod = b[at] // 0x40
			if mod == 1 then
				return b[at + 1]
			elseif mod == 2 then
				return dw(b, at + 1)
			end
		end
	end
	return nil
end

local function strind(b: { number }): (number?, number?)
	for i = 1, 24 do
		local prim: number? = nil
		local at: number? = nil
		if b[i] == 0x48 and b[i + 1] == 0x8B and b[i + 2] == 0x81 then
			prim, at = dw(b, i + 3), i + 7
		elseif b[i] == 0x48 and b[i + 1] == 0x8B and b[i + 2] == 0x41 then
			prim, at = b[i + 3], i + 4
		end
		if prim ~= nil and at ~= nil then
			for s = at, at + 26 do
				local p: number? = nil
				if b[s] == 0x0F and b[s + 1] == 0x10 then
					p = s + 2
				elseif (b[s] == 0xF2 or b[s] == 0xF3) and b[s + 1] == 0x0F and b[s + 2] == 0x10 then
					p = s + 3
				end
				if p ~= nil and b[p] ~= nil and b[p] % 0x8 == 0 and (b[p] // 0x8) % 0x8 == 0 then
					local mod = b[p] // 0x40
					if mod == 1 then
						return prim, b[p + 1]
					elseif mod == 2 then
						return prim, dw(b, p + 1)
					end
				end
			end
		end
	end
	return nil, nil
end

local function leaf(b: { number }, start: number): (number?, string?)
	local kind: string?
	local at: number?
	if b[start] == 0xF3 and b[start + 1] == 0x0F and b[start + 2] == 0x10 then
		kind, at = "f32", start + 3
	elseif b[start] == 0xF2 and b[start + 1] == 0x0F and b[start + 2] == 0x10 then
		kind, at = "f64", start + 3
	elseif b[start] == 0x0F and b[start + 1] == 0xB6 then
		kind, at = "u8", start + 2
	elseif b[start] == 0x0F and b[start + 1] == 0xB7 then
		kind, at = "u16", start + 2
	elseif b[start] == 0x8B then
		kind, at = "i32", start + 1
	elseif b[start] == 0x48 and b[start + 1] == 0x8B then
		kind, at = "i64", start + 2
	end
	if kind == nil or at == nil then
		return nil, nil
	end
	local modrm = b[at]
	if modrm % 0x8 ~= 1 then
		return nil, nil
	end
	local mod = modrm // 0x40
	if mod == 1 then
		return b[at + 1], kind
	elseif mod == 2 then
		return dw(b, at + 1), kind
	end
	return nil, nil
end

local function hunt(b: { number }, want: string): (number?, string?)
	for start = 1, 40 do
		local disp, kind = leaf(b, start)
		if disp ~= nil and kind == want then
			return disp, kind
		end
	end
	return nil, nil
end

local function dirfield(b: { number }, want: string): (number?, string?)
	for i = 1, 36 do
		local disp: number? = nil
		local at: number? = nil
		if b[i] == 0x48 and b[i + 1] == 0x8D and b[i + 2] == 0x41 then
			disp, at = b[i + 3], i + 4
		elseif b[i] == 0x48 and b[i + 1] == 0x8D and b[i + 2] == 0x81 then
			disp, at = dw(b, i + 3), i + 7
		end
		if disp ~= nil and at ~= nil then
			for s = at, at + 16 do
				local kind: string? = nil
				if b[s] == 0x0F and b[s + 1] == 0xB6 and b[s + 2] == 0x00 then
					kind = "u8"
				elseif b[s] == 0x0F and b[s + 1] == 0xB7 and b[s + 2] == 0x00 then
					kind = "u16"
				elseif b[s] == 0x8B and b[s + 1] == 0x00 then
					kind = "i32"
				elseif b[s] == 0x48 and b[s + 1] == 0x8B and b[s + 2] == 0x00 then
					kind = "i64"
				elseif b[s] == 0xF3 and b[s + 1] == 0x0F and b[s + 2] == 0x10 and b[s + 3] == 0x00 then
					kind = "f32"
				elseif b[s] == 0xF2 and b[s + 1] == 0x0F and b[s + 2] == 0x10 and b[s + 3] == 0x00 then
					kind = "f64"
				end
				if kind == want then
					return disp, kind
				end
			end
		end
	end
	return hunt(b, want)
end

--this actually took me some time to figure it out like some alot of time cause of the stupid fflags lol
local function flagfield(b: { number }, want: string, delta: number): (number?, string?)
	local flagged = false
	for i = 1, 18 do
		if b[i] == 0x0F and b[i + 1] == 0xB6 and b[i + 2] == 0x05 then
			flagged = true
			break
		end
	end
	if not flagged then
		return nil
	end
	local rebase = 0
	for i = 1, 80 do
	--oho when u first see it
		if b[i] == 0x48 and b[i + 1] == 0x8D and b[i + 2] == 0xB9 then
			rebase = sx(dw(b, i + 3))
			break
		end
	end
	for i = 3, 88 do
		local kind: string? = nil
		local at: number? = nil
		if want == "f32" and b[i] == 0xF3 and b[i + 1] == 0x0F and b[i + 2] == 0x10 then
			kind, at = "f32", i + 3
		elseif want == "f64" and b[i] == 0xF2 and b[i + 1] == 0x0F and b[i + 2] == 0x10 then
			kind, at = "f64", i + 3
		elseif want == "u8" and b[i] == 0x0F and b[i + 1] == 0xB6 then
			kind, at = "u8", i + 2
		elseif want == "u16" and b[i] == 0x0F and b[i + 1] == 0xB7 then
			kind, at = "u16", i + 2
		elseif want == "i32" and b[i] == 0x8B then
			kind, at = "i32", i + 1
		elseif want == "i64" and b[i] == 0x48 and b[i + 1] == 0x8B then
			kind, at = "i64", i + 2
		end
		if kind ~= nil and at ~= nil then
			local modrm = b[at]
			local rm = modrm % 0x8
			local mod = modrm // 0x40
			local disp: number? = nil
			if mod == 1 then
				disp = b[at + 1]
			elseif mod == 2 then
				disp = dw(b, at + 1)
			end
			if disp ~= nil then
			-- rm= 7 means rebased base rebase already done in so add it
			-- rm=1 -3 -6 means subobject so no rebase is really needed
				if rm == 7 then
					return delta + rebase + disp, kind
				elseif rm == 1 or rm == 3 or rm == 6 then
					return delta + disp, kind
				end
			end
		end
	end
	return nil
end

local function flagstruct(b: { number }): number?
	local flagged = false
	for i = 1, 18 do
		if b[i] == 0x0F and b[i + 1] == 0xB6 and b[i + 2] == 0x05 then
			flagged = true
			break
		end
	end
	if not flagged then
		return nil
	end
	for i = 3, 88 do
		local at: number? = nil
		if (b[i] == 0xF3 or b[i] == 0xF2) and b[i + 1] == 0x0F and b[i + 2] == 0x10 then
			at = i + 3
		elseif b[i] == 0x0F and b[i + 1] == 0x10 then
			at = i + 2
		end
		if at ~= nil and b[at] ~= nil and b[at] % 0x8 == 3 then
			local mod = b[at] // 0x40
			if mod == 1 then
				return b[at + 1]
			elseif mod == 2 then
				return dw(b, at + 1)
			end
		end
	end
	return nil
end

local function lea(b: { number }): number?
	for i = 1, 18 do
		if b[i] == 0x48 and b[i + 1] == 0x8D and b[i + 2] % 0x8 == 1 then
			local mod = b[i + 2] // 0x40
			if mod == 1 then
				return b[i + 3]
			elseif mod == 2 then
				return dw(b, i + 3)
			end
		end
	end
	return nil
end

local function simd(b: { number }): number?
	for i = 1, 18 do
		local at: number? = nil
		if b[i] == 0x0F and b[i + 1] == 0x10 then
			at = i + 2
		elseif (b[i] == 0xF2 or b[i] == 0xF3) and b[i + 1] == 0x0F and b[i + 2] == 0x10 then
			at = i + 3
		end
		if at ~= nil and b[at] ~= nil and b[at] % 0x8 == 1 then
			local mod = b[at] // 0x40
			if mod == 0 then
				return 0 
			elseif mod == 1 then
				return b[at + 1]
			elseif mod == 2 then
				return dw(b, at + 1)
			end
		end
	end
	return nil
end

-- smallest movs in the bytes = the rect base gui rect gettr reads
--+0x110=pos.x +0x114=pos.y +0x118/0x11c =size so min disp is whre it starts
local function minsimd(b: { number }): number?
	local best: number? = nil
	for i = 1, #b - 4 do
		if (b[i] == 0xF3 or b[i] == 0xF2) and b[i + 1] == 0x0F and b[i + 2] == 0x10 and b[i + 3] % 0x8 == 1 then
			local mod = b[i + 3] // 0x40
			local disp: number? = if mod == 1 then b[i + 4] elseif mod == 2 then dw(b, i + 4) else nil
			if disp ~= nil and (best == nil or disp < best) then
				best = disp
			end
		end
	end
	return best
end

local function dlea(b: { number }): number?
	if b[1] == 0x48 and b[2] == 0x8D and b[3] % 0x8 == 1 then
		local mod = b[3] // 0x40
		if mod == 1 then
			return b[4]
		elseif mod == 2 then
			return dw(b, 4)
		end
	end
	return nil
end

-- ai made
local function addthunk(a: number, b: { number }): (number?, { number }?)
	local imm: number? = nil
	local after: number? = nil
	for i = 1, 24 do
		if b[i] == 0x48 and b[i + 1] == 0x81 and b[i + 2] == 0xC1 then
			imm, after = sx(dw(b, i + 3)), i + 7
			break
		elseif b[i] == 0x48 and b[i + 1] == 0x83 and b[i + 2] == 0xC1 then
			imm, after = (if b[i + 3] >= 0x80 then b[i + 3] - 0x100 else b[i + 3]), i + 4
			break
		end
	end
	if imm == nil or after == nil then
		return nil, nil
	end
	for i = after, 40 do
		if b[i] == 0xE9 or b[i] == 0xE8 then
			return imm, code(a + i + 4 + sx(dw(b, i + 1)), 40)
		end
		if b[i] == 0xFF and (b[i + 1] == 0x25 or b[i + 1] == 0x15) then
			local p = ptr(a + i + 5 + sx(dw(b, i + 2)))
			return imm, if p ~= nil then code(p, 40) else nil
		end
	end
	return imm, nil
end

-- bool isjust 1 bit spits out the ptr the byte offset into it and which bit
local function bitflag(b: { number }): (number?, number?, number?)
	if not (b[1] == 0x48 and b[2] == 0x8B and (b[3] == 0x81 or b[3] == 0x41)) then
		return nil, nil, nil
	end
	local prim: number
	local i: number
	if b[3] == 0x81 then
		prim, i = dw(b, 4), 8
	else
		prim, i = b[4], 5
	end
	if not (b[i] == 0x0F and b[i + 1] == 0xB6 and (b[i + 2] == 0x80 or b[i + 2] == 0x40)) then
		return nil, nil, nil
	end
	local flag: number
	local j: number
	if b[i + 2] == 0x80 then
		flag, j = dw(b, i + 3), i + 7
	else
		flag, j = b[i + 3], i + 4
	end
	local bit = 0
	if b[j] == 0xD0 and b[j + 1] == 0xE8 then
		bit = 1
	elseif b[j] == 0xC0 and b[j + 1] == 0xE8 then
		bit = b[j + 2]
	end
	return prim, flag, bit
end

local function kindof(rtti: string): string
	if string.find(rtti, "RefPropDescriptor", 1, true) ~= nil then
		return "ref"
	elseif string.find(rtti, "EnumPropDescriptor", 1, true) ~= nil then
		return "enum"
	elseif string.find(rtti, "basic_string", 1, true) ~= nil then
		return "string"
	elseif string.find(rtti, "Color3", 1, true) ~= nil then
		return "color3"
	elseif string.find(rtti, "Vector3", 1, true) ~= nil then
		return "vector3"
	elseif string.find(rtti, "Vector2", 1, true) ~= nil then
		return "vector2"
	elseif string.find(rtti, "UDim2", 1, true) ~= nil then
		return "udim2"
	elseif string.find(rtti, "NumberRange", 1, true) ~= nil then
		return "numberrange"
	elseif string.find(rtti, "CoordinateFrame", 1, true) ~= nil then
		return "cframe"
	elseif string.find(rtti, "Rect2D", 1, true) ~= nil or string.find(rtti, "Rect>", 1, true) ~= nil then
		return "rect"
	elseif string.find(rtti, ",double>", 1, true) ~= nil then
		return "double"
	elseif string.find(rtti, ",float>", 1, true) ~= nil then
		return "float"
	elseif string.find(rtti, ",bool>", 1, true) ~= nil then
		return "bool"
	elseif string.find(rtti, ",__int64>", 1, true) ~= nil then
		return "int64"
	elseif string.find(rtti, ",int>", 1, true) ~= nil then
		return "int"
	end
	return "other"
end

-- ai made
local function lthunk(a: number, b: { number }): (number?, { number }?)
	local imm: number? = nil
	for i = 1, 24 do
		if (b[i] == 0x48 or b[i] == 0x4C) and b[i + 1] == 0x8D and b[i + 2] == 0x81 then
			imm = sx(dw(b, i + 3))
			break
		end
	end
	if imm == nil then
		return nil, nil
	end
	for i = 1, 50 do
		if b[i] == 0xE8 then
			return imm, code(a + i + 4 + sx(dw(b, i + 1)), 40)
		end
	end
	return imm, nil
end

local function slea(b: { number }): number?
	for i = 1, 16 do
		if b[i] == 0x48 and b[i + 1] == 0x8D and b[i + 2] % 0x8 == 1 then
			local mod = b[i + 2] // 0x40
			if mod == 1 then
				return b[i + 3]
			elseif mod == 2 then
				return dw(b, i + 3)
			end
		end
	end
	return nil
end

local function u8col(b: { number }): number?
	for i = 1, 24 do
		if b[i] == 0x0F and b[i + 1] == 0xB7 then
			if b[i + 2] == 0x81 then
				return dw(b, i + 3)
			elseif b[i + 2] == 0x41 then
				return b[i + 3]
			end
		end
	end
	return nil
end

local function isconv(b: { number }): boolean
	for i = 1, 30 do
		if (b[i] == 0xF2 or b[i] == 0xF3) and b[i + 1] == 0x0F and b[i + 2] == 0x10 then
			return false
		end
		if b[i] == 0x0F and b[i + 1] == 0x10 then
			return false
		end
		if b[i] == 0xE8 then
			return true
		end
	end
	return false
end

-- real getter reads throough a ptrr here
local function indchain(b: { number }): (number?, number?)
	if not (b[1] == 0x48 and b[2] == 0x8B and b[3] == 0x81) then
		return nil, nil
	end
	local prim = dw(b, 4)
	for i = 8, 22 do
		if (b[i] == 0xF2 or b[i] == 0xF3) and b[i + 1] == 0x0F and b[i + 2] == 0x10 and b[i + 3] == 0x80 then
			return prim, dw(b, i + 4)
		end
		if b[i] == 0x0F and b[i + 1] == 0x10 and b[i + 2] == 0x80 then
			return prim, dw(b, i + 3)
		end
	end
	return nil, nil
end

local function hasflag(b: { number }): boolean
	for i = 1, 20 do
		if b[i] == 0x0F and b[i + 1] == 0xB6 and b[i + 2] == 0x05 then
			return true
		end
	end
	return false
end

local wants: { [string]: string } = {
	float = "f32",
	double = "f64",
	bool = "u8",
	int = "i32",
	int64 = "i64",
}

type plan = { mode: string, off: number, flag: number?, bit: number?, vec: number?, indirect: boolean? }
local cache: { [string]: plan } = {}

local function findprop(desc: number, name: string): number?
	local base = ptr(desc + propsoff)
	if base == nil then
		return nil
	end
	for i = 0, 900 do
		local pd = ptr(base + i * 0x10)
		if pd == nil then
			break
		end
		local tok, rtti = pcall(memory.rtti, pd)
		if not tok or rtti == nil or string.find(rtti, "escriptor", 1, true) == nil then
			break
		end
		local np = ptr(pd + nameoff)
		if np ~= nil then
			local nok, n = pcall(memory.readstring, np)
			if nok and n == name then
				return pd
			end
		end
	end
	return nil
end

--figures ou where the gui rect actually lives by looking through the rect2d getter the rebase cancels the delta so whatever disp it reads is already the real offset this was trikcy a bit
local function rectbase(desc: number): number?
	local pd = findprop(desc, "RawRect2D")
	if pd == nil then
		return nil
	end
	local getset = ptr(pd + gsoff)
	if getset == nil then
		return nil
	end
	local getter = ptr(getset + getoff)
	local gb = code(getter, 48)
	if getter == nil or gb == nil then
		return nil
	end
	local _, real = lthunk(getter, gb)
	return if real ~= nil then minsimd(real) else nil
end

local function owner(rtti: string): string?
	local m = string.find(rtti, "Descriptor<class ", 1, true)
	if m == nil then
		return nil
	end
	local start = m + 17
	local comma = string.find(rtti, ",", start, true)
	return if comma ~= nil then string.sub(rtti, start, comma - 1) else nil
end

local dcache: { [string]: number } = {}
local function owndelta(desc: number, who: string?): number?
	if who == nil then
		return nil
	end
	local hit = dcache[who]
	if hit ~= nil then
		return if hit >= 0 then hit else nil
	end
	local base = ptr(desc + propsoff)
	if base ~= nil then
		for k = 0, 1200 do
			local pd = ptr(base + k * stride)
			if pd == nil then
				break
			end
			local tok, rt = pcall(memory.rtti, pd)
			if not tok or rt == nil or string.find(rt, "escriptor", 1, true) == nil then
				break
			end
			if owner(rt) == who then
				local gs = ptr(pd + gsoff)
				local d = if gs ~= nil then getdelta(gs) else nil
				if d ~= nil then
					dcache[who] = d
					return d
				end
			end
		end
	end
	dcache[who] = -1
	return nil
end

-- this part is made by ai
local function makeplan(instance: number, name: string): plan?
	local desc = ptr(instance + descoff)
	if desc == nil then
		return nil
	end
	local pd = findprop(desc, name)
	if pd == nil then
		return nil
	end
	local tok, rt = pcall(memory.rtti, pd)
	local rtti = if tok and rt ~= nil then rt else ""
	local kind = kindof(rtti)
	local getset = ptr(pd + gsoff)
	if getset == nil then
		return nil
	end
	local delta = getdelta(getset)
	local getter = ptr(getset + getoff)
	local gb = code(getter, 48)
	if getter == nil or gb == nil then
		return nil
	end

	if kind == "rect" then
		local _, real = lthunk(getter, gb)
		local base = if real ~= nil then minsimd(real) else nil
		return if base ~= nil then { mode = "rect", off = base } else nil
	end
	if kind == "vector2" and (name == "AbsolutePosition" or name == "AbsoluteSize") then
		local base = rectbase(desc)
		if base ~= nil then
			return { mode = "vector2", off = if name == "AbsoluteSize" then base + 8 else base }
		end
	end

	if delta == nil then
		delta = owndelta(desc, owner(rtti))
	end

	if delta == nil then
		local probe = dlea(gb) or simd(gb) or lea(gb)
		if nogv(getset) and probe ~= nil and probe >= 0x40 then
			delta = 0
		else
			return nil
		end
	end

	if kind == "string" then
		local disp = lea(gb)
		if disp ~= nil then
			return { mode = "string", off = disp + delta }
		end

		local gvd, gva, gvb = grabgv(getset)
		local use = gvd or delta
		if gva ~= nil and gvb ~= nil and use ~= nil then
			local reader = chase(gva, gvb)
			if reader ~= nil then
				local sd = slea(reader)
				if sd ~= nil then
					return { mode = "string", off = sd + use }
				end
			end
		end

		local imm, real = addthunk(getter, gb)
		if imm ~= nil and real ~= nil then
			local sd = slea(real)
			if sd ~= nil then
				return { mode = "string", off = delta + imm + sd }
			end
		end
		return nil
	elseif kind == "color3" then
		local base = simd(gb)
		if base ~= nil then
			return { mode = "color3", off = base + delta }
		end

		local direct = dlea(gb)
		if direct ~= nil then
			return { mode = "color3", off = direct + delta }
		end
		local imm, real = lthunk(getter, gb)
		if imm ~= nil and real ~= nil then
			local ud = u8col(real)
			if ud ~= nil then
				return { mode = "color3uint8", off = delta + imm + ud }
			end
			local disp = slea(real)
			if disp ~= nil then
				if isconv(real) then
					return { mode = "color3uint8", off = delta + imm + disp }
				end
				return { mode = "color3", off = delta + imm + disp }
			end
			local prim, vec = indchain(real)
			if prim ~= nil and vec ~= nil then
				return { mode = "indirectcolor3", off = delta + imm + prim, vec = vec }
			end
		end
		local gvd, gva, gvb = grabgv(getset)
		local use = gvd or delta
		if gva ~= nil and gvb ~= nil and use ~= nil then
			local reader = chase(gva, gvb)
			if reader ~= nil then
				local disp = strdir(reader)
				if disp ~= nil then
					return { mode = "color3", off = disp + use }
				end
				local prim, vec = strind(reader)
				if prim ~= nil and vec ~= nil then
					return { mode = "indirectcolor3", off = prim + use, vec = vec }
				end
			end
		end
		if hasflag(gb) then
			local wide = code(getter, 96)
			local fd = if wide ~= nil then flagstruct(wide) else nil
			if fd ~= nil then
				return { mode = "color3", off = fd + delta }
			end
		end
		return nil
	elseif kind == "vector3" then
		local base = simd(gb)
		if base ~= nil then
			return { mode = "vector3", off = base + delta }
		end
		local direct = dlea(gb)
		if direct ~= nil then
			return { mode = "vector3", off = direct + delta }
		end
		local imm, real = lthunk(getter, gb)
		if imm ~= nil and real ~= nil then
			local disp = slea(real)
			if disp ~= nil then
				return { mode = "vector3", off = delta + imm + disp }
			end
			local prim, vec = indchain(real)
			if prim ~= nil and vec ~= nil then
				return { mode = "indirectvector3", off = delta + imm + prim, vec = vec }
			end
		end
		local gvd, gva, gvb = grabgv(getset)
		local use = gvd or delta
		if gva ~= nil and gvb ~= nil and use ~= nil then
			local reader = chase(gva, gvb)
			if reader ~= nil then
				local disp = strdir(reader)
				if disp ~= nil then
					return { mode = "vector3", off = disp + use }
				end
				local prim, vec = strind(reader)
				if prim ~= nil and vec ~= nil then
					return { mode = "indirectvector3", off = prim + use, vec = vec }
				end
			end
		end
		return nil
	elseif kind == "udim2" then
		local base = simd(gb)
		if base ~= nil then
			return { mode = "udim2", off = base + delta }
		end
		local gvd, gva, gvb = grabgv(getset)
		local use = gvd or delta
		if gva ~= nil and gvb ~= nil and use ~= nil then
			local reader = chase(gva, gvb)
			if reader ~= nil then
				local disp = strdir(reader)
				if disp ~= nil then
					return { mode = "udim2", off = disp + use }
				end
			end
		end
		if hasflag(gb) then
			local wide = code(getter, 96)
			local fd = if wide ~= nil then flagstruct(wide) else nil
			if fd ~= nil then
				return { mode = "udim2", off = fd + delta }
			end
		end
		return nil
	elseif kind == "cframe" then
		local disp = dlea(gb)
		if disp ~= nil then
			return { mode = "cframe", off = disp + delta }
		end
		local imm, real = lthunk(getter, gb)
		if imm ~= nil and real ~= nil then
			local sd = slea(real)
			if sd ~= nil then
				return { mode = "cframe", off = delta + imm + sd }
			end
		end
		local gvd, gva, gvb = grabgv(getset)
		local use = gvd or delta
		if gva ~= nil and gvb ~= nil and use ~= nil then
			local reader = chase(gva, gvb)
			if reader ~= nil then
				local sd = strdir(reader)
				if sd ~= nil then
					return { mode = "cframe", off = sd + use }
				end
				local prim, vec = strind(reader)
				if prim ~= nil and vec ~= nil then
					return { mode = "indirectcframe", off = prim + use, vec = vec }
				end
			end
		end
		return nil
	elseif kind == "vector2" then
		local base = simd(gb)
		if base ~= nil then
			return { mode = "vector2", off = base + delta }
		end
		local direct = dlea(gb)
		if direct ~= nil then
			return { mode = "vector2", off = direct + delta }
		end
		local gvd, gva, gvb = grabgv(getset)
		local use = gvd or delta
		if gva ~= nil and gvb ~= nil and use ~= nil then
			local reader = chase(gva, gvb)
			if reader ~= nil then
				local disp = strdir(reader)
				if disp ~= nil then
					return { mode = "vector2", off = disp + use }
				end
				local prim, vec = strind(reader)
				if prim ~= nil and vec ~= nil then
					return { mode = "indirectvector2", off = prim + use, vec = vec }
				end
			end
		end
		if hasflag(gb) then
			local wide = code(getter, 96)
			local fd = if wide ~= nil then flagstruct(wide) else nil
			if fd ~= nil then
				return { mode = "vector2", off = fd + delta }
			end
		end
		return nil
	elseif kind == "numberrange" then
		local base = simd(gb)
		if base == nil then
			base = lea(gb)
		end
		if base ~= nil then
			return { mode = "numberrange", off = base + delta }
		end
		local gvd, gva, gvb = grabgv(getset)
		local use = gvd or delta
		if gva ~= nil and gvb ~= nil and use ~= nil then
			local reader = chase(gva, gvb)
			if reader ~= nil then
				local disp = strdir(reader) or slea(reader)
				if disp ~= nil then
					return { mode = "numberrange", off = disp + use }
				end
			end
		end
		return nil
	elseif wants[kind] ~= nil or kind == "enum" then
		local want = wants[kind] or "i32"

		if kind == "bool" and gb[3] == 0xC3 then
			if gb[1] == 0xB0 and gb[2] == 0x01 then
				return { mode = "const", off = 0, bit = 1 }
			elseif (gb[1] == 0x32 or gb[1] == 0x33) and gb[2] == 0xC0 then
				return { mode = "const", off = 0, bit = 0 }
			end
		end

		local disp, k = leaf(gb, 1)
		if disp ~= nil and k == want then
			return { mode = k, off = disp + delta }
		end

		local imm, real = addthunk(getter, gb)
		if imm ~= nil and real ~= nil then
			local rdisp, rk = leaf(real, 1)
			if rdisp ~= nil and rk == want then
				return { mode = rk, off = rdisp + delta + imm }
			end
		
			local prim, vec = indleaf(real, want)
			if prim ~= nil and vec ~= nil then
				return { mode = want, off = delta + imm + prim, vec = vec, indirect = true }
			end
			if kind == "bool" then
				local p, flag, bit = bitflag(real)
				if p ~= nil and flag ~= nil then
					return { mode = "flag", off = p + delta + imm, flag = flag, bit = bit }
				end
			end
		end

		if kind == "bool" then
			local prim, flag, bit = bitflag(gb)
			if prim ~= nil and flag ~= nil then
				return { mode = "flag", off = prim + delta, flag = flag, bit = bit }
			end
		end

		if hasflag(gb) then
			local wide = code(getter, 96)
			if wide ~= nil then
				local fo, fk = flagfield(wide, want, delta)
				if fo ~= nil and fk == want then
					return { mode = fk, off = fo }
				end
			end
		end

		if wants[kind] ~= nil then
			local fd, fk = dirfield(gb, want)
			if fd ~= nil and fk == want then
				return { mode = fk, off = fd + delta }
			end
		end

		if wants[kind] ~= nil then
			local gvd, gva, gvb = grabgv(getset)
			local use = gvd or delta
			if gva ~= nil and gvb ~= nil and use ~= nil then
				local reader = chase(gva, gvb)
				if reader ~= nil then
					local rdisp, rk = hunt(reader, want)
					if rdisp ~= nil and rk == want then
						return { mode = rk, off = rdisp + use }
					end
					local prim, vec = indleaf(reader, want)
					if prim ~= nil and vec ~= nil then
						return { mode = want, off = prim + use, vec = vec, indirect = true }
					end
					if kind == "bool" then
						local p, flag, bit = bitflag(reader)
						if p ~= nil and flag ~= nil then
							return { mode = "flag", off = p + use, flag = flag, bit = bit }
						end
					end
				end
			end
		end
		return nil
	end
	return nil
end

local function resolve(instance: number, name: string): plan?
	local desc = ptr(instance + descoff)
	if desc == nil then
		return nil
	end
	local cp = ptr(desc + nameoff)
	if cp == nil then
		return nil
	end
	local cok, class = pcall(memory.readstring, cp)
	if not cok or class == nil then
		return nil
	end
	local key = `{class}.{name}`
	local hit = cache[key]
	if hit ~= nil then
		return hit
	end
	local p = makeplan(instance, name)
	if p ~= nil then
		cache[key] = p
	end
	return p
end

local reflection = {}

function reflection.getprop(instance: Instance, name: string): any
	if instance == nil then
		return nil
	end
	local addr = tonumber((instance :: any).Data)
	if addr == nil then
		return nil
	end
	local plan = resolve(addr, name)
	if plan == nil then
		return nil
	end
	local field = addr + plan.off
	local mode = plan.mode
	if mode == "const" then
		return plan.bit == 1
	end
	if
		plan.indirect
		and (mode == "f32" or mode == "f64" or mode == "u8" or mode == "u16" or mode == "i32" or mode == "i64")
	then
		local p = ptr(field)
		if p == nil then
			return nil
		end
		field = p + (plan.vec or 0)
	end
	if mode == "f32" then
		return (select(2, pcall(memory.readf32, field)))
	elseif mode == "f64" then
		return (select(2, pcall(memory.readf64, field)))
	elseif mode == "u8" then
		local ok, v = pcall(memory.readu8, field)
		return (if ok then v else nil) == 1
	elseif mode == "u16" then
		local ok, v = pcall(memory.readu32, field)
		return if ok then v else nil
	elseif mode == "i32" then
		return (select(2, pcall(memory.readi32, field)))
	elseif mode == "i64" then
		local ok, v = pcall(memory.readu64, field)
		return if ok then v else nil
	elseif mode == "string" then
		local cok, cap = pcall(memory.readu64, field + 0x18)
		local src = if cok and cap ~= nil and cap > 15 then ptr(field) else field
		if src == nil then
			return nil
		end
		local sok, s = pcall(memory.readstring, src)
		return if sok then s else nil
	elseif mode == "color3" then
		local r = select(2, pcall(memory.readf32, field))
		local g = select(2, pcall(memory.readf32, field + 4))
		local b = select(2, pcall(memory.readf32, field + 8))
		return if typeof(r) == "number" then Color3.new(r, g, b) else nil
	elseif mode == "color3uint8" then
		local rok, r = pcall(memory.readu8, field)
		local gok, g = pcall(memory.readu8, field + 1)
		local bok, b = pcall(memory.readu8, field + 2)
		if not (rok and gok and bok) or r == nil or g == nil or b == nil then
			return nil
		end
		return Color3.new(r / 255, g / 255, b / 255)
	elseif mode == "vector3" then
		return (select(2, pcall(memory.readvector, field)))
	elseif mode == "udim2" then
		return {
			XScale = select(2, pcall(memory.readf32, field)),
			XOffset = select(2, pcall(memory.readi32, field + 4)),
			YScale = select(2, pcall(memory.readf32, field + 8)),
			YOffset = select(2, pcall(memory.readi32, field + 12)),
		}
	elseif mode == "vector2" then
		return Vector2.new(select(2, pcall(memory.readf32, field)), select(2, pcall(memory.readf32, field + 4)))
	elseif mode == "rect" then
		local px = select(2, pcall(memory.readf32, field))
		local py = select(2, pcall(memory.readf32, field + 4))
		local sx_ = select(2, pcall(memory.readf32, field + 8))
		local sy = select(2, pcall(memory.readf32, field + 12))
		if typeof(px) ~= "number" or typeof(sx_) ~= "number" then
			return nil
		end
		local ok, rect = pcall(function()
			return Rect.new(px, py, px + sx_, py + sy)
		end)
		return if ok then rect else { Min = Vector2.new(px, py), Max = Vector2.new(px + sx_, py + sy) }
	elseif mode == "numberrange" then
		local minv = select(2, pcall(memory.readf32, field))
		local maxv = select(2, pcall(memory.readf32, field + 4))
		if typeof(minv) ~= "number" or typeof(maxv) ~= "number" then
			return nil
		end
		local ok, range = pcall(function()
			return NumberRange.new(minv, maxv)
		end)
		return if ok then range else { Min = minv, Max = maxv }
	elseif mode == "indirectvector3" then
		local p = ptr(field)
		return if p ~= nil then (select(2, pcall(memory.readvector, p + (plan.vec or 0)))) else nil
	elseif mode == "indirectcolor3" then
		local p = ptr(field)
		if p == nil then
			return nil
		end
		local at = p + (plan.vec or 0)
		local r = select(2, pcall(memory.readf32, at))
		local g = select(2, pcall(memory.readf32, at + 4))
		local b = select(2, pcall(memory.readf32, at + 8))
		return if typeof(r) == "number" then Color3.new(r, g, b) else nil
	elseif mode == "indirectvector2" then
		local p = ptr(field)
		if p == nil then
			return nil
		end
		local at = p + (plan.vec or 0)
		return Vector2.new(select(2, pcall(memory.readf32, at)), select(2, pcall(memory.readf32, at + 4)))
	elseif mode == "cframe" or mode == "indirectcframe" then
		local at = field
		if mode == "indirectcframe" then
			local p = ptr(field)
			if p == nil then
				return nil
			end
			at = p + (plan.vec or 0)
		end
		local c = table.create(12)
		for i = 0, 11 do
			c[i + 1] = select(2, pcall(memory.readf32, at + i * 4))
		end
		local ok, frame =
			pcall(CFrame.new, c[10], c[11], c[12], c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9])
		return if ok then frame else nil
	elseif mode == "flag" then
		local p = ptr(field)
		if p == nil or plan.flag == nil then
			return nil
		end
		local ok, byte = pcall(memory.readu8, p + plan.flag)
		if not ok or byte == nil then
			return nil
		end
		return (byte // (2 ^ (plan.bit or 0))) % 2 == 1
	end
	return nil
end

function reflection.setprop(instance: Instance, name: string, value: any): boolean
	if instance == nil then
		return false
	end
	local addr = tonumber((instance :: any).Data)
	if addr == nil then
		return false
	end
	local plan = resolve(addr, name)
	if plan == nil then
		return false
	end
	local off = plan.off
	local mode = plan.mode
	if
		plan.indirect
		and (mode == "f32" or mode == "f64" or mode == "u8" or mode == "u16" or mode == "i32" or mode == "i64")
	then
		local p = ptr(addr + off)
		if p == nil then
			return false
		end
		local ud = pointer_to_userdata(p)
		local vec = plan.vec or 0
		if mode == "f32" then
			return (pcall(memory.writef32, ud, vec, value :: number))
		elseif mode == "f64" then
			return (pcall(memory.writef64, ud, vec, value :: number))
		elseif mode == "u8" then
			return (pcall(memory.writeu8, ud, vec, if value then 1 else 0))
		elseif mode == "u16" then
			return (pcall(memory.writeu16, ud, vec, value :: number))
		elseif mode == "i32" then
			return (pcall(memory.writei32, ud, vec, value :: number))
		elseif mode == "i64" then
			return (pcall(memory.writeu64, ud, vec, value :: number))
		end
	end
	if mode == "f32" then
		return (pcall(memory.writef32, instance, off, value :: number))
	elseif mode == "f64" then
		return (pcall(memory.writef64, instance, off, value :: number))
	elseif mode == "u8" then
		return (pcall(memory.writeu8, instance, off, if value then 1 else 0))
	elseif mode == "u16" then
		return (pcall(memory.writeu16, instance, off, value :: number))
	elseif mode == "i32" then
		return (pcall(memory.writei32, instance, off, value :: number))
	elseif mode == "i64" then
		return (pcall(memory.writeu64, instance, off, value :: number))
	elseif mode == "vector3" then
		return (pcall(memory.writevector, instance, off, value))
	elseif mode == "color3" then
		local color = value :: Color3
		local ok = pcall(memory.writef32, instance, off, color.R)
		pcall(memory.writef32, instance, off + 4, color.G)
		pcall(memory.writef32, instance, off + 8, color.B)
		return ok
	elseif mode == "color3uint8" then
		local color = value :: Color3
		local ok = pcall(memory.writeu8, instance, off, math.clamp(math.floor(color.R * 255 + 0.5), 0, 255))
		pcall(memory.writeu8, instance, off + 1, math.clamp(math.floor(color.G * 255 + 0.5), 0, 255))
		pcall(memory.writeu8, instance, off + 2, math.clamp(math.floor(color.B * 255 + 0.5), 0, 255))
		return ok
	elseif mode == "udim2" then
		local udim = value :: { XScale: number, XOffset: number, YScale: number, YOffset: number }
		local ok = pcall(memory.writef32, instance, off, udim.XScale)
		pcall(memory.writei32, instance, off + 4, udim.XOffset)
		pcall(memory.writef32, instance, off + 8, udim.YScale)
		pcall(memory.writei32, instance, off + 12, udim.YOffset)
		return ok
	elseif mode == "vector2" then
		local vector = value :: Vector2
		local ok = pcall(memory.writef32, instance, off, vector.X)
		pcall(memory.writef32, instance, off + 4, vector.Y)
		return ok
	elseif mode == "indirectvector3" then
		local p = ptr(addr + off)
		if p == nil then
			return false
		end
		return (pcall(memory.writevector, pointer_to_userdata(p), plan.vec or 0, value))
	elseif mode == "indirectcolor3" then
		local p = ptr(addr + off)
		if p == nil then
			return false
		end
		local ud = pointer_to_userdata(p)
		local color = value :: Color3
		local ok = pcall(memory.writef32, ud, plan.vec or 0, color.R)
		pcall(memory.writef32, ud, (plan.vec or 0) + 4, color.G)
		pcall(memory.writef32, ud, (plan.vec or 0) + 8, color.B)
		return ok
	elseif mode == "cframe" then
		local c = { (value :: CFrame):GetComponents() }
		local ok = pcall(memory.writef32, instance, off, c[4])
		for i = 5, 12 do
			pcall(memory.writef32, instance, off + (i - 4) * 4, c[i])
		end
		pcall(memory.writef32, instance, off + 0x24, c[1])
		pcall(memory.writef32, instance, off + 0x28, c[2])
		pcall(memory.writef32, instance, off + 0x2c, c[3])
		return ok
	elseif mode == "flag" then
		local p = ptr(addr + off)
		if p == nil or plan.flag == nil then
			return false
		end
		local ud = pointer_to_userdata(p)
		local byte = select(2, pcall(memory.readu8, ud, plan.flag))
		if typeof(byte) ~= "number" then
			return false
		end
		local mask = 2 ^ (plan.bit or 0)
		local upd = if value then bit32.bor(byte, mask) else bit32.band(byte, bit32.bnot(mask))
		return (pcall(memory.writeu8, ud, plan.flag, upd))
	end
	return false
end

function reflection.offsetof(instance: Instance, name: string): plan?
	if instance == nil then
		return nil
	end
	local addr = tonumber((instance :: any).Data)
	if addr == nil then
		return nil
	end
	return resolve(addr, name)
end

function reflection.properties(instance: Instance): { { name: string, vtype: string } }
	local list: { { name: string, vtype: string } } = {}
	local addr = tonumber((instance :: any).Data)
	if addr == nil then
		return list
	end
	local desc = ptr(addr + descoff)
	if desc == nil then
		return list
	end
	local base = ptr(desc + propsoff)
	if base == nil then
		return list
	end
	for i = 0, 900 do
		local pd = ptr(base + i * 0x10)
		if pd == nil then
			break
		end
		local tok, rtti = pcall(memory.rtti, pd)
		if not tok or rtti == nil or string.find(rtti, "escriptor", 1, true) == nil then
			break
		end
		local np = ptr(pd + nameoff)
		if np ~= nil then
			local nok, n = pcall(memory.readstring, np)
			if nok and n ~= nil then
				table.insert(list, { name = n, vtype = kindof(rtti) })
			end
		end
	end
	return list
end

function reflection.getproperties_all(instance: Instance): { { name: string, vtype: string, value: any, offset: number? } }
    local list: { { name: string, vtype: string, value: any, offset: number? } } = {}
    for _, property in reflection.properties(instance) do
        local value, offset = reflection.getprop(instance, property.name)
        if value ~= nil then
            table.insert(list, { name = property.name, vtype = property.vtype, value = value, offset = offset })
        end
    end
    return list
end

return reflection
