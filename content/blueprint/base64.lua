local gettext = _
local base64 = {}
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local index = {}
for i = 1, #alphabet do index[alphabet:sub(i, i)] = i - 1 end
local maxBytes = 1024 * 1024

function base64.encode(text)
    assert(type(text) == "string" and #text <= maxBytes, gettext("BLUEPRINT_TRANSFER_SIZE"))
    local result = {}
    for offset = 1, #text, 3 do
        local a, b, c = text:byte(offset, offset + 2)
        local word = a * 65536 + (b or 0) * 256 + (c or 0)
        local function char(shift)
            local value = math.floor(word / shift) % 64
            return alphabet:sub(value + 1, value + 1)
        end
        result[#result + 1] = char(262144) .. char(4096)
            .. (b and char(64) or "=") .. (c and char(1) or "=")
    end
    return table.concat(result)
end

function base64.decode(text)
    assert(type(text) == "string" and #text <= math.ceil(maxBytes / 3) * 4,
        gettext("BLUEPRINT_TRANSFER_SIZE"))
    assert(#text % 4 == 0, gettext("BLUEPRINT_BASE64_INVALID"))
    local result = {}
    for offset = 1, #text, 4 do
        local chars = {text:sub(offset, offset), text:sub(offset + 1, offset + 1),
            text:sub(offset + 2, offset + 2), text:sub(offset + 3, offset + 3)}
        local a, b, c, d = index[chars[1]], index[chars[2]], index[chars[3]], index[chars[4]]
        local padC, padD = chars[3] == "=", chars[4] == "="
        assert(a and b and (c or padC) and (d or padD)
            and (not padC or padD) and (not padD or offset + 3 == #text)
            and (not padC or b % 16 == 0) and (not padD or padC or c % 4 == 0),
            gettext("BLUEPRINT_BASE64_INVALID"))
        local word = a * 262144 + b * 4096 + (c or 0) * 64 + (d or 0)
        local chunk = string.char(math.floor(word / 65536))
        if not padC then chunk = chunk .. string.char(math.floor(word / 256) % 256) end
        if not padD then chunk = chunk .. string.char(word % 256) end
        result[#result + 1] = chunk
    end
    local decoded = table.concat(result)
    assert(#decoded <= maxBytes, gettext("BLUEPRINT_TRANSFER_SIZE"))
    return decoded
end

return base64
