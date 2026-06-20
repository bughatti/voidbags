-- VoidSpy hook: enable with /vspy enable VoidBags  (no-op if VoidSpy missing/disabled)
local function dbg(fmt, ...) if VoidSpy and VoidSpy.Log then VoidSpy:Log("VoidBags", fmt, ...) end end

----------------------------------------------------------------------
-- VoidBags: Core — palette, utilities, config, saved variables
----------------------------------------------------------------------
local ADDON_NAME, VB = ...
_G.VoidBags = VB

----------------------------------------------------------------------
-- Palette (matches VoidUI)
----------------------------------------------------------------------
VB.palette = {
    accent    = { 0.00, 0.78, 1.00 },     -- cyan
    accentDim = { 0.00, 0.78, 1.00, 0.3 },
    text      = { 0.92, 0.92, 0.95 },      -- off-white
    textDim   = { 0.55, 0.55, 0.62 },      -- purple-grey
    textDark  = { 0.40, 0.40, 0.45 },
    green     = { 0.10, 0.80, 0.35 },
    red       = { 1.00, 0.30, 0.30 },
    yellow    = { 1.00, 0.84, 0.00 },
    orange    = { 1.00, 0.50, 0.00 },
    purple    = { 0.64, 0.21, 0.93 },
    bg        = { 0.05, 0.05, 0.05, 0.92 },
    bgLight   = { 0.08, 0.08, 0.10, 0.92 },
    border    = { 0.15, 0.15, 0.15, 1 },
    borderAccent = { 0.00, 0.78, 1.00, 0.5 },
}

VB.QUALITY_COLORS = {
    [0] = { 0.62, 0.62, 0.62 }, -- Poor (grey)
    [1] = { 1.00, 1.00, 1.00 }, -- Common (white)
    [2] = { 0.12, 1.00, 0.00 }, -- Uncommon (green)
    [3] = { 0.00, 0.44, 0.87 }, -- Rare (blue)
    [4] = { 0.64, 0.21, 0.93 }, -- Epic (purple)
    [5] = { 1.00, 0.50, 0.00 }, -- Legendary (orange)
    [6] = { 0.90, 0.80, 0.50 }, -- Artifact
    [7] = { 0.00, 0.80, 1.00 }, -- Heirloom
    [8] = { 0.00, 0.80, 1.00 }, -- WoW Token
}

----------------------------------------------------------------------
-- Color strings
----------------------------------------------------------------------
VB.C_CYAN   = "|cff00c7ff"
VB.C_WHITE  = "|cffebebf2"
VB.C_DIM    = "|cff8c8c9e"
VB.C_GREEN  = "|cff19cc59"
VB.C_RED    = "|cffff4d4d"
VB.C_GOLD   = "|cffffd700"
VB.C_SILVER = "|cffc0c0c0"
VB.C_COPPER = "|cffeda55f"
VB.C_ORANGE = "|cffff8000"
VB.C_PURPLE = "|cffa335ee"

----------------------------------------------------------------------
-- Font
----------------------------------------------------------------------
VB.FONT = "Fonts\\FRIZQT__.TTF"
VB.FONT_BOLD = "Fonts\\ARIALN.TTF"

function VB:SetFont(fs, size, flags)
    fs:SetFont(self.FONT, size or 11, flags or "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.8)
end

----------------------------------------------------------------------
-- Backdrop
----------------------------------------------------------------------
local BACKDROP_INFO = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}

function VB:CreateBackdrop(frame, style)
    frame:SetBackdrop(BACKDROP_INFO)
    if style == "transparent" then
        frame:SetBackdropColor(0.05, 0.05, 0.07, 0.85)
        frame:SetBackdropBorderColor(VB.palette.accent[1], VB.palette.accent[2], VB.palette.accent[3], 0.5)
    elseif style == "section" then
        frame:SetBackdropColor(0.06, 0.06, 0.08, 0.6)
        frame:SetBackdropBorderColor(0.12, 0.12, 0.14, 0.8)
    else
        frame:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
        frame:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)
    end
end

