----------------------------------------------------------------------
-- VoidBags: Categories — item classification engine
----------------------------------------------------------------------
local _, VB = ...

----------------------------------------------------------------------
-- Category definitions
----------------------------------------------------------------------
VB.CATEGORIES = {
    Equipment          = { order = 1,  label = "Equipment",          color = VB.palette.accent },
    Warband            = { order = 2,  label = "Warband",            color = { 1.00, 0.78, 0.20 } },  -- gold (matches Blizzard warband tint)
    Cosmetic           = { order = 3,  label = "Cosmetic",           color = { 1.00, 0.50, 0.95 } },
    Flasks             = { order = 4,  label = "Flasks",             color = { 0.20, 0.85, 1.00 } },
    Potions            = { order = 5,  label = "Potions",            color = { 1.00, 0.40, 0.20 } },
    Food               = { order = 6,  label = "Food & Drink",       color = { 0.40, 0.90, 0.30 } },
    Consumables        = { order = 7,  label = "Consumables",        color = VB.palette.green },
    QuestItems         = { order = 8,  label = "Quest Items",        color = VB.palette.yellow },
    Keys               = { order = 9,  label = "Keys",               color = VB.palette.orange },
    AlchemyMats        = { order = 10, label = "Alchemy Mats",       color = { 0.70, 0.40, 1.00 } },
    CookingMats        = { order = 11, label = "Cooking Mats",       color = { 0.95, 0.55, 0.20 } },
    JewelcraftingMats  = { order = 12, label = "Jewelcrafting Mats", color = { 0.50, 0.85, 1.00 } },
    MyProfMats         = { order = 13, label = "Other Prof Mats",    color = VB.palette.purple },
    Craftable          = { order = 14, label = "Craftable",          color = { 0.50, 0.30, 0.80 } },
    SellableReagents   = { order = 15, label = "Sell / Other Mats",  color = VB.palette.textDim },
    Junk               = { order = 16, label = "Junk",               color = { 0.62, 0.62, 0.62 } },
    Misc               = { order = 17, label = "Miscellaneous",      color = VB.palette.textDark },
}

----------------------------------------------------------------------
-- Built-in item overrides for known Midnight items that don't carry a
-- helpful subclass tag. Players can extend via `/vb override <id> <cat>`.
----------------------------------------------------------------------
VB.BUILTIN_OVERRIDES = {
    -- Alchemy reagents tagged generically
    [240991] = "AlchemyMats",   -- Sunglass Vial
    -- Cooking ingredients that lack a Cooking/Meat/Fish subclass
    [253403] = "CookingMats",   -- Thalassian Fillet (processed from raw fish)
}

-- Returns user-override category for an item (highest priority)
local function GetItemOverride(itemID)
    if VoidBagsDB and VoidBagsDB.itemOverrides and VoidBagsDB.itemOverrides[itemID] then
        return VoidBagsDB.itemOverrides[itemID]
    end
    return VB.BUILTIN_OVERRIDES[itemID]
end

----------------------------------------------------------------------
-- Profession → reagent subclass mappings
----------------------------------------------------------------------
local PROF_REAGENT_MAP = {
    ["Blacksmithing"]   = { "Metal & Stone", "Ore", "Reagent", "Parts", "Optional Reagents", "Finishing Reagents" },
    ["Enchanting"]      = { "Enchanting", "Optional Reagents", "Finishing Reagents" },
    ["Alchemy"]         = { "Herb", "Elemental", "Optional Reagents", "Finishing Reagents" },
    ["Herbalism"]       = { "Herb" },
    ["Mining"]          = { "Metal & Stone", "Ore" },
    ["Skinning"]        = { "Leather", "Cloth" },
    ["Leatherworking"]  = { "Leather", "Cloth", "Optional Reagents", "Finishing Reagents" },
    ["Tailoring"]       = { "Cloth", "Optional Reagents", "Finishing Reagents" },
    ["Jewelcrafting"]   = { "Gem", "Metal & Stone", "Jewelcrafting", "Optional Reagents", "Finishing Reagents" },
    ["Inscription"]     = { "Herb", "Inscription", "Optional Reagents", "Finishing Reagents" },
    ["Engineering"]     = { "Parts", "Metal & Stone", "Engineering", "Optional Reagents", "Finishing Reagents" },
    ["Cooking"]         = { "Cooking", "Meat", "Fish" },
    ["Fishing"]         = { "Fish" },
}

