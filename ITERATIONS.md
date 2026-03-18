# PhobosLib Iteration History

A living document tracking the iterative design journey of Phobos' Shared Library.

---

## v1.0.0–v1.35.0 — Foundation & Growth

### Core Philosophy
- Build once, use everywhere: shared utilities for all Phobos PZ mods
- Every function justified by 2+ consumers minimum
- pcall-wrapped for B42 API resilience

### Key Milestones
- Debug logging (PhobosLib_Debug)
- Sandbox variable wrappers (PhobosLib_Sandbox)
- Quality/purity system (PhobosLib_Quality)
- Item tooltip provider (PhobosLib_Tooltip) — ISToolTipInv render hook
- Dynamic Trading wrapper (PhobosLib_Trading)
- Fermentation registry (PhobosLib_Fermentation)
- Player reputation system (PhobosLib_Reputation)
- Money management (PhobosLib_Money)
- NPC name generation (PhobosLib_NPCNames)

---

## v1.36.0 — Weighted Random Selection

### Consumers
- POSnet market intelligence (category/item selection)
- POSnet market broadcaster (weighted category broadcast)

### Functions Added
- weightedRandom(items, weightFn)
- weightedRandomMultiple(items, count, weightFn)

---

## v1.37.0 — Rolling Window Utilities

### Consumers
- POSnet economy tick (observation trimming, rolling closes)
- POSnet market database (capped observation windows)
- Applicable to PCP fermentation and PIP specimen tracking

### Functions Added
- trimArray(arr, maxCount)
- pushRolling(arr, value, maxCount)
- trimByAge(arr, dayField, maxAge, currentDay)

---

## v1.38.0 — Text Measurement & Truncation

### Consumers
- POSnet terminal UI (button labels, nav panel, separators)
- Applicable to PCP tooltip rendering, PIP future UI

### Functions Added
- truncateText(text, font, maxPixelWidth, ellipsis)
- measureCharWidth(font)
- maxCharsForWidth(font, pixelWidth, padding)

---

## v1.39.0 — Price Formatting & Document Builder

### Consumers
- POSnet dynamic tooltips, market note journal pages
- Applicable to PCP trading prices, PIP specimen reports

### Functions Added
- formatPrice(value, prefix) — "$0.60" formatting
- titleCase(text) — "grocery store" → "Grocery Store"
- createReadableDocument(item, title, pages) — PZ Literature API wrapper
- readDocumentPage(item, pageIndex)
- getDocumentPageCount(item)

### Design Principle
- PhobosLib_Address.lua is 100% clean-room implementation
- Parses vanilla streets.xml, builds spatial grid index
- No external mod code used or referenced
