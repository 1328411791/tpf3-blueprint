local gettext = _
local tr = require "blueprint_demo::/blueprint/i18n.lua"
local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local constructionUi = ug_require "::/gui/construction/construction_react_util.tl"
local core = require "blueprint_demo::/blueprint/core.lua"
local library = require "blueprint_demo::/blueprint/library.lua"
local feedback = gettext("BLUEPRINT_SAVE_HINT")

local FeedbackTooltip = react.RegisterRecipe("BlueprintSaveFeedback", function(param)
    -- DeferredTooltipTree 要求根节点是布局，不能直接返回 TextView。
    return builtin.BoxLayout {
        orientation = builtin.type.Orientation.Vertical,
        children = {builtin.TextView {text = param.text}},
    }
end)

local SaveAction = constructionUi.RegisterCustomSelectorBasedActionRecipe("BlueprintSaveSingle", {
    isAvailable = function() return true end,
    onHover = function(_params, entity)
        local root, reason = core.resolveConstruction(entity, api.engine, api.type.ComponentType)
        local text = root and feedback or (reason or gettext("BLUEPRINT_SELECT_BUILDING"))
        return {param = {recipe = FeedbackTooltip, param = {text = text}}, mouseCursor = 0}
    end,
    onSelect = function(_params, entity)
        local ok, snapshot = pcall(library.save, entity)
        if not ok then
            feedback = tr("BLUEPRINT_SAVE_FAILED", {error = snapshot})
            debugPrint("[Blueprint] " .. feedback)
            return
        end
        feedback = tr("BLUEPRINT_SAVE_SYNCING", {name = snapshot.name})
    end,
})

function data()
    return {
        getDefinition = function(resName)
            return {
                resName = resName, name = gettext("BLUEPRINT_SAVE_TOOL"),
                description = gettext("BLUEPRINT_SAVE_TOOL_DESCRIPTION"),
                icon = {icon = "blueprint_demo::/blueprint/icons/save_template.tga"},
                previewIcon = {icon = "blueprint_demo::/blueprint/icons/save_template_preview.tga"},
                availability = {yearFrom = 0, yearTo = 0},
                action = "ACTION_CUSTOM", customAction = {recipe = SaveAction, customParam = {}},
                constructions = {}, categories = {}, params = {}, builderAudioRes = {},
                menuCategory = {categories = {
                    {category = "rail_buildings", order = 9400, filterCategories = {"tools"}},
                    {category = "road_buildings", order = 9400, filterCategories = {"tools"}},
                    {category = "water_buildings", order = 9400, filterCategories = {"tools"}},
                    {category = "air_buildings", order = 9400, filterCategories = {"tools"}},
                    {category = "warehouses", order = 9400, filterCategories = {"tools"}},
                }},
            }
        end,
    }
end
