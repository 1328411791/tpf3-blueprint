local gettext = _
local core = require "blueprint_demo::/blueprint/core.lua"
local transport = require "blueprint_demo::/blueprint/transport.lua"

function data()
    return {
        createTemplateFn = function(_captureParams, params)
            -- 配置由 GUI 完整传入；这里不访问 api、用户文件或共享 VM 状态。
            local template = type(params) == "table" and params.blueprintTemplate
            -- 兼容旧版菜单或存档仍携带的数字块；新对象缺失时才解码旧格式。
            if template == nil and type(params) == "table" and params.blueprintBytes ~= nil then
                template = transport.decode(params)
            end
            assert(type(template) == "table" and type(template.constructions) == "table"
                and #template.constructions == 1,
                gettext("BLUEPRINT_MISSING_SINGLE"))
            local construction = template.constructions[1]
            assert(type(construction) == "table" and type(construction.constructionFileName) == "string"
                and type(construction.params) == "table" and type(construction.modules) == "table",
                gettext("BLUEPRINT_MISSING_SINGLE"))
            return core.copy(template)
        end,
    }
end
