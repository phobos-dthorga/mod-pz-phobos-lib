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