local REAGENT_TO_PROF = {}
for prof, subs in pairs(PROF_REAGENT_MAP) do
    for _, sub in ipairs(subs) do
        if not REAGENT_TO_PROF[sub] then
            REAGENT_TO_PROF[sub] = {}
        end
        REAGENT_TO_PROF[sub][prof] = true
    end
end

----------------------------------------------------------------------
-- Key item detection
----------------------------------------------------------------------
local KEY_ITEM_IDS = {
    [224172] = true, -- Coffer Key
    [224173] = true, -- Restored Coffer Key
}

local function IsKeyItem(itemID, itemName)
    if KEY_ITEM_IDS[itemID] then return true end
    if itemName and (itemName:lower():find("coffer key") or itemName:lower():find("keystone")) then
        return true
    end
    return false
end

----------------------------------------------------------------------
-- Learnable detection
----------------------------------------------------------------------
function VB:IsLearnable(bag, slot, itemID, itemLink)
    if not itemLink then return false end

    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemLink)

    -- Recipes (classID 9)
    if classID == 9 then return true end

    -- Toys
    if C_ToyBox and C_ToyBox.GetToyInfo then
        local toyID = C_ToyBox.GetToyInfo(itemID)
        if toyID and not PlayerHasToy(itemID) then return true end
    end

    -- Mounts
    local mountID = C_MountJournal and C_MountJournal.GetMountFromItem and C_MountJournal.GetMountFromItem(itemID)
    if mountID then
        local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
        if not isCollected then return true end
    end

    -- Pets
    local petID = C_PetJournal and C_PetJournal.GetPetInfoByItemID and C_PetJournal.GetPetInfoByItemID(itemID)
    if petID then return true end

    -- Transmog (appearances)
    if C_TransmogCollection and C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance then
        local itemLoc = ItemLocation:CreateFromBagAndSlot(bag, slot)
        if itemLoc and itemLoc:IsValid() and C_Item.DoesItemExist(itemLoc) then
            local ok, appearanceID = pcall(C_TransmogCollection.GetItemInfo, itemLink)
            if ok and appearanceID then
                local hasAppearance = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(appearanceID)
                if not hasAppearance then return true end
            end
        end
    end

    return false
end

