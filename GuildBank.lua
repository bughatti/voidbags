----------------------------------------------------------------------
-- VoidBags: GuildBank — READ-ONLY guild vault browser + search + cache
----------------------------------------------------------------------
-- SAFETY RULES (do not break):
--  1. Item/money moves happen ONLY from explicit user clicks — NEVER from a
--     loop, timer, or event handler, and NEVER bridged into VoidBags' own
--     auto-sell / sort / move code. The server enforces all guild permissions
--     + per-tab withdrawal limits (these calls no-op without permission), and
--     items can't be destroyed — only moved/withdrawn, every move logged.
--  2. Withdrawing items to your bags (the one-click path) goes behind a
--     CONFIRMATION dialog so nothing leaves the guild bank by accident.
--
-- Item clicks:
--   Left-click  = cursor pickup/place (PickupGuildBankItem) — deposit by
--                 placing a held bag item, or manual within-bank moves.
--   Right-click = quick withdraw to bags (AutoStoreGuildBankItem), CONFIRMED.
--   Shift-click = link to chat (via HandleModifiedItemClick).
-- Money: Deposit/Withdraw buttons open Blizzard's own GUILDBANK_DEPOSIT /
-- GUILDBANK_WITHDRAW confirmation dialogs (StaticPopup_Show) — we never call
-- the money APIs directly.
----------------------------------------------------------------------
local _, VB = ...
local P = VB.palette

local C_CYAN = VB.C_CYAN or "|cff00c7ff"
local C_DIM  = VB.C_DIM  or "|cff808080"

-- Blizzard globals (fall back to known 12.0.7 values if a constant is nil)
local MAX_TABS      = _G.MAX_GUILDBANK_TABS or 8
local SLOTS_PER_TAB = 98   -- MAX_GUILDBANK_SLOTS_PER_TAB
-- Landscape grid: 14 columns wide (slots fill the top rows first). Slot index
-- is just storage order, so we lay the 98 slots out wide rather than Blizzard's
-- tall 7×14 — keeps the window a comfortable landscape shape.
local COLUMNS       = 14
local ROWS          = math.ceil(98 / 14)  -- 7 rows
local SLOT_SIZE     = 37
local SLOT_PAD      = 3

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local guildFrame
local guildIsOpen   = false
local currentTab    = 1
local searchText    = ""
local slotButtons   = {}   -- [index] = button (reused across tabs)
local tabButtons    = {}   -- [tab]   = item-tab switch button
local currentMode   = "bank"  -- "bank" | "log" | "moneylog" | "info" | "repairs"
local modeButtons   = {}   -- bottom mode tabs
local MONEY_LOG_TAB = (_G.MAX_GUILDBANK_TABS or 8) + 1  -- money log lives at MAX+1
local viewingCached = false   -- true = browsing the SavedVariables snapshot away from a bank

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function GuildKey()
    -- Cache key per guild (name is stable enough for personal use).
    local g = (GetGuildInfo and GetGuildInfo("player")) or nil
    return g
end

local function ItemNameFromLink(link)
    if not link then return nil end
    return link:match("%[(.-)%]")
end

