# VoidBags

**Smart bag organizer with auto-categorization, cross-character tracking, and one-click merchant tools.**

Replaces Blizzard's stock bag UI with a single unified inventory window that auto-sorts every item into 17 contextual lanes. Includes a matching bank panel, cross-character item search, junk auto-sell, auto-repair (optional guild funds), and AH value awareness.

---

## Features

### Single-window bag UI
- One frame shows backpack + bags 1-4 + reagent bag together
- Resizable, draggable, position persists
- Right-click items to send between bags/bank (uses Blizzard's native handlers)
- Free slot count + total gold displayed in the header

### 17-lane auto-categorization
Items are routed into intuitive groups so you never lose anything:
1. Equipment
2. **Warband** (bindType 7/8 detection)
3. **Cosmetic** (armor subClass 5 / IsCosmeticItem)
4. **Flasks** (consumable subclass 3)
5. **Potions** (subclasses 1/2)
6. **Food & Drink** (subclass 5)
7. Consumables (generic)
8. Quest Items
9. Keys
10. **Alchemy Mats** (Herbs/Elemental)
11. **Cooking Mats** (Meat/Fish/Cooking subclass)
12. **Jewelcrafting Mats** (Gems/JC subclass)
13. Other Profession Mats
14. Craftable
15. Sell / Other Mats
16. Junk
17. Miscellaneous

### Merchant integration
- `/vb sell` — sells all junk + AH-trash reagents below threshold
- `/vb repair` — manual repair
- `/vb autorepair` — toggle repair-on-merchant
- `/vb guildrepair` — toggle guild-bank funds preference
- `/vb autosell` — toggle auto-sell junk on merchant interaction
- `/vb threshold <gold>` — set AH value threshold under which reagents count as "trash" for selling

### Bank panel
- Companion frame for the bank
- Same categorization logic
- Right-click to send items between bags ↔ bank
- Full Warband bank support (12.0)

### Cross-character inventory
- `/vb search <name>` — finds an item across all your characters' bags
- `/vb chars` — list every character with VoidBags inventory tracked
- Per-character snapshot saved on logout

### Protected items
- `/vb protect` — list of items the addon refuses to junk-sell
- Prevents accidentally vendoring rare/sentimental items

### Fallback to Blizzard bags
- `/vb default` (or `/vb blizz`) — temporarily switch to the stock UI for the session
- Useful if an addon conflict breaks something — reload restores VoidBags

---

## Slash commands

| Command | Action |
|---|---|
| `/vb` | Toggle bag window |
| `/vb reset` | Reset frame position + size |
| `/vb sell` | Sell junk + below-threshold reagents |
| `/vb repair` | Manual repair |
| `/vb autorepair` | Toggle auto-repair on merchant |
| `/vb guildrepair` | Toggle guild-funds preference for repair |
| `/vb autosell` | Toggle auto-sell junk on merchant |
| `/vb threshold <gold>` | Set AH value threshold |
| `/vb search <name>` | Cross-character item search |
| `/vb chars` | List tracked characters |
| `/vb protect` | List protected items |
| `/vb default` | Switch to Blizzard's stock bags (toggle) |
| `/vb help` | In-game command reference |

---

## Installation

1. Download and extract to `Interface/AddOns/VoidBags/`
2. Reload your UI (`/reload`)
3. Press **B** to open VoidBags instead of the default Blizzard bag UI

---

## Storage

- **`VoidBagsDB`** (account-wide): config, AH price cache, character inventory snapshots
- **`VoidBagsCharDB`** (per-character): protected items, per-char preferences

---

## Compatibility

- **WoW Interface 12.0.7** (Midnight Season 1)
- Plays nice with most UI replacements (ElvUI, VoidUI, default)
- No taint in normal usage — falls back to Blizzard bags via `/vb default` if anything weird happens
- Works with the Reagent Bag (slot 5) and Warband Bank (12.0)

---

## Credits

Built for Vede on Elune. Part of the Void* addon family.
