# Changelog

## [1.2.0] — 2026-06-20

### New: Guild Bank
- **Full guild bank panel** built into VoidBags, opened from the bag window's
  **Guild** button or automatically at a guild banker. Replaces Blizzard's
  default window (its frame is suppressed so you don't get two).
- **Browse + search** every tab; **browse-anywhere** shows a cached snapshot of
  your guild bank even when you're away from a banker.
- **Mode tabs:** Guild Bank · Log · Money Log · Repairs · Info.
- **Money box** with deposit/withdraw (uses Blizzard's own confirm dialogs;
  respects your rank's withdraw limit).
- **Item deposit/withdraw** via click or drag — only ever moved by your own
  click/drag, never automated.
- **Repair-spend tracker** — per-player repair gold pulled from the money log
  (last 7 days), visible to everyone.
- **Repair budget target** (officers + GM) — set a Raid-week / Off-week gold
  target to measure spend against. Note: this is a local target tracker; the
  actual rank withdraw limit is still set in Blizzard's Guild Control (that
  write is protected and can't be done from an addon).

## [1.1.3] — 2026-06-20

### Compatibility
- Updated for WoW **12.0.7** (Sporefall). No code changes required — all bag,
  bank, and item APIs VoidBags uses are unchanged this patch; this release just
  bumps the supported interface version so it no longer shows as out of date.

## [1.1.2] — 2026-06-02

### Bug fixes
- **Embedded VoidLib.** Previously VoidBags declared `## Dependencies: VoidLib`
  but VoidLib was never published to CurseForge, so downloads from CurseForge
  failed to load with "Dependency: VoidLib is missing." Now ships with VoidLib
  bundled under `Libs/VoidLib/` — no separate addon required.

## [1.1.1] — 2026-05-31

### Bug fixes
- **Ghost bag fixed.** Closing the bag now actually hides the frame when out of
  combat instead of just going transparent. The previous design left a
  click-swallowing overlay in the bag's footprint, so any UI element under
  that space (cooldowns, mouseover frames, world clicks) couldn't be
  interacted with. In combat the alpha+blocker pattern is preserved
  because `:Hide()` on SecureActionButton-containing frames triggers taint.

## [1.0.4] — 2026-05-17

### Bug fixes
- **Right-click to USE items now works for equipment, consumables, gold bags, etc.**
  Right-click is now wired through a secure `/use bag slot` macro (required —
  protected actions like equipping gear can't be done from Lua and were
  triggering AddOnActionBlocked popups). The macro updates dynamically when
  LayoutBags reassigns slots, so it never goes stale.
- **Ctrl+Right-Click on a stack now opens a split-stack prompt.**
  Three compatibility paths: `OpenStackSplitFrame()` global → `StackSplitFrame:OpenStackSplitFrame()`
  method (the surviving path in 12.0.5) → custom StaticPopup fallback with a
  numeric input. Works even if Blizzard removes the helper entirely in the future.
- **Other windows on the right side are now clickable when the bag is closed.**
  Previously the bag's invisible click-blocker sat at frame strata HIGH (above
  Character / Talents / Spec / Settings windows), eating clicks anywhere in
  the bag's right-side footprint. The blocker now drops to BACKGROUND when
  the bag is hidden — secure children below it are still protected, but other
  UI sits on top and gets clicks first.
- **Shift+Right-Click now opens dress-up preview** as expected.

### Click cheat sheet
| Click | Action |
|-------|--------|
| Left | Pick up / place |
| Right | USE item (consume / equip / open) |
| Ctrl+Right | Split stack |
| Shift+Right | Dress-up preview |
| Ctrl+Left | Item compare |
| Drag | Pick up |

## [1.0.3] — 2026-05-17

### Bug fixes
- **Fixed click-through on hidden bag.** Previously when the bag was "closed"
  (alpha=0) the SecureActionButton item children could still receive mouse
  clicks because `EnableMouse(false)` on a parent doesn't propagate to
  children. Added a non-secure mouse-blocking overlay that silently swallows
  clicks + scroll wheel events while the bag is hidden. The overlay is itself
  combat-safe (it's a plain Frame with no protected children, so Show/Hide
  on it works in combat).

## [1.0.2] — 2026-05-17

### New features
- **Categorization expanded from 9 → 17 lanes.** Now includes dedicated
  lanes for Warband (bindType 7/8), Cosmetic (armor subClass 5 / IsCosmeticItem),
  Flasks (consumable subclass 3), Potions (subclasses 1/2), Food & Drink
  (subclass 5), and per-profession material routing for Alchemy/Cooking/JC.
- **Auto-migration of existing user `sortOrder` configs.** Players upgrading
  from 1.0.x will automatically receive the new categories — no manual reset
  required. Any custom user-only categories you'd added are preserved.
- **Item override system.** Built-in overrides for Midnight items that don't
  carry a proper class/subclass tag (e.g. Sunglass Vial → AlchemyMats,
  Thalassian Fillet → CookingMats). Extensible via Categories.lua.
- **Improved Warband detection** with multiple `IsBattlePayItem`/bind-type
  checks for items in WoW 12.0.5's expanded warband system.
- **Item upgrade markers.** Items show small ilvl / "upgrade" indicators
  when they're at-or-above your equipped item in that slot.

### Internal
- `GetProfessions` handling updated for 12.0's 5-position sparse return
  (profession ID 5 = Fishing slot reuse handled properly).

## [1.0.1] — 2026-05-17

### Bug fixes
- **B key now works in combat.** Added hooks for `ToggleBackpack`, `OpenBackpack`, `CloseBackpack` — previously only `ToggleAllBags` family was hooked, so the B keybind (which calls `ToggleBackpack`) bypassed VoidBags entirely.
- **Bag now closes instantly mid-combat** instead of staying open until combat ends. Switched to alpha-only visibility (no `Show()`/`Hide()` on the bag frame after creation) so combat-protected operations are never triggered on its SecureActionButton children.
- **Fixed "Cannot change equipment status while in combat" error** when hovering Blizzard's bag UI. The `HideBlizzBag` Show-hook was calling `ClearAllPoints` + `SetPoint` + `Hide` on ContainerFrames in combat — those are protected. Now combat-deferred to `PLAYER_REGEN_ENABLED`.
- **Cascade-collapsed hook firings.** Pressing B can trigger multiple Blizzard bag functions in one keystroke (`OpenAllBags` then `ToggleBackpack`, etc.). Added a 10ms intent-collapse so the addon doesn't flip the bag state twice in a single keypress.
- **Removed stale `f:Hide()` in `CreateBagFrame`** that prevented the bag from being visible after the alpha-only refactor.

### Internal
- Hoisted `pendingRefresh` declaration so all combat-handlers see the same upvalue.

## [1.0.0] — 2026-05-16

Initial CurseForge release.

### Features
- Single-window bag UI replacing Blizzard's stock backpack + bags 1-4 + reagent bag
- 17-lane auto-categorization with detection for Warband (bindType 7/8), Cosmetic (subClass 5 + IsCosmeticItem), and per-profession material routing (Alchemy/Cooking/JC)
- Companion bank panel with same categorization, full Warband bank support
- Merchant integration: `/vb sell`, `/vb repair`, auto-repair, guild-funds preference, auto-sell on merchant
- AH value awareness with configurable threshold (`/vb threshold <gold>`) — reagents below threshold count as "AH trash" for junk-sell
- Cross-character inventory: `/vb search <name>` finds items across all your characters' bags
- Protected items list to prevent accidental junk-sell of rare/sentimental items
- Fallback toggle to Blizzard stock bags (`/vb default`) for addon-conflict troubleshooting

### WoW 12.0.5 (Midnight) compatibility
- Reagent bag (slot 5) and Warband bank fully supported
- bindType 7/8 detection for Warband-bound items
- No taint in normal usage; cleanly falls back to Blizzard bags if needed
