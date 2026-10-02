# Blueprint

A Transport Fever 3 mod that saves existing player buildings as reusable blueprints and adds them to the construction menu.

## Features

- Save individual stations, warehouses and depots with their building parameters, modules and supported cargo settings.
- Place saved blueprints using the game's construction controls, including rotation and height adjustment.
- Inherit the original building's construction sounds, with a standard building sound as fallback.
- Manage templates in a searchable list with building previews.
- Edit template names and descriptions, duplicate templates, and delete unwanted entries.
- Filter saved templates by railway, road, water, air or warehouse category.
- Import and share individual blueprints as Base64 strings.
- Keep a local template library that can be used across maps.
- English and Simplified Chinese interface.

## How to Use

1. Enable **Blueprint** for your map.
2. Open a supported construction category and select **Save Building Template**.
3. Click a building you own and wait for the template to appear in the menu.
4. Select the saved template and place it like a normal building.
5. Open **Template Manager** at the upper right of the construction menu to search, edit, duplicate or delete templates.
6. Use the category buttons below the search field to filter the list.
7. Click **Share** on a template, click its string field and press **Ctrl+A**, then **Ctrl+C**. Click **Import Blueprint** to paste a shared string, review its name and category, then import it. Imports receive a new local ID. Templates with missing dependencies can be stored but need the required mods before placement.

## Scope

Each blueprint contains one building. Nearby roads and tracks, vehicles, routes and building inventories are not included. Templates require the original building and module mods to be available.

Deleting a template leaves buildings already placed on the map intact.

Default template names use a separate counter from internal IDs. Deleting every template resets the next default name to Template 1; internal IDs keep increasing. Duplicating a template adds a copy suffix without consuming a default name number. Existing template names remain unchanged.

## Experimental Template Parameters

This branch passes a nested `blueprintTemplate` Lua table through `ConstructionBuilder.params`. The carrier's `createTemplateFn` validates and returns a copy of this object. Numeric payload blocks are no longer generated during placement. The built-in API declares builder parameters as `table`. Local in-game testing confirmed successful placement with modules intact, alongside automated tests and read-only verification of game-written library files; see [verification results](tests/VERIFICATION.md). This evidence covers the tested game build and templates, rather than every building mod or future engine version.

The carrier also accepts legacy numeric `blueprintBytes`/`blueprintWordN` parameters, and the menu adapter accepts older `blueprintPayload` cards. These compatibility paths decode existing data only; new cards use direct objects. Invalid direct objects are rejected rather than silently replaced by legacy payloads.

Library files now use version 4 with one independently encoded template per array element:

```lua
{
    version = 4,
    encoding = "base64",
    nextId = 25,
    nextNameNumber = 5,
    templateOrder = {21, 22, 23, 24},
    data = {
        rail_buildings = {"<template Base64>", "<template Base64>"},
        road_buildings = {},
        water_buildings = {},
        air_buildings = {"<template Base64>"},
        warehouses = {"<template Base64>"},
    },
}
```

Each Base64 element decodes to a complete template snapshot with its own ID, name, description, construction parameters and modules. Known resource directories determine the storage group; custom resources use their first saved category, including custom categories. A template is stored once even if it belongs to multiple menu categories. `templateOrder` preserves the original cross-category list order. These storage groups do not change the template's in-game menu categories.

Base64 wraps the lossless tagged serialization, preserving sparse module slots, Unicode, booleans and integer precision. Version 1, 2 and 3 libraries remain readable; the next successful edit saves them in version 4. Loading alone does not migrate the file. Older implementations do not read version 4 libraries, so back up `local/mod_presets/blueprint_demo_library.lua` before switching back. Each shared string uses the same format as one v4 category-array element. Share exports only the selected template; it does not export the entire library. The native input field supports keyboard copying and pasting; the exposed game API does not provide a direct clipboard-write function.

To verify the experiment, reload a map, select an existing template, check its preview, rotate it, adjust height and place it. Try both a modular rail station and a road station or warehouse, then save a new template and reload again. Verify module count, cargo settings and building parameters. An error about a missing single-building template indicates the nested payload may not have reached the callback intact.

## Userdata Directory Compatibility

The current game restricts `app.getAllUserdata`, `app.loadUserdata` and `app.saveUserdata` to a fixed directory allowlist. Blueprint stores its library in `local/mod_presets/blueprint_demo_library.lua`, using a dedicated filename without the native `.preset.lua` suffix.

When upgrading from the old storage path, copy `local/blueprint_demo/library.lua` to `local/mod_presets/blueprint_demo_library.lua` before reloading the map. Keep the old file as a backup and do not overwrite an existing new library. Current engines reject the old directory even when it exists; the mod cannot migrate it through these APIs. Older engines that allow the old directory can still load it, and the next successful edit writes to the new location. Failures reading an existing library remain errors and never silently reset its templates.
