-- .luacheckrc — PhobosLib
-- Lua 5.1 (Kahlua) for Project Zomboid Build 42

std = "lua51"

-- PZ mods define globals at top level (e.g. PhobosLib = PhobosLib or {})
allow_defined_top = true

-- PZ modding uses long lines freely
max_line_length = false

-- PhobosLib's own global namespace
globals = {
    "PhobosLib",
}

read_globals = {
    -- PZ engine core
    "Events",
    "SandboxVars",
    "Perks",
    "ModData",
    "FluidType",
    "UIFont",

    -- PZ engine functions
    "getActivatedMods",
    "getCore",
    "getDebug",
    "getGameTime",
    "getModInfoByID",
    "getPlayer",
    "getSpecificPlayer",
    "getSandboxOptions",
    "getText",
    "getTextManager",
    "getTimestampMs",
    "getWorld",
    "instanceof",
    "instanceItem",
    "isClient",
    "isServer",
    "sendItemStats",
    "sendAddItemToContainer",
    "sendRemoveItemFromContainer",

    -- PZ UI classes (used via require)
    "ISBaseTimedAction",
    "ISButton",
    "ISCollapsableWindow",
    "ISCurePlantAction",
    "ISFarmingMenu",
    "ISPanelJoypad",
    "ISRecipeScrollingListBox",
    "ISRichTextPanel",
    "ISScrollingListBox",
    "ISTickBox",
    "ISTiledIconPanel",
    "ISTimedActionQueue",
    "ISToolTipInv",
    "ISWidgetHandCraftControl",
    "ISWidgetTitleHeader",
    "ISWorldObjectContextMenu",

    -- Cross-mod (optional, runtime-guarded)
    "DynamicTrading",
}
