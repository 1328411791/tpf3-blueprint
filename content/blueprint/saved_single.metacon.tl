-- 载入时注册的固定载体。菜单包装器将其替换为已同步的模板卡片。
return {
    availability = {yearFrom = 0, yearTo = 0},
    description = {
        name = _("BLUEPRINT_CARRIER_NAME"),
        description = _("BLUEPRINT_CARRIER_DESCRIPTION"),
        icon = "::/warehouses/icons/wh_goods.tga",
        previewIcon = "::/warehouses/icons/wh_goods_preview.tga",
    },
    params = {},
    menuCategory = {categories = {{category = "warehouses", order = 9500}}},
    heightAdjustable = true,
    order = 9500,
    createTemplateScript = {
        fileName = "blueprint_demo::/blueprint/saved_single.script@createTemplateFn",
        params = {},
    },
}
