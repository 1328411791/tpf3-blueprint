local gettext = _
local transport = require "blueprint_demo::/blueprint/transport.lua"

function data()
    return {
        createTemplateFn = function(_captureParams, params)
            -- 配置由 GUI 完整传入；这里不访问 api、用户文件或共享 VM 状态。
            local template = transport.decode(params)
            assert(type(template.constructions) == "table" and #template.constructions == 1,
                gettext("BLUEPRINT_MISSING_SINGLE"))
            return template
        end,
    }
end
