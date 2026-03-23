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

# PhobosLib UI Reference

Terminal UI components for building PZ mod interfaces. Reusable PZ widget helpers for tabbed views, status badges, and collapsible rows within the ISPanel/ISButton system. All callback invocations use `PhobosLib.safecall`. Added in v1.60.0.

For other PhobosLib API documentation, see: [error-handling.md](error-handling.md), [utilities-reference.md](utilities-reference.md), [data-systems-reference.md](data-systems-reference.md)

---

## Terminal UI Utilities

### `PhobosLib.createTabbedView(panel, tabs, opts)` --> controller

Create a row of tab header buttons with a shared content panel. Clicking a tab clears the content panel and calls the selected tab's render function.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `panel` | ISPanel | Parent panel to add tab buttons and content panel to |
| `tabs` | table[] | Array of `{ id=string, labelKey=string, renderFn=function(contentPanel, y) }` |
| `opts` | table\|nil | Optional: `{ x, y, width, height, activeTab, colours }` |

**`opts` fields:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `x` | number | 0 | X offset for tab row |
| `y` | number | 0 | Y offset for tab row |
| `width` | number | panel width | Width of content panel |
| `height` | number | panel height - y | Total height (tabs + content) |
| `activeTab` | string | first tab's id | Initially active tab |
| `colours` | table\|nil | grey tones | `{ active={r,g,b,a}, inactive={r,g,b,a} }` |

**Returns:** Controller table:

| Method / Field | Type | Description |
|----------------|------|-------------|
| `switchTab(id)` | function | Programmatically switch to a tab by id |
| `getActiveTab()` | function | Returns the currently active tab id |
| `contentPanel` | ISPanel | Direct reference to the content area |
| `destroy()` | function | Remove all created UI elements from parent |

**Usage -- terminal screen with tabs:**

```lua
local ctrl = PhobosLib.createTabbedView(self, {
    { id = "overview", labelKey = "UI_POS_TabOverview", renderFn = function(cp, y)
        ISLabel:new(10, y, 25, "Overview content", 1, 1, 1, 1, UIFont.Small, true)
    end },
    { id = "details", labelKey = "UI_POS_TabDetails", renderFn = function(cp, y)
        ISLabel:new(10, y, 25, "Detail content", 1, 1, 1, 1, UIFont.Small, true)
    end },
}, { activeTab = "overview" })

-- Later: programmatic switch
ctrl.switchTab("details")

-- Cleanup
ctrl.destroy()
```

### `PhobosLib.createStatusBadge(panel, x, y, text, colour)` --> ISLabel

Create a coloured text label for inline status or type indicators. Enforces consistent sizing and font across all terminal screens.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `panel` | ISPanel | Parent panel to add the label to |
| `x` | number | X position |
| `y` | number | Y position |
| `text` | string | Text to display |
| `colour` | table | `{ r, g, b, a }` text colour |

**Returns:** The ISLabel element.

**Usage -- status indicator:**

```lua
local badge = PhobosLib.createStatusBadge(row, 200, 5, "ACTIVE", { r = 0.2, g = 0.9, b = 0.2, a = 1.0 })

-- Red warning badge
PhobosLib.createStatusBadge(row, 200, 5, "OFFLINE", { r = 0.9, g = 0.2, b = 0.2, a = 1.0 })
```

### `PhobosLib.createExpandableRow(panel, opts)` --> controller

Create a collapsible row with a clickable header panel and a toggleable detail panel. Detail content is rendered lazily on first expand.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `panel` | ISPanel | Parent panel to add header and detail panels to |
| `opts` | table | Configuration table (see fields below) |

**`opts` fields:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `x` | number | 0 | X offset |
| `y` | number | 0 | Y offset |
| `width` | number | panel width | Row width |
| `headerHeight` | number | 25 | Height of the header panel |
| `detailHeight` | number | 50 | Height of the detail panel |
| `headerFn` | function(headerPanel) | nil | Called once to populate header content |
| `detailFn` | function(detailPanel) | nil | Called lazily on first expand to populate detail |
| `startExpanded` | boolean | false | Whether to start in expanded state |

**Returns:** Controller table:

| Method | Type | Description |
|--------|------|-------------|
| `toggle()` | function | Toggle expanded/collapsed state |
| `isExpanded()` | function | Returns `true` if currently expanded |
| `destroy()` | function | Remove all created UI elements from parent |
| `totalHeight()` | function | Returns `headerHeight` (collapsed) or `headerHeight + detailHeight` (expanded) |

**Usage -- expandable commodity row:**

```lua
local row = PhobosLib.createExpandableRow(listPanel, {
    x = 0, y = currentY, width = 400,
    headerHeight = 30, detailHeight = 60,
    headerFn = function(hp)
        ISLabel:new(10, 5, 20, "Fuel - $4.50/unit", 1, 1, 1, 1, UIFont.Small, true)
    end,
    detailFn = function(dp)
        ISLabel:new(10, 5, 20, "Supply: 340 units | Demand: High", 0.8, 0.8, 0.8, 1, UIFont.Small, true)
    end,
    startExpanded = false,
})

currentY = currentY + row.totalHeight()

-- Programmatic toggle
row.toggle()
```

---

## Scroll Panel

`PhobosLib.createScrollPanel(parent, x, y, w, h)` — creates a stencil-clipped
ISPanel that scrolls its children with the mouse wheel when content exceeds the
visible height.

The panel has transparent background/border so it blends with any parent. Use it
to wrap variable-height content areas while keeping fixed headers/footers outside
the scroll region.

**Parameters:**

| Param | Type | Description |
|---|---|---|
| `parent` | ISPanel | Parent container to add the scroll panel to |
| `x` | number | X position relative to parent |
| `y` | number | Y position relative to parent |
| `w` | number | Width |
| `h` | number | Height (content beyond this scrolls) |

**Returns:** ISPanel with stencil clipping and `setScrollChildren(true)` enabled.

**Example:**

```lua
-- Create a scroll area below a header, leaving room for a footer button
local headerY = 40  -- after drawing header
local footerH = 30  -- space for back button
local scrollH = contentPanel:getHeight() - headerY - footerH
local scrollPanel = PhobosLib.createScrollPanel(contentPanel, 0, headerY,
    contentPanel:getWidth(), scrollH)

-- All content widgets added to scrollPanel use y=0 as their origin
-- Mouse wheel scrolling activates when total child height > scrollH
```
