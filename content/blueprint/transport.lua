-- 建造脚本运行在没有 api.engine 的资源 VM 中。
-- 将已解析的模板装入数值参数；每个数值只有 24 位，浮点传输也能精确保存。
local core = require "blueprint_demo::/blueprint/core.lua"
local transport = {}
local limit = 1024 * 1024

local function serialize(value)
    local kind = type(value)
    if kind == "nil" then return "z" end
    if kind == "boolean" then return value and "y" or "x" end
    if kind == "number" or kind == "string" then
        local text = value
        if kind == "number" then
            text = math.type and math.type(value) == "integer" and tostring(value) or string.format("%.17g", value)
        end
        return (kind == "number" and "n" or "s") .. tostring(#text) .. ":" .. text
    end
    assert(kind == "table", "模板包含不可传输的数据")
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        if type(a) ~= type(b) then return type(a) < type(b) end
        return a < b
    end)
    local parts = {"t" .. tostring(#keys) .. ":"}
    for _, key in ipairs(keys) do
        parts[#parts + 1] = serialize(key)
        parts[#parts + 1] = serialize(value[key])
    end
    return table.concat(parts)
end

function transport.encode(template)
    local text = serialize(core.copy(template))
    assert(#text <= limit, "模板配置过大，无法传输")
    local params = {blueprintBytes = #text}
    for offset = 1, #text, 3 do
        local a, b, c = text:byte(offset, offset + 2)
        params["blueprintWord" .. tostring(math.floor((offset + 2) / 3))] = a * 65536 + (b or 0) * 256 + (c or 0)
    end
    return params
end

function transport.decode(params)
    local size = params.blueprintBytes
    assert(type(size) == "number" and size >= 1 and size <= limit and size % 1 == 0, "缺少有效的模板配置数据")
    local chunks = {}
    for index = 1, math.ceil(size / 3) do
        local word = params["blueprintWord" .. tostring(index)]
        assert(type(word) == "number" and word >= 0 and word <= 16777215 and word % 1 == 0, "模板配置数据不完整")
        chunks[index] = string.char(math.floor(word / 65536), math.floor(word / 256) % 256, word % 256)
    end
    local text, pos = table.concat(chunks):sub(1, size), 1
    local function count()
        local finish = text:find(":", pos, true)
        assert(finish, "模板配置长度无效")
        local value = tonumber(text:sub(pos, finish - 1))
        assert(value and value >= 0 and value % 1 == 0 and value <= size, "模板配置长度无效")
        pos = finish + 1
        return value
    end
    local read
    read = function(depth)
        assert(depth < 32 and pos <= size, "模板配置结构无效")
        local tag = text:sub(pos, pos)
        pos = pos + 1
        if tag == "z" then return nil end
        if tag == "y" then return true end
        if tag == "x" then return false end
        if tag == "n" or tag == "s" then
            local length = count()
            assert(pos + length - 1 <= size, "模板配置数据不完整")
            local value = text:sub(pos, pos + length - 1)
            pos = pos + length
            if tag == "s" then return value end
            value = tonumber(value)
            assert(value and value == value and value ~= math.huge and value ~= -math.huge, "模板配置数字无效")
            return value
        end
        assert(tag == "t", "模板配置类型无效")
        local result, entries = {}, count()
        for _ = 1, entries do
            local key = read(depth + 1)
            assert(type(key) == "string" or type(key) == "number", "模板配置键无效")
            result[key] = read(depth + 1)
        end
        return result
    end
    local template = read(0)
    assert(pos == size + 1 and type(template) == "table", "模板配置结构无效")
    return core.copy(template)
end
return transport
