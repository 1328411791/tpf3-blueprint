local function translation(x, y, z)
    return {
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        x, y, z, 1,
    }
end

-- 这个槽位公式来自本机原版 warehouse.script.lua。
-- 仓库模块放在 (0, 3) 的 warehouse_large 槽位。
-- 每种建筑的槽位规则不同，不能直接把这个数字用于铁路车站。
local initialSlotId = 10 * (250000 * (3 + 250) + 250)

local function makeWarehouse(x, params)
    return {
        constructionFileName = "::/warehouses/warehouse.con",
        modules = {
            [initialSlotId] = "::/warehouses/wh_goods.module",
        },
        transf = translation(x, 0, 0),
        params = { year = params.year, seed = params.seed },
    }
end

function data()
    return {
        createTemplateFn = function(captureParams, params)
            return {
                constructions = {
                    makeWarehouse(-40, params),
                    makeWarehouse(40, params),
                },
            }
        end,
    }
end
