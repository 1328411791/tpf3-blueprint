-- Loaded by the game's native stylesheet loader; only blueprint classes match.
local stylesheetutil = require "::/gui/main/stylesheetutil.lua"

function data()
    local rules = {}
    local add = stylesheetutil.makeAdder(rules)
    add("TextView!blueprint-manager-count", {textAlignment = {1, 0.5}})
    add("TextInputField!blueprint-manager-exchange-input", {
        color = {1, 1, 1, 1},
        fontSize = 14,
        fontWeight = "Regular",
    })
    -- Native selection uses its own text style; avoid covering its glyphs.
    add("TextInputField!blueprint-manager-exchange-input > Selection", {
        color = {1, 1, 1, 1},
        fontSize = 14,
        fontWeight = "Regular",
        backgroundColor = {0.25, 0.45, 0.65, 0.35},
    })
    add("TextInputField!blueprint-manager-share-input", {color = {1, 1, 1, 0}})
    -- Preview/Placeholder have native colors independent of the parent field.
    add("TextInputField!blueprint-manager-share-input > Preview", {color = {1, 1, 1, 0}})
    add("TextInputField!blueprint-manager-share-input > Placeholder", {visibility = "none"})
    add("TextInputField!blueprint-manager-share-input > Selection", {color = {1, 1, 1, 0}})
    -- RichTextView fonts follow the game's own richtext scaling rules.
    add("RichTextView!blueprint-manager-description RichTextView::Text", {color = {0.66, 0.71, 0.76, 1}})
    return rules
end
