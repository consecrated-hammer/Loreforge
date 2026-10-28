local _, ns = ...
-- A small canonical, non-executable wire codec. No loadstring or Lua source.
local C = { MAX = 32768 }
ns.Codec = C
local function encode(value, depth, seen)
    assert(depth <= 8, "wire nesting")
    local kind = type(value)
    if kind == "string" then assert(#value <= 4096, "wire string"); return "s" .. #value .. ":" .. value end
    if kind == "number" then
        assert(value == math.floor(value) and math.abs(value) <= 1000000000000, "wire number")
        return "n" .. string.format("%.0f", value) .. ":"
    end
    if kind == "boolean" then return value and "t" or "f" end
    assert(kind == "table" and not seen[value], "wire type")
    seen[value] = true
    local keys, out = {}, {}
    for key in pairs(value) do
        assert(type(key) == "string" or (type(key) == "number" and key >= 1 and key <= 1000 and key == math.floor(key)), "wire key")
        keys[#keys + 1] = key
    end
    assert(#keys <= 128, "wire entries")
    table.sort(keys, function(a, b) if type(a) ~= type(b) then return type(a) < type(b) end; return a < b end)
    for _, key in ipairs(keys) do out[#out + 1] = encode(key, depth + 1, seen) .. encode(value[key], depth + 1, seen) end
    seen[value] = nil
    return "m" .. #keys .. ":" .. table.concat(out)
end
function C.Encode(value)
    local ok, text = pcall(encode, value, 0, {})
    if not ok or #text > C.MAX then return nil, "Invalid or oversized message" end
    return text
end
function C.Decode(text)
    if type(text) ~= "string" or #text > C.MAX then return nil end
    local pos, count = 1, 0
    local function integer()
        local stop = text:find(":", pos, true)
        assert(stop and stop - pos <= 14, "wire length")
        local s = text:sub(pos, stop - 1)
        assert(s:match("^%-?%d+$"), "wire integer")
        pos = stop + 1
        local n = tonumber(s)
        assert(n and math.abs(n) <= 1000000000000, "wire range")
        return n
    end
    local parse
    parse = function(depth)
        count = count + 1
        assert(depth <= 8 and count <= 8192, "wire complexity")
        local tag = text:sub(pos, pos); pos = pos + 1
        if tag == "t" then return true elseif tag == "f" then return false end
        if tag == "n" then return integer() end
        if tag == "s" then
            local n = integer()
            assert(n >= 0 and n <= 4096 and pos + n - 1 <= #text, "wire string")
            local s = text:sub(pos, pos + n - 1); pos = pos + n; return s
        end
        assert(tag == "m", "wire tag")
        local n, value = integer(), {}
        assert(n >= 0 and n <= 128, "wire entries")
        for _ = 1, n do
            local key = parse(depth + 1)
            assert(type(key) == "string" or (type(key) == "number" and key >= 1 and key <= 1000), "wire key")
            assert(value[key] == nil, "wire duplicate")
            value[key] = parse(depth + 1)
        end
        return value
    end
    local ok, value = pcall(parse, 0)
    if not ok or pos ~= #text + 1 or type(value) ~= "table" then return nil end
    return value
end
function C.Sum(text)
    local a, b = 1, 0
    for i = 1, #text do a = (a + text:byte(i)) % 65521; b = (b + a) % 65521 end
    return string.format("%08x", b * 65536 + a)
end
