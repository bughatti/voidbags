# VoidBags — categorized bag overhaul

**Status:** Published. Public repo: `bughatti/voidbags`.

## File layout (6 files)

| File | Role |
|---|---|
| `VoidBags.toc` | Load order |
| `Core.lua` | Module shim, config persistence |
| `Categories.lua` | Item classification rules — Equipment/Consumables/Quest/Keys/ProfMats/Sellable/Junk/Misc/Empty |
| `VoidBags.lua` | Main bag UI |
| `Bank.lua` | Bank + warband bag UI |
| `SmartSell.lua` | Junk auto-sell |
| `VoidHubBundle.lua` | Minimap registration |

## Features

- Categorized bags (drag-free auto-sort by category)
- Item markers: **L** (learnable), **C** (catalyzable), **T** (transmog new), **$** (sellable), **A** (AH-valuable), **P** (profession mat)
- Bank + warband integration
- Search, sort, bag filters
- Cross-character tracking (alt inventory)
- SmartSell: bulk-sells flagged junk

## Performance pattern (March 2026)

**Two-tier update system** — biggest perf win.

| Trigger | Action |
|---|---|
| `BAG_UPDATE` | `QuickUpdateButton` — icon/count/quality/lock only |
| Bag open | Full `UpdateButton` — gear arrows, AH values, learnable marks |
| `PLAYER_MONEY` | Gold text only |

Equipped score cache eliminates redundant `gs.calc`.

**Critical click registration:**
```lua
RegisterForClicks("LeftButtonUp", "RightButtonDown")
-- NOT "AnyDown" — double-fires
```

## Click conventions

See [[wow-bag-click-conventions]] memory:
- **Blizzard SPLITSTACK is Ctrl+Right**, NOT Shift+Left (common misconception)
- Use `C_Container.UseContainerItem` from Lua `OnClick`, NOT `/use` secure macro

## AH taint findings

See [[voidbags-smartsell-findings]] memory:
- `pcall` strips hardware events
- `VB` table tainted by SecureActionButtons inside this addon → required extracting AH posting to standalone VoidAH
- `priceCache` tainted by AH APIs

## Categorization rules

In `Categories.lua`. Order matters — first match wins. Equipment slot detection uses `GetItemInfoInstant`. Profession mat detection via `IsArtifactRelicItem` / classID checks. Sellable = vendor value > 0 AND not in keep list.
