----------------------------------------------------------------------
-- VoidBags — Income: what your play earns, per hour
--
-- The user, 2026-11-23: "my guildie has an add-on that tracks gold per hour ... is that something we could tie into
-- void bags? And since we actually have all the auction house ... if somebody gets a drop, it should be able to add
-- that in". VoidGather's Earnings box counts gathering only; this counts everything you earn:
--   * items you loot (mobs, gathering, fishing, chests, bags and boxes you open, rolls you win)
--   * coin you loot (and your share of a group's), quest gold and quest reward items
-- and nothing you buy, craft, get by mail or trade for (that isn't income; selling your loot later isn't either: it
-- was counted when you looted it).
--
-- Each item gets two values:
--   cash  = what a vendor pays (money you can always have)
--   worth = what you'd really get: with VoidAH, what the item has been SEEN SELLING for in your scan pairs (never
--           above today's cheapest listing), after the AH's 5% cut; the vendor's price when that's more. An item
--           that's listed but hasn't sold in a day of watching is "slow": worth only the vendor price. Without sales
--           data the cheapest listing is used ("listed": not proven to sell). Soulbound, quest and grey items: vendor.
-- Time = active time: the gaps between things you earn, fights and gathers; a gap over 5 minutes (flying, AFK, the
-- bank) isn't counted. A session carries over a /reload and ends 30 minutes after you last earned or fought.
-- Everything is this character's own (VoidBagsCharDB.income): gold per hour depends on the character's level.
----------------------------------------------------------------------
local ADDON, VB = ...
local I = {}
VB.Income = I

local GAP        = 300    -- seconds between activity that still count as playing
local FIRST      = 30     -- seconds credited for the first activity after a gap
local RESUME     = 1800   -- a session idle this long is filed under recent sessions
local HISTORY    = 50     -- finished sessions kept
local MIN_ACTIVE = 60     -- no hourly rate before a minute
local CUT        = 0.95   -- the AH's cut
local WINDOW     = 2      -- seconds after a loot window closes / a quest turn-in that its chat lines still belong to it
local GATHER_WINDOW = 5   -- a loot window this soon after a gather cast is gathering
local SLOW_HOURS = 24     -- hours of scan pairs before "listed but never sold" means slow
I.GAP, I.FIRST, I.RESUME = GAP, FIRST, RESUME

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

I.SOURCES = {
    { key = "mobs",      label = "Mobs" },
    { key = "quest",     label = "Quests" },
    { key = "gather",    label = "Gathering" },
    { key = "fish",      label = "Fishing" },
    { key = "chest",     label = "Chests" },
    { key = "container", label = "Bags and boxes opened" },
}
local SOURCE_LABEL = {}
for _, s in ipairs(I.SOURCES) do SOURCE_LABEL[s.key] = s.label end

-- the clocks: time() for what's saved, GetTime() for the seconds-long windows (both stubbed by the test)
local function clock() return GetTime and GetTime() or time() end

local function secret(v) return issecretvalue and issecretvalue(v) end

----------------------------------------------------------------------
-- Store
----------------------------------------------------------------------
local function store()
    VoidBagsCharDB = VoidBagsCharDB or {}
    local e = VoidBagsCharDB.income
    if type(e) ~= "table" then e = {}; VoidBagsCharDB.income = e end
    e.sessions = e.sessions or {}
    e.zones = e.zones or {}
    return e
end

local function newSession(t)
    local e = store()
    e.nextId = (e.nextId or 0) + 1
    return { id = e.nextId, start = t or time(), last = 0, active = 0, coin = 0, cash = 0, worth = 0, listed = 0,
             unpriced = 0, src = {}, items = {}, zones = {} }
end

local function bestMap(s)
    local best, bestV
    for m, z in pairs(s.zones) do
        if not bestV or z.v > bestV then best, bestV = m, z.v end
    end
    return best
end

local function archive(s)
    if not s or (s.worth or 0) <= 0 then return end
    local list = store().sessions
    table.insert(list, 1, { id = s.id, start = s.start, stop = s.last, active = s.active, cash = s.cash,
                            worth = s.worth, src = s.src, map = bestMap(s) })
    while #list > HISTORY do table.remove(list) end
end

-- a filed session that a late-loading item added to: its record follows (found by its id, Sol), or it's filed now
-- when it had nothing yet at the time
local function refile(s)
    local list = store().sessions
    for _, a in ipairs(list) do
        if a.id and a.id == s.id then
            a.worth, a.cash, a.map = s.worth, s.cash, bestMap(s)
            return
        end
    end
    archive(s)
    table.sort(list, function(a, b) return (a.start or 0) > (b.start or 0) end)
end

function I:Session()
    local e = store()
    local s = e.current
    if s and s.last > 0 and time() - s.last > RESUME then
        archive(s)
        s = nil
    end
    e.current = s or newSession()
    return e.current
end

function I:Reset()
    local e = store()
    archive(e.current)
    e.current = newSession()
    self:Update()
end

----------------------------------------------------------------------
-- Money + rates
----------------------------------------------------------------------
local fmtNum = BreakUpLargeNumbers or tostring
function I.Money(c)
    c = math.floor(c or 0)
    if c >= 100000 then return fmtNum(math.floor(c / 10000)) .. "|cffffd700g|r" end
    if c >= 10000 then
        local s = math.floor(c % 10000 / 100)
        return math.floor(c / 10000) .. "|cffffd700g|r" .. (s > 0 and (" " .. s .. "|cffc7c7cfs|r") or "")
    end
    if c >= 100 then return math.floor(c / 100) .. "|cffc7c7cfs|r" end
    return c .. "|cffeda55fc|r"
end

function I.Rate(value, active)
    if not active or active < MIN_ACTIVE then return nil end
    return value * 3600 / active
end

local function minutes(sec) return math.floor((sec or 0) / 60 + 0.5) end

----------------------------------------------------------------------
-- Chat lines, read with the game's own strings (any client language)
----------------------------------------------------------------------
-- "You receive loot: %s." -> "^You receive loot: (.+)%.$"; "%d" -> "(%d+)"; "%1$s" positional forms too
local function toPattern(fmt, anchored)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    fmt = fmt:gsub("%%%d%$", "%%")
    local p = fmt:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
    p = p:gsub("%%s", "(.+)"):gsub("%%d", "([%%d,]+)")
    if anchored then p = "^" .. p .. "$" end
    return p
end
I.toPattern = toPattern

local lootPats
local function buildLootPats()
    lootPats = {}
    -- the "x3" forms first: the plain one would take "[Item]x3" as the item
    for _, d in ipairs({ { "LOOT_ITEM_SELF_MULTIPLE", "loot" }, { "LOOT_ITEM_SELF", "loot" },
                         { "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "pushed" }, { "LOOT_ITEM_PUSHED_SELF", "pushed" } }) do
        local p = toPattern(_G[d[1]], true)
        if p then lootPats[#lootPats + 1] = { p, d[2] } end
    end
end

-- "You receive loot: [Linen Cloth]x3." -> itemID, link, qty, "loot" | "pushed"; nil for anyone else's loot
function I.ParseLoot(msg)
    if type(msg) ~= "string" or secret(msg) then return nil end
    if not lootPats then buildLootPats() end
    for _, lp in ipairs(lootPats) do
        local link, n = msg:match(lp[1])
        if link then
            local id = tonumber((link:match("|Hitem:(%d+)")))
            if not id then return nil end   -- a currency, not an item
            n = n and tonumber((n:gsub(",", ""))) or 1
            return id, link, n, lp[2]
        end
    end
end

-- "You loot 1 Gold, 2 Silver, 3 Copper" / "Your share of the loot is ..." -> copper. Only before a "(": the retail
-- "(25 Silver deposited to guild bank)" isn't yours.
function I.ParseMoney(msg)
    if type(msg) ~= "string" or secret(msg) then return nil end
    msg = msg:match("^[^%(]*") or msg
    local total, any = 0, false
    for _, d in ipairs({ { "GOLD_AMOUNT", 10000 }, { "SILVER_AMOUNT", 100 }, { "COPPER_AMOUNT", 1 } }) do
        local p = toPattern(_G[d[1]], false)
        local n = p and msg:match(p)
        if n then total, any = total + (tonumber((n:gsub(",", ""))) or 0) * d[2], true end
    end
    return any and total or nil
end

----------------------------------------------------------------------
-- What an item is worth
----------------------------------------------------------------------
local watchedCache, watchedAt
local function watchedHours()
    if watchedAt and clock() - watchedAt < 300 then return watchedCache end
    local AH = VoidUI and VoidUI.AH
    local db = VoidUIAuctionDB
    local h = 0
    local key = AH and AH.HouseKey and AH:HouseKey()
    local obs = key and type(db) == "table" and db._obs and db._obs[key]
    if type(obs) == "table" then
        local cut = time() - 14 * 86400
        for _, o in ipairs(obs) do
            if type(o[1]) == "number" and type(o[2]) == "number" and o[2] > cut and o[2] > o[1] then
                h = h + (o[2] - o[1]) / 3600
            end
        end
    end
    watchedCache, watchedAt = h, clock()
    return h
end
function I._ResetCache() watchedAt = nil end

-- the auction house's price for one, after the cut: net, "sells" | "listed" | "slow"; nil when nothing knows it
local function ahNet(id)
    local AH = VoidUI and VoidUI.AH
    if AH and AH.GetPrice then
        local market = AH:GetPrice(id)
        market = type(market) == "number" and market > 0 and market or nil
        local sold = AH.SoldSummary and AH:SoldSummary(id, nil, 14 * 24)
        if sold and (sold.median or 0) > 0 then
            local p = sold.median
            if market and market < p then p = market end   -- today you'd list under the cheapest one up
            return p * CUT, "sells"
        end
        if market then
            -- slow: the house was watched a day AND this item was up on 2+ days of it, never seen selling (an item
            -- that only just turned up hasn't had its chance yet; Sol 11-23)
            if watchedHours() >= SLOW_HOURS then
                local db = VoidUIAuctionDB
                local e = AH.HouseKey and type(db) == "table" and db[AH:HouseKey()]
                e = type(e) == "table" and e[tostring(id)]
                local days = 0
                for _ in pairs(type(e) == "table" and type(e.h) == "table" and e.h or {}) do days = days + 1 end
                if days >= 2 then return market * CUT, "slow" end
            end
            return market * CUT, "listed"
        end
        return nil
    end
    local A = _G.Auctionator
    if A and A.API and A.API.v1 and A.API.v1.GetAuctionPriceByItemID then
        local ok, p = pcall(A.API.v1.GetAuctionPriceByItemID, ADDON, id)
        if ok and type(p) == "number" and p > 0 then return p * CUT, "listed" end
    end
    local T = _G.TSM_API
    if T and T.GetCustomPriceValue then
        local ok, p = pcall(T.GetCustomPriceValue, "dbmarket", "i:" .. id)
        if ok and type(p) == "number" and p > 0 then return p * CUT, "listed" end
    end
end

-- one of the item: { cash, worth, how, ah }; nil while the game hasn't loaded the item. The looted link when there is
-- one: a retail item-level variant sells to a vendor for its own price (Sol); the AH prices go by the item.
function I.Value(id, link)
    local name, _, quality, _, _, _, _, _, _, _, sell, classID, _, bind = GetItemInfo(link or id)
    if not name and link then name, _, quality, _, _, _, _, _, _, _, sell, classID, _, bind = GetItemInfo(id) end
    if not name then return nil end
    sell = tonumber(sell) or 0
    local v = { cash = sell, worth = sell, how = "vendor" }
    if classID == 12 or bind == 1 or bind == 4 or quality == 0 then return v end
    local net, how = ahNet(id)
    if net then
        v.ah = net
        if how == "slow" then
            v.how = "slow"   -- listed, never seen selling: the vendor's price is what it's worth
        elseif net > sell then
            v.worth, v.how = net, how
        end
    end
    return v
end

----------------------------------------------------------------------
-- Counting
----------------------------------------------------------------------
-- where you are: the map, or in a dungeon with no map (WoW Forever's old dungeons: Blackrock Depths, live 11-23:
-- 77 of 91 minutes had no zone) the instance, kept as -instanceID with its name
function I.Here()
    local m = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if m then return m end
    if GetInstanceInfo then
        local name, kind, _, _, _, _, _, instID = GetInstanceInfo()
        if type(instID) == "number" and instID > 0 and kind and kind ~= "none" then return -instID, name end
    end
end

-- activity: time between things you do while playing counts; a gap over GAP doesn't
function I:Touch(t)
    t = t or time()
    local s = self:Session()
    local dt = (s.last > 0 and t - s.last <= GAP) and math.max(0, t - s.last) or FIRST
    s.last, s.active = t, s.active + dt
    local mapID, name = I.Here()
    if mapID then
        local z = s.zones[mapID] or { v = 0, a = 0 }
        z.a = z.a + dt
        s.zones[mapID] = z
        local L = store().zones[mapID] or { v = 0, a = 0, src = {} }
        L.a = L.a + dt
        L.n = name or L.n
        store().zones[mapID] = L
    end
    return s, mapID
end

local function credit(s, mapID, src, worth)
    s.src[src] = (s.src[src] or 0) + worth
    if mapID then
        local z = s.zones[mapID]
        if z then z.v = z.v + worth end
        local L = store().zones[mapID]
        if L then
            L.v = L.v + worth
            L.src[src] = (L.src[src] or 0) + worth
        end
    end
end

function I:AddCoin(copper, src)
    if not copper or copper <= 0 then return end
    local s, mapID = self:Touch()
    s.coin = s.coin + copper
    s.cash, s.worth = s.cash + copper, s.worth + copper
    credit(s, mapID, src, copper)
    self:Update()
    return s, mapID
end

-- coin already counted under one source that turns out to be another's (a quest's money line before its turn-in)
local function moveCoin(s, mapID, from, to, copper)
    s.src[from] = (s.src[from] or 0) - copper
    s.src[to] = (s.src[to] or 0) + copper
    local L = mapID and store().zones[mapID]
    if L then
        L.src[from] = (L.src[from] or 0) - copper
        L.src[to] = (L.src[to] or 0) + copper
    end
end

-- Sacks, lockboxes and the like (right-click to open) count when opened, by what's inside: counting the sack too
-- counted it twice (live 11-23: Small Sack of Coins and Sack of Gems at their vendor price, then their contents).
-- Read from the bags (the looted item is there by its loot line); remembered per item once seen.
local openable = {}
function I.IsOpenable(id)
    if openable[id] ~= nil then return openable[id] end
    local C = C_Container
    if not (C and C.GetContainerNumSlots and C.GetContainerItemInfo) then return false end
    for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
        for slot = 1, C.GetContainerNumSlots(bag) or 0 do
            local info = C.GetContainerItemInfo(bag, slot)
            if info and info.itemID == id then
                openable[id] = info.hasLoot and true or false
                return openable[id]
            end
        end
    end
    return false   -- not in the bags (full, or gone already): counted, and asked again next time
end

local RETRIES = 10   -- seconds to wait for the game to load an item it hadn't

-- ctx (a retry): the session and zone it dropped in (the time was counted then). Still that session when a new one
-- started since, and its record in recent sessions too (Sol).
function I:AddItem(id, link, n, src, tries, ctx)
    local s, mapID
    if ctx then
        s, mapID = ctx.s, ctx.map
    else
        s, mapID = self:Touch()
        -- a sack or box: what's inside counts when you open it. Checked first, while it's still in the bags (its
        -- price may load after you've opened it, Sol)
        if I.IsOpenable(id) then return end
    end
    local v = I.Value(id, link)
    if not v then
        tries = (tries or 0) + 1
        if tries <= RETRIES and C_Timer and C_Timer.After then
            if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
            local c = ctx or { s = s, map = mapID }
            C_Timer.After(1, function() I:AddItem(id, link, n, src, tries, c) end)
        else
            s.unpriced = s.unpriced + n
            self:Update()
        end
        return
    end
    if v.worth <= 0 and v.cash <= 0 then return end   -- quest items and the like: nothing to count
    s.cash, s.worth = s.cash + v.cash * n, s.worth + v.worth * n
    if v.how == "listed" then s.listed = s.listed + v.worth * n end
    local row = s.items[id] or { n = 0, w = 0, c = 0, link = link, how = v.how }
    row.n, row.w, row.c, row.how = row.n + n, row.w + v.worth * n, row.c + v.cash * n, v.how
    row.link = row.link or link
    s.items[id] = row
    credit(s, mapID, src, v.worth * n)
    if ctx and store().current ~= s then refile(s) end
    self:Update()
end

----------------------------------------------------------------------
-- Where loot comes from
----------------------------------------------------------------------
local loot = { open = false, closed = -100, src = nil, items = {}, coinSrc = nil }
local questAt, gatherAt, questMoney = -100, -100, nil
local held = {}      -- "you receive item" lines that may be a reward whose quest event hasn't fired yet
local rewards = {}   -- item IDs the quest being turned in can give (its reward page, or retail's QUEST_LOOT_RECEIVED)
local rewardsUntil   -- the list is for one turn-in: dropped WINDOW seconds after it (Sol: not a later quest's)
local lastCoin       -- the last coin counted outside a loot window: { t, c, s, src, map }
I._loot = loot
function I._ResetState()
    loot.open, loot.closed, loot.src, loot.coinSrc = false, -100, nil, nil
    wipe(loot.items); wipe(held); wipe(rewards)
    questAt, gatherAt, questMoney, rewardsUntil, lastCoin = -100, -100, nil, nil, nil
end

local function isReward(id)
    if rewardsUntil and clock() > rewardsUntil then wipe(rewards); rewardsUntil = nil end
    return rewards[id]
end

-- held lines that are this quest's rewards count now; others wait out their WINDOW (the reward list may still come)
function I:FlushHeld()
    local t = clock()
    for i = #held, 1, -1 do
        local h = held[i]
        if t - h.t > WINDOW then
            table.remove(held, i)
        elseif isReward(h.id) then
            table.remove(held, i)
            self:AddItem(h.id, h.link, h.n, "quest")
        end
    end
end

local function sourceOfGUID(guid)
    if type(guid) ~= "string" or secret(guid) then return nil end
    local t = guid:match("^(%a+)")
    if t == "Creature" or t == "Vehicle" then return "mobs" end
    if t == "GameObject" then return "chest" end
    if t == "Item" then return "container" end
end

local gatherNames
local function isGatherSpell(spellID)
    if not gatherNames then
        gatherNames = {}
        local getName = (C_Spell and C_Spell.GetSpellName) or (GetSpellInfo and function(id) return (GetSpellInfo(id)) end)
        for _, id in ipairs({ 2575, 2366, 8613 }) do   -- Mining, Herb Gathering, Skinning (every tier shares the name)
            local nm = getName and getName(id)
            if nm then gatherNames[nm] = true end
        end
    end
    local getName = (C_Spell and C_Spell.GetSpellName) or (GetSpellInfo and function(id) return (GetSpellInfo(id)) end)
    local nm = getName and spellID and not secret(spellID) and getName(spellID)
    return nm and gatherNames[nm] or false
end

local function readLootWindow()
    wipe(loot.items)
    loot.src, loot.coinSrc = nil, nil
    local fishing = IsFishingLoot and IsFishingLoot()
    local gathering = clock() - gatherAt <= GATHER_WINDOW
    for slot = 1, (GetNumLootItems and GetNumLootItems() or 0) do
        local src
        if GetLootSourceInfo then src = sourceOfGUID((GetLootSourceInfo(slot))) end
        if fishing then src = "fish" elseif gathering then src = "gather" end
        src = src or loot.src or "mobs"
        loot.src = loot.src or src
        local link = GetLootSlotLink and GetLootSlotLink(slot)
        local id = type(link) == "string" and not secret(link) and tonumber((link:match("|Hitem:(%d+)")))
        if id then loot.items[id] = loot.items[id] or src end
        if GetLootSlotType and GetLootSlotType(slot) == 2 then loot.coinSrc = loot.coinSrc or src end
    end
end

local function inLootWindow() return loot.open or clock() - loot.closed <= WINDOW end

-- the events, as one entry point (the test drives it)
function I:OnEvent(event, ...)
    if event == "CHAT_MSG_LOOT" then
        local id, link, n, kind = I.ParseLoot((...))
        if not id then return end
        local src
        if kind == "loot" then
            src = inLootWindow() and (loot.items[id] or loot.src) or "mobs"   -- outside a window: a roll you won
        elseif isReward(id) and clock() - questAt <= WINDOW then
            src = "quest"                                                      -- one of the quest's rewards
        else
            -- bought, crafted, mailed: not income. Unless it turns out to be a reward whose turn-in (or retail's
            -- QUEST_LOOT_RECEIVED) hasn't fired yet: the order isn't promised, so held WINDOW seconds for that
            local t = clock()
            for i = #held, 1, -1 do if t - held[i].t > WINDOW then table.remove(held, i) end end
            held[#held + 1] = { t = t, id = id, link = link, n = n }
            return
        end
        self:AddItem(id, link, n, src)
    elseif event == "CHAT_MSG_MONEY" then
        local c = I.ParseMoney((...))
        if not c then return end
        -- the quest's own money line: QUEST_TURNED_IN counted it (checked first: a loot window may be closing, Sol)
        if questMoney and c == questMoney and clock() - questAt <= WINDOW then
            questMoney = nil
            return
        end
        local src = inLootWindow() and (loot.coinSrc or loot.src or "mobs") or "mobs"   -- else your group share
        local s, mapID = self:AddCoin(c, src)
        lastCoin = { t = clock(), c = c, s = s, src = src, map = mapID }
    elseif event == "QUEST_COMPLETE" then
        -- the reward page: the items this quest can give (only those count as its reward when they arrive)
        wipe(rewards)
        rewardsUntil = nil
        for _, kind in ipairs({ "reward", "choice" }) do
            local num = kind == "reward" and (GetNumQuestRewards and GetNumQuestRewards() or 0)
                or (GetNumQuestChoices and GetNumQuestChoices() or 0)
            for i = 1, num do
                local l = GetQuestItemLink and GetQuestItemLink(kind, i)
                local rid = type(l) == "string" and not secret(l) and tonumber((l:match("|Hitem:(%d+)")))
                if rid then rewards[rid] = true end
            end
        end
    elseif event == "QUEST_LOOT_RECEIVED" then
        -- retail: a quest that hands out its reward without the reward page; its chat line does the counting
        local _, l = ...
        local rid = type(l) == "string" and not secret(l) and tonumber((l:match("|Hitem:(%d+)")))
        if rid then
            isReward(rid)   -- an earlier quest's list expires first
            rewards[rid] = true
            questAt = clock()
            rewardsUntil = questAt + WINDOW
            self:FlushHeld()
        end
    elseif event == "QUEST_TURNED_IN" then
        local _, _, money = ...
        questAt = clock()
        isReward(0)   -- an earlier quest's list expires first (Sol), the reward page's stays
        rewardsUntil = questAt + WINDOW
        money = type(money) == "number" and not secret(money) and money > 0 and money or nil
        questMoney = money
        if money then
            local lc = lastCoin
            if lc and lc.c == money and questAt - lc.t <= WINDOW and lc.s == store().current then
                -- its money line came first and was counted as loot: it's the quest's (Sol: not twice)
                moveCoin(lc.s, lc.map, lc.src, "quest", money)
                lastCoin, questMoney = nil, nil
            else
                self:AddCoin(money, "quest")
            end
        end
        self:FlushHeld()
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        if not loot.open then
            loot.open = true
            readLootWindow()
        end
    elseif event == "LOOT_CLOSED" then
        loot.open, loot.closed = false, clock()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit == "player" and isGatherSpell(spellID) then
            gatherAt = clock()
            self:Touch()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        self:Touch()
    end
end

----------------------------------------------------------------------
-- Chat reports (from the box's menu)
----------------------------------------------------------------------
local PREFIX = (VB.C_CYAN or "|cff00c7ff") .. "[VoidBags]|r"

local function mapName(m)
    if type(m) == "number" and m < 0 then
        local L = store().zones[m]
        return L and L.n or "a dungeon"
    end
    local info = m and C_Map.GetMapInfo(m)
    return info and info.name or "?"
end

function I:PrintZones()
    local rows = {}
    for m, z in pairs(store().zones) do
        local rate = I.Rate(z.v, z.a)
        if rate and z.a >= 600 and z.v > 0 then rows[#rows + 1] = { m = m, rate = rate, z = z } end
    end
    table.sort(rows, function(a, b) return a.rate > b.rate end)
    if #rows == 0 then
        print(PREFIX .. " no zone has 10 minutes of play with income yet.")
        return
    end
    print(PREFIX .. " best gold per hour by zone (this character, worth if sold):")
    for i, r in ipairs(rows) do
        if i > 8 then break end
        local topK, topV
        for k, v in pairs(r.z.src or {}) do
            if not topV or v > topV then topK, topV = k, v end
        end
        print(("  %s  %s/hr  |cff999999%d min%s|r"):format(mapName(r.m), I.Money(r.rate), minutes(r.z.a),
            topK and (", mostly " .. SOURCE_LABEL[topK]:lower()) or ""))
    end
end

function I:PrintHistory()
    self:Session()
    local list = store().sessions
    if #list == 0 then
        print(PREFIX .. " no finished sessions yet (one ends with \"Start a new session\", or 30 minutes after you last earned anything).")
        return
    end
    print(PREFIX .. " recent sessions:")
    for i, s in ipairs(list) do
        if i > 10 then break end
        local rate = I.Rate(s.worth, s.active)
        print(("  %s  %s%s  |cff999999%d min, %s|r"):format(date("%b %d %H:%M", s.start), I.Money(s.worth),
            rate and (" (" .. I.Money(rate) .. "/hr)") or "", minutes(s.active), mapName(s.map)))
    end
end

----------------------------------------------------------------------
-- The tooltip (the box, and the gold in the bag window)
----------------------------------------------------------------------
local HOW = {
    sells  = "|cff19cc59sells|r",
    listed = "|cffffd700listed|r",
    slow   = "|cff8c8c9eslow: vendor|r",
    vendor = "|cff8c8c9evendor|r",
}

function I:FillTooltip(tt)
    local s = self:Session()
    tt:AddLine("VoidBags income — this session", 0, 0.78, 1)
    if s.worth <= 0 and s.active <= 0 then
        tt:AddLine("Nothing earned yet. Loot, coin and quest rewards count from here.", 0.7, 0.7, 0.7, true)
        return
    end
    local rw, rc = I.Rate(s.worth, s.active), I.Rate(s.cash, s.active)
    tt:AddDoubleLine("Worth if you sell it all", I.Money(s.worth) .. (rw and ("  (" .. I.Money(rw) .. "/hr)") or ""),
        0.8, 0.8, 0.8, 1, 1, 1)
    tt:AddDoubleLine("Cash: coin + vendor price", I.Money(s.cash) .. (rc and ("  (" .. I.Money(rc) .. "/hr)") or ""),
        0.8, 0.8, 0.8, 1, 1, 1)
    tt:AddDoubleLine("Time playing", minutes(s.active) .. " min", 0.8, 0.8, 0.8, 1, 1, 1)
    local srcs = {}
    for _, d in ipairs(I.SOURCES) do
        if (s.src[d.key] or 0) > 0 then srcs[#srcs + 1] = d end
    end
    table.sort(srcs, function(a, b) return s.src[a.key] > s.src[b.key] end)
    if #srcs > 0 then
        tt:AddLine(" ")
        for _, d in ipairs(srcs) do
            tt:AddDoubleLine(d.label, I.Money(s.src[d.key]), 0.8, 0.8, 0.8, 1, 1, 1)
        end
    end
    local ids = {}
    for id, row in pairs(s.items) do
        if row.w > 0 then ids[#ids + 1] = id end
    end
    table.sort(ids, function(a, b) return s.items[a].w > s.items[b].w end)
    if #ids > 0 then
        tt:AddLine(" ")
        if s.coin > 0 then tt:AddDoubleLine("Coin", I.Money(s.coin), 1, 1, 1, 1, 1, 1) end
        for i, id in ipairs(ids) do
            local row = s.items[id]
            if i <= 8 then
                tt:AddDoubleLine(("%s x%d"):format(row.link or ("item " .. id), row.n),
                    I.Money(row.w) .. "  " .. (HOW[row.how] or ""), 1, 1, 1, 1, 1, 1)
            elseif i == 9 then
                tt:AddLine(("…and %d more"):format(#ids - 8), 0.6, 0.6, 0.6)
            end
        end
    end
    if s.listed > 0 then
        tt:AddLine(("%s of it is priced from listings: not seen selling yet. Full scans in pairs (VoidAH) show what sells.")
            :format(I.Money(s.listed)), 0.6, 0.6, 0.6, true)
    end
    if s.unpriced > 0 then
        tt:AddLine(("%d item%s the game never loaded a price for"):format(s.unpriced, s.unpriced == 1 and "" or "s"),
            0.6, 0.6, 0.6, true)
    end
end

----------------------------------------------------------------------
-- The box: worth and gold per hour; hover for the split, drag to move, right-click for options
----------------------------------------------------------------------
local box

local function VoidPX()
    local sc = UIParent and UIParent:GetEffectiveScale()
    if sc and sc > 0 and PixelUtil and PixelUtil.GetPixelToUIUnitFactor then return PixelUtil.GetPixelToUIUnitFactor() / sc end
    return 1
end

-- a 1-pixel border from four anchored textures (the VoidLFG B.PixelBox way: edges never vanish)
local function PixelBox(f)
    local px = VoidPX() * 1.01
    local function tex(layer)
        local t = f:CreateTexture(nil, layer, nil, -8)
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(true) end
        return t
    end
    local bg = tex("BACKGROUND")
    bg:SetPoint("TOPLEFT", f, "TOPLEFT", px, -px)
    bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -px, px)
    bg:SetVertexColor(0.05, 0.05, 0.08, 0.85)
    local top, bottom, left, right = tex("BORDER"), tex("BORDER"), tex("BORDER"), tex("BORDER")
    top:SetPoint("TOPLEFT", f, "TOPLEFT"); top:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, -px)
    bottom:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, px); bottom:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")
    left:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -px); left:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", px, px)
    right:SetPoint("TOPLEFT", f, "TOPRIGHT", -px, -px); right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, px)
    for _, t in ipairs({ top, bottom, left, right }) do t:SetVertexColor(0, 0.78, 1, 0.45) end
end

local function menu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("VoidBags income")
        root:CreateButton("Start a new session", function() I:Reset() end)
        root:CreateButton("Best zones (chat)", function() I:PrintZones() end)
        root:CreateButton("Recent sessions (chat)", function() I:PrintHistory() end)
        root:CreateButton(I:Shown() and "Hide the box" or "Show the box", function() I:SetShown(not I:Shown()) end)
    end)
end
I.Menu = menu

local function buildBox()
    local f = CreateFrame("Button", "VoidBagsIncomeBox", UIParent)
    f:SetSize(130, 36)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    PixelBox(f)
    f:SetPoint("TOP", UIParent, "TOP", 0, -200)
    f:RegisterForClicks("RightButtonUp")
    f:SetScript("OnClick", menu)
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        I:FillTooltip(GameTooltip)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Drag to move · right-click for options", 0.4, 0.8, 1)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.top = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.top:SetPoint("TOP", 0, -5)
    f.bottom = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.bottom:SetPoint("TOP", f.top, "BOTTOM", 0, -3)
    if VB.Move then VB.Move(f, { db = function() return VoidBagsDB end, key = "income" }) end
    f:Hide()
    return f
end

function I:Shown() return VB:GetConfig("showIncome") == true end

function I:Update()
    if not self:Shown() then
        if box then box:Hide() end
        return
    end
    box = box or buildBox()
    local s = self:Session()
    local rate = I.Rate(s.worth, s.active)
    box.top:SetText(I.Money(s.worth))
    box.bottom:SetText((rate and (I.Money(rate) .. "/hr") or "—/hr") .. ("  ·  %d min"):format(minutes(s.active)))
    box:SetWidth(math.max(110, box.top:GetStringWidth() + 24, box.bottom:GetStringWidth() + 24))
    box:Show()
end

function I:SetShown(on)
    if VoidBagsDB and VoidBagsDB.config then VoidBagsDB.config.showIncome = on and true or false end
    self:Update()
    print(PREFIX .. " income box " .. (on and "|cff33ff33on|r (drag it anywhere; right-click for options)" or "|cffff5555off|r"))
end

-- the gold in the bag window: hover for this session, click for the box, right-click for the menu
function I:AttachGold(parent, goldText)
    if not (parent and goldText) or parent.voidIncomeHover then return end
    local h = CreateFrame("Button", nil, parent)
    h:SetPoint("TOPLEFT", goldText, "TOPLEFT", -2, 2)
    h:SetPoint("BOTTOMRIGHT", goldText, "BOTTOMRIGHT", 2, -2)
    h:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    h:SetScript("OnClick", function(self, btn)
        if btn == "RightButton" then menu(self) else I:SetShown(not I:Shown()) end
    end)
    h:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        I:FillTooltip(GameTooltip)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine((I:Shown() and "Click: hide" or "Click: show") .. " the income box · right-click for options",
            0.4, 0.8, 1)
        GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function() GameTooltip:Hide() end)
    parent.voidIncomeHover = h
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
if CreateFrame then
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_LOGIN", "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "QUEST_TURNED_IN", "LOOT_READY",
                         "LOOT_OPENED", "LOOT_CLOSED", "PLAYER_REGEN_DISABLED", "QUEST_COMPLETE", "QUEST_LOOT_RECEIVED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SUCCEEDED", "player")
    ev:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_LOGIN" then
            I:Update()   -- a session from before a /reload carries on
            return
        end
        I:OnEvent(event, ...)
    end)
end
