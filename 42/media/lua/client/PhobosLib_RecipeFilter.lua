---------------------------------------------------------------
-- PhobosLib_RecipeFilter.lua
-- Client-side crafting menu recipe visibility filter.
--
-- Provides a filter registry that mods can use to hide/show
-- craftRecipe entries based on sandbox settings or any other
-- runtime condition.
--
-- Supports three UI code paths:
--   Path 1: Vanilla ISRecipeScrollingListBox:addGroup() (list view)
--   Path 2: Vanilla ISTiledIconPanel:setDataList() (grid view)
--   Path 3: Neat Crafting NC_FilterBar:shouldIncludeRecipe()
--
-- B42 craftRecipe "OnTest" is a server-side execution gate,
-- NOT a UI visibility gate. getOnAddToMenu() only works for
-- entity building recipes. This module fills the gap.
--
-- Part of PhobosLib >= 1.6.0
---------------------------------------------------------------

require "ISUI/ISScrollingListBox"
require "Entity/ISUI/CraftRecipe/ISRecipeScrollingListBox"
require "Entity/ISUI/CraftRecipe/ISTiledIconPanel"

PhobosLib = PhobosLib or {}

--- Internal filter registry: recipeName -> function() -> boolean
-- true = show the recipe, false = hide it
PhobosLib._recipeFilters = PhobosLib._recipeFilters or {}

--- Register a visibility filter for a single recipe.
-- The filter function is called each time the crafting menu is
-- populated. It receives no arguments and should return true if
-- the recipe should be shown, false to hide it.
-- @param recipeName string  The recipe's script name (e.g. "PCPDistillMethanol")
-- @param filterFunc function  A function returning boolean (true = show)
function PhobosLib.registerRecipeFilter(recipeName, filterFunc)
    if type(recipeName) ~= "string" or recipeName == "" then
        print("[PhobosLib:RecipeFilter] registerRecipeFilter: invalid recipeName")
        return
    end
    if type(filterFunc) ~= "function" then
        print("[PhobosLib:RecipeFilter] registerRecipeFilter: filterFunc must be a function")
        return
    end
    PhobosLib._recipeFilters[recipeName] = filterFunc
end

--- Bulk-register visibility filters from a table.
-- @param filterTable table  { ["RecipeName"] = filterFunc, ... }
function PhobosLib.registerRecipeFilters(filterTable)
    if type(filterTable) ~= "table" then
        print("[PhobosLib:RecipeFilter] registerRecipeFilters: expected table")
        return
    end
    local count = 0
    for recipeName, filterFunc in pairs(filterTable) do
        PhobosLib.registerRecipeFilter(recipeName, filterFunc)
        count = count + 1
    end
    print("[PhobosLib:RecipeFilter] registered " .. count .. " recipe filter(s)")
end

--- Check a recipe name against the filter registry.
-- @param recipeName string  The recipe name to check
-- @return boolean  true if the recipe should be shown (or has no filter)
function PhobosLib._checkRecipeFilter(recipeName)
    local filter = PhobosLib._recipeFilters[recipeName]
    if filter then
        local ok, result = pcall(filter)
        if ok then
            return result == true
        else
            print("[PhobosLib:RecipeFilter] ERROR in filter for '" .. recipeName .. "': " .. tostring(result))
            return true  -- fail-open: show recipe if filter errors
        end
    end
    return true  -- no filter registered = always show
end

---------------------------------------------------------------
-- Path 1: Override ISRecipeScrollingListBox:addGroup()
-- For vanilla crafting UI list view.
-- Identical to vanilla except: after the getOnAddToMenu() check,
-- also checks PhobosLib._recipeFilters for the recipe name.
---------------------------------------------------------------

local _orig_addGroup = ISRecipeScrollingListBox.addGroup

