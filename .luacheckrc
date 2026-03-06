-- .luacheckrc — PhobosLib
-- Lua 5.1 (Kahlua) for Project Zomboid Build 42

std = "lua51"

-- PZ mods define globals at top level (e.g. PhobosLib = PhobosLib or {})
allow_defined_top = true

-- PZ modding uses long lines freely
max_line_length = false

-- PZ callback signatures have fixed args that aren't always used
unused_args = false

-- pcall returns ok,result; ok is often checked only implicitly
unused_secondaries = false

-- PhobosLib's own namespace + PZ classes that PhobosLib monkey-patches
-- (overriding methods is standard PZ modding practice)
globals = {
    "PhobosLib",
    -- PZ UI classes PhobosLib overrides methods on
    "ISFarmingMenu",
    "ISRecipeScrollingListBox",
    "ISTiledIconPanel",
    "ISToolTipInv",
    "ISWidgetHandCraftControl",
    "ISWidgetTitleHeader",
    -- Cross-mod (written to when patching)
    "CFarming_Interact",
    "NC_FilterBar",
    "NC_RecipeInfoPanel",
}

read_globals = {
    -- PZ engine core
    "Events",
    "SandboxVars",
    "Perks",
    "ModData",
    "FluidType",
    "UIFont",
    "CharacterStat",

    -- PZ engine functions
    "getActivatedMods",
    "getCore",
    "getDebug",
    "getGameTime",
    "getModInfoByID",
    "getMouseX",
    "getMouseY",
    "getPlayer",
    "getPlayerScreenLeft",
    "getPlayerScreenTop",
    "getSpecificPlayer",
    "getSandboxOptions",
    "getText",
    "getTextManager",
    "getTimestampMs",
    "getWorld",
    "instanceof",
    "instanceItem",
    "isClient",
    "isJoypadCharacter",
    "isServer",
    "sendItemStats",
    "sendAddItemToContainer",
    "sendRemoveItemFromContainer",

    -- PZ Java classes
    "ArrayList",
    "CFarmingSystem",
    "CraftRecipeListNode",
    "GameEntityFactory",
    "MapObjects",
    "callLuaBool",

    -- PZ UI classes (read-only access)
    "ISBaseTimedAction",
    "ISButton",
    "ISCollapsableWindow",
    "ISContextMenu",
    "ISCurePlantAction",
    "ISPanelJoypad",
    "ISRichTextPanel",
    "ISScrollingListBox",
    "ISTickBox",
    "ISTimedActionQueue",
    "ISWorldObjectContextMenu",

    -- Cross-mod (optional, runtime-guarded)
    "DynamicTrading",
    "EHR",
    "NeatTool",
}
