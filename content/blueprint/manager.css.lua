-- Loaded by the game's native stylesheet loader; only blueprint classes match.
local stylesheetutil = require "::/gui/main/stylesheetutil.lua"

function data()
    local rules = {}
    local add = stylesheetutil.makeAdder(rules)
    add("TextView!blueprint-manager-count", {textAlignment = {1, 0.5}})
    -- RichTextView fonts follow the game's own richtext scaling rules.
    add("RichTextView!blueprint-manager-description RichTextView::Text", {color = {0.66, 0.71, 0.76, 1}})
    return rules
end