function ISRecipeScrollingListBox:addGroup(_groupNode, _nodes, _recipeToSelect, _enabledShowAllFilter)
    local recipeFoundIndex = -1

    if _groupNode then
        local groupTitle = _groupNode:getTitle()
        local listItem = self:addItem(groupTitle, nil)
        listItem.groupNode = _groupNode
    end

    for i = 0, _nodes:size() - 1 do
        local craftRecipeListNode = _nodes:get(i)
        if craftRecipeListNode:getType() == CraftRecipeListNode.CraftRecipeListNodeType.RECIPE then
            local failed = false
            local craftRecipe = craftRecipeListNode:getRecipe()

            -- Vanilla OnAddToMenu check (entity recipes only)
            if craftRecipe and craftRecipe:getOnAddToMenu() then
                local func = craftRecipe:getOnAddToMenu()
                local params = {player = self.player, recipe = craftRecipe, shouldShowAll = _enabledShowAllFilter}
                failed = not callLuaBool(func, params)
            end

            -- PhobosLib recipe filter check
            if not failed and craftRecipe then
                local recipeName = craftRecipe:getName()
                if recipeName then
                    failed = not PhobosLib._checkRecipeFilter(recipeName)
                end
            end

            if not failed then
                local listItem = self:addItem(craftRecipe:getTranslationName(), craftRecipe)
                listItem.node = craftRecipeListNode
                if listItem.item == _recipeToSelect then
                    recipeFoundIndex = listItem.itemindex
                end
            end
        elseif craftRecipeListNode:getType() == CraftRecipeListNode.CraftRecipeListNodeType.GROUP then
            local groupRecipeFoundIndex = self:addGroup(craftRecipeListNode, craftRecipeListNode:getChildren(), _recipeToSelect, _enabledShowAllFilter)
            if groupRecipeFoundIndex ~= -1 then
                recipeFoundIndex = groupRecipeFoundIndex
            end
        end
    end

    return recipeFoundIndex
end

---------------------------------------------------------------
-- Path 2: Override ISTiledIconPanel:setDataList()
-- For vanilla crafting UI grid/tiled view.
-- Identical to vanilla except: after the getOnAddToMenu() check,
-- also checks PhobosLib._recipeFilters for the recipe name.
---------------------------------------------------------------

local _orig_setDataList = ISTiledIconPanel.setDataList

function ISTiledIconPanel:setDataList(_dataList)
    local currentRecipe = self.callbackTarget and self.callbackTarget.logic and self.callbackTarget.logic:getRecipe()
    local currentRecipeFound = false

    self.sourceDataList = ArrayList.new()
    local recipeList = _dataList:getAllRecipes()
    for i = 0, recipeList:size() - 1 do
        local failed = false
        local recipe = recipeList:get(i)

        -- Vanilla OnAddToMenu check (entity recipes only)
        if recipe:getOnAddToMenu() then
            local func = recipe:getOnAddToMenu()
            local params = {player = self.player, recipe = recipe}
            failed = not callLuaBool(func, params)
        end

        -- PhobosLib recipe filter check
        if not failed then
            local recipeName = recipe:getName()
            if recipeName then
                failed = not PhobosLib._checkRecipeFilter(recipeName)
            end
        end

        if not failed then
            self.sourceDataList:add(recipe)
            if recipe == currentRecipe then
                currentRecipeFound = true
            end
        end
    end

    self.dataList:clear()
    self.dataList:addAll(self.sourceDataList)

    self:filterData(self.searchText)

    if currentRecipeFound then
        self:setSelectedData(currentRecipe)
    end
end

---------------------------------------------------------------
-- Path 3: Neat Crafting compatibility
-- NC_FilterBar:shouldIncludeRecipe() is the single gatekeeper
-- for all recipes in Neat Crafting's custom crafting UI.
-- Wrap it to inject PhobosLib filter checks after NC's own
-- filters pass.
---------------------------------------------------------------

--- Install the NC_FilterBar hook (shared by immediate and deferred paths).
local function _installNCFilterBarHook()
    if not NC_FilterBar or not NC_FilterBar.shouldIncludeRecipe then
        return false
    end

    local _orig_shouldIncludeRecipe = NC_FilterBar.shouldIncludeRecipe

    function NC_FilterBar:shouldIncludeRecipe(recipe)
        -- Run Neat Crafting's own filters first
        if not _orig_shouldIncludeRecipe(self, recipe) then
            return false
        end
        -- Apply PhobosLib recipe filters
        if recipe then
            local recipeName = recipe:getName()
            if recipeName then
                return PhobosLib._checkRecipeFilter(recipeName)
            end
        end
        return true
    end

    return true
end

-- Try immediate install (works if Neat Crafting loaded before PhobosLib)
if _installNCFilterBarHook() then
    print("[PhobosLib:RecipeFilter] Neat Crafting detected — NC_FilterBar override installed")
else
    -- Deferred install: try again after all mods are fully loaded
    local function _tryDeferredNCHook()
        if _installNCFilterBarHook() then
            print("[PhobosLib:RecipeFilter] Neat Crafting detected (deferred) — NC_FilterBar override installed")
        end
    end
    Events.OnGameStart.Add(_tryDeferredNCHook)
end

---------------------------------------------------------------
-- Startup confirmation
---------------------------------------------------------------

print("[PhobosLib:RecipeFilter] UI overrides installed (vanilla list + vanilla tiled + NC compat)")