-- ForEachViewableTab iterates the tabs to show. Live: the player's viewable
-- tabs. Cached: the tabs present in the SavedVariables snapshot.
local function ForEachViewableTab(fn)
    if viewingCached then
        local g = VoidBagsDB and VoidBagsDB.guildBank and VoidBagsDB.guildBank[GuildKey() or ""]
        if not g then return end
        local tabs = {}
        for tab in pairs(g) do tabs[#tabs+1] = tab end
        table.sort(tabs)
        for _, tab in ipairs(tabs) do fn(tab, g[tab].name or ("Tab " .. tab)) end
        return
    end
    local n = (GetNumGuildBankTabs and GetNumGuildBankTabs()) or 0
    for tab = 1, n do
        local name, icon, isViewable = GetGuildBankTabInfo(tab)
        if isViewable then fn(tab, name, icon) end
    end
end

----------------------------------------------------------------------
-- Cache (browse-anywhere): VoidBagsDB.guildBank[guild][tab] = {name, items, scannedAt}
----------------------------------------------------------------------
local function SnapshotTab(tab)
    local guild = GuildKey()
    if not guild or not VoidBagsDB then return end
    VoidBagsDB.guildBank = VoidBagsDB.guildBank or {}
    VoidBagsDB.guildBank[guild] = VoidBagsDB.guildBank[guild] or {}
    local tabName = GetGuildBankTabInfo(tab)
    local items = {}
    for slot = 1, SLOTS_PER_TAB do
        local texture, count = GetGuildBankItemInfo(tab, slot)
        if texture then
            local link = GetGuildBankItemLink(tab, slot)
            items[slot] = { link = link, count = count or 1, texture = texture }
        end
    end
    VoidBagsDB.guildBank[guild][tab] = { name = tabName, items = items, scannedAt = time() }
end

-- Cached snapshot accessors (browse-anywhere).
local function cacheForGuild()
    local guild = GuildKey()
    return guild and VoidBagsDB and VoidBagsDB.guildBank and VoidBagsDB.guildBank[guild] or nil
end

-- slotData returns texture, count, locked, quality, link for a tab/slot — from
-- the live API when at a bank, or the SavedVariables snapshot when browsing away.
local function slotData(tab, slot)
    if viewingCached then
        local g = cacheForGuild()
        local t = g and g[tab]
        local it = t and t.items and t.items[slot]
        if it then return it.texture, it.count, false, nil, it.link end
        return nil
    end
    local texture, count, locked, _, quality = GetGuildBankItemInfo(tab, slot)
    local link = texture and GetGuildBankItemLink(tab, slot) or nil
    return texture, count, locked, quality, link
end

----------------------------------------------------------------------
-- Withdraw confirmation (right-click quick-withdraw to bags)
----------------------------------------------------------------------
StaticPopupDialogs["VOIDBAGS_GUILD_WITHDRAW"] = {
    text = "Withdraw %s to your bags?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data)
        if data and AutoStoreGuildBankItem then
            AutoStoreGuildBankItem(data.tab, data.slot)  -- server enforces permission/limits
        end
    end,
    timeout = 0,
    hideOnEscape = 1,
    whileDead = 1,
}

-- Budget preset confirmation (GM-gated guild-rank gold-limit change).
----------------------------------------------------------------------
-- Slot button — display + item moves (deliberate clicks only)
----------------------------------------------------------------------
-- Slot styling mirrors Bank.lua's CreateBankButton: a colored quality border
-- (BACKGROUND), a dark cell bg (BORDER), and an inset icon (ARTWORK). Empty
-- slots stay visible as clean dark cells — the familiar guild-bank grid look.
local EMPTY_BORDER = { 0.18, 0.18, 0.20, 0.9 }

local function CreateSlotButton(parent, slotNum)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(SLOT_SIZE, SLOT_SIZE)
    btn.slotNum = slotNum   -- this cell always maps to guild-bank slot `slotNum`

    btn.qualBorder = btn:CreateTexture(nil, "BACKGROUND")
    btn.qualBorder:SetPoint("TOPLEFT", -1, 1)
    btn.qualBorder:SetPoint("BOTTOMRIGHT", 1, -1)
    btn.qualBorder:SetColorTexture(unpack(EMPTY_BORDER))

    btn.bg = btn:CreateTexture(nil, "BORDER")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(0.08, 0.08, 0.10, 0.92)

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", 1, -1)
    btn.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    btn.count = btn:CreateFontString(nil, "OVERLAY")
    VB:SetFont(btn.count, 11, "OUTLINE")
    btn.count:SetPoint("BOTTOMRIGHT", -2, 2)

    btn:SetScript("OnEnter", function(self)
        if not self.tab or not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetGuildBankItem, GameTooltip, self.tab, self.slotNum)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Click model (mirrors Blizzard's GuildBankItemButtonMixin, with a confirm
    -- on the one-click withdraw). ONLY runs from a real user click.
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, button)
        local tab = self.tab or currentTab
        -- shift-link / ctrl-compare / etc.
        if HandleModifiedItemClick and self.link and HandleModifiedItemClick(self.link) then
            return
        end
        if viewingCached then return end  -- away-from-bank snapshot: display + link only
        if button == "RightButton" then
            -- Quick withdraw to bags — confirmed. (No-op on an empty slot.)
            if self.link then
                StaticPopup_Show("VOIDBAGS_GUILD_WITHDRAW", self.link, nil, { tab = tab, slot = self.slotNum })
            end
        else
            -- Left-click: cursor pickup/place. Picking up just moves the item to
            -- your cursor (not a withdrawal yet); placing a held bag item here
            -- deposits it. Server enforces permissions.
            if PickupGuildBankItem then PickupGuildBankItem(tab, self.slotNum) end
        end
    end)

    -- Drag support (mirrors Blizzard's GuildBankItemButtonMixin): OnClick alone
    -- doesn't handle click-hold-drag — these do. OnDragStart picks the item up
    -- onto the cursor; OnReceiveDrag drops a held item onto this slot.
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self)
        if viewingCached then return end
        if PickupGuildBankItem then PickupGuildBankItem(self.tab or currentTab, self.slotNum) end
    end)
    btn:SetScript("OnReceiveDrag", function(self)
        if viewingCached then return end
        if PickupGuildBankItem then PickupGuildBankItem(self.tab or currentTab, self.slotNum) end
    end)
    return btn
end

-- Reset a slot to the empty-cell look (keeps tab + slotNum so it stays a valid
-- deposit target; only the item content is cleared).
local function ClearSlot(btn)
    btn.link = nil
    btn.icon:SetTexture(nil)
    btn.icon:SetAlpha(1)
    btn.count:SetText("")
    btn.qualBorder:SetColorTexture(unpack(EMPTY_BORDER))
end

----------------------------------------------------------------------
-- Render one tab's contents (read-only). Applies the search filter by
-- dimming non-matching items so the grid stays stable.
----------------------------------------------------------------------
local function RenderTab(tab)
    if not guildFrame then return end
    local grid = guildFrame.grid
    local filter = searchText ~= "" and searchText:lower() or nil

    for slot = 1, SLOTS_PER_TAB do
        local btn = slotButtons[slot]
        if not btn then
            btn = CreateSlotButton(grid, slot)
            -- Row-major, 14 wide: slot 1-14 = top row, 15-28 = second row, …
            local col = (slot - 1) % COLUMNS
            local row = math.floor((slot - 1) / COLUMNS)
            btn:SetPoint("TOPLEFT", grid, "TOPLEFT",
                col * (SLOT_SIZE + SLOT_PAD), -row * (SLOT_SIZE + SLOT_PAD))
            btn:Show()
            slotButtons[slot] = btn
        end
        btn.tab = tab   -- every cell is a valid deposit target for the current tab

        local texture, count, locked, quality, link = slotData(tab, slot)
        if texture then
            btn.link = link
            btn.icon:SetTexture(texture)
            btn.icon:SetDesaturated(locked and true or false)
            btn.count:SetText((count and count > 1) and count or "")

            -- Like Blizzard: only uncommon+ items get a quality-colored edge.
            -- Common/poor items keep the plain neutral cell (no cyan-on-everything).
            local c = quality and quality > 1 and BAG_ITEM_QUALITY_COLORS and BAG_ITEM_QUALITY_COLORS[quality]
            if c then
                btn.qualBorder:SetColorTexture(c.r, c.g, c.b, 0.9)
            else
                btn.qualBorder:SetColorTexture(unpack(EMPTY_BORDER))
            end

            -- Search dim: matching items full alpha, others faded.
            local a = 1
            if filter then
                local name = ItemNameFromLink(link)
                a = (name and name:lower():find(filter, 1, true)) and 1 or 0.2
            end
            btn.icon:SetAlpha(a)
            btn.count:SetAlpha(a)
        else
            ClearSlot(btn)   -- empty cell stays visible
        end
    end
    if not viewingCached then SnapshotTab(tab) end  -- don't overwrite cache with nothing
