-- 使用游戏原生 strings.json 查找，具名占位符允许译者调整词序。
return function(key, values)
    local text = _(key)
    return (text:gsub("{([%w_]+)}", function(name)
        local value = values and values[name]
        assert(value ~= nil, _("BLUEPRINT_MISSING_PLACEHOLDER") .. key .. "." .. name)
        return tostring(value)
    end))
end
