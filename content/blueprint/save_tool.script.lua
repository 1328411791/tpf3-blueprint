local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local constructionUi = ug_require "::/gui/construction/construction_react_util.tl"
local core = require "blueprint_demo::/blueprint/core.lua"
local library = require "blueprint_demo::/blueprint/library.lua"
local feedback = "点击一座建筑，将它保存为新模板"

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
        local text = root and feedback or (reason or "请点击单座车站、仓库或车库")
        return {param = {recipe = FeedbackTooltip, param = {text = text}}, mouseCursor = 0}
    end,
    onSelect = function(_params, entity)
        local ok, snapshot = pcall(library.save, entity)
        if not ok then
            feedback = "保存失败：" .. tostring(snapshot)
            debugPrint("[Blueprint] " .. feedback)
            return
        end
        feedback = "已写入：" .. snapshot.name .. "；正在同步菜单"
    end,
})

function data()
    return {
        getDefinition = function(resName)
            return {
                resName = resName, name = "保存建筑模板",
                description = "选择此工具后点击单座车站、仓库或车库。保存参数和全部模块，立即添加模板卡片。",
                icon = {icon = "::/warehouses/icons/wh_goods.tga"},
                previewIcon = {icon = "::/warehouses/icons/wh_goods_preview.tga"},
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