end

----------------------------------------------------------------------
-- Tab switching
----------------------------------------------------------------------
local function SwitchTab(tab)
    currentTab = tab
    if not viewingCached then
        if SetCurrentGuildBankTab then pcall(SetCurrentGuildBankTab, tab) end
        if QueryGuildBankTab then pcall(QueryGuildBankTab, tab) end  -- async -> GUILDBANKBAGSLOTS_CHANGED
    end
    RenderTab(tab)  -- render immediately from whatever is loaded; refresh on the event
    -- Update tab button highlight
    for t, b in pairs(tabButtons) do
        b.txt:SetText((t == tab and C_CYAN or C_DIM) .. (b.tabName or ("Tab " .. t)) .. "|r")
    end
end

local function BuildTabButtons()
    for _, b in pairs(tabButtons) do b:Hide() end
    local x = 14
    ForEachViewableTab(function(tab, name)
        local b = tabButtons[tab]
        if not b then
            b = CreateFrame("Button", nil, guildFrame, "BackdropTemplate")
            b:SetHeight(18)
            VB:CreateBackdrop(b, "section")
            b.txt = b:CreateFontString(nil, "OVERLAY")
            VB:SetFont(b.txt, 10, "")
            b.txt:SetPoint("CENTER")
            b:SetScript("OnClick", function(self) SwitchTab(self.tab) end)
            tabButtons[tab] = b
        end
        b.tab, b.tabName = tab, (name ~= "" and name) or ("Tab " .. tab)
        b.txt:SetText(C_DIM .. b.tabName .. "|r")
        -- Auto-width to the label so tabs aren't cramped/overlapping.
        b:SetWidth(math.max(40, b.txt:GetStringWidth() + 16))
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", guildFrame, "TOPLEFT", x, -30)
        b:Show()
        x = x + b:GetWidth() + 4
    end)
end

----------------------------------------------------------------------
-- Log / Money Log / Info views (all READ-ONLY queries)
----------------------------------------------------------------------
local function fmtTime(year, month, day, hour)
    if RecentTimeDate and GUILD_BANK_LOG_TIME then
        return GUILD_BANK_LOG_TIME:format(RecentTimeDate(year, month, day, hour))
    end
    return ""
end

-- Item transaction log for the current tab (who deposited/withdrew/moved what).
local function RenderItemLog()
    local lf = guildFrame and guildFrame.logFrame
    if not lf then return end
    lf:Clear()
    local tab = currentTab
    local n = (GetNumGuildBankTransactions and GetNumGuildBankTransactions(tab)) or 0
    if n == 0 then
        lf:AddMessage(C_DIM .. "No item transactions recorded for this tab.|r")
        return
    end
    for i = 1, n do
        local ttype, name, itemLink, count, tab1, tab2, year, month, day, hour = GetGuildBankTransaction(tab, i)
        name = NORMAL_FONT_COLOR_CODE .. (name or UNKNOWN) .. FONT_COLOR_CODE_CLOSE
        local msg
        if ttype == "deposit" and GUILDBANK_DEPOSIT_FORMAT then
            msg = format(GUILDBANK_DEPOSIT_FORMAT, name, itemLink or "?")
            if count and count > 1 and GUILDBANK_LOG_QUANTITY then msg = msg .. format(GUILDBANK_LOG_QUANTITY, count) end
        elseif ttype == "withdraw" and GUILDBANK_WITHDRAW_FORMAT then
            msg = format(GUILDBANK_WITHDRAW_FORMAT, name, itemLink or "?")
            if count and count > 1 and GUILDBANK_LOG_QUANTITY then msg = msg .. format(GUILDBANK_LOG_QUANTITY, count) end
        elseif ttype == "move" and GUILDBANK_MOVE_FORMAT then
            msg = format(GUILDBANK_MOVE_FORMAT, name, itemLink or "?", count or 1,
                GetGuildBankTabInfo(tab1), GetGuildBankTabInfo(tab2))
        end
        if msg then lf:AddMessage(msg .. fmtTime(year, month, day, hour)) end
    end
end