----------------------------------------------------------------------
-- Upgrade detection (simple ilvl comparison, VoidGearScore if available)
----------------------------------------------------------------------
function VB:IsUpgrade(bag, slot, itemLink)
    if not itemLink then return false, 0 end

    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemLink)
    if classID ~= Enum.ItemClass.Armor and classID ~= Enum.ItemClass.Weapon then
        return false, 0
    end

    local equipSlot = select(4, C_Item.GetItemInfoInstant(itemLink))
    if not equipSlot or equipSlot == "" or equipSlot == "INVTYPE_NON_EQUIP" or equipSlot == "INVTYPE_BAG" or equipSlot == "INVTYPE_TABARD" or equipSlot == "INVTYPE_BODY" then
        return false, 0
    end

    -- Try VoidGearScore / VoidUI ceiling
    local ceilingScore = VB:GetGearCeiling(bag, slot)
    if ceilingScore and ceilingScore > 0 then
        return true, ceilingScore
    end

    -- Fallback: simple ilvl comparison
    local bagIlvl = C_Item.GetCurrentItemLevel(ItemLocation:CreateFromBagAndSlot(bag, slot))
    if not bagIlvl then return false, 0 end

    local SLOT_MAP = {
        INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3,
        INVTYPE_CHEST = 5, INVTYPE_ROBE = 5, INVTYPE_WAIST = 6,
        INVTYPE_LEGS = 7, INVTYPE_FEET = 8, INVTYPE_WRIST = 9,
        INVTYPE_HAND = 10, INVTYPE_FINGER = 11, INVTYPE_TRINKET = 13,
        INVTYPE_CLOAK = 15, INVTYPE_WEAPON = 16, INVTYPE_SHIELD = 17,
        INVTYPE_2HWEAPON = 16, INVTYPE_WEAPONMAINHAND = 16,
        INVTYPE_WEAPONOFFHAND = 17, INVTYPE_HOLDABLE = 17,
        INVTYPE_RANGED = 16, INVTYPE_RANGEDRIGHT = 16,
    }

    local slotID = SLOT_MAP[equipSlot]
    if not slotID then return false, 0 end

    -- C_Item.GetCurrentItemLevel(ItemLocation:CreateFromEquipmentSlot(N)) is the
    -- modern path; works for empty slots (returns 0) and is taint-stable in 12.0.5.
    local function equippedSlotIlvl(invSlot)
        local loc = ItemLocation:CreateFromEquipmentSlot(invSlot)
        if not loc or not loc:IsValid() then return 0 end
        return C_Item.GetCurrentItemLevel(loc) or 0
    end

    local equippedIlvl = 0
    if equipSlot == "INVTYPE_FINGER" then
        equippedIlvl = math.min(equippedSlotIlvl(11), equippedSlotIlvl(12))
    elseif equipSlot == "INVTYPE_TRINKET" then
        equippedIlvl = math.min(equippedSlotIlvl(13), equippedSlotIlvl(14))
    else
        equippedIlvl = equippedSlotIlvl(slotID)
    end

    if equippedIlvl == 0 then return true, 100 end
    local pctChange = ((bagIlvl - equippedIlvl) / equippedIlvl) * 100
    return pctChange > 0, pctChange
end

