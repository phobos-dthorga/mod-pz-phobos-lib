<!--
  ________________________________________________________________________
 / Copyright (c) 2026 Phobos A. D'thorga                                \
 |                                                                        |
 |           /\_/\                                                         |
 |         =/ o o \=    Phobos' PZ Modding                                |
 |          (  V  )     All rights reserved.                              |
 |     /\  / \   / \                                                      |
 |    /  \/   '-'   \   This source code is part of the Phobos            |
 |   /  /  \  ^  /\  \  mod suite for Project Zomboid (Build 42).         |
 |  (__/    \_/ \/  \__)                                                  |
 |     |   | |  | |     Unauthorised copying, modification, or            |
 |     |___|_|  |_|     distribution of this file is prohibited.          |
 |                                                                        |
 \________________________________________________________________________/
-->

# Frequently Asked Questions

## What does PhobosLib do?

PhobosLib provides shared utility code used by all Phobos PZ mods. It handles common tasks like safe function calling, debug logging, tooltip rendering, sandbox variable access, save migration, and data validation so that each mod does not have to reimplement these features independently.

## Do I need to configure anything?

No. PhobosLib works automatically once installed. There are no sandbox options, settings screens, or configuration files to manage.

## Which mods use PhobosLib?

The following mods depend on PhobosLib:

| Mod | Workshop |
|-----|----------|
| **Phobos' Industrial Pathways: Biomass** (PCP) | [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3668197831) |
| **Phobos' Operational Signals** (POSnet) | [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3686788646) |
| **Phobos' Industrial Pathology** (PIP) | [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3686101131) |
| **Phobos' Notifications** (PN) | [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3687876465) |

## Is it safe to remove PhobosLib?

Only if none of the mods listed above (or any other mod that declares PhobosLib as a dependency) is active in your load order. Removing PhobosLib while a dependent mod is still enabled will cause that mod to fail to load.

## Does PhobosLib work in multiplayer?

Yes. PhobosLib is compatible with both singleplayer and multiplayer. It includes proper client/server module separation and MP-safe data synchronisation where needed.

## I found a bug -- where do I report it?

File an issue on the [GitHub repository](https://github.com/phobos-dthorga/mod-pz-phobos-lib/issues). Include your `console.txt` log and a description of what went wrong.
