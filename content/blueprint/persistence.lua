local gettext = _
local transport = require "blueprint_demo::/blueprint/transport.lua"
local runtime = require "blueprint_demo::/blueprint/runtime.lua"
local base64 = require "blueprint_demo::/blueprint/base64.lua"
local persistence = {}

function persistence.encode(value)
    -- 单个字符串保留稀疏数字键、Unicode 和整数精度，不再写数字块。
    return {version = 3, encoding = "base64",
        data = base64.encode(transport.serialize(runtime.validateLibrary(value)))}
end

function persistence.decode(value)
    if type(value) == "table" and value.version == 3 then
        assert(value.encoding == "base64" and type(value.data) == "string", gettext("BLUEPRINT_MISSING_ENCODING"))
        return runtime.validateLibrary(transport.deserialize(base64.decode(value.data)))
    end
    if type(value) == "table" and value.version == 2 then
        assert(type(value.data) == "table", gettext("BLUEPRINT_MISSING_ENCODING"))
        return runtime.validateLibrary(transport.decode(value.data))
    end
    -- 读取旧版模板；下次成功保存时自动升级文件格式。
    return runtime.validateLibrary(value)
end
return persistence