-- Money log: deposits / withdrawals / REPAIRS / etc.
local function RenderMoneyLog()
    local lf = guildFrame and guildFrame.logFrame
    if not lf then return end
    lf:Clear()
    local n = (GetNumGuildBankMoneyTransactions and GetNumGuildBankMoneyTransactions()) or 0
    if n == 0 then
        lf:AddMessage(C_DIM .. "No money transactions recorded.|r")
        return
    end
    for i = 1, n do
        local ttype, name, amount, year, month, day, hour = GetGuildBankMoneyTransaction(i)
        amount = amount or 0
        name = NORMAL_FONT_COLOR_CODE .. (name or UNKNOWN) .. FONT_COLOR_CODE_CLOSE
        local money = GetDenominationsFromCopper and GetDenominationsFromCopper(amount) or tostring(amount)
        local fmtMap = {
            deposit       = GUILDBANK_DEPOSIT_MONEY_FORMAT,
            withdraw      = GUILDBANK_WITHDRAW_MONEY_FORMAT,
            repair        = GUILDBANK_REPAIR_MONEY_FORMAT,
            withdrawForTab= GUILDBANK_WITHDRAWFORTAB_MONEY_FORMAT,
        }
        local f = fmtMap[ttype]
        local msg = f and f:format(name, money)
        if msg then lf:AddMessage(msg .. fmtTime(year, month, day, hour)) end
    end
end

