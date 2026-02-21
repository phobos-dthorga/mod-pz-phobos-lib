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

Technical reference for the PhobosLib shared utility library.

## Contents

| Document | Description |
|----------|-------------|
| [Module Overview & API Reference](diagrams/module-overview.md) | All 17 modules (12 shared + 5 client) with function signatures, parameters, and descriptions |

PhobosLib is a dependency library with no user-facing recipes, items, or sandbox options. It provides safe wrappers, helpers, and reusable systems for all Phobos PZ mods.

All diagrams use [Mermaid.js](https://mermaid.js.org/) syntax and render natively on GitHub.

## Exported Images

Pre-rendered PNG versions are in [`images/`](images/) for use in Steam Workshop descriptions and Discord.

## Mermaid Sources

Standalone `.mmd` source files for CLI re-rendering are in [`mermaid-src/`](mermaid-src/). See the [README](mermaid-src/README.md) for batch render instructions.
