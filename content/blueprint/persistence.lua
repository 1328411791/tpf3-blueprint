local transport = require "blueprint_demo::/blueprint/transport.lua"
local runtime = require "blueprint_demo::/blueprint/runtime.lua"
local persistence = {}

function persistence.encode(value)
    -- app.saveUserdata 的 Lua 文件输出会丢失稀疏数字键。
    -- 外层和数据块都只使用字符串键；模块槽位由 codec 完整保留。
    return {version = 2, data = transport.encode(runtime.validateLibrary(value))}
end

function persistence.decode(value)
    if type(value) == "table" and value.version == 2 then
        assert(type(value.data) == "table", _("BLUEPRINT_MISSING_ENCODING"))
        return runtime.validateLibrary(transport.decode(value.data))
    end
    -- 读取旧版模板；下次成功保存时自动升级文件格式。
    return runtime.validateLibrary(value)
end
return persistence
