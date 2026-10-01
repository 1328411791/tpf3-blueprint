# Blueprint

A Transport Fever 3 mod that saves existing player buildings as reusable blueprints and adds them to the construction menu.

## Features

- Save individual stations, warehouses and depots with their building parameters, modules and supported cargo settings.
- Place saved blueprints using the game's construction controls, including rotation and height adjustment.
- Inherit the original building's construction sounds, with a standard building sound as fallback.
- Manage templates in a searchable list with building previews.
- Edit template names and descriptions, duplicate templates, and delete unwanted entries.
- Keep a local template library that can be used across maps.
- English and Simplified Chinese interface.

## How to Use

1. Enable **Blueprint** for your map.
2. Open a supported construction category and select **Save Building Template**.
3. Click a building you own and wait for the template to appear in the menu.
4. Select the saved template and place it like a normal building.
5. Open **Template Manager** at the upper right of the construction menu to search, edit, duplicate or delete templates.

## Scope

Each blueprint contains one building. Nearby roads and tracks, vehicles, routes and building inventories are not included. Templates require the original building and module mods to be available.

Deleting a template leaves buildings already placed on the map intact.

Default template names use a separate counter from internal IDs. Deleting every template resets the next default name to Template 1; internal IDs keep increasing. Duplicating a template adds a copy suffix without consuming a default name number. Existing template names remain unchanged.
