---------------------------------------------------------------
-- PhobosLib.lua
-- Namespace root and module aggregator for PhobosLib.
-- All Phobos PZ mods should: require "PhobosLib"
---------------------------------------------------------------

PhobosLib = PhobosLib or {}
PhobosLib.VERSION = "1.0.0"

require "PhobosLib_Util"
require "PhobosLib_Fluid"
require "PhobosLib_World"
require "PhobosLib_Sandbox"