----------------------------------------------------------------------
-- Main categorization function
----------------------------------------------------------------------
function VB:CategorizeItem(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info then return nil end

    local itemID = info.itemID
    local itemLink = C_Container.GetContainerItemLink(bag, slot)
    if not itemLink then return nil end

    -- GetItemInfoInstant for numeric classID/subClassID
    local _, itemType, itemSubType, itemEquipLoc, _, classIDNum, subClassIDNum = C_Item.GetItemInfoInstant(itemLink)

    -- GetItemInfo for name, quality, vendor price, bind type, etc.
    -- Return 14 (bindType) — values: 0=none, 1=BoP, 2=BoE, 3=BoU, 4=Quest,
    -- 7=Warbound-until-equipped, 8=Account-bound (Warbound/Heirloom)
    local itemName, _, quality, _, _, _, _, _, equipSlot, _, vendorPrice, _, _, bindType, _, _, isCraftingReagent = C_Item.GetItemInfo(itemLink)
    if not itemName then
        itemName = info.iconFileID and "Loading..." or "Unknown"
    end

    local classID = classIDNum or 0
    local subClassID = subClassIDNum or 0
    local subClassName = itemSubType or ""
    equipSlot = equipSlot or itemEquipLoc or ""
    quality = quality or info.quality or 0

    -- Markers
    local markers = {}

    -- Protected items skip T/Junk marking
    local isProtected = VoidBagsDB and VoidBagsDB.protected and VoidBagsDB.protected[itemID]
    if isProtected then
        markers.protected = true
    end

    -- USER / BUILTIN OVERRIDE — highest priority, user-specified category wins
    local override = GetItemOverride(itemID)
    if override and VB.CATEGORIES[override] then
        return override, markers
    end

    -- Junk (grey quality) — unless protected
    if quality == 0 and not isProtected then
        return "Junk", markers
    end

    -- Quest items
    if classID == Enum.ItemClass.Questitem then
        return "QuestItems", markers
    end

    -- Keys
    if IsKeyItem(itemID, itemName) then
        return "Keys", markers
    end
    if classID == Enum.ItemClass.Key then
        return "Keys", markers
    end

    -- Warband detection — items that are warbound until equipped, or
    -- account-bound. Two detection paths:
    --   1. bindType from GetItemInfo (return 14): 7 = Warbound-until-equipped,
    --      8 = Account-bound (Warbound/Heirloom). Most reliable.
    --   2. C_Item APIs as fallback (names vary across patches).
    do
        local isWarband = false
        if bindType == 7 or bindType == 8 then
            isWarband = true
        end
        if not isWarband then
            local itemLoc = ItemLocation:CreateFromBagAndSlot(bag, slot)
            if itemLoc and C_Item.DoesItemExist(itemLoc) then
                if C_Item.IsBoundToAccountUntilEquip then
                    local ok, r = pcall(C_Item.IsBoundToAccountUntilEquip, itemLoc)
                    if ok and r then isWarband = true end
                end
                if not isWarband and C_Item.IsItemBoundToAccountUntilEquip then
                    local ok, r = pcall(C_Item.IsItemBoundToAccountUntilEquip, itemLoc)
                    if ok and r then isWarband = true end
                end
                if not isWarband and C_Item.IsBoundToAccount then
                    local ok, r = pcall(C_Item.IsBoundToAccount, itemLoc)
                    if ok and r then isWarband = true end
                end
            end
        end
        if isWarband then
            if classID == Enum.ItemClass.Armor or classID == Enum.ItemClass.Weapon then
                local itemLoc = ItemLocation:CreateFromBagAndSlot(bag, slot)
                if itemLoc and C_Item.DoesItemExist(itemLoc) then
                    local ilvl = C_Item.GetCurrentItemLevel(itemLoc)
                    if ilvl and ilvl > 0 then markers.ilvl = ilvl end
                end
                local isUpgrade, pct = VB:IsUpgrade(bag, slot, itemLink)
                if isUpgrade then markers.upgrade = true; markers.upgradePct = pct end
            end
            return "Warband", markers
        end
    end

    -- Cosmetic detection — must come BEFORE the Equipment block so cosmetic
    -- armor doesn't get classified as gear. Three signals:
    --   1. Armor subclass = Cosmetic (Enum.ItemArmorSubclass.Cosmetic == 5)
    --   2. Tooltip contains "Cosmetic" line (catches non-armor cosmetics)
    --   3. IsCosmeticItem global API if available
    do
        local isCosmetic = false
        if classID == Enum.ItemClass.Armor and subClassID == 5 then
            isCosmetic = true
        end
        -- _G.IsCosmeticItem global was removed in 12.0; only C_Item.IsCosmeticItem remains.
        if not isCosmetic and C_Item and C_Item.IsCosmeticItem then
            local ok, r = pcall(C_Item.IsCosmeticItem, itemLink)
            if ok and r then isCosmetic = true end
        end
        if isCosmetic then
            -- Mark whether the appearance is already collected so the bag
            -- can show a "new!" indicator on uncollected drops.
            if C_TransmogCollection and C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance then
                local ok, appearanceID = pcall(C_TransmogCollection.GetItemInfo, itemLink)
                if ok and appearanceID then
                    local hasIt = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(appearanceID)
                    if not hasIt then markers.learnable = true end
                end
            end
            return "Cosmetic", markers
        end
    end

    -- Equipment (armor/weapons)
    if classID == Enum.ItemClass.Armor or classID == Enum.ItemClass.Weapon then
        if equipSlot and equipSlot ~= "" and equipSlot ~= "INVTYPE_NON_EQUIP" and equipSlot ~= "INVTYPE_BAG" then
            -- Learnable check (transmog)
            if VB:IsLearnable(bag, slot, itemID, itemLink) then
                markers.learnable = true
            end
            -- Upgrade check
            local isUpgrade, pct = VB:IsUpgrade(bag, slot, itemLink)
            if isUpgrade and pct > 0 then
                markers.upgrade = true
                markers.upgradePct = pct
            end
            -- Item level
            local ilvl = C_Item.GetCurrentItemLevel(ItemLocation:CreateFromBagAndSlot(bag, slot))
            if ilvl and ilvl > 0 then
                markers.ilvl = ilvl
            end
            return "Equipment", markers
        end
    end

    -- Consumables — break out into Flasks / Potions / Food / generic.
    -- Subclass IDs (Enum.ItemConsumableSubclass):
    --   1=Potion, 2=Elixir, 3=Flask, 5=Food&Drink, others=generic
    if classID == Enum.ItemClass.Consumable then
        if subClassID == 3 then
            return "Flasks", markers
        elseif subClassID == 1 or subClassID == 2 then
            return "Potions", markers
        elseif subClassID == 5 then
            return "Food", markers
        else
            return "Consumables", markers
        end
    end
    -- Item Enhancement (weapon oils, armor kits, enchant vellums)
    if classID == Enum.ItemClass.ItemEnhancement then
        return "Consumables", markers
    end

    -- Gems
    if classID == Enum.ItemClass.Gem then
        if VB.playerProfs["Jewelcrafting"] then
            markers.craftable = true
            return "MyProfMats", markers
        else
            markers.trash = true
            return "SellableReagents", markers
        end
    end

    -- Recipes
    if classID == Enum.ItemClass.Recipe then
        markers.learnable = true
        return "Consumables", markers
    end

    -- Tradegoods / Reagents
    if classID == Enum.ItemClass.Tradegoods or isCraftingReagent then
        local isMyProf = false
        local isAnyProf = false
        local matchingProfs = {}

        if subClassName then
            local profsForSub = REAGENT_TO_PROF[subClassName]
            if profsForSub then
                isAnyProf = true
                for prof in pairs(profsForSub) do
                    if VB.playerProfs[prof] then
                        isMyProf = true
                        matchingProfs[prof] = true
                    end
                end
            end
        end

        if isMyProf then
            markers.craftable = true
            -- Route into per-profession lanes when applicable, in this priority:
            -- Alchemy > Cooking > Jewelcrafting > generic MyProfMats. Items
            -- shared between professions (e.g. Herbs used by Alchemy AND
            -- Inscription) prefer the more relevant active spec.
            if matchingProfs["Alchemy"]
               and (subClassName == "Herb" or subClassName == "Elemental"
                    or subClassName == "Optional Reagents" or subClassName == "Finishing Reagents") then
                return "AlchemyMats", markers
            elseif matchingProfs["Cooking"]
                   and (subClassName == "Cooking" or subClassName == "Meat" or subClassName == "Fish") then
                return "CookingMats", markers
            elseif matchingProfs["Jewelcrafting"]
                   and (subClassName == "Gem" or subClassName == "Jewelcrafting") then
                return "JewelcraftingMats", markers
            end
            return "MyProfMats", markers
        else
            -- Check if an alt needs this reagent
            local altNeeds, altName = VB:AltHasProfessionFor(subClassName)
            if altNeeds then
                markers.altNeeds = true
                markers.altName = altName
                return "SellableReagents", markers
            end

            -- Check AH value vs vendor price
            local ahPrice = VB:GetAHPrice(itemID)
            if ahPrice then
                local vp = vendorPrice or 0
                local ratio = vp > 0 and (ahPrice / vp) or 0
                local goldFloor = (VB:GetConfig("ahThresholdFloor") or 50) * 10000
                if ratio >= (VB:GetConfig("ahThresholdRatio") or 3) and ahPrice >= goldFloor then
                    markers.ahValue = ahPrice
                    markers.sellAH = true
                    return "SellableReagents", markers
                end
            end

            -- Truly vendor-worthy (unless protected)
            if not isProtected then
                markers.trash = true
                return "SellableReagents", markers
            else
                return "Misc", markers
            end
        end
    end

    -- Learnable misc (toys, mounts, pets)
    if VB:IsLearnable(bag, slot, itemID, itemLink) then
        markers.learnable = true
        return "Misc", markers
    end

    -- AH value check
    local ahPrice = VB:GetAHPrice(itemID)
    if ahPrice then
        local ratio = vendorPrice and vendorPrice > 0 and (ahPrice / vendorPrice) or 0
        local goldFloor = (VB:GetConfig("ahThresholdFloor") or 50) * 10000
        if ratio >= (VB:GetConfig("ahThresholdRatio") or 3) and ahPrice >= goldFloor then
            markers.ahValue = ahPrice
        end
    end

    return "Misc", markers
end

----------------------------------------------------------------------
-- Cross-character inventory snapshot
----------------------------------------------------------------------
function VB:SnapshotInventory()
    local key = VB:GetPlayerKey()
    local displayKey = self:GetPlayerDisplayKey()
    local guid = UnitGUID("player")

    -- One-shot migration: copy legacy Name-Realm entry to GUID key.
    -- (key == guid here once GUID is available; key == displayKey on
    -- pre-PLAYER_LOGIN edge cases. The migration runs once both keys
    -- exist and the GUID slot is empty.)
    VoidBagsDB.characters = VoidBagsDB.characters or {}
    if guid and VoidBagsDB.characters[displayKey] and not VoidBagsDB.characters[guid] then
        VoidBagsDB.characters[guid] = VoidBagsDB.characters[displayKey]
    end

    local data = {
        guid = guid,
        displayKey = displayKey,  -- "Name-Realm" for UI
        class = select(2, UnitClass("player")),
        level = UnitLevel("player"),
        money = GetMoney(),
        ilvl = select(2, GetAverageItemLevel()),
        bags = {},
        timestamp = time(),
    }

    -- Include reagent bag (slot 5). Iterating 0..4 silently dropped every
    -- profession reagent from cross-character snapshots.
    local REAGENT = Enum.BagIndex and Enum.BagIndex.ReagentBag or 5
    local snapshotBags = { 0, 1, 2, 3, 4, REAGENT }
    for _, bag in ipairs(snapshotBags) do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not VoidLib.Secrets.IsSecret(info.itemID) then
                local link = C_Container.GetContainerItemLink(bag, slot)
                data.bags[#data.bags + 1] = {
                    id = info.itemID,
                    count = info.stackCount,
                    link = link,
                    name = C_Item.GetItemNameByID(info.itemID),
                    quality = info.quality,
                    bag = bag,
                    slot = slot,
                }
            end
        end
    end

    VoidBagsDB.characters[key] = data
end

----------------------------------------------------------------------
-- Get other characters' items
----------------------------------------------------------------------
function VB:GetCharacterList()
    local list = {}
    local myKey = VB:GetPlayerKey()
    for key, data in pairs(VoidBagsDB.characters or {}) do
        if key ~= myKey then
            list[#list + 1] = { key = key, data = data }
        end
    end
    table.sort(list, function(a, b) return a.key < b.key end)
    return list
end

function VB:SearchAllCharacters(searchText)
    local results = {}
    searchText = searchText:lower()
    for key, data in pairs(VoidBagsDB.characters or {}) do
        for _, item in ipairs(data.bags or {}) do
            if item.name and item.name:lower():find(searchText, 1, true) then
                results[#results + 1] = {
                    character = key,
                    class = data.class,
                    itemID = item.id,
                    name = item.name,
                    count = item.count,
                    link = item.link,
                    quality = item.quality,
                }
            end
        end
    end
    return results
end
