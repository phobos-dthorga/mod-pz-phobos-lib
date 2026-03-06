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

-- Suppress common PZ modding code patterns:
--   211/ok          — unused pcall success flag (very common PZ pattern)
--   211/_orig_.*    — saved original functions before monkey-patching
--   221             — variable with _ prefix that IS used (underscore convention mismatch)
--   411/ok          — shadowing ok in nested pcall blocks
--   542             — empty if branch (guard clauses)
ignore = {
    "211/ok",
    "211/_orig_.*",
    "221",
    "411/ok",
    "542",
}

-- PhobosLib's own namespace + PZ classes that PhobosLib monkey-patches
-- (overriding methods is standard PZ modding practice)
globals = {
    "PhobosLib",
    -- PZ engine core (PhobosLib writes to SandboxVars for sandbox management)
    "SandboxVars",
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
    "Perks",
    "ModData",
    "Fluid",
    "FluidType",
    "ScriptManager",
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
    "sendServerCommand",
    "ZombRand",

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
