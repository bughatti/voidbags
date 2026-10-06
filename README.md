# VoidBags

**Smart bag organizer with auto-categorization, cross-character tracking, and one-click merchant tools.**

VoidBags replaces Blizzard's bags with one unified window that sorts every item into 17 categories automatically. It adds a matching bank panel, cross-character item search, junk auto-sell, auto-repair (optionally from guild funds), and auction-value awareness.

---

## Features

### One window for everything
- **Backpack, bags 1–4, and the reagent bag** together in one frame
- Resizable and draggable — the position is remembered
- **Free slots and your gold** shown in the header
- **Bag swapping** — drag a bag onto the bag bar to equip it, drag it out to remove it
- **Settings** behind the gear icon in the title bar

### 17 automatic categories
Equipment · **Warband** · **Cosmetic** · **Flasks** · **Potions** · **Food & Drink** · Consumables · Quest Items · Keys · **Alchemy Mats** · **Cooking Mats** · **Jewelcrafting Mats** · Other Profession Mats · Craftable · Sell / Other Mats · Junk · Miscellaneous

### Item markers at a glance
- **Item level** on gear and a **green upgrade arrow** on real upgrades — only armor your class can wear
- Letter markers: **L** learnable · **C** a material for your professions · **A** an alt's profession needs it · **$** worth selling on the AH · **T** vendor trash · **P** protected
- **Auction value** shown on items worth selling

### Merchant tools
- **Auto-sell junk** when you open a vendor, plus AH-trash reagents below your price threshold
- **Auto-repair**, optionally using guild-bank funds
- **Protected items** — hover an item and type `/vb protect`; VoidBags will never sell it

### Bank and Warband bank
- A **companion bank panel** with the same categories
- **Right-click** to move items between bags and bank
- **Full Warband bank support**, including tabs you buy later
- **Buy Tab button** shows the next tab's cost (opens Blizzard's bank to complete the purchase)

### Cross-character inventory
- **Search every character's bags** for an item with `/vb search`
- Each character's inventory is snapshotted on logout

### Safe fallback
- **`/vb default`** switches back to Blizzard's bags for the session if another addon ever conflicts; a `/reload` brings VoidBags back

---

## Slash Commands

| Command | What it does |
|---|---|
| `/vb` | Open or close the bags |
| `/vb sell` | Sell junk and below-threshold reagents |
| `/vb repair` | Repair now |
| `/vb autorepair` | Turn auto-repair on or off |
| `/vb guildrepair` | Prefer guild funds for repairs |
| `/vb autosell` | Turn auto-sell junk on or off |
| `/vb threshold <gold>` | Set the AH value below which reagents count as trash |
| `/vb search <name>` | Find an item across all your characters |
| `/vb chars` | List tracked characters |
| `/vb protect` | List protected items — or hover an item first to protect/unprotect it |
| `/vb default` | Switch to Blizzard's bags (toggle) |
| `/vb reset` | Reset position and size |
| `/vb help` | Show all commands in game |

---

## Getting Started

1. Install with the CurseForge app, or copy the `VoidBags` folder into `World of Warcraft/_retail_/Interface/AddOns/`.
2. Restart WoW or `/reload`.
3. Press **B** — VoidBags opens instead of the default bags.

---

## Compatibility

- **WoW 12.1** (Midnight Season 2)
- **WoW Forever** supported too
- Standalone — nothing else to install
- Plays nicely with ElvUI, VoidUI, and the default UI
- Supports the reagent bag and the Warband bank

---

*Part of the Void addon family by Vede · MIT licensed · free M+ & raid player lookups at [voidscout.io](https://voidscout.io) · more addons & apps at [tinkerline.io](https://tinkerline.io) · [Discord](https://discord.gg/7ZHmx7zMDh)*
