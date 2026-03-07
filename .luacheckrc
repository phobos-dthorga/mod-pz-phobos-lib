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

-- Suppress local variable code quality warnings (2XX–5XX).
-- The primary value of luacheck for PZ modding is catching undefined
-- globals (1XX) — typos in function names, missing requires, etc.
-- Local variable warnings (unused vars, shadowing, empty branches)
-- are non-critical in the PZ modding context where pcall patterns,
-- monkey-patching, and callback signatures create many false positives.
ignore = {
    "21.",   -- unused variable / argument / loop variable
    "22.",   -- variable accessed but never set
    "23.",   -- variable set but never used
    "31.",   -- value assigned is unused
    "4..",   -- shadowing / redefinition
    "5..",   -- code quality (unreachable code, empty blocks)
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
    "getCell",
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
    "MF",
    "NeatTool",
}