-- Info: per-tab names, view/deposit permissions, and remaining withdrawals.
local function RenderInfo()
    local it = guildFrame and guildFrame.infoText
    if not it then return end
    local lines = {}
    local guild = GuildKey()
    lines[#lines+1] = C_CYAN .. (guild or "Guild") .. "|r"
    lines[#lines+1] = " "
    local total = (GetNumGuildBankTabs and GetNumGuildBankTabs()) or 0
    for tab = 1, total do
        local name, _, isViewable, canDeposit, numWithdrawals, remaining = GetGuildBankTabInfo(tab)
        name = (name ~= "" and name) or ("Tab " .. tab)
        if isViewable then
            local perms = {}
            perms[#perms+1] = canDeposit and "deposit" or "no deposit"
            if numWithdrawals and numWithdrawals >= 0 then
                perms[#perms+1] = (remaining or numWithdrawals) .. "/" .. numWithdrawals .. " withdrawals left"
            else
                perms[#perms+1] = "withdraw"
            end
            lines[#lines+1] = C_CYAN .. name .. "|r  " .. C_DIM .. "(" .. table.concat(perms, ", ") .. ")|r"
            local txt = GetGuildBankText and GetGuildBankText(tab)
            if txt and txt ~= "" then lines[#lines+1] = "   " .. txt end
        else
            lines[#lines+1] = C_DIM .. name .. "  (officer-only — not viewable)|r"
        end
    end
    it:SetText(table.concat(lines, "\n"))
end

-- Repair-spend tracker: aggregate guild-bank money-log "repair" transactions by
-- player for the last 7 days. The money-log time fields are elapsed-since values.
local function elapsedDays(year, month, day)
    return (year or 0) * 365 + (month or 0) * 30 + (day or 0)
end

local function RenderRepairs()
    local it = guildFrame and guildFrame.repairsText
    if not it then return end
    local byPlayer, order, total = {}, {}, 0
    local n = (GetNumGuildBankMoneyTransactions and GetNumGuildBankMoneyTransactions()) or 0
    for i = 1, n do
        local ttype, name, amount, year, month, day = GetGuildBankMoneyTransaction(i)
        if ttype == "repair" and elapsedDays(year, month, day) < 7 then
            name = name or UNKNOWN
            if not byPlayer[name] then byPlayer[name] = 0; order[#order+1] = name end
            byPlayer[name] = byPlayer[name] + (amount or 0)
            total = total + (amount or 0)
        end
    end
    table.sort(order, function(a, b) return byPlayer[a] > byPlayer[b] end)

    local coin = function(c) return GetCoinTextureString and GetCoinTextureString(c) or tostring(c) end
    local lines = {}
    lines[#lines+1] = C_CYAN .. "Repairs — last 7 days|r"
    lines[#lines+1] = " "
    if #order == 0 then
        lines[#lines+1] = C_DIM .. "No guild-funded repairs in the recent money log.|r"
    else
        for _, name in ipairs(order) do
            lines[#lines+1] = string.format("%s%-20s|r  %s", NORMAL_FONT_COLOR_CODE, name, coin(byPlayer[name]))
        end
        lines[#lines+1] = " "
        lines[#lines+1] = C_CYAN .. "Total: |r" .. coin(total)
        lines[#lines+1] = C_DIM .. "(limited to what the guild bank money log retains)|r"
    end
    it:SetText(table.concat(lines, "\n"))
end

----------------------------------------------------------------------
-- Mode switching (Guild Bank | Log | Money Log | Info | Repairs)
----------------------------------------------------------------------
local function ShowMode(mode)
    currentMode = mode
    local f = guildFrame
    if not f then return end
    local bankMode = (mode == "bank")

    -- Bank-mode widgets (item tabs + search + grid)
    f.search:SetShown(bankMode)
    f.grid:SetShown(bankMode)
    for _, b in pairs(tabButtons) do b:SetShown(bankMode and b.tab ~= nil) end

    -- Log frame (shared by log + moneylog); Info frame; Repairs frame
    f.logFrame:SetShown(mode == "log" or mode == "moneylog")
    f.infoScroll:SetShown(mode == "info")
    f.repairsScroll:SetShown(mode == "repairs")

    -- Budget panel: shown to officers + GM in Repairs mode. Only the GM can
    -- actually edit (the server gates rank/gold-limit writes on IsGuildLeader,
    -- per Blizzard's own CommunitiesFrame) — officers get a read-only view.
    local isGM = IsGuildLeader and IsGuildLeader() or false
    local isOfficer = isGM or (C_GuildInfo and C_GuildInfo.IsGuildOfficer and C_GuildInfo.IsGuildOfficer()) or false
    local showBudget = (mode == "repairs") and isOfficer
    f.budgetPanel:SetShown(showBudget and true or false)
    if mode == "repairs" then
        f.repairsScroll:ClearAllPoints()
        f.repairsScroll:SetPoint("TOPLEFT", 12, -(28 + 6))
        f.repairsScroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, f.BOTTOM + (showBudget and 104 or 4))
        if showBudget then
            f.budgetPanel.SetEditable(isGM)
            f.budgetPanel.Refresh()
        end
    end

    -- Highlight the active mode tab
    for m, b in pairs(modeButtons) do
        b.txt:SetText((m == mode and C_CYAN or C_DIM) .. b.label .. "|r")
    end

    if mode == "log" then
        if QueryGuildBankLog then pcall(QueryGuildBankLog, currentTab) end
        RenderItemLog()
    elseif mode == "moneylog" then
        if QueryGuildBankLog then pcall(QueryGuildBankLog, MONEY_LOG_TAB) end
        RenderMoneyLog()
    elseif mode == "info" then
        RenderInfo()
    elseif mode == "repairs" then
        -- repairs come from the money log; query it then aggregate.
        if QueryGuildBankLog then pcall(QueryGuildBankLog, MONEY_LOG_TAB) end
        RenderRepairs()
    end
end

local function BuildModeTabs()
    local defs = {
        { mode = "bank",     label = "Guild Bank" },
        { mode = "log",      label = "Log" },
        { mode = "moneylog", label = "Money Log" },
        { mode = "repairs",  label = "Repairs" },
        { mode = "info",     label = "Info" },
    }
    local x = 14
    for _, d in ipairs(defs) do
        local b = modeButtons[d.mode]
        if not b then
            b = CreateFrame("Button", nil, guildFrame, "BackdropTemplate")
            b:SetHeight(20)
            VB:CreateBackdrop(b, "section")
            b.txt = b:CreateFontString(nil, "OVERLAY")
            VB:SetFont(b.txt, 10, "")
            b.txt:SetPoint("CENTER")
            b.mode, b.label = d.mode, d.label
            b:SetScript("OnClick", function(self) ShowMode(self.mode) end)
            modeButtons[d.mode] = b
        end
        b.txt:SetText(C_DIM .. d.label .. "|r")
        b:SetWidth(math.max(50, b.txt:GetStringWidth() + 18))
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", guildFrame, "BOTTOMLEFT", x, 6)
        b:Show()
        x = x + b:GetWidth() + 4
    end
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------
local function CreateGuildFrame()
    local gridW = COLUMNS * (SLOT_SIZE + SLOT_PAD) - SLOT_PAD
    local gridH = ROWS * (SLOT_SIZE + SLOT_PAD) - SLOT_PAD
    -- Vertical layout: title(28) + item-tabs(22) + search(26) + grid + a bottom
    -- money bar(26) + mode-tabs(30). Log/Info views reuse the grid's region.
    local TOP = 28 + 22 + 26
    local MONEYBAR = 26
    local BOTTOM = 30 + MONEYBAR

    local f = CreateFrame("Frame", "VoidBagsGuildFrame", UIParent, "BackdropTemplate")
    f:SetSize(gridW + 16, TOP + gridH + BOTTOM)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(100)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    VB:CreateBackdrop(f, "transparent")

    if VoidBagsDB and VoidBagsDB.config and VoidBagsDB.config.guildPosition then
        local p = VoidBagsDB.config.guildPosition
        f:ClearAllPoints()
        f:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
    end

    -- Title bar (drag)
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetHeight(28)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local point, _, relPoint, x, y = f:GetPoint(1)
        if VoidBagsDB and VoidBagsDB.config then
            VoidBagsDB.config.guildPosition = { point = point, relPoint = relPoint, x = x, y = y }
        end
    end)

    local title = titleBar:CreateFontString(nil, "OVERLAY")
    VB:SetFont(title, 13, "OUTLINE")
    title:SetPoint("LEFT", 8, 0)
    title:SetText(C_CYAN .. "VoidBags — Guild Bank|r")
    f.title = title

    local close = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", 0, 0)
    close:SetScript("OnClick", function() f:Hide() end)

    -- Search box (below the tab row)
    local search = CreateFrame("EditBox", "VoidBagsGuildSearch", f, "SearchBoxTemplate")
    search:SetSize(gridW - 8, 20)
    search:SetPoint("TOPLEFT", 14, -(28 + 22))
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function(self)
        -- Call the template handler so the grey "Search" placeholder hides while
        -- you type (otherwise white text renders on top of it = unreadable).
        if SearchBoxTemplate_OnTextChanged then SearchBoxTemplate_OnTextChanged(self) end
        searchText = self:GetText() or ""
        RenderTab(currentTab)
    end)
    f.search = search

    -- Item grid container
    local grid = CreateFrame("Frame", nil, f)
    grid:SetSize(gridW, gridH)
    grid:SetPoint("TOPLEFT", 8, -TOP)
    f.grid = grid

    -- Log view (shared by Log + Money Log): a scrolling, hyperlink-aware text
    -- frame spanning the content region. READ-only display.
    local logFrame = CreateFrame("ScrollingMessageFrame", nil, f)
    logFrame:SetPoint("TOPLEFT", 12, -(28 + 6))
    logFrame:SetPoint("BOTTOMRIGHT", -12, BOTTOM + 4)
    logFrame:SetFontObject(GameFontHighlightSmall or "GameFontHighlightSmall")
    logFrame:SetJustifyH("LEFT")
    logFrame:SetFading(false)
    logFrame:SetMaxLines(500)
    logFrame:SetHyperlinksEnabled(true)
    logFrame:SetScript("OnHyperlinkClick", function(_, link, text, button)
        SetItemRef(link, text, button)
    end)
    logFrame:SetScript("OnHyperlinkEnter", function(self, link)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        pcall(GameTooltip.SetHyperlink, GameTooltip, link)
        GameTooltip:Show()
    end)
    logFrame:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
    logFrame:EnableMouseWheel(true)
    logFrame:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then self:ScrollUp() else self:ScrollDown() end
    end)
    logFrame:Hide()
    f.logFrame = logFrame

    -- Info view: a scroll frame holding a left-justified text block.
    local infoScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    infoScroll:SetPoint("TOPLEFT", 12, -(28 + 6))
    infoScroll:SetPoint("BOTTOMRIGHT", -28, BOTTOM + 4)
    local infoContent = CreateFrame("Frame", nil, infoScroll)
    infoContent:SetSize(gridW - 40, 10)
    infoScroll:SetScrollChild(infoContent)
    local infoText = infoContent:CreateFontString(nil, "OVERLAY")
    VB:SetFont(infoText, 11, "")
    infoText:SetPoint("TOPLEFT", 0, 0)
    infoText:SetWidth(gridW - 44)
    infoText:SetJustifyH("LEFT")
    infoText:SetSpacing(3)
    f.infoScroll = infoScroll
    f.infoText = infoText

    -- Repairs view: per-player weekly repair-spend summary.
    local repairsScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    repairsScroll:SetPoint("TOPLEFT", 12, -(28 + 6))
    repairsScroll:SetPoint("BOTTOMRIGHT", -28, BOTTOM + 4)
    local repairsContent = CreateFrame("Frame", nil, repairsScroll)
    repairsContent:SetSize(gridW - 40, 10)
    repairsScroll:SetScrollChild(repairsContent)
    local repairsText = repairsContent:CreateFontString(nil, "OVERLAY")
    VB:SetFont(repairsText, 11, "")
    repairsText:SetPoint("TOPLEFT", 0, 0)
    repairsText:SetWidth(gridW - 44)
    repairsText:SetJustifyH("LEFT")
    repairsText:SetSpacing(3)
    repairsScroll:Hide()
    f.repairsScroll = repairsScroll
    f.repairsText = repairsText

    ------------------------------------------------------------------
    -- Budget presets (GM only): one-click Raid Week / Off Week daily
    -- gold limit for a chosen rank. Sensitive guild-config write — gated
    -- on IsGuildLeader + a confirmation dialog.
    ------------------------------------------------------------------
    VoidBagsDB.config = VoidBagsDB.config or {}
    VoidBagsDB.config.guildRepair = VoidBagsDB.config.guildRepair or { rank = 2, raid = 1000, off = 200 }

    local bp = CreateFrame("Frame", nil, f, "BackdropTemplate")
    bp:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, BOTTOM + 4)
    bp:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, BOTTOM + 4)
    bp:SetHeight(96)
    VB:CreateBackdrop(bp, "section")

    local bpHdr = bp:CreateFontString(nil, "OVERLAY")
    VB:SetFont(bpHdr, 11, "OUTLINE")
    bpHdr:SetPoint("TOPLEFT", 8, -6)
    bpHdr:SetTextColor(0, 0.78, 1)
    bpHdr:SetText("Repair budget (officer)")

    -- Rank cycle button (shows the chosen rank + its current daily limit).
    local rankBtn = CreateFrame("Button", nil, bp, "BackdropTemplate")
    rankBtn:SetSize(150, 18)
    rankBtn:SetPoint("TOPLEFT", 8, -26)
    VB:CreateBackdrop(rankBtn, "section")
    local rankTxt = rankBtn:CreateFontString(nil, "OVERLAY")
    VB:SetFont(rankTxt, 10, "")
    rankTxt:SetPoint("CENTER")
    bp.rankTxt = rankTxt

    local function rankCount() return (GuildControlGetNumRanks and GuildControlGetNumRanks()) or 0 end
    local RefreshBudget   -- fwd
    rankBtn:SetScript("OnClick", function()
        local n = rankCount()
        if n <= 1 then return end
        local r = VoidBagsDB.config.guildRepair.rank + 1
        if r > n then r = 2 end   -- skip rank 1 (guild master)
        if r < 2 then r = 2 end
        VoidBagsDB.config.guildRepair.rank = r
        RefreshBudget()
    end)

    -- Raid / Off amount inputs.
    local function makeAmt(label, key, y)
        local l = bp:CreateFontString(nil, "OVERLAY")
        VB:SetFont(l, 10, "")
        l:SetPoint("TOPLEFT", 8, y)
        l:SetText(label)
        local box = CreateFrame("EditBox", nil, bp, "InputBoxTemplate")
        box:SetSize(54, 16)
        box:SetPoint("LEFT", l, "RIGHT", 8, 0)
        box:SetAutoFocus(false)
        box:SetNumeric(true)
        box:SetText(tostring(VoidBagsDB.config.guildRepair[key] or 0))
        box:SetScript("OnTextChanged", function(self)
            VoidBagsDB.config.guildRepair[key] = tonumber(self:GetText()) or 0
        end)
        local g = bp:CreateFontString(nil, "OVERLAY")
        VB:SetFont(g, 10, "")
        g:SetPoint("LEFT", box, "RIGHT", 2, 0)
        g:SetText("g")
        return box
    end
    local raidBox = makeAmt("Raid:", "raid", -48)
    local offBox  = makeAmt("Off:",  "off",  -70)

    -- IMPORTANT: this panel is a LOCAL budget *target*, not an enforcer. The
    -- actual rank gold limit can ONLY be changed in Blizzard's Guild Control --
    -- GuildControlSetRank / SetGuildBankWithdrawGoldLimit are protected and fire
    -- a "blocked from action" popup if an addon calls them. So we never call
    -- them; the GM sets the real limit there, and VoidBags tracks repair spend
    -- against this target in the list above.
    local hint = bp:CreateFontString(nil, "OVERLAY")
    VB:SetFont(hint, 9, "")
    hint:SetPoint("TOPLEFT", 175, -46)
    hint:SetWidth(150)
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(0.6, 0.6, 0.6)
    hint:SetText("Set the live limit in Guild Control. The spend list above is measured against this target.")

    RefreshBudget = function()
        local cfg = VoidBagsDB.config.guildRepair
        local name = (GuildControlGetRankName and GuildControlGetRankName(cfg.rank)) or ("rank " .. cfg.rank)
        rankTxt:SetText(C_CYAN .. name .. "|r  " .. C_DIM ..
            "(raid " .. (cfg.raid or 0) .. "g / off " .. (cfg.off or 0) .. "g)|r")
    end
    bp.Refresh = RefreshBudget

    -- The target is local SavedVariables config (no protected write), so anyone
    -- who can see the panel (officers + GM) may edit it. Kept as a hook so the
    -- ShowMode call site stays valid.
    function bp.SetEditable()
        raidBox:Enable()
        offBox:Enable()
        bpHdr:SetText("Repair budget target")
    end

    bp:Hide()
    f.budgetPanel = bp
    f.BOTTOM = BOTTOM

    ------------------------------------------------------------------
    -- Money bar (just above the mode tabs): total + deposit/withdraw.
    -- Deposit/Withdraw open Blizzard's own confirmation dialogs.
    ------------------------------------------------------------------
    local moneyText = f:CreateFontString(nil, "OVERLAY")
    VB:SetFont(moneyText, 11, "")
    moneyText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 36)
    moneyText:SetJustifyH("LEFT")
    f.moneyText = moneyText

    local withdrawBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    withdrawBtn:SetSize(74, 20)
    withdrawBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 34)
    VB:CreateBackdrop(withdrawBtn, "section")
    local wT = withdrawBtn:CreateFontString(nil, "OVERLAY")
    VB:SetFont(wT, 10, "")
    wT:SetPoint("CENTER")
    wT:SetText("Withdraw")
    withdrawBtn.txt = wT
    withdrawBtn:SetScript("OnClick", function()
        if CanWithdrawGuildBankMoney and not CanWithdrawGuildBankMoney() then return end
        StaticPopup_Show("GUILDBANK_WITHDRAW")  -- Blizzard dialog: money input + Accept
    end)
    f.withdrawBtn = withdrawBtn

    local depositBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    depositBtn:SetSize(74, 20)
    depositBtn:SetPoint("RIGHT", withdrawBtn, "LEFT", -6, 0)
    VB:CreateBackdrop(depositBtn, "section")
    local dT = depositBtn:CreateFontString(nil, "OVERLAY")
    VB:SetFont(dT, 10, "")
    dT:SetPoint("CENTER")
    dT:SetText("Deposit")
    depositBtn:SetScript("OnClick", function()
        StaticPopup_Show("GUILDBANK_DEPOSIT")   -- Blizzard dialog: money input + Accept
    end)
    f.depositBtn = depositBtn

    guildFrame = f
    return f
end

-- UpdateMoney refreshes the total + the withdraw button's enabled state.
local function UpdateMoney()
    local f = guildFrame
    if not f or not f.moneyText then return end
    local total = (GetGuildBankMoney and GetGuildBankMoney()) or 0
    local coins = GetCoinTextureString and GetCoinTextureString(total) or tostring(total)
    local s = "Guild Bank: " .. coins
    -- Show today's remaining personal withdraw allowance (>=0; -1 = unlimited).
    local remain = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney()
    if remain and remain >= 0 then
        s = s .. "    " .. C_DIM .. "(you can withdraw " ..
            (GetCoinTextureString and GetCoinTextureString(remain) or remain) .. " today)|r"
    end
    f.moneyText:SetText(s)

    local canWithdraw = (CanWithdrawGuildBankMoney == nil) or CanWithdrawGuildBankMoney()
    if canWithdraw then
        f.withdrawBtn:Enable(); f.withdrawBtn.txt:SetTextColor(1, 1, 1)
    else
        f.withdrawBtn:Disable(); f.withdrawBtn.txt:SetTextColor(0.4, 0.4, 0.4)
    end
end

----------------------------------------------------------------------
-- Open / close
----------------------------------------------------------------------
local atBanker = false   -- true only while standing at a live guild banker

-- applyChrome shows/hides the live-only controls (money bar + mode tabs +
-- budget) — hidden when browsing the cached snapshot away from a bank.
local function applyChrome(cached)
    local f = guildFrame
    if not f then return end
    f.moneyText:SetShown(not cached)
    f.depositBtn:SetShown(not cached)
    f.withdrawBtn:SetShown(not cached)
    for _, b in pairs(modeButtons) do b:SetShown(not cached) end
    if cached then
        f.budgetPanel:Hide()
        local g = cacheForGuild()
        local when = ""
        if g then
            local newest = 0
            for _, t in pairs(g) do if (t.scannedAt or 0) > newest then newest = t.scannedAt end end
            if newest > 0 then when = "  " .. C_DIM .. "(cached " .. SecondsToTime(time() - newest) .. " ago)|r" end
        end
        f.title:SetText(C_CYAN .. "VoidBags — Guild Bank|r" .. when)
    else
        f.title:SetText(C_CYAN .. "VoidBags — Guild Bank|r")
    end
end

-- Suppress Blizzard's default guild bank window. We show our own UI, but must
-- NOT hide Blizzard's GuildBankFrame: GuildBankFrameMixin:OnHide() calls
-- CloseGuildBankFrame(), which ends the banker session every one of our data
-- reads depends on (and fires the interaction-HIDE event, slamming our own
-- window shut). The frame manager opens it with a plain ShowUIPanel. So instead
-- of hiding it, we keep it *shown* (session alive) but parked fully off-screen
-- and click-through, and drop it from the UIPanel layout so nothing repositions
-- it back.
local blizzSuppressed = false
local function SuppressBlizzGuildBank()
    if blizzSuppressed or not GuildBankFrame then return end
    blizzSuppressed = true
    if UIPanelWindows and UIPanelWindows["GuildBankFrame"] then
        UIPanelWindows["GuildBankFrame"] = nil
    end
    local function park(self)
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", 500, 0)  -- entirely off the right edge
        self:EnableMouse(false)
    end
    GuildBankFrame:HookScript("OnShow", park)
    if GuildBankFrame:IsShown() then park(GuildBankFrame) end
end

local function OnGuildBankOpened()
    if not guildFrame then CreateGuildFrame() end
    SuppressBlizzGuildBank()   -- park Blizzard's frame off-screen (if already loaded)
    atBanker = true
    viewingCached = false
    guildIsOpen = true
    guildFrame:Show()
    applyChrome(false)
    BuildModeTabs()
    BuildTabButtons()
    -- Default to the currently-selected item tab (or 1), in Guild Bank mode.
    local cur = (GetCurrentGuildBankTab and GetCurrentGuildBankTab()) or 1
    if cur < 1 then cur = 1 end
    SwitchTab(cur)
    ShowMode("bank")
    UpdateMoney()
end

local function OnGuildBankClosed()
    atBanker = false
    guildIsOpen = false
    if guildFrame and not viewingCached then guildFrame:Hide() end
end

-- Browse-anywhere: open the cached snapshot when not at a bank. Display-only
-- (item moves + money + budget are disabled; mode tabs hidden).
local function OpenCached()
    if not cacheForGuild() then
        print(VB.C_CYAN .. "[VoidBags]|r No cached guild bank yet — open your guild bank once to snapshot it.")
        return
    end
    if not guildFrame then CreateGuildFrame() end
    viewingCached = true
    guildIsOpen = true
    guildFrame:Show()
    applyChrome(true)
    BuildTabButtons()
    local g = cacheForGuild()
    local firstTab
    for t in pairs(g) do if not firstTab or t < firstTab then firstTab = t end end
    ShowMode("bank")
    SwitchTab(firstTab or 1)
end

-- Public toggle (wired to a bag-window button). At a bank → live; away → cached.
function VB:ToggleGuildBank()
    if guildFrame and guildFrame:IsShown() then
        guildFrame:Hide()
        return
    end
    if atBanker then OnGuildBankOpened() else OpenCached() end
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
-- NOTE: GUILDBANKFRAME_OPENED/_CLOSED are Classic-only and never fire on
-- Midnight retail. Modern retail signals a guild banker via the unified
-- PLAYER_INTERACTION_MANAGER_FRAME_SHOW/HIDE events, filtered on
-- Enum.PlayerInteractionType.GuildBanker (=10). Data refresh still comes
-- from GUILDBANKBAGSLOTS_CHANGED / GUILDBANK_UPDATE_TABS (those are live).
local GUILD_BANKER = (Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker) or 10

local ef = CreateFrame("Frame")
ef:RegisterEvent("ADDON_LOADED")
ef:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
ef:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
ef:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")
ef:RegisterEvent("GUILDBANK_UPDATE_TABS")
ef:RegisterEvent("GUILDBANKLOG_UPDATE")
ef:RegisterEvent("GUILDBANK_UPDATE_MONEY")
ef:RegisterEvent("GUILDBANK_UPDATE_WITHDRAWMONEY")
ef:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        -- Blizzard_GuildBankUI is load-on-demand — hook it the instant it loads,
        -- before its first ShowUIPanel, so our park runs on the very first open.
        if arg1 == "Blizzard_GuildBankUI" then SuppressBlizzGuildBank() end
        return
    end
    if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        if arg1 == GUILD_BANKER then OnGuildBankOpened() end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        if arg1 == GUILD_BANKER then OnGuildBankClosed() end
    elseif guildIsOpen then
        if event == "GUILDBANK_UPDATE_MONEY" or event == "GUILDBANK_UPDATE_WITHDRAWMONEY" then
            UpdateMoney()
        elseif event == "GUILDBANKLOG_UPDATE" then
            -- Async log data arrived — refresh whichever log view is showing.
            if currentMode == "log" then RenderItemLog()
            elseif currentMode == "moneylog" then RenderMoneyLog()
            elseif currentMode == "repairs" then RenderRepairs() end
        else
            if event == "GUILDBANK_UPDATE_TABS" then BuildTabButtons() end
            if currentMode == "bank" then RenderTab(currentTab) end
        end
    end
end)
