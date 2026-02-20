--  ________________________________________________________________________
-- / Copyright (c) 2026 Phobos A. D'thorga                                \
-- |                                                                        |
-- |           /\_/\                                                         |
-- |         =/ o o \=    Phobos' PZ Modding                                |
-- |          (  V  )     All rights reserved.                              |
-- |     /\  / \   / \                                                      |
-- |    /  \/   '-'   \   This source code is part of the Phobos            |
-- |   /  /  \  ^  /\  \  mod suite for Project Zomboid (Build 42).         |
-- |  (__/    \_/ \/  \__)                                                  |
-- |     |   | |  | |     Unauthorised copying, modification, or            |
-- |     |___|_|  |_|     distribution of this file is prohibited.          |
-- |                                                                        |
-- \________________________________________________________________________/
--

---------------------------------------------------------------
-- PhobosLib.lua
-- Namespace root and module aggregator for PhobosLib.
-- All Phobos PZ mods should: require "PhobosLib"
---------------------------------------------------------------

PhobosLib = PhobosLib or {}
PhobosLib.VERSION = "1.9.0"

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
require "PhobosLib_Migrate"
