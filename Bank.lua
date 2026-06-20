----------------------------------------------------------------------
-- VoidBags: Bank — bank frame, warband bank, cross-char viewer
----------------------------------------------------------------------
local _, VB = ...

local P = VB.palette
local bankFrame
local bankButtons = {}
local bankSections = {}
local bankSectionButtons = {}
local bankIsOpen = false
local warbandTab
local bankRefreshTimer

----------------------------------------------------------------------
-- Bank bag IDs (Midnight 12.0)
----------------------------------------------------------------------
local BagIndex = Enum.BagIndex
-- TWW+ unified bank: character bank lives entirely in CharacterBankTab_1..6.
-- The legacy main-bank container (BANK_CONTAINER = -1) was removed in 11.0.
-- (Prior code had `Characterbanktab or -2` — lowercase 't' was never a valid
-- enum key, and -2 is unused container space, so it silently iterated 0 slots.)
local BANK_BAG_IDS = {
    BagIndex.CharacterBankTab_1 or 6,
    BagIndex.CharacterBankTab_2 or 7,
    BagIndex.CharacterBankTab_3 or 8,
    BagIndex.CharacterBankTab_4 or 9,
    BagIndex.CharacterBankTab_5 or 10,
    BagIndex.CharacterBankTab_6 or 11,
}
local WARBAND_BAG_IDS = {
    BagIndex.AccountBankTab_1 or 12,
    BagIndex.AccountBankTab_2 or 13,
    BagIndex.AccountBankTab_3 or 14,
    BagIndex.AccountBankTab_4 or 15,
    BagIndex.AccountBankTab_5 or 16,
}