----------------------------------------------------------------------
-- Utility
----------------------------------------------------------------------
function VB:FormatMoney(copper)
    if not copper or copper == 0 then return "0" end
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    if gold > 0 then
        return VB.C_GOLD .. gold .. "g|r"
    elseif silver > 0 then
        return VB.C_SILVER .. silver .. "s|r"
    else
        return VB.C_COPPER .. copper .. "c|r"
    end
end

function VB:FormatNumber(n)
    if not n then return "0" end
    if n >= 1000000 then
        return string.format("%.1fM", n / 1000000)
    elseif n >= 1000 then
        return string.format("%.1fK", n / 1000)
    end
    return tostring(math.floor(n))
end

-- Player key: prefer GUID (immune to rename/transfer collisions). Falls back
-- to Name-Realm for displays/UI. GUID may be unavailable very early in login,
-- so cache both forms and migrate-on-first-GUID for legacy data.
function VB:GetPlayerKey()
    local guid = UnitGUID("player")
    if guid then return guid end
    -- Login race: GUID not yet ready. Use display key for this session.
    return self:GetPlayerDisplayKey()
end

function VB:GetPlayerDisplayKey()
    local name = UnitName("player") or "?"
    local realm = GetRealmName() or "?"
    return name .. "-" .. realm
end

----------------------------------------------------------------------
-- Config defaults
----------------------------------------------------------------------
VB.defaults = {
    iconSize = 37,
    columns = 12,
    spacing = 3,
    sectionSpacing = 8,
    showBagBar = true,
    showItemLevel = true,
    showMarkers = true,
    showAHValue = true,
    ahThresholdRatio = 3,
    ahThresholdFloor = 50,  -- gold
    autoSellJunk = true,
    autoRepair = true,
    useGuildRepair = true,
    repairCostCap = 0,            -- 0 = no cap; otherwise max copper to spend per repair (personal funds only)
    sortOrder = { "Equipment", "Warband", "Cosmetic", "Flasks", "Potions", "Food", "Consumables", "QuestItems", "Keys", "AlchemyMats", "CookingMats", "JewelcraftingMats", "MyProfMats", "Craftable", "SellableReagents", "Junk", "Misc" },
    position = nil,
    bankPosition = nil,
}

