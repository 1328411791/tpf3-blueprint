-- 最小研究示例：给原生建造菜单增加一张模板卡片。
-- 采用本机仓库使用的 .metacon.tl 格式，直接返回元建筑描述。
return {
    availability = { yearFrom = 1900, yearTo = 0 },
    description = {
        name = "Blueprint Demo: Warehouse Pair",
        description = "Place two vanilla goods warehouses. Development prototype.",
        icon = "::/warehouses/icons/wh_goods.tga",
        previewIcon = "::/warehouses/icons/wh_goods_preview.tga",
    },
    params = {},
    menuCategory = {
        categories = {
            { category = "rail_buildings", order = 9000 },
            { category = "warehouses", order = 9000 },
        },
    },
    order = 9000,
    configureHudIconsScript = {
        fileName = "::/gui/construction/construction_desc_hud_icons.script@configureWarehouseHudIconsFn",
    },
    createTemplateScript = {
        fileName = "warehouse_pair.script@createTemplateFn",
        params = {},
    },
}