----------------------------------------------------------------------
-- Categorize bank items
----------------------------------------------------------------------
local function CategorizeBank(bagList)
    local sorted = {}
    for cat in pairs(VB.CATEGORIES) do
        sorted[cat] = {}
    end

    for _, bag in ipairs(bagList) do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then
                local ok, category, markers = pcall(VB.CategorizeItem, VB, bag, slot)
                if ok and category then
                    sorted[category][#sorted[category] + 1] = { bag = bag, slot = slot, markers = markers or {} }
                else
                    sorted["Misc"][#sorted["Misc"] + 1] = { bag = bag, slot = slot, markers = {} }
                end
            end
        end
    end

    return sorted
end

local LayoutBank -- forward declaration

----------------------------------------------------------------------
-- Create bank item button (same pattern as bag buttons)
----------------------------------------------------------------------
local bankBtnCounter = 0
local function CreateBankButton(parent, bag, slot)
    bankBtnCounter = bankBtnCounter + 1
    local size = VB:GetConfig("iconSize")
    local name = "VoidBankBtn" .. bankBtnCounter
    local btn = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
    btn:SetSize(size, size)

    local border = btn:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0, 0.78, 1, 0.5)

    local bg = btn:CreateTexture(nil, "BORDER")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.08, 0.10, 0.92)
    btn.qualBorder = border

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", 1, -1)
    btn.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    btn.count = btn:CreateFontString(nil, "OVERLAY")
    VB:SetFont(btn.count, 11, "OUTLINE")
    btn.count:SetPoint("BOTTOMRIGHT", -2, 2)
    btn.count:SetJustifyH("RIGHT")

    btn.ilvlText = btn:CreateFontString(nil, "OVERLAY")
    VB:SetFont(btn.ilvlText, 10, "OUTLINE")
    btn.ilvlText:SetPoint("TOPLEFT", 2, -2)
    btn.ilvlText:SetTextColor(P.text[1], P.text[2], P.text[3])

    btn.learnMark = btn:CreateFontString(nil, "OVERLAY")
    VB:SetFont(btn.learnMark, 12, "OUTLINE")
    btn.learnMark:SetPoint("TOP", 0, -1)
    btn.learnMark:SetText("|cff00ff00L|r") --green
    btn.learnMark:Hide()

    btn.craftMark = btn:CreateFontString(nil, "OVERLAY")
    VB:SetFont(btn.craftMark, 12, "OUTLINE")
    btn.craftMark:SetPoint("TOP", 0, -1)
    btn.craftMark:SetText("|cff00ff00C|r")
    btn.craftMark:Hide()

    btn.trashMark = btn:CreateFontString(nil, "OVERLAY")
    VB:SetFont(btn.trashMark, 12, "OUTLINE")
    btn.trashMark:SetPoint("TOP", 0, -1)
    btn.trashMark:SetText("|cff00ff00T|r")
    btn.trashMark:Hide()

    btn.upgradeMark = btn:CreateFontString(nil, "OVERLAY")
    VB:SetFont(btn.upgradeMark, 14, "OUTLINE")
    btn.upgradeMark:SetPoint("TOPLEFT", -1, 2)
    btn.upgradeMark:SetText("|cff00ff00^|r")
    btn.upgradeMark:Hide()

    btn.ahMark = btn:CreateFontString(nil, "OVERLAY")
    VB:SetFont(btn.ahMark, 9, "OUTLINE")
    btn.ahMark:SetPoint("BOTTOMLEFT", 2, 2)
    btn.ahMark:SetTextColor(0, 1, 0)
    btn.ahMark:Hide()

    btn.cooldown = CreateFrame("Cooldown", name .. "CD", btn, "CooldownFrameTemplate")
    btn.cooldown:SetAllPoints(btn.icon)
    btn.cooldown:SetDrawEdge(false)

    btn.bag = bag
    btn.slot = slot
    btn.hasItem = false

    btn.SplitStack = function(self, amount)
        C_Container.SplitContainerItem(self.bag, self.slot, amount)
    end

    -- Middle-click protection toggle is handled directly in the button's
    -- OnClick HookScript below (no overlay needed). The overlay caused
    -- click-propagation conflicts that blocked left/right clicks.

    -- Click semantics — mirrors VoidBags.lua main bag layout:
    --   Left            = pick up / place           (Lua)
    --   Right           = USE item                  (SECURE macro — required
    --                                                for equipment)
    --   Ctrl+Right      = split stack               (Lua, secure cleared)
    --   Shift+Right     = dress-up preview          (Lua, secure cleared)
    --   Ctrl+Left       = compare                   (Lua via HandleModifiedItemClick)
    --   Middle          = toggle item protection    (Lua)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetAttribute("type2", "macro")
    btn:SetAttribute("macrotext2", "/use " .. bag .. " " .. slot)
    btn:SetAttribute("shift-type2", "")
    btn:SetAttribute("ctrl-type2", "")
    btn:SetAttribute("alt-type2", "")

    btn:HookScript("OnClick", function(self, button)
        -- Middle-click: toggle protection
        if button == "MiddleButton" then
            local info = C_Container.GetContainerItemInfo(self.bag, self.slot)
            if info and info.itemID then
                VoidBagsDB.protected = VoidBagsDB.protected or {}
                if VoidBagsDB.protected[info.itemID] then
                    VoidBagsDB.protected[info.itemID] = nil
                    local itemName = C_Item.GetItemNameByID(info.itemID) or "item"
                    print(VB.C_CYAN .. "[VoidBags]|r Unprotected: " .. itemName)
                else
                    VoidBagsDB.protected[info.itemID] = true
                    local itemName = C_Item.GetItemNameByID(info.itemID) or "item"
                    print(VB.C_CYAN .. "[VoidBags]|r Protected: " .. itemName ..
                        " — will never be marked T or auto-sold.")
                end
                if bankIsOpen and bankFrame then
                    C_Timer.After(0.1, function()
                        LayoutBank(bankFrame.activeTab == "warband" and WARBAND_BAG_IDS or BANK_BAG_IDS)
                    end)
                end
            end
            return
        end

        -- Cursor has item → place it
        if CursorHasItem() then
            C_Container.PickupContainerItem(self.bag, self.slot)
            return
        end

        local info = C_Container.GetContainerItemInfo(self.bag, self.slot)
        if not info then return end

        if button == "RightButton" then
            if IsShiftKeyDown() then
                local link = C_Container.GetContainerItemLink(self.bag, self.slot)
                if link then DressUpItemLink(link) end
                return
            end
            if IsControlKeyDown() and (info.stackCount or 0) > 1 then
                if VB.ShowSplitPrompt then
                    if VB.ShowSplitPrompt(info.stackCount, self, "BOTTOMLEFT", "TOPLEFT",
                                           self.bag, self.slot) then
                        return
                    end
                end
            end
            -- Plain right-click handled by secure macro (set via SetAttribute)
            return
        end

        -- Left button: modified clicks (dress-up, compare, chat-link, etc)
        if IsModifiedClick() then
            local link = C_Container.GetContainerItemLink(self.bag, self.slot)
            if link and HandleModifiedItemClick(link) then return end
        end

        C_Container.PickupContainerItem(self.bag, self.slot)
    end)
    btn:SetScript("OnDragStart", function(self)
        C_Container.PickupContainerItem(self.bag, self.slot)
    end)
    btn:SetScript("OnReceiveDrag", function(self)
        C_Container.PickupContainerItem(self.bag, self.slot)
    end)

    btn:SetScript("OnDragStart", function(self)
        C_Container.PickupContainerItem(self.bag, self.slot)
    end)
    btn:SetScript("OnReceiveDrag", function(self)
        C_Container.PickupContainerItem(self.bag, self.slot)
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetBagItem(self.bag, self.slot)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return btn
end

----------------------------------------------------------------------
-- Update bank button (reuse logic from bags)
----------------------------------------------------------------------
local function UpdateBankButton(btn, bag, slot, markers)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info then
        btn.icon:SetTexture(nil)
        btn.count:SetText("")
        btn.ilvlText:SetText("")
        btn.learnMark:Hide()
        btn.craftMark:Hide()
        btn.trashMark:Hide()
        btn.upgradeMark:Hide()
        btn.ahMark:Hide()
        btn.qualBorder:SetColorTexture(0, 0.78, 1, 0.3)
        btn.hasItem = false
        return
    end

    btn.hasItem = true
    btn.icon:SetTexture(info.iconFileID)
    btn.icon:SetDesaturated(info.isLocked)

    if info.stackCount and info.stackCount > 1 then
        btn.count:SetText(info.stackCount)
    else
        btn.count:SetText("")
    end

    local quality = info.quality or 0
    local qc = VB.QUALITY_COLORS[quality]
    if qc and quality > 1 then
        btn.qualBorder:SetColorTexture(qc[1], qc[2], qc[3], 0.8)
    else
        btn.qualBorder:SetColorTexture(0.15, 0.15, 0.15, 1)
    end

    markers = markers or {}

    if markers.ilvl and VB:GetConfig("showItemLevel") then
        btn.ilvlText:SetText(markers.ilvl)
        local qcI = VB.QUALITY_COLORS[quality] or P.text
        btn.ilvlText:SetTextColor(qcI[1], qcI[2], qcI[3])
    else
        btn.ilvlText:SetText("")
    end

    if VB:GetConfig("showMarkers") then
        if markers.learnable then
            btn.learnMark:Show() btn.craftMark:Hide() btn.trashMark:Hide()
        elseif markers.craftable then
            btn.learnMark:Hide() btn.craftMark:Show() btn.trashMark:Hide()
        elseif markers.trash then
            btn.learnMark:Hide() btn.craftMark:Hide() btn.trashMark:Show()
        else
            btn.learnMark:Hide() btn.craftMark:Hide() btn.trashMark:Hide()
        end
        if markers.upgrade then btn.upgradeMark:Show() else btn.upgradeMark:Hide() end
    else
        btn.learnMark:Hide() btn.craftMark:Hide() btn.trashMark:Hide() btn.upgradeMark:Hide()
    end

    if VB:GetConfig("showAHValue") and markers.ahValue then
        btn.ahMark:SetText(VB:FormatMoney(markers.ahValue))
        btn.ahMark:Show()
    else
        btn.ahMark:Hide()
    end
end

----------------------------------------------------------------------
-- Create section header for bank
----------------------------------------------------------------------
local function CreateBankSectionFrame(parent, catKey)
    local catInfo = VB.CATEGORIES[catKey]
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(20)

    local label = f:CreateFontString(nil, "OVERLAY")
    VB:SetFont(label, 11, "OUTLINE")
    label:SetPoint("LEFT", 4, 0)
    label:SetTextColor(catInfo.color[1], catInfo.color[2], catInfo.color[3])
    label:SetText(catInfo.label)
    f.label = label

    local countText = f:CreateFontString(nil, "OVERLAY")
    VB:SetFont(countText, 9, "")
    countText:SetPoint("RIGHT", -4, 0)
    countText:SetTextColor(P.textDim[1], P.textDim[2], P.textDim[3])
    f.countText = countText

    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    line:SetTexture("Interface\\Buttons\\WHITE8X8")
    line:SetVertexColor(catInfo.color[1], catInfo.color[2], catInfo.color[3], 0.3)

    return f
end

----------------------------------------------------------------------
-- Layout bank content — categorized + empty slots
----------------------------------------------------------------------
local function ClearBankButton(btn)
    btn.icon:SetTexture(nil)
    btn.count:SetText("")
    btn.ilvlText:SetText("")
    btn.learnMark:Hide()
    btn.craftMark:Hide()
    btn.trashMark:Hide()
    btn.upgradeMark:Hide()
    btn.ahMark:Hide()
    btn.qualBorder:SetColorTexture(0, 0.78, 1, 0.3)
    btn.hasItem = false
end

LayoutBank = function(bagList)
    if not bankFrame then return end

    local columns = VB:GetConfig("columns")
    local iconSize = VB:GetConfig("iconSize")
    local spacing = VB:GetConfig("spacing")
    local sectionSpacing = VB:GetConfig("sectionSpacing")
    local contentParent = bankFrame.content

    -- Hide all existing buttons and sections
    for _, btns in pairs(bankSectionButtons) do
        for _, btn in ipairs(btns) do btn:Hide() end
    end
    for _, sf in pairs(bankSections) do sf:Hide() end

    -- Categorize bank items
    local sorted = CategorizeBank(bagList)

    -- Collect empty slots
    local emptySlots = {}
    for _, bag in ipairs(bagList) do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            if not C_Container.GetContainerItemInfo(bag, slot) then
                emptySlots[#emptySlots + 1] = { bag = bag, slot = slot }
            end
        end
    end

    local yOffset = 0
    local totalWidth = columns * (iconSize + spacing) - spacing
    local sortOrder = VB:GetConfig("sortOrder")
    local totalItems = 0

    -- Render each category with header
    for _, catKey in ipairs(sortOrder) do
        local items = sorted[catKey]
        if items and #items > 0 then
            totalItems = totalItems + #items

            if not bankSections[catKey] then
                bankSections[catKey] = CreateBankSectionFrame(contentParent, catKey)
            end
            local sf = bankSections[catKey]
            sf:SetWidth(totalWidth)
            sf:ClearAllPoints()
            sf:SetPoint("TOPLEFT", contentParent, "TOPLEFT", 0, -yOffset)
            sf.countText:SetText(#items)
            sf:Show()
            yOffset = yOffset + 22

            if not bankSectionButtons[catKey] then
                bankSectionButtons[catKey] = {}
            end
            local btns = bankSectionButtons[catKey]

            for i, itemData in ipairs(items) do
                if not btns[i] then
                    btns[i] = CreateBankButton(contentParent, 0, 0)
                end
                local btn = btns[i]
                btn.bag = itemData.bag
                btn.slot = itemData.slot
                if not InCombatLockdown() then pcall(btn.SetAttribute, btn, "macrotext2", "/use " .. itemData.bag .. " " .. itemData.slot) end

                local col = (i - 1) % columns
                local row = math.floor((i - 1) / columns)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", contentParent, "TOPLEFT", col * (iconSize + spacing), -(yOffset + row * (iconSize + spacing)))
                btn:SetSize(iconSize, iconSize)

                UpdateBankButton(btn, itemData.bag, itemData.slot, itemData.markers)
                btn:Show()
            end

            for i = #items + 1, #btns do
                btns[i]:Hide()
            end

            local rows = math.ceil(#items / columns)
            yOffset = yOffset + rows * (iconSize + spacing) + sectionSpacing
        end
    end

    -- Empty slots section at bottom
    if #emptySlots > 0 then
        local catKey = "Empty"
        if not bankSections[catKey] then
            local sf = CreateFrame("Frame", nil, contentParent)
            sf:SetHeight(20)
            local label = sf:CreateFontString(nil, "OVERLAY")
            VB:SetFont(label, 11, "OUTLINE")
            label:SetPoint("LEFT", 4, 0)
            label:SetTextColor(P.textDark[1], P.textDark[2], P.textDark[3])
            label:SetText("Empty")
            sf.label = label
            local countText = sf:CreateFontString(nil, "OVERLAY")
            VB:SetFont(countText, 9, "")
            countText:SetPoint("RIGHT", -4, 0)
            countText:SetTextColor(P.textDim[1], P.textDim[2], P.textDim[3])
            sf.countText = countText
            local line = sf:CreateTexture(nil, "ARTWORK")
            line:SetHeight(1)
            line:SetPoint("BOTTOMLEFT", 0, 0)
            line:SetPoint("BOTTOMRIGHT", 0, 0)
            line:SetTexture("Interface\\Buttons\\WHITE8X8")
            line:SetVertexColor(P.textDark[1], P.textDark[2], P.textDark[3], 0.3)
            bankSections[catKey] = sf
        end
        local sf = bankSections[catKey]
        sf:SetWidth(totalWidth)
        sf:ClearAllPoints()
        sf:SetPoint("TOPLEFT", contentParent, "TOPLEFT", 0, -yOffset)
        sf.countText:SetText(#emptySlots .. " free")
        sf:Show()
        yOffset = yOffset + 22

        if not bankSectionButtons[catKey] then
            bankSectionButtons[catKey] = {}
        end
        local btns = bankSectionButtons[catKey]

        for i, slotData in ipairs(emptySlots) do
            if not btns[i] then
                btns[i] = CreateBankButton(contentParent, 0, 0)
            end
            local btn = btns[i]
            btn.bag = slotData.bag
            btn.slot = slotData.slot
            if not InCombatLockdown() then pcall(btn.SetAttribute, btn, "macrotext2", "") end

            local col = (i - 1) % columns
            local row = math.floor((i - 1) / columns)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", contentParent, "TOPLEFT", col * (iconSize + spacing), -(yOffset + row * (iconSize + spacing)))
            btn:SetSize(iconSize, iconSize)

            ClearBankButton(btn)
            btn:Show()
        end

        for i = #emptySlots + 1, #btns do
            btns[i]:Hide()
        end

        local rows = math.ceil(#emptySlots / columns)
        yOffset = yOffset + rows * (iconSize + spacing) + sectionSpacing
    end

    contentParent:SetHeight(math.max(yOffset, 100))

    if bankFrame.scroll then
        bankFrame.scroll:SetVerticalScroll(0)
    end

    -- Empty message if no items AND no slots
    if totalItems == 0 and #emptySlots == 0 then
        if not bankFrame.emptyText then
            bankFrame.emptyText = bankFrame.content:CreateFontString(nil, "OVERLAY")
            VB:SetFont(bankFrame.emptyText, 12, "")
            bankFrame.emptyText:SetPoint("CENTER", bankFrame.content, "TOP", 0, -60)
        end
        bankFrame.emptyText:SetText(VB.C_DIM .. "No items in this tab.|r")
        bankFrame.emptyText:Show()
    elseif bankFrame.emptyText then
        bankFrame.emptyText:Hide()
    end
end

----------------------------------------------------------------------
-- Create bank frame
----------------------------------------------------------------------
local function CreateBankFrame()
    if bankFrame then return bankFrame end

    local f = CreateFrame("Frame", "VoidBagsBankFrame", UIParent, "BackdropTemplate")
    f:SetSize(560, 650)
    f:SetPoint("LEFT", UIParent, "LEFT", 20, 0)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(100)
    f:EnableMouse(true)
    VB:CreateBackdrop(f, "transparent")

    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(300, 300, 900, 900)
    end

    if VoidBagsDB and VoidBagsDB.config and VoidBagsDB.config.bankPosition then
        local pos = VoidBagsDB.config.bankPosition
        f:ClearAllPoints()
        f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    end

    -- Title bar
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
        VoidBagsDB.config.bankPosition = { point = point, relPoint = relPoint, x = x, y = y }
    end)

    local title = titleBar:CreateFontString(nil, "OVERLAY")
    VB:SetFont(title, 13, "OUTLINE")
    title:SetPoint("LEFT", 8, 0)
    title:SetText(VB.C_CYAN .. "VoidBags — Bank|r")
    f.titleText = title

    -- Close button
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("RIGHT", -6, 0)
    local closeTxt = closeBtn:CreateFontString(nil, "OVERLAY")
    VB:SetFont(closeTxt, 14, "OUTLINE")
    closeTxt:SetPoint("CENTER")
    closeTxt:SetText(VB.C_RED .. "X|r")
    closeBtn:SetScript("OnClick", function()
        if C_Bank and C_Bank.CloseBankFrame then
            C_Bank.CloseBankFrame()
        elseif BankFrame and BankFrame.CloseBank then
            BankFrame:CloseBank()
        end
        f:Hide()
        bankIsOpen = false
    end)

    -- Sort button
    local sortBtn = CreateFrame("Button", nil, titleBar, "BackdropTemplate")
    sortBtn:SetSize(50, 18)
    sortBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
    VB:CreateBackdrop(sortBtn, "section")
    local sortTxt = sortBtn:CreateFontString(nil, "OVERLAY")
    VB:SetFont(sortTxt, 10, "")
    sortTxt:SetPoint("CENTER")
    sortTxt:SetText(VB.C_DIM .. "Sort|r")
    sortBtn:SetScript("OnClick", function()
        -- Gate on C_Bank.IsBankUIInteractionAllowed to avoid client errors when
        -- the bank window closed mid-action (e.g., user walks away from banker).
        if C_Bank and C_Bank.IsBankUIInteractionAllowed
           and not C_Bank.IsBankUIInteractionAllowed() then
            return
        end
        if f.activeTab == "warband" then
            if C_Container.SortAccountBankBags then
                C_Container.SortAccountBankBags()
            end
        else
            if C_Container.SortBankBags then
                C_Container.SortBankBags()
            end
        end
        C_Timer.After(0.5, function()
            if bankIsOpen then
                LayoutBank(f.activeTab == "warband" and WARBAND_BAG_IDS or BANK_BAG_IDS)
            end
        end)
    end)

    -- Tab: Bank / Warband
    local bankTabBtn = CreateFrame("Button", nil, titleBar, "BackdropTemplate")
    bankTabBtn:SetSize(60, 18)
    bankTabBtn:SetPoint("RIGHT", sortBtn, "LEFT", -4, 0)
    VB:CreateBackdrop(bankTabBtn, "section")
    local bankTabTxt = bankTabBtn:CreateFontString(nil, "OVERLAY")
    VB:SetFont(bankTabTxt, 10, "")
    bankTabTxt:SetPoint("CENTER")
    bankTabTxt:SetText(VB.C_CYAN .. "Bank|r")
    f.bankTabBtn = bankTabBtn

    local warbandTabBtn = CreateFrame("Button", nil, titleBar, "BackdropTemplate")
    warbandTabBtn:SetSize(70, 18)
    warbandTabBtn:SetPoint("RIGHT", bankTabBtn, "LEFT", -4, 0)
    VB:CreateBackdrop(warbandTabBtn, "section")
    local warbandTabTxt = warbandTabBtn:CreateFontString(nil, "OVERLAY")
    VB:SetFont(warbandTabTxt, 10, "")
    warbandTabTxt:SetPoint("CENTER")
    warbandTabTxt:SetText(VB.C_DIM .. "Warband|r")
    f.warbandTabBtn = warbandTabBtn

    -- Deposit Warband Items button — visible only on Warband tab.
    -- Calls Blizzard's auto-deposit API which moves any items with the
    -- "Warband Bound" / "Warband Equipment" flag from bags to warband bank.
    local depositBtn = CreateFrame("Button", nil, titleBar, "BackdropTemplate")
    depositBtn:SetSize(100, 18)
    depositBtn:SetPoint("RIGHT", warbandTabBtn, "LEFT", -4, 0)
    VB:CreateBackdrop(depositBtn, "section")
    local depositTxt = depositBtn:CreateFontString(nil, "OVERLAY")
    VB:SetFont(depositTxt, 10, "")
    depositTxt:SetPoint("CENTER")
    depositTxt:SetText(VB.C_GREEN .. "Deposit Warband|r")
    depositBtn:SetScript("OnClick", function()
        local bankType = (Enum and Enum.BankType and Enum.BankType.Account) or 2
        local ok, err = pcall(function()
            if C_Bank and C_Bank.AutoDepositItemsIntoBank then
                C_Bank.AutoDepositItemsIntoBank(bankType)
            end
        end)
        if ok then
            print(VB.C_CYAN .. "[VoidBags]|r Warband-tagged items deposited.")
        else
            print(VB.C_RED .. "[VoidBags]|r Deposit failed: " .. tostring(err) .. "|r")
        end
    end)
    depositBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Deposit Warband Items", 0, 0.78, 1)
        GameTooltip:AddLine("Moves all Warband-Bound / Warband Equipment items", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("from your bags into the Warband bank.", 0.9, 0.9, 0.9)
        GameTooltip:Show()
    end)
    depositBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    depositBtn:Hide()  -- only show on Warband tab
    f.depositBtn = depositBtn

    -- Move T to Bags button (anchored left of Deposit button)
    local moveTBtn = CreateFrame("Button", nil, titleBar, "BackdropTemplate")
    moveTBtn:SetSize(90, 18)
    moveTBtn:SetPoint("RIGHT", depositBtn, "LEFT", -4, 0)
    VB:CreateBackdrop(moveTBtn, "section")
    local moveTTxt = moveTBtn:CreateFontString(nil, "OVERLAY")
    VB:SetFont(moveTTxt, 10, "")
    moveTTxt:SetPoint("CENTER")
    moveTTxt:SetText(VB.C_DIM .. "T -> Bags|r")
    moveTBtn:SetScript("OnClick", function()
        local toMove = {}
        local bankBags = f.activeTab == "warband" and WARBAND_BAG_IDS or BANK_BAG_IDS
        for _, bankBag in ipairs(bankBags) do
            local numSlots = C_Container.GetContainerNumSlots(bankBag) or 0
            for slot = 1, numSlots do
                local info = C_Container.GetContainerItemInfo(bankBag, slot)
                if info then
                    local ok, cat, markers = pcall(VB.CategorizeItem, VB, bankBag, slot)
                    if ok and cat == "SellableReagents" and markers and markers.trash then
                        toMove[#toMove + 1] = { bag = bankBag, slot = slot }
                    end
                end
            end
        end

        if #toMove == 0 then
            print(VB.C_CYAN .. "[VoidBags]|r No T-marked items to move.")
            return
        end

        -- Move items one at a time with delay so WoW processes each
        local idx = 0
        local function MoveNext()
            idx = idx + 1
            if idx > #toMove then
                print(VB.C_CYAN .. "[VoidBags]|r Moved " .. #toMove .. " vendor-trash items to bags. Visit a vendor to sell.")
                C_Timer.After(0.3, function()
                    if bankIsOpen then
                        LayoutBank(f.activeTab == "warband" and WARBAND_BAG_IDS or BANK_BAG_IDS)
                    end
                    VB:OpenBags()
                end)
                return
            end
            local item = toMove[idx]
            C_Container.UseContainerItem(item.bag, item.slot)
            C_Timer.After(0.05, MoveNext)
        end
        MoveNext()
    end)
    moveTBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Move to Bags", 0, 0.78, 1)
        GameTooltip:AddLine("Moves all T-marked (vendor trash) items", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("from bank to your bags for selling.", 0.9, 0.9, 0.9)
        GameTooltip:Show()
    end)
    moveTBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Bound the title's right edge to the left of the button cluster so a long
    -- title ("VoidBags — Warband Bank") can never overlap "T -> Bags" on a
    -- narrow window. Single-line, left-justified, truncates instead of bleeding.
    title:SetPoint("RIGHT", moveTBtn, "LEFT", -8, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)

    f.activeTab = "bank"

    bankTabBtn:SetScript("OnClick", function()
        f.activeTab = "bank"
        bankTabTxt:SetText(VB.C_CYAN .. "Bank|r")
        warbandTabTxt:SetText(VB.C_DIM .. "Warband|r")
        title:SetText(VB.C_CYAN .. "VoidBags — Bank|r")
        activeBankBagFilter = nil
        if f.depositBtn then f.depositBtn:Hide() end
        if f.BuildBagBar then f.BuildBagBar(BANK_BAG_IDS, "Bank") end
        LayoutBank(BANK_BAG_IDS)
    end)

    warbandTabBtn:SetScript("OnClick", function()
        f.activeTab = "warband"
        if f.depositBtn then f.depositBtn:Show() end
        bankTabTxt:SetText(VB.C_DIM .. "Bank|r")
        warbandTabTxt:SetText(VB.C_CYAN .. "Warband|r")
        title:SetText(VB.C_CYAN .. "VoidBags — Warband Bank|r")
        activeBankBagFilter = nil
        if C_Bank and C_Bank.FetchPurchasedBankTabData then
            pcall(C_Bank.FetchPurchasedBankTabData, Enum.BankType and Enum.BankType.Account or 2)
        end
        if f.BuildBagBar then f.BuildBagBar(WARBAND_BAG_IDS, "Warband") end
        LayoutBank(WARBAND_BAG_IDS)
    end)

    -- Search box
    local bankSearchBox = CreateFrame("EditBox", "VoidBagsBankSearch", f, "SearchBoxTemplate")
    bankSearchBox:SetSize(200, 20)
    bankSearchBox:SetPoint("TOPLEFT", 8, -30)
    bankSearchBox:SetAutoFocus(false)
    bankSearchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        if not text or text == "" then
            for _, btns in pairs(bankSectionButtons) do
                for _, btn in ipairs(btns) do
                    if btn:IsShown() then
                        btn.icon:SetDesaturated(false)
                        btn:SetAlpha(1)
                    end
                end
            end
            for _, sf in pairs(bankSections) do
                if sf:IsShown() then sf:SetAlpha(1) end
            end
            return
        end
        text = text:lower()
        for catKey, btns in pairs(bankSectionButtons) do
            local anyMatch = false
            for _, btn in ipairs(btns) do
                if btn:IsShown() and btn.hasItem then
                    local link = C_Container.GetContainerItemLink(btn.bag, btn.slot)
                    -- Parse name from link to avoid stricter C_Item.GetItemNameByID
                    -- signature in 12.0.X — also works for Keystones/dynamic items.
                    local name = link and link:match("%[(.-)%]") or ""
                    if name and name:lower():find(text, 1, true) then
                        btn.icon:SetDesaturated(false)
                        btn:SetAlpha(1)
                        anyMatch = true
                    else
                        btn.icon:SetDesaturated(true)
                        btn:SetAlpha(0.3)
                    end
                end
            end
            if bankSections[catKey] then
                bankSections[catKey]:SetAlpha(anyMatch and 1 or 0.3)
            end
        end
    end)
    bankSearchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    f.searchBox = bankSearchBox

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "VoidBagsBankScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, -54)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 42)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)
    f.content = content
    f.scroll = scrollFrame

    -- Bank bag bar
    local bankBagBar = CreateFrame("Frame", nil, f)
    bankBagBar:SetHeight(32)
    bankBagBar:SetPoint("BOTTOMLEFT", 8, 8)
    bankBagBar:SetPoint("BOTTOMRIGHT", -8, 8)
    f.bankBagBar = bankBagBar
    f.bankBagBtns = {}

    local activeBankBagFilter = nil

    local function BuildBagBar(bagList, label)
        -- Hide old buttons
        for _, btn in ipairs(f.bankBagBtns) do btn:Hide() end
        wipe(f.bankBagBtns)

        for i, bag in ipairs(bagList) do
            local numSlots = C_Container.GetContainerNumSlots(bag) or 0
            if numSlots > 0 then
                local bagBtn = CreateFrame("Button", nil, bankBagBar, "BackdropTemplate")
                bagBtn:SetSize(30, 30)
                bagBtn:SetPoint("LEFT", (#f.bankBagBtns) * 34, 0)
                VB:CreateBackdrop(bagBtn, "section")
                bagBtn._bagID = bag

                local bagIcon = bagBtn:CreateTexture(nil, "ARTWORK")
                bagIcon:SetPoint("TOPLEFT", 2, -2)
                bagIcon:SetPoint("BOTTOMRIGHT", -2, 2)
                bagIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                if bag <= 4 then
                    local invID = C_Container.ContainerIDToInventoryID(bag)
                    local texID = GetInventoryItemTexture("player", invID)
                    bagIcon:SetTexture(texID or "Interface\\Icons\\INV_Misc_Bag_07")
                else
                    bagIcon:SetTexture("Interface\\Icons\\INV_Misc_Bag_07")
                end

                bagBtn:RegisterForClicks("LeftButtonUp")
                bagBtn:SetScript("OnClick", function()
                    if activeBankBagFilter == bag then
                        activeBankBagFilter = nil
                        local allBtns = bankSectionButtons["all"] or {}
                        for _, btn in ipairs(allBtns) do
                            if btn:IsShown() then
                                btn:SetAlpha(1)
                                btn.icon:SetDesaturated(false)
                            end
                        end
                    else
                        activeBankBagFilter = bag
                        local allBtns = bankSectionButtons["all"] or {}
                        for _, btn in ipairs(allBtns) do
                            if btn:IsShown() then
                                if btn.bag == bag then
                                    btn:SetAlpha(1)
                                    btn.icon:SetDesaturated(false)
                                else
                                    btn:SetAlpha(0.3)
                                    btn.icon:SetDesaturated(true)
                                end
                            end
                        end
                    end
                end)

                bagBtn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(label .. " Tab " .. i, P.accent[1], P.accent[2], P.accent[3])
                    local slots = C_Container.GetContainerNumSlots(bag) or 0
                    local free = C_Container.GetContainerNumFreeSlots(bag) or 0
                    GameTooltip:AddLine((slots - free) .. "/" .. slots .. " used", P.textDim[1], P.textDim[2], P.textDim[3])
                    GameTooltip:AddLine("Click to filter this tab", P.textDim[1], P.textDim[2], P.textDim[3])
                    GameTooltip:Show()
                end)
                bagBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

                f.bankBagBtns[#f.bankBagBtns + 1] = bagBtn
                bagBtn:Show()
            end
        end
    end

    f.BuildBagBar = BuildBagBar

    -- Resize handle
    local resizer = CreateFrame("Button", nil, f)
    resizer:SetSize(16, 16)
    resizer:SetPoint("BOTTOMRIGHT", -2, 2)
    resizer:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizer:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizer:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizer:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    resizer:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        VoidBagsDB.config.bankSize = { w = f:GetWidth(), h = f:GetHeight() }
        if f.activeTab == "bank" then
            LayoutBank(BANK_BAG_IDS)
        end
    end)

    f:Hide()
    bankFrame = f
    return f
end

----------------------------------------------------------------------
-- Bank open/close hooks
----------------------------------------------------------------------
local function OnBankOpened()
    if not bankFrame then CreateBankFrame() end
    VB:UpdateProfessions()

    -- Fetch bank tab data
    if C_Bank and C_Bank.FetchPurchasedBankTabData then
        pcall(C_Bank.FetchPurchasedBankTabData, Enum.BankType and Enum.BankType.Character or 0)
        pcall(C_Bank.FetchPurchasedBankTabData, Enum.BankType and Enum.BankType.Account or 2)
    end

    bankFrame.activeTab = "bank"
    bankFrame:Show()
    bankIsOpen = true

    -- Delay slightly to let bank data load
    C_Timer.After(0.3, function()
        if bankIsOpen then
            if bankFrame.BuildBagBar then
                bankFrame.BuildBagBar(BANK_BAG_IDS, "Bank")
            end
            LayoutBank(BANK_BAG_IDS)
        end
    end)

    -- Also open bags
    VB:OpenBags()
end

local function OnBankClosed()
    if bankFrame then bankFrame:Hide() end
    bankIsOpen = false
end

----------------------------------------------------------------------
-- Warband bank snapshot (for cross-char viewing)
----------------------------------------------------------------------
local function SnapshotWarbandBank()
    if not VoidBagsDB then return end
    VoidBagsDB.warband = VoidBagsDB.warband or {}
    VoidBagsDB.warband.items = {}
    VoidBagsDB.warband.timestamp = time()

    local warbandBags = WARBAND_BAG_IDS

    for _, bag in ipairs(warbandBags) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then
                local link = C_Container.GetContainerItemLink(bag, slot)
                VoidBagsDB.warband.items[#VoidBagsDB.warband.items + 1] = {
                    id = info.itemID,
                    count = info.stackCount,
                    link = link,
                    name = C_Item.GetItemNameByID(info.itemID),
                    quality = info.quality,
                }
            end
        end
    end
end

----------------------------------------------------------------------
-- Bank events
----------------------------------------------------------------------
local bankEf = CreateFrame("Frame")
bankEf:RegisterEvent("BANKFRAME_OPENED")
bankEf:RegisterEvent("BANKFRAME_CLOSED")
bankEf:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
bankEf:RegisterEvent("BAG_UPDATE")
bankEf:RegisterEvent("BAG_UPDATE_DELAYED")
pcall(function() bankEf:RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED") end)
pcall(function() bankEf:RegisterEvent("BANK_BAG_SLOT_FLAGS_UPDATED") end)
pcall(function() bankEf:RegisterEvent("PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED") end)

local function RefreshBank()
    if not bankIsOpen or not bankFrame then return end
    if bankRefreshTimer then bankRefreshTimer:Cancel() end
    bankRefreshTimer = C_Timer.NewTimer(0.15, function()
        if bankIsOpen and bankFrame then
            LayoutBank(bankFrame.activeTab == "warband" and WARBAND_BAG_IDS or BANK_BAG_IDS)
        end
    end)
end

bankEf:SetScript("OnEvent", function(_, event)
    if event == "BANKFRAME_OPENED" then
        OnBankOpened()
        SnapshotWarbandBank()
        return
    end

    if event == "BANKFRAME_CLOSED" then
        OnBankClosed()
        return
    end

    -- Any bag/bank change while bank is open — refresh
    if bankIsOpen then
        RefreshBank()
    end
end)

----------------------------------------------------------------------
-- Hide Blizzard bank frame (move off-screen, don't actually Hide()
-- because hiding it tells the game the bank is closed)
----------------------------------------------------------------------
local function HideBlizzardBank()
    if BankFrame then
        BankFrame:SetAlpha(0)
        BankFrame:ClearAllPoints()
        BankFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -5000, 0)
        BankFrame:EnableMouse(false)
    end
end

local bankHideHooked = false
local bankHideEf = CreateFrame("Frame")
bankHideEf:RegisterEvent("BANKFRAME_OPENED")
bankHideEf:SetScript("OnEvent", function()
    if not bankHideHooked then
        C_Timer.After(0.05, HideBlizzardBank)
        bankHideHooked = true
    else
        HideBlizzardBank()
    end
end)
