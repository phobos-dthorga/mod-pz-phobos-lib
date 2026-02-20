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

# Mermaid Source Files

Standalone `.mmd` diagram sources for CLI rendering.
These are the same diagrams embedded in [`../diagrams/*.md`](../diagrams/), extracted for batch processing.

## Files

| File | Diagram |
|------|---------|
| `phoboslib-modules.mmd` | PhobosLib v1.4.1 module architecture (9 modules) |

## Re-render all to PNG

```bash
npm install -g @mermaid-js/mermaid-cli
for f in *.mmd; do mmdc -i "$f" -o "../images/${f%.mmd}.png" -b white -s 2; done
```
