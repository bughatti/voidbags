-- VoidTip (_shared, kept equal in every addon that carries it by tools/cmd/sync-libs): an item tooltip BESIDE a
-- window, never over it, with the game's "Equipped" comparisons stacked under it in the same column.
--
-- Why: anchored to the item button (ANCHOR_RIGHT), a window near the screen's edge left the comparisons no room, and
-- the game clamped each one onto the screen by itself: both "Equipped With" boxes on top of each other, unreadable
-- (VoidBags, the user 2026-11-27: "we have worked on this multiple times, why is it still an issue" - the fix of
-- 2026-11-12 lived only inside VoidAH's list rows). WoW Forever doesn't load Blizzard's TooltipComparisonManager: its
-- client places the comparisons itself, so the column is put back on the tooltip's OnUpdate; retail's Lua placement
-- is hooked too.
--
-- Use:  VoidTip.Place(button[, window])  instead of  GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
--       (then SetBagItem / SetHyperlink / ... and Show as before). No window given: the button's top frame. Not shown: plain ANCHOR_RIGHT.
--
-- Several addons carry this file: the newest copy (V) wins, and the hooks look the functions up on the global table,
-- so an older copy that loaded first runs the newest code.
local V = 1
if VoidTip and (VoidTip.v or 0) >= V then return end
VoidTip = VoidTip or {}
local T = VoidTip
T.v = V

local TIP_W = 330   -- a usual item tooltip's width (UI units): room needed beside the window

-- which side of the window: the left when what goes there (need, screen pixels: the tooltip, plus the comparisons'
-- column when they stand beside it) fits there, else the right when it fits there, else the side with more room.
-- (need was a fixed guess: a wide tooltip, or the comparisons' own column, could be clamped back over the window, Sol)
function T.Side(p, need)
    if not (p and p:IsShown()) then return nil end
    local l, r = p:GetLeft(), p:GetRight()
    if not (l and r) then return nil end
    local ps, us = p:GetEffectiveScale(), UIParent:GetEffectiveScale()
    local left = l * ps                                              -- in screen pixels
    local right = (UIParent:GetRight() or 0) * us - r * ps
    need = need or TIP_W * GameTooltip:GetEffectiveScale()
    if left >= need then return "left" end
    if right >= need then return "right" end
    return left >= right and "left" or "right"
end

-- raise: how far up (tooltip units) the column starts above the window's top, so a tall stack fits on the screen
function T.PlaceTip(side, p, raise)
    local tip = GameTooltip
    raise = raise or 0
    local pt, rel, rp = "TOPRIGHT", "TOPLEFT", -4
    if side == "right" then pt, rel, rp = "TOPLEFT", "TOPRIGHT", 4 end
    local a, r, b, x, y = tip:GetPoint(1)
    if tip:GetNumPoints() == 1 and a == pt and r == p and b == rel and x == rp and y and math.abs(y - raise) < 0.5 then
        return
    end
    tip:ClearAllPoints()
    tip:SetPoint(pt, p, rel, rp, raise)
end

-- the window a button sits in: its top frame under UIParent
function T.WindowOf(f)
    for _ = 1, 20 do
        local up = f and f:GetParent()
        if not up or up == UIParent then return f end
        f = up
    end
    return f
end

-- the hover we placed: this owner, beside this window. Only while the tooltip is still theirs (a flag left on the
-- button pulled a later, unrelated tooltip of the same button beside the old window, Sol)
function T.Place(owner, p)
    p = p or T.WindowOf(owner)
    local side = T.Side(p)
    T._owner, T._panel = nil, nil
    if not side then GameTooltip:SetOwner(owner, "ANCHOR_RIGHT") return end
    T._placing = true
    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    T._placing = nil
    T._owner, T._panel = owner, p
    T.PlaceTip(side, p)
end

local GAP = 20   -- room for the "Equipped" tab the game draws above each comparison

-- every comparison hangs off the item tooltip itself, never off the other comparison (a chain back = a "dependent
-- region" loop); x, y in the item tooltip's units
local function hang(t, tip, s, pt, rp, x, y)
    local k = s / t:GetEffectiveScale()
    local wantX, wantY = x * k, y * k
    local a, rel, b, ox, oy = t:GetPoint(1)
    if t:GetNumPoints() ~= 1 or a ~= pt or rel ~= tip or b ~= rp or not (ox and oy)
        or math.abs(ox - wantX) >= 0.5 or math.abs(oy - wantY) >= 0.5 then
        t:ClearAllPoints()
        t:SetPoint(pt, tip, rp, wantX, wantY)
    end
end

-- the comparisons under the tooltip; when the column is taller than the screen, in a column of their own beside it
-- (away from the window), and side by side when even that column is taller than the screen
function T.Stack()
    local tip = GameTooltip
    if not (T._owner and tip:IsShown() and tip:GetOwner() == T._owner) then return end
    local p = T._panel
    local list = tip.shoppingTooltips or { _G.ShoppingTooltip1, _G.ShoppingTooltip2 }
    local shown = {}
    for i = 1, 2 do
        local t = list[i]
        if t and t:IsShown() then shown[#shown + 1] = t end
    end
    -- heights and offsets in the item tooltip's units (s); widths in screen pixels
    local s, ps, us = tip:GetEffectiveScale(), p:GetEffectiveScale(), UIParent:GetEffectiveScale()
    local function h(t) return (t:GetHeight() or 0) * t:GetEffectiveScale() / s end
    local function wpx(t) return (t:GetWidth() or 0) * t:GetEffectiveScale() end
    local total = tip:GetHeight() or 0
    local colH, colW = 0, 0
    for _, t in ipairs(shown) do
        total = total + GAP + h(t)
        colH = colH + GAP + h(t)
        colW = math.max(colW, wpx(t))
    end
    local screenH = (UIParent:GetTop() or 0) * us / s
    local room = (p:GetTop() or 0) * ps / s                      -- the window's top to the screen's bottom
    local headroom = screenH - room
    local beside = total > screenH                               -- doesn't fit under: a column of their own
    local wide = beside and #shown > 1 and colH > screenH        -- even that column doesn't fit: side by side
    -- the side, from what really goes there: the tooltip's own width, plus the comparisons beside it
    -- (stacked under it: the wider of the tooltip and its comparisons, a wider comparison was clamped onto the window, Sol)
    local need = math.max(wpx(tip), colW) + 4 * s
    if beside then
        need = wpx(tip) + 4 * s
        if wide then for _, t in ipairs(shown) do need = need + wpx(t) + 4 * s end
        else need = need + colW + 4 * s end
    end
    local side = T.Side(p, need)
    if not side then return end
    local raise = beside and math.max(0, headroom) or math.max(0, math.min(total - room, headroom))
    T.PlaceTip(side, p, raise)
    if not beside then
        local pt, rp = "TOPRIGHT", "BOTTOMRIGHT"
        if side == "right" then pt, rp = "TOPLEFT", "BOTTOMLEFT" end
        local down = GAP
        for _, t in ipairs(shown) do
            hang(t, tip, s, pt, rp, 0, -down)
            down = down + h(t) + GAP
        end
        return
    end
    -- beside: away from the window (outward = left of a tooltip that is left of the window)
    local pt, rp, dir = "TOPRIGHT", "TOPLEFT", -1
    if side == "right" then pt, rp, dir = "TOPLEFT", "TOPRIGHT", 1 end
    local x, down = 4 * dir, GAP
    for _, t in ipairs(shown) do
        hang(t, tip, s, pt, rp, x, -down)
        if wide then x = x + dir * (wpx(t) / s + 4) else down = down + h(t) + GAP end
    end
end

if not GameTooltip.__voidTipHook then
    GameTooltip.__voidTipHook = true
    local function stack() VoidTip.Stack() end   -- (the newest copy's code, looked up each time)
    if TooltipComparisonManager and TooltipComparisonManager.AnchorShoppingTooltips then
        hooksecurefunc(TooltipComparisonManager, "AnchorShoppingTooltips", function(self)
            if self.tooltip == GameTooltip then stack() end
        end)
    end
    -- any other SetOwner ends our hover, even on the same button (Sol)
    hooksecurefunc(GameTooltip, "SetOwner", function() if not VoidTip._placing then VoidTip._owner = nil end end)
    GameTooltip:HookScript("OnUpdate", stack)
    for _, n in ipairs({ "ShoppingTooltip1", "ShoppingTooltip2" }) do
        if _G[n] then _G[n]:HookScript("OnShow", stack) end
    end
end
