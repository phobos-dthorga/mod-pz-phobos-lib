---------------------------------------------------------------
-- PhobosLib.lua
-- Namespace root and module aggregator for PhobosLib.
-- All Phobos PZ mods should: require "PhobosLib"
---------------------------------------------------------------

PhobosLib = PhobosLib or {}
PhobosLib.VERSION = "1.7.0"

require "PhobosLib_Util"
require "PhobosLib_Fluid"
require "PhobosLib_World"
require "PhobosLib_Sandbox"
require "PhobosLib_Quality"
require "PhobosLib_Hazard"
require "PhobosLib_Skill"
require "PhobosLib_Reset"
require "PhobosLib_Validate"
require "PhobosLib_Trading"
