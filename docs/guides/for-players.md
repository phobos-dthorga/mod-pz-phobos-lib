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

# PhobosLib -- For Players

You are here because a mod you installed requires PhobosLib.

## What is PhobosLib?

PhobosLib is a shared library used by several Project Zomboid mods. It does not add any gameplay features, items, recipes, or sandbox options on its own. Think of it as a toolbox that other mods use behind the scenes.

## Installation

Just subscribe to [PhobosLib on Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3668598865) and it works automatically. No configuration needed.

## Troubleshooting

### "Mod says PhobosLib is missing"

1. Make sure you are subscribed to [PhobosLib on Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3668598865).
2. In the PZ mod manager, ensure PhobosLib is **enabled** and appears **above** the mod that requires it in the load order.
3. Restart the game after enabling PhobosLib.

### "Can I remove PhobosLib?"

Only if no other mod in your load order depends on it. If you unsubscribe while a dependent mod is still active, that mod will fail to load.

### "Does PhobosLib affect performance?"

No. It only runs code when another mod calls it. On its own, it sits idle.