----------------------------------------------------------------------
-- Saved variables init
----------------------------------------------------------------------
function VB:InitDB()
    VoidBagsDB = VoidBagsDB or {}
    VoidBagsDB.config = VoidBagsDB.config or {}
    VoidBagsDB.characters = VoidBagsDB.characters or {}
    VoidBagsDB.warband = VoidBagsDB.warband or {}
    VoidBagsDB.protected = VoidBagsDB.protected or {}

    VoidBagsCharDB = VoidBagsCharDB or {}

    for k, v in pairs(self.defaults) do
        if VoidBagsDB.config[k] == nil then
            VoidBagsDB.config[k] = v
        end
    end

    -- Migrate sortOrder: insert any missing default categories so users
    -- with old saved configs see the new Flasks/Potions/Food/per-prof lanes.
    local existing = VoidBagsDB.config.sortOrder or {}
    local existingSet = {}
    for _, c in ipairs(existing) do existingSet[c] = true end
    local migrated = false
    for _, c in ipairs(self.defaults.sortOrder) do
        if not existingSet[c] then
            -- Insert each new category at the position from defaults
            existing[#existing + 1] = c
            migrated = true
        end
    end
    if migrated then
        -- Re-sort to match defaults order
        local ordered = {}
        local saw = {}
        for _, c in ipairs(self.defaults.sortOrder) do
            if existingSet[c] or true then  -- include all defaults
                ordered[#ordered + 1] = c
                saw[c] = true
            end
        end
        -- Append any user-only categories not in defaults (defensive)
        for _, c in ipairs(existing) do
            if not saw[c] then ordered[#ordered + 1] = c end
        end
        VoidBagsDB.config.sortOrder = ordered
    end

    self.config = VoidBagsDB.config
end

function VB:GetConfig(key)
    return self.config and self.config[key] or self.defaults[key]
end

----------------------------------------------------------------------
-- External API detection
----------------------------------------------------------------------
function VB:GetGearScore(itemLink)
    if VoidGearScore and VoidGearScore.Calc then
        return VoidGearScore.Calc(itemLink)
    end
    if VoidUI and VoidUI.gearScore and VoidUI.gearScore.calc then
        return VoidUI.gearScore.calc(itemLink)
    end
    return nil
end

function VB:GetGearCeiling(bag, slot)
    if VoidUI and VoidUI.gearCeiling and VoidUI.gearCeiling.forBag then
        return VoidUI.gearCeiling.forBag(bag, slot)
    end
    return nil
end

function VB:GetAHPrice(itemID)
    if VoidUI and VoidUI.AH and VoidUI.AH.GetPrice then
        return VoidUI.AH.GetPrice(itemID)
    end
    if VoidUIAuctionDB and VoidUIAuctionDB.prices then
        return VoidUIAuctionDB.prices[itemID]
    end
    return nil
end

----------------------------------------------------------------------
-- Player profession cache
----------------------------------------------------------------------
VB.playerProfs = {}

function VB:UpdateProfessions()
    wipe(self.playerProfs)
    -- GetProfessions returns up to 5 sparse positional values:
    --   prof1, prof2, archaeology(removed in 12.0), fishing, cooking
    -- ipairs stops at first nil, so iterate explicitly via select.
    local raw = { select(1, GetProfessions()), select(2, GetProfessions()),
                  select(3, GetProfessions()), select(4, GetProfessions()),
                  select(5, GetProfessions()) }
    for i = 1, 5 do
        local idx = raw[i]
        if idx then
            local name, _, _, _, _, _, skillLine = GetProfessionInfo(idx)
            if name then
                self.playerProfs[name] = true
                if skillLine then
                    self.playerProfs[skillLine] = true
                end
            end
        end
    end

    -- Save professions to cross-char DB for alt detection
    local key = self:GetPlayerKey()
    if VoidBagsDB and VoidBagsDB.characters then
        VoidBagsDB.characters[key] = VoidBagsDB.characters[key] or {}
        VoidBagsDB.characters[key].professions = {}
        for name in pairs(self.playerProfs) do
            VoidBagsDB.characters[key].professions[name] = true
        end
    end
end

function VB:AltHasProfessionFor(subClassName)
    if not VoidBagsDB or not VoidBagsDB.characters then return false, nil end
    local myKey = self:GetPlayerKey()

    for charKey, charData in pairs(VoidBagsDB.characters) do
        if charKey ~= myKey and charData.professions then
            for profName in pairs(charData.professions) do
                if profName and type(profName) == "string" then
                    local found = false
                    -- Check if this profession uses this reagent subclass
                    local PROF_MAP = {
                        ["Blacksmithing"] = { ["Metal & Stone"] = true, ["Ore"] = true, ["Reagent"] = true, ["Parts"] = true },
                        ["Enchanting"] = { ["Enchanting"] = true },
                        ["Alchemy"] = { ["Herb"] = true, ["Elemental"] = true },
                        ["Herbalism"] = { ["Herb"] = true },
                        ["Mining"] = { ["Metal & Stone"] = true, ["Ore"] = true },
                        ["Skinning"] = { ["Leather"] = true, ["Cloth"] = true },
                        ["Leatherworking"] = { ["Leather"] = true, ["Cloth"] = true },
                        ["Tailoring"] = { ["Cloth"] = true },
                        ["Jewelcrafting"] = { ["Gem"] = true, ["Metal & Stone"] = true, ["Jewelcrafting"] = true },
                        ["Inscription"] = { ["Herb"] = true, ["Inscription"] = true },
                        ["Engineering"] = { ["Parts"] = true, ["Metal & Stone"] = true, ["Engineering"] = true },
                        ["Cooking"] = { ["Cooking"] = true, ["Meat"] = true, ["Fish"] = true },
                    }
                    local profReagents = PROF_MAP[profName]
                    if profReagents and profReagents[subClassName] then
                        return true, charKey
                    end
                end
            end
        end
    end
    return false, nil
end
