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

# PhobosLib Documentation

PhobosLib is a shared utility library for Project Zomboid Build 42 mods. It is a dependency -- players install it because other mods require it.

## Guides

| Document | Audience | Description |
|----------|----------|-------------|
| [Getting Started](guides/getting-started.md) | Mod developers | Add PhobosLib as a dependency, key modules, quick examples |
| [For Players](guides/for-players.md) | Players | What PhobosLib is, installation, troubleshooting |
| [FAQ](guides/faq.md) | Everyone | Common questions about PhobosLib |

## Architecture & API Reference

| Document | Description |
|----------|-------------|
| [Module Overview & API Reference](architecture/diagrams/module-overview.md) | All modules with function signatures, parameters, and descriptions |
| [Data Systems Reference](architecture/data-systems-reference.md) | Schema, Registry, and DataLoader systems |
| [UI Reference](architecture/ui-reference.md) | Tooltip, Popup, RecipeFilter, and other client-side modules |
| [Utilities Reference](architecture/utilities-reference.md) | Util, Sandbox, Debug, and other shared helpers |
| [Error Handling](architecture/error-handling.md) | safecall patterns, Strict Mode, and error propagation |

## Diagrams & Images

Pre-rendered PNG diagrams are in [`architecture/images/`](architecture/images/) for use in Steam Workshop descriptions and Discord.

Mermaid `.mmd` source files for CLI re-rendering are in [`architecture/mermaid-src/`](architecture/mermaid-src/). See the [mermaid-src README](architecture/mermaid-src/README.md) for batch render instructions.

## Steam Workshop

| File | Description |
|------|-------------|
| [steam-workshop-description.bbcode](steam-workshop-description.bbcode) | Workshop page description |
| [steam-workshop-changelog.bbcode](steam-workshop-changelog.bbcode) | Workshop changelog |
