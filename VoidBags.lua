----------------------------------------------------------------------
-- VoidBags: Main — bag frame, buttons, layout, markers
----------------------------------------------------------------------
-- VoidSpy hook: enable with /vspy enable VoidBags  (no-op if VoidSpy missing/disabled)
local function dbg(fmt, ...) if VoidSpy and VoidSpy.Log then VoidSpy:Log("VoidBags", fmt, ...) end end

local _, VB = ...

-- Open Blizzard's stack-split prompt with multiple compatibility paths.
-- Midnight 12.0.5 removed the OpenStackSplitFrame() global; the method form
-- on StackSplitFrame is what survived. If both are missing, fall back to a
-- StaticPopup with a numeric input. Returns true on success.
local function ShowSplitPrompt(stackCount, anchorFrame, anchorPoint, relativePoint, bag, slot)
    if type(_G.OpenStackSplitFrame) == "function" then
        _G.OpenStackSplitFrame(stackCount, anchorFrame, anchorPoint, relativePoint)
        return true
    end
    if StackSplitFrame and type(StackSplitFrame.OpenStackSplitFrame) == "function" then
        StackSplitFrame:OpenStackSplitFrame(stackCount, anchorFrame, anchorPoint, relativePoint)
        return true
    end
    -- Final fallback: StaticPopup with numeric input.
    StaticPopupDialogs["VOIDBAGS_SPLIT_STACK"] = StaticPopupDialogs["VOIDBAGS_SPLIT_STACK"] or {
        text = "Split how many of %d? (1-%d)",
        button1 = "Split",
        button2 = "Cancel",
        hasEditBox = true,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = STATICPOPUP_NUMDIALOGS,
        OnAccept = function(self, data)
            local n = tonumber((self.editBox:GetText()) or "")
            if n and data and data.bag and data.slot and n > 0 and n < (data.max or 0) then
                C_Container.SplitContainerItem(data.bag, data.slot, n)
            end
        end,
        EditBoxOnEnterPressed = function(self) self:GetParent().button1:Click() end,
        OnShow = function(self) self.editBox:SetFocus() end,
    }
    local data = { bag = bag, slot = slot, max = stackCount }
    local popup = StaticPopup_Show("VOIDBAGS_SPLIT_STACK", stackCount - 1, stackCount, data)
    if popup then popup.data = data end
    return popup ~= nil
end

-- Expose for Bank.lua (single source of truth for the prompt logic)
VB.ShowSplitPrompt = ShowSplitPrompt

local FONT = VB.FONT
local P = VB.palette
local REAGENT_BAG = Enum.BagIndex and Enum.BagIndex.ReagentBag or 5
local ALL_BAGS = { 0, 1, 2, 3, 4, REAGENT_BAG }

----------------------------------------------------------------------
-- Main bag frame
----------------------------------------------------------------------
local bagFrame
local bagButtons = {}      -- [bag][slot] = button
local sectionFrames = {}   -- [category] = frame
local sectionButtons = {}  -- [category] = { button, button, ... }
VB._sectionButtons = sectionButtons
local categoryCache = {}   -- [bag][slot] = { category, markers }
local bagBar
local searchBox
local goldText
local slotText
local charDropdown
local crossCharFrame
local isOpen = false
local refreshTimer
local layoutDirty = true
local pendingRefresh = false  -- hoisted: referenced by OpenBags/CloseBags + LayoutBags

----------------------------------------------------------------------
-- Create item button
----------------------------------------------------------------------
local btnCounter = 0
local function CreateItemButton(parent, bag, slot)
    btnCounter = btnCounter + 1
    local size = VB:GetConfig("iconSize")
    local name = "VoidBagsBtn" .. btnCounter
    local btn = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
    btn:SetSize(size, size)

    -- Border (behind everything, extends 1px beyond button)
    local border = btn:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0, 0.78, 1, 0.5)

    -- Dark fill (covers interior, leaving 1px border visible)
    local bg = btn:CreateTexture(nil, "BORDER")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.08, 0.10, 0.92)
    btn.qualBorder = border

    -- Icon
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", 1, -1)
    btn.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Stack count
    btn.count = btn:CreateFontString(nil, "OVERLAY")
    VB:SetFont(btn.count, 11, "OUTLINE")
    btn.count:SetPoint("BOTTOMRIGHT", -2, 2)
    btn.count:SetJustifyH("RIGHT")

    -- Item level
    btn.ilvlText = btn:CreateFontString(nil, "OVERLAY")
    VB:SetFont(btn.ilvlText, 10, "OUTLINE")
    btn.ilvlText:SetPoint("TOPLEFT", 2, -2)
    btn.ilvlText:SetTextColor(P.text[1], P.text[2], P.text[3])

    -- Markers (L/C/T/$/A/P)
    btn.learnMark = btn:CreateFontString(nil, "OVERLAY")
    VB:SetFont(btn.learnMark, 12, "OUTLINE")
    btn.learnMark:SetPoint("TOP", 0, -1)
    btn.learnMark:SetText("|cff00ff00L|r")
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

    btn.sellAHMark = btn:CreateFontString(nil, "OVERLAY")
    VB:SetFont(btn.sellAHMark, 12, "OUTLINE")
    btn.sellAHMark:SetPoint("TOP", 0, -1)
    btn.sellAHMark:SetText("|cff00ff00$|r")
    btn.sellAHMark:Hide()

    btn.altMark = btn:CreateFontString(nil, "OVERLAY")
    VB:SetFont(btn.altMark, 12, "OUTLINE")
    btn.altMark:SetPoint("TOP", 0, -1)
    btn.altMark:SetText("|cff00ff00A|r")
    btn.altMark:Hide()

    btn.protectedMark = btn:CreateFontString(nil, "OVERLAY")
    VB:SetFont(btn.protectedMark, 12, "OUTLINE")
    btn.protectedMark:SetPoint("TOP", 0, -1)
    btn.protectedMark:SetText("|cff00ff00P|r")
    btn.protectedMark:Hide()

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

    -- Cooldown
    btn.cooldown = CreateFrame("Cooldown", name .. "CD", btn, "CooldownFrameTemplate")
    btn.cooldown:SetAllPoints(btn.icon)
    btn.cooldown:SetDrawEdge(false)

    btn.bag = bag
    btn.slot = slot

    -- Required by StackSplitFrame
    btn.SplitStack = function(self, amount)
        C_Container.SplitContainerItem(self.bag, self.slot, amount)
    end

    -- Protection toggle moved to /vb protect command (overlay caused scroll wheel issues)

    -- Click semantics:
    --   Left-click             = pick up / place        (Lua)
    --   Right-click            = USE item               (SECURE macro — required
    --                                                    for equipment, can't be
    --                                                    done from Lua without
    --                                                    AddOnActionBlocked)
    --   Ctrl+Right-click       = split stack            (Lua, secure cleared)
    --   Shift+Right-click      = dress-up preview       (Lua, secure cleared)
    --   Ctrl+Left-click        = item compare           (Lua via HandleModifiedItemClick)
    --   Drag                   = pick up                (Lua)
    -- We use BOTH approaches because: plain right-click needs the secure
    -- /use macro (equipment is protected), but the modified-right variants
    -- need Lua handling. We clear shift-type2/ctrl-type2 so the secure macro
    -- doesn't fire on those modifiers; HookScript handles them instead.
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetAttribute("type2", "macro")
    btn:SetAttribute("macrotext2", "/use " .. bag .. " " .. slot)
    btn:SetAttribute("shift-type2", "")   -- shift+right handled in Lua (dressup)
    btn:SetAttribute("ctrl-type2", "")    -- ctrl+right handled in Lua (split)
    btn:SetAttribute("alt-type2", "")

    btn:HookScript("OnClick", function(self, button)
        -- Cursor has item → place it down here regardless of button
        if CursorHasItem() then
            C_Container.PickupContainerItem(self.bag, self.slot)
            return
        end

        local info = C_Container.GetContainerItemInfo(self.bag, self.slot)
        if not info then return end  -- empty slot

        if button == "RightButton" then
            -- Shift+Right = dress-up preview
            if IsShiftKeyDown() then
                local link = C_Container.GetContainerItemLink(self.bag, self.slot)
                if link then DressUpItemLink(link) end
                return
            end
            -- Ctrl+Right = split stack (Blizzard default SPLITSTACK bind)
            if IsControlKeyDown() and (info.stackCount or 0) > 1 then
                if ShowSplitPrompt(info.stackCount, self, "BOTTOMLEFT", "TOPLEFT",
                                    self.bag, self.slot) then
                    return
                end
            end
            -- Plain right-click: secure /use macro handles it (required for
            -- equipment items — Lua C_Container.UseContainerItem triggers
            -- AddOnActionBlocked for protected actions). Just return.
            return
        end

        -- Left button below — Ctrl/Shift modifiers handled by HandleModifiedItemClick
        -- (dress-up preview, chat-link, item compare, etc).
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

    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetBagItem(self.bag, self.slot)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return btn
end

-- Upgrade arrow fallback
UPGRADE_ATLAS_FALLBACK = "^"

----------------------------------------------------------------------
-- Update a single button
----------------------------------------------------------------------
local function UpdateButton(btn, bag, slot, markers)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info then
        btn.icon:SetTexture(nil)
        btn.count:SetText("")
        btn.ilvlText:SetText("")
        btn.learnMark:Hide()
        btn.craftMark:Hide()
        btn.trashMark:Hide()
        btn.sellAHMark:Hide()
        btn.altMark:Hide()
        btn.protectedMark:Hide()
        btn.upgradeMark:Hide()
        btn.ahMark:Hide()
        btn.qualBorder:Hide()
        btn.qualBorder:SetColorTexture(0, 0.78, 1, 0.3)
        btn.hasItem = false
        return
    end

    btn.hasItem = true
    btn.icon:SetTexture(info.iconFileID)
    btn.icon:SetDesaturated(info.isLocked)

    -- Stack count
    if info.stackCount and info.stackCount > 1 then
        btn.count:SetText(info.stackCount)
    else
        btn.count:SetText("")
    end

    -- Quality border
    local quality = info.quality or 0
    local qc = VB.QUALITY_COLORS[quality]
    if qc and quality > 1 then
        btn.qualBorder:SetColorTexture(qc[1], qc[2], qc[3], 0.8)
    else
        btn.qualBorder:SetColorTexture(0.15, 0.15, 0.15, 1)
    end

    -- Cooldown
    local start, duration, enable = C_Container.GetContainerItemCooldown(bag, slot)
    if start and duration and duration > 0 and enable == 1 then
        btn.cooldown:SetCooldown(start, duration)
        btn.cooldown:Show()
    else
        btn.cooldown:Hide()
    end

    -- Markers
    markers = markers or {}

    -- Item level
    if markers.ilvl and VB:GetConfig("showItemLevel") then
        btn.ilvlText:SetText(markers.ilvl)
        local qcI = VB.QUALITY_COLORS[quality] or VB.palette.text
        btn.ilvlText:SetTextColor(qcI[1], qcI[2], qcI[3])
        btn.ilvlText:Show()
    else
        btn.ilvlText:SetText("")
    end

    if VB:GetConfig("showMarkers") then
        -- Top marker priority: P > L > C > A > $ > T
        btn.learnMark:Hide()
        btn.craftMark:Hide()
        btn.trashMark:Hide()
        btn.sellAHMark:Hide()
        btn.altMark:Hide()
        btn.protectedMark:Hide()

        if markers.protected then
            btn.protectedMark:Show()
        elseif markers.learnable then
            btn.learnMark:Show()
        elseif markers.craftable then
            btn.craftMark:Show()
        elseif markers.altNeeds then
            btn.altMark:Show()
        elseif markers.sellAH then
            btn.sellAHMark:Show()
        elseif markers.trash then
            btn.trashMark:Show()
        end

        -- Upgrade
        if markers.upgrade then
            btn.upgradeMark:Show()
        else
            btn.upgradeMark:Hide()
        end
    else
        btn.learnMark:Hide()
        btn.craftMark:Hide()
        btn.trashMark:Hide()
        btn.sellAHMark:Hide()
        btn.altMark:Hide()
        btn.protectedMark:Hide()
        btn.upgradeMark:Hide()
    end

    -- AH value
    if VB:GetConfig("showAHValue") and markers.ahValue then
        btn.ahMark:SetText(VB:FormatMoney(markers.ahValue))
        btn.ahMark:Show()
    else
        btn.ahMark:Hide()
    end
end

----------------------------------------------------------------------
-- Categorize all bag items
----------------------------------------------------------------------
local function CategorizeAllItems()
    wipe(categoryCache)
    local sorted = {}
    for cat in pairs(VB.CATEGORIES) do
        sorted[cat] = {}
    end

    for _, bag in ipairs(ALL_BAGS) do
        categoryCache[bag] = categoryCache[bag] or {}
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then
                local category, markers = VB:CategorizeItem(bag, slot)
                category = category or "Misc"
                categoryCache[bag][slot] = { category = category, markers = markers or {} }
                sorted[category][#sorted[category] + 1] = { bag = bag, slot = slot, markers = markers or {} }
            end
        end
    end

    return sorted
end

----------------------------------------------------------------------
-- Create section header
----------------------------------------------------------------------
local function CreateSectionFrame(parent, catKey)
    local catInfo = VB.CATEGORIES[catKey]
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
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

    f.catKey = catKey
    return f
end

----------------------------------------------------------------------
-- Build / rebuild the bag layout — Option A: categorized + empty slots
----------------------------------------------------------------------
local function ClearButton(btn)
    btn.icon:SetTexture(nil)
    btn.count:SetText("")
    btn.ilvlText:SetText("")
    btn.learnMark:Hide()
    btn.craftMark:Hide()
    btn.trashMark:Hide()
    btn.sellAHMark:Hide()
    btn.altMark:Hide()
    btn.protectedMark:Hide()
    btn.upgradeMark:Hide()
    btn.ahMark:Hide()
    btn.qualBorder:SetColorTexture(0, 0.78, 1, 0.3)
    btn.hasItem = false
end

local function LayoutBags()
    dbg("LayoutBags ENTER dirty=%s", tostring(layoutDirty))
    if not bagFrame then return end

    local columns = VB:GetConfig("columns")
    local iconSize = VB:GetConfig("iconSize")
    local spacing = VB:GetConfig("spacing")
    local sectionSpacing = VB:GetConfig("sectionSpacing")
    local contentParent = bagFrame.content

    -- Hide all existing buttons and sections
    for _, btns in pairs(sectionButtons) do
        for _, btn in ipairs(btns) do btn:Hide() end
    end
    for _, sf in pairs(sectionFrames) do sf:Hide() end

    -- Categorize all items
    local sorted = CategorizeAllItems()

    -- Collect empty slots
    local emptySlots = {}
    for _, bag in ipairs(ALL_BAGS) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            if not C_Container.GetContainerItemInfo(bag, slot) then
                emptySlots[#emptySlots + 1] = { bag = bag, slot = slot }
            end
        end
    end

    local yOffset = 0
    local totalWidth = columns * (iconSize + spacing) - spacing
    local sortOrder = VB:GetConfig("sortOrder")

    -- Render each category with header
    for _, catKey in ipairs(sortOrder) do
        local items = sorted[catKey]
        if items and #items > 0 then
            -- Section header
            if not sectionFrames[catKey] then
                sectionFrames[catKey] = CreateSectionFrame(contentParent, catKey)
            end
            local sf = sectionFrames[catKey]
            sf:SetWidth(totalWidth)
            sf:ClearAllPoints()
            sf:SetPoint("TOPLEFT", contentParent, "TOPLEFT", 0, -yOffset)
            sf.countText:SetText(#items)
            sf:Show()
            yOffset = yOffset + 22

            if not sectionButtons[catKey] then
                sectionButtons[catKey] = {}
            end
            local btns = sectionButtons[catKey]

            for i, itemData in ipairs(items) do
                if not btns[i] then
                    btns[i] = CreateItemButton(contentParent, 0, 0)
                end
                local btn = btns[i]
                btn.bag = itemData.bag
                btn.slot = itemData.slot
                -- Update secure right-click macro to point at the new slot.
                -- SetAttribute is forbidden in combat for secure templates.
                if not InCombatLockdown() then
                    btn:SetAttribute("macrotext2", "/use " .. itemData.bag .. " " .. itemData.slot)
                end

                local col = (i - 1) % columns
                local row = math.floor((i - 1) / columns)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", contentParent, "TOPLEFT", col * (iconSize + spacing), -(yOffset + row * (iconSize + spacing)))
                btn:SetSize(iconSize, iconSize)

                UpdateButton(btn, itemData.bag, itemData.slot, itemData.markers)
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
        if not sectionFrames[catKey] then
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
            sectionFrames[catKey] = sf
        end
        local sf = sectionFrames[catKey]
        sf:SetWidth(totalWidth)
        sf:ClearAllPoints()
        sf:SetPoint("TOPLEFT", contentParent, "TOPLEFT", 0, -yOffset)
        sf.countText:SetText(#emptySlots .. " free")
        sf:Show()
        yOffset = yOffset + 22

        if not sectionButtons[catKey] then
            sectionButtons[catKey] = {}
        end
        local btns = sectionButtons[catKey]

        for i, slotData in ipairs(emptySlots) do
            if not btns[i] then
                btns[i] = CreateItemButton(contentParent, 0, 0)
            end
            local btn = btns[i]
            btn.bag = slotData.bag
            btn.slot = slotData.slot
            -- Empty slot: clear the secure /use macro (nothing to use).
            if not InCombatLockdown() then
                btn:SetAttribute("macrotext2", "")
            end

            local col = (i - 1) % columns
            local row = math.floor((i - 1) / columns)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", contentParent, "TOPLEFT", col * (iconSize + spacing), -(yOffset + row * (iconSize + spacing)))
            btn:SetSize(iconSize, iconSize)

            ClearButton(btn)
            btn:Show()
        end

        for i = #emptySlots + 1, #btns do
            btns[i]:Hide()
        end

        local rows = math.ceil(#emptySlots / columns)
        yOffset = yOffset + rows * (iconSize + spacing) + sectionSpacing
    end

    contentParent:SetHeight(math.max(yOffset, 100))

    -- Update slot count and gold
    local usedSlots, totalSlots = 0, 0
    for _, bag in ipairs(ALL_BAGS) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        local free = C_Container.GetContainerNumFreeSlots(bag)
        totalSlots = totalSlots + numSlots
        usedSlots = usedSlots + (numSlots - free)
    end
    if slotText then
        slotText:SetText(VB.C_DIM .. usedSlots .. "/" .. totalSlots .. "|r")
    end
    if goldText then
        goldText:SetText(VB:FormatMoney(GetMoney()))
    end

    layoutDirty = false
end

----------------------------------------------------------------------
-- Search filter
----------------------------------------------------------------------
local function ApplySearch(text)
    if not text or text == "" then
        for _, btns in pairs(sectionButtons) do
            for _, btn in ipairs(btns) do
                if btn:IsShown() then
                    btn.icon:SetDesaturated(false)
                    btn:SetAlpha(1)
                end
            end
        end
        for _, sf in pairs(sectionFrames) do
            if sf:IsShown() then sf:SetAlpha(1) end
        end
        return
    end

    text = text:lower()
    for catKey, btns in pairs(sectionButtons) do
        local anyMatch = false
        for _, btn in ipairs(btns) do
            if btn:IsShown() and btn.hasItem then
                local link = C_Container.GetContainerItemLink(btn.bag, btn.slot)
                -- Parse name from the link's [Name] segment directly. Avoids the
                -- new stricter C_Item.GetItemNameByID API (post-12.0.X patch)
                -- and works for Keystones/dynamic items that don't resolve via
                -- GetItemInfoInstant.
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
        if sectionFrames[catKey] then
            sectionFrames[catKey]:SetAlpha(anyMatch and 1 or 0.3)
        end
    end
end

----------------------------------------------------------------------
-- Auto-sell junk
----------------------------------------------------------------------
local function SellJunk(includeTrash)
    if not MerchantFrame or not MerchantFrame:IsShown() then
        print(VB.C_CYAN .. "[VoidBags]|r Open a vendor to sell junk.")
        return
    end

    local count, total = 0, 0
    for _, bag in ipairs(ALL_BAGS) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then
                local shouldSell = false
                -- Always sell grey junk
                if info.quality == 0 then
                    shouldSell = true
                end
                -- Also sell T-marked items if requested
                if includeTrash and not shouldSell then
                    local ok, cat, markers = pcall(VB.CategorizeItem, VB, bag, slot)
                    if ok and cat == "SellableReagents" and markers and markers.trash then
                        shouldSell = true
                    end
                end
                if shouldSell then
                    C_Container.UseContainerItem(bag, slot)
                    count = count + 1
                    -- info.itemID / stackCount can be secret values in tainted contexts; guard via VoidLib.
                    if info.itemID and not VoidLib.Secrets.IsSecret(info.itemID) then
                        local _, _, _, _, _, _, _, _, _, _, vendorPrice = C_Item.GetItemInfo(info.itemID)
                        local stack = info.stackCount or 1
                        if not VoidLib.Secrets.IsSecret(stack) then
                            total = total + (vendorPrice or 0) * stack
                        end
                    end
                end
            end
        end
    end

    if count > 0 then
        print(VB.C_CYAN .. "[VoidBags]|r Sold " .. count .. " junk items for " .. VB:FormatMoney(total))
    else
        print(VB.C_CYAN .. "[VoidBags]|r No junk to sell.")
    end
end

----------------------------------------------------------------------
-- Cross-character search panel
----------------------------------------------------------------------
local function CreateCrossCharFrame(parent)
    if crossCharFrame then return crossCharFrame end

    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(300, 200)
    f:SetPoint("TOPRIGHT", parent, "TOPLEFT", -4, 0)
    VB:CreateBackdrop(f)
    f:SetFrameStrata("HIGH")

    local title = f:CreateFontString(nil, "OVERLAY")
    VB:SetFont(title, 12, "OUTLINE")
    title:SetPoint("TOPLEFT", 8, -6)
    title:SetText(VB.C_CYAN .. "Other Characters|r")

    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(16, 16)
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetNormalFontObject(GameFontNormal)
    local closeTxt = closeBtn:CreateFontString(nil, "OVERLAY")
    VB:SetFont(closeTxt, 12, "OUTLINE")
    closeTxt:SetPoint("CENTER")
    closeTxt:SetText(VB.C_RED .. "X|r")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local scrollParent = CreateFrame("Frame", nil, f)
    scrollParent:SetPoint("TOPLEFT", 8, -24)
    scrollParent:SetPoint("BOTTOMRIGHT", -8, 8)
    f.scrollParent = scrollParent

    f.rows = {}

    f:Hide()
    crossCharFrame = f
    return f
end

local function ShowCrossCharSearch(searchText)
    if not searchText or searchText == "" then return end

    local f = CreateCrossCharFrame(bagFrame)
    local results = VB:SearchAllCharacters(searchText)

    -- Clear existing rows
    for _, row in ipairs(f.rows) do row:Hide() end

    if #results == 0 then
        if not f.rows[1] then
            f.rows[1] = f.scrollParent:CreateFontString(nil, "OVERLAY")
            VB:SetFont(f.rows[1], 10, "")
        end
        f.rows[1]:SetPoint("TOPLEFT", 0, 0)
        f.rows[1]:SetText(VB.C_DIM .. "No matches on other characters.|r")
        f.rows[1]:Show()
    else
        for i, r in ipairs(results) do
            if i > 15 then break end
            if not f.rows[i] then
                f.rows[i] = f.scrollParent:CreateFontString(nil, "OVERLAY")
                VB:SetFont(f.rows[i], 10, "")
            end
            local classColor = RAID_CLASS_COLORS[r.class]
            local cc = classColor and classColor.colorStr or "ffffffff"
            f.rows[i]:ClearAllPoints()
            f.rows[i]:SetPoint("TOPLEFT", 0, -(i - 1) * 16)
            f.rows[i]:SetPoint("RIGHT", f.scrollParent, "RIGHT", 0, 0)
            f.rows[i]:SetText("|c" .. cc .. r.character .. "|r  " .. (r.link or r.name or "?") .. " x" .. (r.count or 1))
            f.rows[i]:Show()
        end
    end

    f:SetHeight(math.max(40, math.min(#results, 15) * 16 + 36))
    f:Show()
end

----------------------------------------------------------------------
-- Create the main bag frame
----------------------------------------------------------------------
local function CreateBagFrame()
    if bagFrame then return bagFrame end

    local f = CreateFrame("Frame", "VoidBagsFrame", UIParent, "BackdropTemplate")
    f:SetSize(520, 600)
    f:SetPoint("RIGHT", UIParent, "RIGHT", -20, 0)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(100)
    f:EnableMouse(true)
    f:SetPropagateKeyboardInput(true)
    VB:CreateBackdrop(f, "transparent")

    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(300, 300, 900, 900)
    end

    -- Restore position
    if VoidBagsDB and VoidBagsDB.config and VoidBagsDB.config.position then
        local pos = VoidBagsDB.config.position
        f:ClearAllPoints()
        f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    end
    if VoidBagsDB and VoidBagsDB.config and VoidBagsDB.config.size then
        f:SetSize(VoidBagsDB.config.size.w, VoidBagsDB.config.size.h)
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
        VoidBagsDB.config.position = { point = point, relPoint = relPoint, x = x, y = y }
    end)

    local title = titleBar:CreateFontString(nil, "OVERLAY")
    VB:SetFont(title, 13, "OUTLINE")
    title:SetPoint("LEFT", 8, 0)
    title:SetText(VB.C_CYAN .. "VoidBags|r")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("RIGHT", -6, 0)
    local closeTxt = closeBtn:CreateFontString(nil, "OVERLAY")
    VB:SetFont(closeTxt, 14, "OUTLINE")
    closeTxt:SetPoint("CENTER")
    closeTxt:SetText(VB.C_RED .. "X|r")
    closeBtn:SetScript("OnClick", function() VB:CloseBags() end)

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
        C_Container.SortBags()
        C_Timer.After(0.5, function() layoutDirty = true; LayoutBags() end)
    end)

    -- Settings gear button — opens popup with auto-sell/auto-repair toggles
    local settingsBtn = CreateFrame("Button", nil, titleBar, "BackdropTemplate")
    settingsBtn:SetSize(20, 18)
    settingsBtn:SetPoint("RIGHT", sortBtn, "LEFT", -4, 0)
    VB:CreateBackdrop(settingsBtn, "section")
    local settingsTxt = settingsBtn:CreateFontString(nil, "OVERLAY")
    VB:SetFont(settingsTxt, 12, "OUTLINE")
    settingsTxt:SetPoint("CENTER")
    settingsTxt:SetText("|cffd4a24c*|r")
    settingsBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("VoidBags Settings", 0, 0.78, 1)
        GameTooltip:AddLine("Auto-sell junk, auto-repair, guild repair", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    settingsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    settingsBtn:SetScript("OnClick", function() VB:ToggleSettings(f) end)

    -- Sell Junk button (left-click = grey only, right-click = grey + T items)
    local junkBtn = CreateFrame("Button", nil, titleBar, "BackdropTemplate")
    junkBtn:SetSize(70, 18)
    junkBtn:SetPoint("RIGHT", settingsBtn, "LEFT", -4, 0)
    VB:CreateBackdrop(junkBtn, "section")
    local junkTxt = junkBtn:CreateFontString(nil, "OVERLAY")
    VB:SetFont(junkTxt, 10, "")
    junkTxt:SetPoint("CENTER")
    junkTxt:SetText(VB.C_DIM .. "Sell Junk|r")
    junkBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    junkBtn:SetScript("OnClick", function(_, mouseBtn)
        if mouseBtn == "RightButton" then
            SellJunk(true)
        else
            SellJunk(false)
        end
    end)
    junkBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Sell Junk", 0, 0.78, 1)
        GameTooltip:AddLine("Left-click: Sell grey items only", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Right-click: Sell grey + T-marked items", 1, 0.84, 0)
        GameTooltip:Show()
    end)
    junkBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Cross-char search button
    local crossBtn = CreateFrame("Button", nil, titleBar, "BackdropTemplate")
    crossBtn:SetSize(18, 18)
    crossBtn:SetPoint("RIGHT", junkBtn, "LEFT", -4, 0)
    VB:CreateBackdrop(crossBtn, "section")
    local crossTxt = crossBtn:CreateFontString(nil, "OVERLAY")
    VB:SetFont(crossTxt, 11, "OUTLINE")
    crossTxt:SetPoint("CENTER")
    crossTxt:SetText(VB.C_CYAN .. "?|r")
    crossBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Search other characters")
        GameTooltip:Show()
    end)
    crossBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    crossBtn:SetScript("OnClick", function()
        local text = searchBox and searchBox:GetText() or ""
        if text ~= "" then
            ShowCrossCharSearch(text)
        else
            print(VB.C_CYAN .. "[VoidBags]|r Type a search term first, then click ? to search other characters.")
        end
    end)

    -- Guild bank button — opens the guild bank view (live at a banker, or the
    -- cached snapshot when browsing away from one).
    local guildBtn = CreateFrame("Button", nil, titleBar, "BackdropTemplate")
    guildBtn:SetSize(48, 18)
    guildBtn:SetPoint("RIGHT", crossBtn, "LEFT", -4, 0)
    VB:CreateBackdrop(guildBtn, "section")
    local guildTxt = guildBtn:CreateFontString(nil, "OVERLAY")
    VB:SetFont(guildTxt, 10, "")
    guildTxt:SetPoint("CENTER")
    guildTxt:SetText(VB.C_DIM .. "Guild|r")
    guildBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Guild Bank", 0, 0.78, 1)
        GameTooltip:AddLine("View the guild bank — live at a banker,", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("or the last-seen snapshot when away.", 0.9, 0.9, 0.9)
        GameTooltip:Show()
    end)
    guildBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    guildBtn:SetScript("OnClick", function() if VB.ToggleGuildBank then VB:ToggleGuildBank() end end)

    -- Search box
    searchBox = CreateFrame("EditBox", "VoidBagsSearch", f, "SearchBoxTemplate")
    searchBox:SetSize(200, 20)
    searchBox:SetPoint("TOPLEFT", 8, -30)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        ApplySearch(text)
        if crossCharFrame and crossCharFrame:IsShown() and text ~= "" then
            ShowCrossCharSearch(text)
        end
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
        ApplySearch("")
        if crossCharFrame then crossCharFrame:Hide() end
    end)

    -- Scroll frame for content
    local scrollFrame = CreateFrame("ScrollFrame", "VoidBagsScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, -54)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 52)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)
    f.content = content
    f.scroll = scrollFrame

    -- Gold and slot count at bottom
    goldText = f:CreateFontString(nil, "OVERLAY")
    VB:SetFont(goldText, 11, "")
    goldText:SetPoint("BOTTOMRIGHT", -8, 8)

    slotText = f:CreateFontString(nil, "OVERLAY")
    VB:SetFont(slotText, 11, "")
    slotText:SetPoint("BOTTOMLEFT", 8, 8)

    -- Bag bar
    if VB:GetConfig("showBagBar") then
        bagBar = CreateFrame("Frame", nil, f)
        bagBar:SetHeight(32)
        bagBar:SetPoint("BOTTOMLEFT", 8, 26)
        bagBar:SetPoint("BOTTOMRIGHT", -8, 26)

        local activeBagFilter = nil -- nil = show all

        -- Bag filter dropdown menu
        local filterMenu
        local BAG_FILTERS = {
            { flag = Enum.BagSlotFlags.ClassEquipment, label = "Equipment" },
            { flag = Enum.BagSlotFlags.ClassConsumables, label = "Consumables" },
            { flag = Enum.BagSlotFlags.ClassProfessionGoods, label = "Trade Goods" },
            { flag = Enum.BagSlotFlags.ClassQuestItems, label = "Quest Items" },
            { flag = Enum.BagSlotFlags.ClassReagents, label = "Reagents" },
            { flag = Enum.BagSlotFlags.ClassJunk, label = "Junk" },
        }

        local function ShowFilterMenu(bagID, anchor)
            if bagID == 0 then return end -- can't filter backpack
            if not filterMenu then
                filterMenu = CreateFrame("Frame", "VoidBagsFilterMenu", f, "BackdropTemplate")
                filterMenu:SetFrameStrata("DIALOG")
                filterMenu:SetSize(150, 10)
                VB:CreateBackdrop(filterMenu, "transparent")
                filterMenu.buttons = {}
            end

            -- Clear old buttons
            for _, btn in ipairs(filterMenu.buttons) do btn:Hide() end

            local yOff = -4
            for i, fInfo in ipairs(BAG_FILTERS) do
                if not filterMenu.buttons[i] then
                    local fb = CreateFrame("Button", nil, filterMenu)
                    fb:SetHeight(18)
                    fb.text = fb:CreateFontString(nil, "OVERLAY")
                    VB:SetFont(fb.text, 10, "")
                    fb.text:SetPoint("LEFT", 20, 0)
                    fb.check = fb:CreateFontString(nil, "OVERLAY")
                    VB:SetFont(fb.check, 10, "OUTLINE")
                    fb.check:SetPoint("LEFT", 4, 0)
                    fb:SetScript("OnEnter", function(self) self.text:SetTextColor(P.accent[1], P.accent[2], P.accent[3]) end)
                    fb:SetScript("OnLeave", function(self) self.text:SetTextColor(P.text[1], P.text[2], P.text[3]) end)
                    filterMenu.buttons[i] = fb
                end
                local fb = filterMenu.buttons[i]
                fb:SetPoint("TOPLEFT", 4, yOff)
                fb:SetPoint("RIGHT", -4, 0)
                fb.text:SetText(fInfo.label)
                fb.text:SetTextColor(P.text[1], P.text[2], P.text[3])

                local ok, active = pcall(C_Container.GetBagSlotFlag, bagID, fInfo.flag)
                fb.check:SetText((ok and active) and VB.C_GREEN .. "+|r" or VB.C_DIM .. "-|r")

                fb:SetScript("OnClick", function()
                    local curOk, curActive = pcall(C_Container.GetBagSlotFlag, bagID, fInfo.flag)
                    pcall(C_Container.SetBagSlotFlag, bagID, fInfo.flag, not (curOk and curActive))
                    -- Refresh checks
                    C_Timer.After(0.1, function() ShowFilterMenu(bagID, anchor) end)
                end)
                fb:Show()
                yOff = yOff - 18
            end

            filterMenu:SetHeight(math.abs(yOff) + 8)
            filterMenu:ClearAllPoints()
            filterMenu:SetPoint("BOTTOM", anchor, "TOP", 0, 4)
            filterMenu._bag = bagID
            filterMenu:Show()
        end

        for bagIdx, bag in ipairs(ALL_BAGS) do
            local bagBtn = CreateFrame("Button", nil, bagBar, "BackdropTemplate")
            bagBtn:SetSize(30, 30)
            bagBtn:SetPoint("LEFT", (bagIdx - 1) * 34, 0)
            VB:CreateBackdrop(bagBtn, "section")
            bagBtn._bagID = bag

            local bagIcon = bagBtn:CreateTexture(nil, "ARTWORK")
            bagIcon:SetPoint("TOPLEFT", 2, -2)
            bagIcon:SetPoint("BOTTOMRIGHT", -2, 2)
            bagIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            if bag == 0 then
                bagIcon:SetTexture("Interface\\Buttons\\Button-Backpack-Up")
            else
                local invID = C_Container.ContainerIDToInventoryID(bag)
                local texID = GetInventoryItemTexture("player", invID)
                bagIcon:SetTexture(texID or "Interface\\Icons\\INV_Misc_Bag_07")
            end

            bagBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            bagBtn:SetScript("OnClick", function(self, mouseBtn)
                if mouseBtn == "RightButton" then
                    -- Right-click: show filter assignment menu
                    if filterMenu and filterMenu:IsShown() and filterMenu._bag == bag then
                        filterMenu:Hide()
                    else
                        ShowFilterMenu(bag, self)
                    end
                else
                    -- Left-click: toggle highlight for this bag
                    if activeBagFilter == bag then
                        -- Already filtering this bag, reset
                        activeBagFilter = nil
                        local allBtns = sectionButtons["all"] or {}
                        for _, btn in ipairs(allBtns) do
                            if btn:IsShown() then
                                btn:SetAlpha(1)
                                btn.icon:SetDesaturated(false)
                            end
                        end
                    else
                        activeBagFilter = bag
                        local allBtns = sectionButtons["all"] or {}
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
                    if filterMenu then filterMenu:Hide() end
                end
            end)

            bagBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if bag == 0 then
                    GameTooltip:AddLine("Backpack", P.accent[1], P.accent[2], P.accent[3])
                else
                    GameTooltip:SetInventoryItem("player", C_Container.ContainerIDToInventoryID(bag))
                end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Left-click: Filter this bag", P.textDim[1], P.textDim[2], P.textDim[3])
                if bag > 0 then
                    GameTooltip:AddLine("Right-click: Assign bag type", P.textDim[1], P.textDim[2], P.textDim[3])
                end
                GameTooltip:Show()
            end)
            bagBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
    end

    -- Resize handle
    local resizer = CreateFrame("Button", nil, f)
    resizer:SetSize(16, 16)
    resizer:SetPoint("BOTTOMRIGHT", -2, 2)
    resizer:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizer:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizer:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizer:SetScript("OnMouseDown", function()
        f:StartSizing("BOTTOMRIGHT")
    end)
    resizer:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        VoidBagsDB.config.size = { w = f:GetWidth(), h = f:GetHeight() }
        layoutDirty = true
        LayoutBags()
    end)

    -- Mouse-blocking overlay. EnableMouse(false) on the parent doesn't
    -- propagate to SecureActionButton children, so they remain clickable
    -- through the "invisible" bag. This overlay sits on top of every child
    -- at the same strata and silently consumes mouse clicks + wheel events
    -- when shown. We Show()/Hide() the overlay only (regular Frame, no
    -- secure children) so it's combat-safe.
    local block = CreateFrame("Frame", nil, f)
    block:SetAllPoints(f)
    block:SetFrameStrata(f:GetFrameStrata())
    block:SetFrameLevel((f:GetFrameLevel() or 1) + 1000)
    block:EnableMouse(true)
    block:EnableMouseWheel(true)
    block:SetScript("OnMouseDown",  function() end)  -- swallow clicks
    block:SetScript("OnMouseWheel", function() end)  -- swallow scroll
    block:Hide()
    f._mouseBlocker = block

    -- DON'T Hide() the bag frame here — bagFrame contains SecureActionButton-
    -- Template children, so any Hide() in combat causes "Cannot change
    -- equipment status." We keep it permanently Shown and toggle visibility
    -- with alpha + the mouse-blocker overlay instead.
    f:SetAlpha(0)
    f:EnableMouse(false)
    f:SetFrameStrata("BACKGROUND")     -- start hidden + out of the way
    block:SetFrameStrata("BACKGROUND")
    block:Show()                       -- start in blocked state
    bagFrame = f
    return f
end

----------------------------------------------------------------------
-- Open / Close
----------------------------------------------------------------------
-- ALPHA-ONLY visibility. We never call Show()/Hide() on bagFrame after
-- creation because bagFrame contains SecureActionButtonTemplate children;
-- Show()/Hide() on such a parent in combat triggers "Cannot change
-- equipment status." The frame is always technically Shown; alpha + mouse
-- enable/disable controls whether the user can see/interact with it.
-- A non-secure overlay frame swallows mouse clicks/wheel when the bag is
-- "hidden" so the invisible-but-shown SecureActionButton children can't
-- still receive clicks.
-- Strata management: bag lives at HIGH when visible (above default UI so it
-- renders on top). When "hidden" we drop to BACKGROUND so other windows
-- (Character / Talents / Spec / etc.) can be clicked over the bag's right-side
-- footprint. The blocker preserves its parent-relative level so it still
-- swallows clicks meant for the SecureActionButton children below it, but
-- because the whole stratum is BACKGROUND, any other UI at MEDIUM+ sits
-- above it and gets clicks first.
local function VisualShow(frame)
    if not frame then return end
    -- Ensure frame is actually shown — VisualHide may have :Hide()'d it
    -- when out of combat. Safe to :Show() in or out of combat.
    if not frame:IsShown() then frame:Show() end
    frame:SetAlpha(1)
    frame:EnableMouse(true)
    frame:SetFrameStrata("HIGH")
    if frame._mouseBlocker then
        frame._mouseBlocker:SetFrameStrata("HIGH")
        frame._mouseBlocker:Hide()
    end
end

local function VisualHide(frame)
    if not frame then return end
    -- OUT OF COMBAT: actually :Hide() the frame. This is the only way to
    -- prevent the "ghost bag" — alpha 0 still leaves the frame rendered
    -- and the mouse blocker on top swallows clicks in the bag's footprint.
    -- :Hide() during combat would taint SecureActionButton children.
    if not InCombatLockdown() then
        frame:SetAlpha(0)
        frame:EnableMouse(false)
        frame:Hide()
        if frame._mouseBlocker then frame._mouseBlocker:Hide() end
        return
    end
    -- IN COMBAT: keep the alpha + blocker pattern (can't :Hide() safely)
    frame:SetAlpha(0)
    frame:EnableMouse(false)
    frame:SetFrameStrata("BACKGROUND")
    if frame._mouseBlocker then
        frame._mouseBlocker:SetFrameStrata("BACKGROUND")
        frame._mouseBlocker:Show()
    end
end

function VB:OpenBags()
    dbg("OpenBags ENTER incombat=%s bagFrame=%s isOpen=%s",
        tostring(InCombatLockdown()), tostring(bagFrame ~= nil), tostring(isOpen))
    if InCombatLockdown() then
        if not bagFrame then
            VB:Print("|cffff5555Bags weren't initialized before combat. Try /vb after combat ends.|r")
            return
        end
        VisualShow(bagFrame)
        isOpen = true
        VB._pendingClose = nil
        pendingRefresh = true
        dbg("OpenBags EXIT (combat path)")
        return
    end
    if not bagFrame then
        dbg("OpenBags: creating bagFrame for first time")
        CreateBagFrame()
    end
    VB:UpdateProfessions()
    layoutDirty = true
    LayoutBags()
    VisualShow(bagFrame)
    isOpen = true
    VB:SnapshotInventory()
    dbg("OpenBags EXIT (normal) alpha=%s shown=%s",
        bagFrame and tostring(bagFrame:GetAlpha()) or "nil",
        bagFrame and tostring(bagFrame:IsShown()) or "nil")
end

function VB:CloseBags()
    dbg("CloseBags ENTER incombat=%s isOpen=%s",
        tostring(InCombatLockdown()), tostring(isOpen))
    VisualHide(bagFrame)
    VisualHide(crossCharFrame)
    isOpen = false
    VB._pendingClose = nil
    dbg("CloseBags EXIT")
end

-- Post-combat handler: restore alpha for any frame that was left open
-- during combat, and apply any deferred layout refresh.
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function()
        if pendingRefresh and isOpen and bagFrame then
            pendingRefresh = false
            layoutDirty = true
            LayoutBags()
        end
        -- Finish any Blizzard ContainerFrame hides that were deferred in combat
        if VB._pendingBlizzHide then
            for frame in pairs(VB._pendingBlizzHide) do
                if frame then
                    frame:ClearAllPoints()
                    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 0)
                    frame:SetAlpha(0)
                    frame:Hide()
                end
            end
            VB._pendingBlizzHide = nil
        end
    end)
end

----------------------------------------------------------------------
-- Settings popup panel — toggles for auto-sell, auto-repair, guild repair
----------------------------------------------------------------------
local settingsFrame
function VB:ToggleSettings(parent)
    if settingsFrame and settingsFrame:IsShown() then
        settingsFrame:Hide()
        return
    end
    if not settingsFrame then
        local f = CreateFrame("Frame", "VoidBagsSettings", parent or UIParent, "BackdropTemplate")
        f:SetSize(300, 300)
        f:SetFrameStrata("DIALOG")
        VB:CreateBackdrop(f, "main")

        local title = f:CreateFontString(nil, "OVERLAY")
        VB:SetFont(title, 12, "OUTLINE")
        title:SetPoint("TOP", 0, -8)
        title:SetTextColor(0, 0.78, 1)
        title:SetText("VoidBags Settings")

        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetSize(22, 22)
        close:SetPoint("TOPRIGHT", 0, 0)
        close:SetScript("OnClick", function() f:Hide() end)

        -- Helper to make a checkbox + label row
        local function MakeToggle(yOffset, configKey, labelText, tooltip)
            local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
            cb:SetPoint("TOPLEFT", 12, yOffset)
            cb:SetSize(22, 22)
            cb:SetChecked(VB:GetConfig(configKey))
            cb:SetScript("OnClick", function(self)
                VoidBagsDB.config[configKey] = self:GetChecked()
                print(VB.C_CYAN .. "[VoidBags]|r " .. labelText .. " " ..
                    (self:GetChecked() and "|cff30ff30on|r" or "|cffff4040off|r"))
            end)
            local lbl = f:CreateFontString(nil, "OVERLAY")
            VB:SetFont(lbl, 11, "")
            lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
            lbl:SetText(labelText)
            if tooltip then
                cb:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(labelText, 0, 0.78, 1)
                    GameTooltip:AddLine(tooltip, 0.85, 0.85, 0.85, true)
                    GameTooltip:Show()
                end)
                cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
            return cb
        end

        f._cbAutoSell = MakeToggle(-32, "autoSellJunk", "Auto-sell junk at vendor",
            "Sell grey-quality items automatically when a vendor opens.")
        f._cbAutoRepair = MakeToggle(-58, "autoRepair", "Auto-repair gear at vendor",
            "Repair all gear automatically when you visit a repair vendor.")
        f._cbGuildRepair = MakeToggle(-84, "useGuildRepair", "Use guild bank for repairs",
            "Try guild bank funds first; fall back to your gold if unavailable.")

        -- Repair cap input
        local capLbl = f:CreateFontString(nil, "OVERLAY")
        VB:SetFont(capLbl, 10, "")
        capLbl:SetPoint("TOPLEFT", 14, -114)
        capLbl:SetText(VB.C_DIM .. "Personal repair cap (gold, 0=none):|r")

        local capBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        capBox:SetSize(60, 18)
        capBox:SetPoint("TOPLEFT", 16, -130)
        capBox:SetAutoFocus(false)
        capBox:SetNumeric(true)
        capBox:SetText(tostring(VB:GetConfig("repairCostCap") or 0))
        capBox:SetScript("OnEnterPressed", function(self)
            local v = tonumber(self:GetText()) or 0
            VoidBagsDB.config.repairCostCap = v
            print(VB.C_CYAN .. "[VoidBags]|r Repair cap = " .. v .. "g (0 = no cap)")
            self:ClearFocus()
        end)
        capBox:SetScript("OnEscapePressed", function(self)
            self:SetText(tostring(VB:GetConfig("repairCostCap") or 0))
            self:ClearFocus()
        end)

        -- Item-marker legend — explains the little letters drawn on bag slots
        -- so users know what L / C / T / ^ / $ mean. Marker colors mirror the
        -- actual in-bag markers (green) so the legend reads at a glance.
        local legendHdr = f:CreateFontString(nil, "OVERLAY")
        VB:SetFont(legendHdr, 11, "OUTLINE")
        legendHdr:SetPoint("TOPLEFT", 14, -156)
        legendHdr:SetTextColor(0, 0.78, 1)
        legendHdr:SetText("Item markers")

        -- { letter (already colored), meaning }. Descriptions kept short enough
        -- to fit one line in the widened panel; word-wrap is off so a row can
        -- never spill into the one below it.
        local legend = {
            { "|cff00ff00L|r", "Learnable — appearance / recipe / mount / pet / toy" },
            { "|cff00ff00C|r", "Craftable — mat for a profession you know" },
            { "|cff00ff00T|r", "Trash — vendor junk, sell for gold" },
            { "|cff00ff00^|r", "Upgrade — higher item level than equipped" },
            { "|cff00ff00$|r", "Value — worth more on the Auction House than vendor" },
        }
        local rowY = -174
        for _, row in ipairs(legend) do
            local key = f:CreateFontString(nil, "OVERLAY")
            VB:SetFont(key, 11, "OUTLINE")
            key:SetPoint("TOPLEFT", 16, rowY)
            key:SetWidth(12)
            key:SetJustifyH("LEFT")
            key:SetText(row[1])

            local desc = f:CreateFontString(nil, "OVERLAY")
            VB:SetFont(desc, 9, "")
            desc:SetPoint("LEFT", key, "RIGHT", 6, 0)
            desc:SetJustifyH("LEFT")
            desc:SetWordWrap(false)
            desc:SetTextColor(0.82, 0.82, 0.82)
            desc:SetText(row[2])

            rowY = rowY - 18
        end

        -- Manual action buttons
        local repairBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        repairBtn:SetSize(80, 22)
        repairBtn:SetPoint("BOTTOMLEFT", 12, 12)
        VB:CreateBackdrop(repairBtn, "section")
        local rT = repairBtn:CreateFontString(nil, "OVERLAY")
        VB:SetFont(rT, 11, "")
        rT:SetPoint("CENTER")
        rT:SetText("Repair Now")
        repairBtn:SetScript("OnClick", function() VB:DoAutoRepair() end)

        local sellBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        sellBtn:SetSize(80, 22)
        sellBtn:SetPoint("LEFT", repairBtn, "RIGHT", 6, 0)
        VB:CreateBackdrop(sellBtn, "section")
        local sT = sellBtn:CreateFontString(nil, "OVERLAY")
        VB:SetFont(sT, 11, "")
        sT:SetPoint("CENTER")
        sT:SetText("Sell Junk")
        sellBtn:SetScript("OnClick", function() VB:DoSellJunk() end)

        settingsFrame = f
    end
    -- Sync checkbox states (in case toggled via slash)
    if settingsFrame._cbAutoSell then settingsFrame._cbAutoSell:SetChecked(VB:GetConfig("autoSellJunk")) end
    if settingsFrame._cbAutoRepair then settingsFrame._cbAutoRepair:SetChecked(VB:GetConfig("autoRepair")) end
    if settingsFrame._cbGuildRepair then settingsFrame._cbGuildRepair:SetChecked(VB:GetConfig("useGuildRepair")) end

    -- Position next to bag frame. Default opens to the RIGHT of the bag; if the
    -- bag is near the right screen edge that would push the panel off-screen, so
    -- flip it to the LEFT of the bag instead. SetClampedToScreen is a final
    -- safety net (also keeps it on-screen if the user drags the bag mid-open).
    settingsFrame:SetClampedToScreen(true)
    settingsFrame:ClearAllPoints()
    if parent and parent:IsShown() then
        settingsFrame:SetPoint("TOPLEFT", parent, "TOPRIGHT", 6, 0)
        settingsFrame:Show()
        local right = settingsFrame:GetRight()
        local screenRight = UIParent:GetRight()
        if right and screenRight and right > screenRight then
            settingsFrame:ClearAllPoints()
            settingsFrame:SetPoint("TOPRIGHT", parent, "TOPLEFT", -6, 0)
        end
    else
        settingsFrame:SetPoint("CENTER")
        settingsFrame:Show()
    end
end

function VB:ToggleBags()
    if isOpen then
        VB:CloseBags()
    else
        VB:OpenBags()
    end
end

----------------------------------------------------------------------
-- Debounced refresh (combat-safe).
-- `pendingRefresh` is hoisted to the top of the file so OpenBags/CloseBags
-- and the PLAYER_REGEN_ENABLED handler can all see the same upvalue.
----------------------------------------------------------------------
local function DebouncedRefresh()
    if InCombatLockdown() then
        pendingRefresh = true
        return
    end
    if refreshTimer then refreshTimer:Cancel() end
    refreshTimer = C_Timer.NewTimer(0.1, function()
        if InCombatLockdown() then
            pendingRefresh = true
            return
        end
        if isOpen then
            LayoutBags()
        end
    end)
end

----------------------------------------------------------------------
-- Suppress Blizzard's auto-opened ContainerFrame*s
-- Blizzard auto-opens individual bag panels when a Merchant/Mail/Trade/Bank
-- frame opens. VoidBags hooks Show but Blizzard sometimes bypasses Show()
-- by directly setting alpha or calling internal methods. This function
-- forcibly hides ANY ContainerFrame* in _G plus the combined-bags frame,
-- and is called on every relevant event.
----------------------------------------------------------------------
-- Permanent OnShow hook: when ANY Blizzard ContainerFrame tries to Show
-- itself, immediately re-Hide. Survives any internal Blizzard code path
-- (auto-loot, bank tab open, merchant suppression races, etc.) because
-- it's frame-level, not event-driven. OnShow is non-secure so safe to hook.
local function _hideOnShow(self)
    self:SetAlpha(0)
    self:EnableMouse(false)
    self:Hide()
end

local function InstallContainerFrameOnShowHooks()
    if ContainerFrameCombinedBags and not ContainerFrameCombinedBags._vbOnShowHooked then
        ContainerFrameCombinedBags._vbOnShowHooked = true
        ContainerFrameCombinedBags:HookScript("OnShow", _hideOnShow)
    end
    for i = 1, 30 do
        local f = _G["ContainerFrame" .. i]
        if f and not f._vbOnShowHooked then
            f._vbOnShowHooked = true
            f:HookScript("OnShow", _hideOnShow)
        end
    end
end

local function SuppressBlizzardBags()
    -- Ensure OnShow hooks are installed (newly-created frames get covered)
    InstallContainerFrameOnShowHooks()
    -- Combined frame
    if ContainerFrameCombinedBags then
        ContainerFrameCombinedBags:SetAlpha(0)
        ContainerFrameCombinedBags:EnableMouse(false)
        ContainerFrameCombinedBags:Hide()
    end
    -- Numbered ContainerFrames (1-13 covers backpack + bags + reagent + bank tabs)
    for i = 1, 30 do
        local f = _G["ContainerFrame" .. i]
        if f then
            f:SetAlpha(0)
            f:EnableMouse(false)
            f:Hide()
        end
    end
    -- Repeat after the next frame in case Blizzard re-shows them
    C_Timer.After(0, function()
        if ContainerFrameCombinedBags then ContainerFrameCombinedBags:SetAlpha(0); ContainerFrameCombinedBags:Hide() end
        for i = 1, 30 do
            local f = _G["ContainerFrame" .. i]
            if f then f:SetAlpha(0); f:Hide() end
        end
    end)
end

-- (Watchdog removed — using targeted event-driven suppression only.)
local function StartContainerFrameWatchdog() end

----------------------------------------------------------------------
-- Auto-repair (guild bank first, fall back to personal funds)
-- Stored on VB so settings panel buttons (defined earlier in file) can call it.
----------------------------------------------------------------------
local AutoRepair
function VB:DoAutoRepair() if AutoRepair then AutoRepair() end end
function VB:DoSellJunk() SellJunk(false) end
AutoRepair = function()
    if not MerchantFrame or not MerchantFrame:IsShown() then return end
    if not CanMerchantRepair or not CanMerchantRepair() then return end
    local cost, canRepair = GetRepairAllCost()
    if not canRepair or not cost or cost <= 0 then return end

    -- Try guild bank repair first if enabled
    if VB:GetConfig("useGuildRepair") and IsInGuild() and CanGuildBankRepair and CanGuildBankRepair() then
        -- C_GuildBank.GetWithdrawMoney is the 11.x replacement for the deprecated global.
        local getGuildMoney = (C_GuildBank and C_GuildBank.GetWithdrawMoney) or GetGuildBankWithdrawMoney
        local guildAvail = getGuildMoney and getGuildMoney() or 0
        -- -1 means unlimited (guild leader)
        if guildAvail == -1 or guildAvail >= cost then
            RepairAllItems(true)
            print(VB.C_CYAN .. "[VoidBags]|r Repaired for " .. VB:FormatMoney(cost) ..
                "|r |cff30ff30(guild bank)|r")
            return
        end
    end

    -- Fall back to personal gold
    local cap = VB:GetConfig("repairCostCap") or 0
    if cap > 0 and cost > cap * 10000 then
        print(VB.C_CYAN .. "[VoidBags]|r Repair cost " .. VB:FormatMoney(cost) ..
            " exceeds cap (" .. cap .. "g). Skipping. |cff888888/vb repair|r to override.")
        return
    end
    if GetMoney() < cost then
        print(VB.C_CYAN .. "[VoidBags]|r Cannot afford repair (" .. VB:FormatMoney(cost) .. ").")
        return
    end
    RepairAllItems(false)
    print(VB.C_CYAN .. "[VoidBags]|r Repaired for " .. VB:FormatMoney(cost) .. "|r |cffffd700(personal)|r")
end

----------------------------------------------------------------------
-- Auto-sell junk + auto-repair at vendor
----------------------------------------------------------------------
local function OnMerchantShow()
    if VB:GetConfig("autoRepair") then
        C_Timer.After(0.2, AutoRepair)
    end
    if VB:GetConfig("autoSellJunk") then
        C_Timer.After(0.5, SellJunk)
    end
end

----------------------------------------------------------------------
-- Event handler
----------------------------------------------------------------------
local ef = CreateFrame("Frame")
ef:RegisterEvent("ADDON_LOADED")
ef:RegisterEvent("BAG_UPDATE")
ef:RegisterEvent("BAG_UPDATE_DELAYED")
ef:RegisterEvent("ITEM_LOCK_CHANGED")
ef:RegisterEvent("PLAYER_MONEY")
ef:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
ef:RegisterEvent("MERCHANT_SHOW")
ef:RegisterEvent("MERCHANT_CLOSED")
ef:RegisterEvent("MAIL_SHOW")
ef:RegisterEvent("MAIL_CLOSED")
ef:RegisterEvent("TRADE_SHOW")
ef:RegisterEvent("TRADE_CLOSED")
ef:RegisterEvent("BANKFRAME_OPENED")
ef:RegisterEvent("BANKFRAME_CLOSED")
ef:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
ef:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
ef:RegisterEvent("PLAYER_ENTERING_WORLD")
ef:RegisterEvent("PLAYER_REGEN_ENABLED")

ef:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "VoidBags" then
        VB:InitDB()
        VB:UpdateProfessions()

        -- Hook every Blizzard bag-toggle entry point. Pressing B triggers
        -- BACKPACKTOGGLE → ToggleBackpack(), which often internally also
        -- invokes OpenAllBags / OpenBackpack as part of Blizzard's combined-
        -- bags chain. That cascade fires multiple of our hooks in a single
        -- keystroke, and a naive `hooking` boolean reset between hooks lets
        -- the state flip twice (open then close) — net result B "does
        -- nothing." We collapse cascades with a deferred "intent" applied
        -- on the next frame: the LAST intent wins, which matches what the
        -- user actually pressed.
        local pendingOp, pendingTimer = nil, nil
        local function applyPending()
            pendingTimer = nil
            local op = pendingOp
            pendingOp = nil
            dbg("applyPending FIRE op=%s", tostring(op))
            if     op == "toggle" then VB:ToggleBags()
            elseif op == "open"   then VB:OpenBags()
            elseif op == "close"  then VB:CloseBags()
            end
        end
        local function scheduleOp(op, src)
            dbg("hook %s -> queue %s (was=%s)", tostring(src), op, tostring(pendingOp))
            pendingOp = op
            if not pendingTimer and C_Timer and C_Timer.NewTimer then
                pendingTimer = C_Timer.NewTimer(0.01, applyPending)
            end
        end

        hooksecurefunc("ToggleAllBags",  function() scheduleOp("toggle", "ToggleAllBags")  end)
        hooksecurefunc("OpenAllBags",    function() scheduleOp("open",   "OpenAllBags")    end)
        hooksecurefunc("CloseAllBags",   function() scheduleOp("close",  "CloseAllBags")   end)
        if ToggleBackpack then hooksecurefunc("ToggleBackpack", function() scheduleOp("toggle", "ToggleBackpack") end) end
        if OpenBackpack   then hooksecurefunc("OpenBackpack",   function() scheduleOp("open",   "OpenBackpack")   end) end
        if CloseBackpack  then hooksecurefunc("CloseBackpack",  function() scheduleOp("close",  "CloseBackpack")  end) end

        -- Hide Blizzard bags — combat-safe.
        -- In combat we can only touch unprotected attrs (alpha, mouse).
        -- ClearAllPoints/SetPoint/Hide on a ContainerFrame (which contains
        -- SecureActionButtonTemplate item buttons) trigger ADDON_ACTION_BLOCKED
        -- = "Cannot change equipment status while in combat".
        local function HideBlizzBag(frame)
            if not frame then return end
            frame:SetAlpha(0)
            frame:EnableMouse(false)
            if not InCombatLockdown() then
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 0)
                frame:Hide()
            end
            if not frame._voidHooked then
                hooksecurefunc(frame, "Show", function(self)
                    -- ALWAYS safe: alpha + mouse-off
                    self:SetAlpha(0)
                    self:EnableMouse(false)
                    -- COMBAT-PROTECTED: position changes + Hide. Skip in combat;
                    -- run them on PLAYER_REGEN_ENABLED instead.
                    if InCombatLockdown() then
                        VB._pendingBlizzHide = VB._pendingBlizzHide or {}
                        VB._pendingBlizzHide[self] = true
                        return
                    end
                    self:ClearAllPoints()
                    self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 0)
                    C_Timer.After(0, function()
                        if InCombatLockdown() then
                            VB._pendingBlizzHide = VB._pendingBlizzHide or {}
                            VB._pendingBlizzHide[self] = true
                            return
                        end
                        self:SetAlpha(0)
                        self:Hide()
                    end)
                end)
                frame._voidHooked = true
            end
        end
        HideBlizzBag(ContainerFrameCombinedBags)
        for i = 1, 30 do
            HideBlizzBag(_G["ContainerFrame" .. i])
        end

        -- Start the watchdog ticker — it'll continuously suppress any
        -- ContainerFrame that becomes visible from any auto-open path.
        StartContainerFrameWatchdog()

        return
    end

    if event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" or event == "ITEM_LOCK_CHANGED" then
        DebouncedRefresh()
        return
    end

    if event == "PLAYER_MONEY" then
        if goldText and isOpen then
            goldText:SetText(VB:FormatMoney(GetMoney()))
        end
        return
    end

    if event == "PLAYER_EQUIPMENT_CHANGED" then
        DebouncedRefresh()
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        -- Combat ended — process any pending refresh
        if pendingRefresh and isOpen then
            pendingRefresh = false
            LayoutBags()
        end
        return
    end

    if event == "MERCHANT_SHOW" then
        OnMerchantShow()
        SuppressBlizzardBags()
        return
    end

    if event == "MAIL_SHOW" or event == "TRADE_SHOW" or event == "BANKFRAME_OPENED" then
        SuppressBlizzardBags()
        return
    end

    -- PLAYER_INTERACTION_MANAGER_FRAME_SHOW fires for EVERY NPC interaction
    -- (merchant, banker, trainer, mailbox, auction house, transmog, ...).
    -- Filter to only the ones that should suppress bags. Without this filter
    -- we were calling SuppressBlizzardBags on trainer/quest/gossip too.
    if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        local IT = Enum.PlayerInteractionType
        if arg1 == IT.Banker or arg1 == IT.Merchant or arg1 == IT.MailInfo
           or arg1 == IT.TradePartner or arg1 == IT.GuildBanker
           or arg1 == IT.AuctionHouse or arg1 == IT.VoidStorageBanker then
            SuppressBlizzardBags()
        end
        return
    end

    if event == "MERCHANT_CLOSED" or event == "MAIL_CLOSED" or event == "TRADE_CLOSED"
       or event == "BANKFRAME_CLOSED" then
        -- Suppress again on close — Blizzard sometimes re-opens bags during the close transition
        SuppressBlizzardBags()
        return
    end

    -- Modern (TWW+) bank-close path. BANKFRAME_CLOSED is being phased out;
    -- PLAYER_INTERACTION_MANAGER_FRAME_HIDE with Enum.PlayerInteractionType.Banker
    -- is the canonical close signal for the unified banking flow.
    if event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        local IT = Enum.PlayerInteractionType
        if arg1 == IT.Banker or arg1 == IT.Merchant or arg1 == IT.MailInfo
           or arg1 == IT.TradePartner or arg1 == IT.GuildBanker
           or arg1 == IT.AuctionHouse or arg1 == IT.VoidStorageBanker then
            SuppressBlizzardBags()
        end
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        -- Install ContainerFrame OnShow hooks RIGHT NOW so ghost bags
        -- can never appear, even briefly. Called again on every event
        -- via SuppressBlizzardBags to catch newly-created frames (e.g.
        -- bank tabs that only exist after BANKFRAME_OPENED).
        InstallContainerFrameOnShowHooks()
        VB:UpdateProfessions()
        C_Timer.After(2, function()
            if VoidBagsDB then VB:SnapshotInventory() end
        end)
        return
    end
end)

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------
SLASH_VOIDBAGS1 = "/vb"
SLASH_VOIDBAGS2 = "/voidbags"
SlashCmdList["VOIDBAGS"] = function(msg)
    msg = (msg or ""):lower():trim()

    if msg == "" or msg == "toggle" then
        VB:ToggleBags()
        return
    end

    if msg == "reset" then
        VoidBagsDB.config.position = nil
        VoidBagsDB.config.size = nil
        VoidBagsDB.config.bankPosition = nil
        if bagFrame then
            bagFrame:ClearAllPoints()
            bagFrame:SetPoint("RIGHT", UIParent, "RIGHT", -20, 0)
            bagFrame:SetSize(520, 600)
            layoutDirty = true
            if isOpen then LayoutBags() end
        end
        print(VB.C_CYAN .. "[VoidBags]|r Position and size reset.")
        return
    end

    if msg == "sell" then
        SellJunk()
        return
    end

    if msg == "repair" then
        AutoRepair()
        return
    end

    if msg == "autorepair" then
        VoidBagsDB.config.autoRepair = not VB:GetConfig("autoRepair")
        print(VB.C_CYAN .. "[VoidBags]|r Auto-repair " ..
            (VB:GetConfig("autoRepair") and "|cff30ff30enabled|r" or "|cffff4040disabled|r"))
        return
    end

    if msg == "guildrepair" then
        VoidBagsDB.config.useGuildRepair = not VB:GetConfig("useGuildRepair")
        print(VB.C_CYAN .. "[VoidBags]|r Guild-bank repair " ..
            (VB:GetConfig("useGuildRepair") and "|cff30ff30enabled|r" or "|cffff4040disabled|r (personal funds only)"))
        return
    end

    if msg == "autosell" then
        VoidBagsDB.config.autoSellJunk = not VB:GetConfig("autoSellJunk")
        print(VB.C_CYAN .. "[VoidBags]|r Auto-sell junk " ..
            (VB:GetConfig("autoSellJunk") and "|cff30ff30enabled|r" or "|cffff4040disabled|r"))
        return
    end

    if msg == "default" or msg == "blizz" then
        -- Temporary swap to Blizzard's default bag UI for this session.
        -- Use this when VoidBags' click handling can't apply enchants/gems
        -- due to taint. /vb default again toggles back to VoidBags.
        VB._useBlizzardBags = not VB._useBlizzardBags
        if VB._useBlizzardBags then
            -- Hide VoidBags
            if bagFrame then bagFrame:Hide() end
            -- Restore Blizzard ContainerFrames to normal positions
            for i = 1, 30 do
                local f = _G["ContainerFrame" .. i]
                if f then
                    f:SetAlpha(1)
                    f:EnableMouse(true)
                    f:ClearAllPoints()
                end
            end
            if ContainerFrameCombinedBags then
                ContainerFrameCombinedBags:SetAlpha(1)
                ContainerFrameCombinedBags:EnableMouse(true)
                ContainerFrameCombinedBags:ClearAllPoints()
                ContainerFrameCombinedBags:SetPoint("BOTTOMRIGHT", -100, 100)
            end
            print(VB.C_CYAN .. "[VoidBags]|r Switched to Blizzard's default bag UI. " ..
                "Press B to open. " .. VB.C_DIM .. "/vb default|r toggles back.")
            -- Open default bags
            ToggleBackpack()
        else
            print(VB.C_CYAN .. "[VoidBags]|r Switched back to VoidBags. " ..
                "Reload required to fully restore Blizzard frame suppression: |cffffd700/reload|r")
        end
        return
    end

    if msg == "hideghost" or msg == "killbags" then
        -- Force-hide every Blizzard ContainerFrame right now (no reload needed).
        local n = 0
        for i = 1, 30 do
            local f = _G["ContainerFrame" .. i]
            if f then
                f:SetAlpha(0)
                f:EnableMouse(false)
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 0)
                f:Hide()
                if f.IsShown and not f:IsShown() then n = n + 1 end
            end
        end
        if ContainerFrameCombinedBags then
            ContainerFrameCombinedBags:SetAlpha(0)
            ContainerFrameCombinedBags:EnableMouse(false)
            ContainerFrameCombinedBags:ClearAllPoints()
            ContainerFrameCombinedBags:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 0)
            ContainerFrameCombinedBags:Hide()
        end
        print(VB.C_CYAN .. "[VoidBags]|r Force-hid " .. n .. " ContainerFrames + Combined.")
        return
    end

    if msg == "bankdebug" then
        VB._bankClickDebug = not VB._bankClickDebug
        print(VB.C_CYAN .. "[VoidBags]|r Bank click debug " ..
            (VB._bankClickDebug and "|cff30ff30ON|r — click items in the bank" or "|cffff4040off|r"))
        return
    end

    if msg == "diag" or msg == "ghost" then
        -- Diagnostic: dump every visible top-level frame on the right half of
        -- the screen. Run this WITH THE GHOST BAG VISIBLE to find what it is.
        local lines = {}
        local function L(s) lines[#lines+1] = s end
        local screenW = GetScreenWidth() or 1920
        local rightThreshold = screenW * 0.5  -- right half of screen
        L("=== VoidBags Ghost-Bag Diagnostic ===")
        L(string.format("Screen width: %.0f, scanning frames with Left > %.0f", screenW, rightThreshold))
        L("")

        L("--- All ContainerFrame* in _G (visible AND hidden) ---")
        for i = 1, 30 do
            local f = _G["ContainerFrame" .. i]
            if f then
                L(string.format("  ContainerFrame%d shown=%s alpha=%.2f size=%.0fx%.0f left=%s",
                    i, tostring(f:IsShown()), f:GetAlpha() or 0,
                    f:GetWidth() or 0, f:GetHeight() or 0,
                    tostring(f:GetLeft())))
            end
        end
        if ContainerFrameCombinedBags then
            L(string.format("  ContainerFrameCombinedBags shown=%s alpha=%.2f left=%s",
                tostring(ContainerFrameCombinedBags:IsShown()),
                ContainerFrameCombinedBags:GetAlpha() or 0,
                tostring(ContainerFrameCombinedBags:GetLeft())))
        end
        L("")

        L("--- Visible frames on right half (recursive 2 levels) ---")
        local count = 0
        local function ScanChildren(parent, depth)
            local ok, kids = pcall(function() return { parent:GetChildren() } end)
            if not ok then return end
            for _, frame in ipairs(kids) do
                if type(frame) == "table" and frame.IsShown then
                    local okShown, shown = pcall(frame.IsShown, frame)
                    if okShown and shown then
                        local left = frame.GetLeft and frame:GetLeft()
                        local alpha = (frame.GetAlpha and frame:GetAlpha()) or 0
                        if left and left > rightThreshold and alpha > 0.1 then
                            local name = (frame.GetName and frame:GetName()) or "(unnamed)"
                            local w, h = frame:GetSize()
                            if (w or 0) > 30 and (h or 0) > 30 then
                                count = count + 1
                                L(string.format("%s%s | left=%.0f top=%.0f size=%.0fx%.0f alpha=%.2f",
                                    string.rep("  ", depth + 1), name, left,
                                    frame:GetTop() or 0, w, h, alpha))
                            end
                            if depth < 2 then ScanChildren(frame, depth + 1) end
                        end
                    end
                end
            end
        end
        ScanChildren(UIParent, 0)
        L("")
        L(string.format("Total visible frames on right: %d", count))
        L("")
        L("If you see UNNAMED frames here, they're probably the ghost bag.")
        L("Note any frames that look bag-shaped (small + tall/skinny strips).")

        local Angler = _G.VoidFisher and _G.VoidFisher._modules and _G.VoidFisher._modules.Angler
        if Angler and Angler.ShowPopup then
            Angler:ShowPopup("VoidBags Ghost Diag", table.concat(lines, "\n"))
        else
            for _, l in ipairs(lines) do print(l) end
        end
        return
    end

    if msg:find("^threshold") then
        local val = tonumber(msg:match("threshold%s+(%d+)"))
        if val then
            VoidBagsDB.config.ahThresholdFloor = val
            print(VB.C_CYAN .. "[VoidBags]|r AH threshold set to " .. val .. "g")
        else
            print(VB.C_CYAN .. "[VoidBags]|r Current AH threshold: " .. (VB:GetConfig("ahThresholdFloor") or 50) .. "g. Usage: /vb threshold 200")
        end
        return
    end

    -- /vb override <itemID> <category>  → forces an item into a specific category
    -- /vb override <itemID> clear        → removes the override
    -- /vb override list                  → lists all current overrides
    if msg:find("^override") then
        VoidBagsDB.itemOverrides = VoidBagsDB.itemOverrides or {}
        local rest = msg:match("override%s+(.+)") or ""
        if rest == "" or rest == "list" then
            local count = 0
            print(VB.C_CYAN .. "[VoidBags]|r Item overrides:")
            for id, cat in pairs(VoidBagsDB.itemOverrides) do
                count = count + 1
                local name = C_Item.GetItemNameByID(id) or ("itemID " .. id)
                print("  " .. id .. " → " .. cat .. "  " .. VB.C_DIM .. "(" .. name .. ")|r")
            end
            if count == 0 then
                print("  " .. VB.C_DIM .. "(none)|r")
            end
            print(VB.C_DIM .. "Usage: /vb override <itemID> <Category>  |  /vb override <itemID> clear|r")
            print(VB.C_DIM .. "Categories: Equipment, Flasks, Potions, Food, Consumables, AlchemyMats, CookingMats, JewelcraftingMats, MyProfMats, SellableReagents, Junk, Misc, QuestItems, Keys|r")
            return
        end
        local id, cat = rest:match("(%d+)%s+(.+)")
        if not id then
            print(VB.C_CYAN .. "[VoidBags]|r Usage: /vb override <itemID> <Category>")
            return
        end
        id = tonumber(id)
        if cat == "clear" or cat == "remove" or cat == "none" then
            VoidBagsDB.itemOverrides[id] = nil
            print(VB.C_CYAN .. "[VoidBags]|r Override cleared for itemID " .. id)
        elseif VB.CATEGORIES[cat] then
            VoidBagsDB.itemOverrides[id] = cat
            local name = C_Item.GetItemNameByID(id) or ("itemID " .. id)
            print(VB.C_CYAN .. "[VoidBags]|r " .. name .. " → " .. cat)
        else
            print(VB.C_CYAN .. "[VoidBags]|r Unknown category '" .. cat .. "'. Valid: " ..
                "Equipment, Flasks, Potions, Food, Consumables, AlchemyMats, CookingMats, JewelcraftingMats, MyProfMats, SellableReagents, Junk, Misc")
        end
        -- Force a re-layout so the change reflects immediately
        if VB.layoutDirty ~= nil then VB.layoutDirty = true end
        return
    end

    if msg == "search" or msg:find("^search") then
        local term = msg:match("search%s+(.+)")
        if term and term ~= "" then
            local results = VB:SearchAllCharacters(term)
            if #results == 0 then
                print(VB.C_CYAN .. "[VoidBags]|r No matches for '" .. term .. "' on other characters.")
            else
                print(VB.C_CYAN .. "[VoidBags]|r Found on other characters:")
                for _, r in ipairs(results) do
                    local classColor = RAID_CLASS_COLORS[r.class]
                    local cc = classColor and classColor.colorStr or "ffffffff"
                    print("  |c" .. cc .. r.character .. "|r  " .. (r.link or r.name) .. " x" .. r.count)
                end
            end
        else
            print(VB.C_CYAN .. "[VoidBags]|r Usage: /vb search <item name>")
        end
        return
    end

    if msg == "chars" then
        local chars = VB:GetCharacterList()
        if #chars == 0 then
            print(VB.C_CYAN .. "[VoidBags]|r No other characters tracked yet. Log into them to snapshot their bags.")
        else
            print(VB.C_CYAN .. "[VoidBags]|r Tracked characters:")
            for _, c in ipairs(chars) do
                local classColor = RAID_CLASS_COLORS[c.data.class]
                local cc = classColor and classColor.colorStr or "ffffffff"
                local ago = time() - (c.data.timestamp or 0)
                local agoStr = ago < 3600 and (math.floor(ago / 60) .. "m ago") or (math.floor(ago / 3600) .. "h ago")
                print("  |c" .. cc .. c.key .. "|r  ilvl " .. (c.data.ilvl or "?") .. "  " .. VB:FormatMoney(c.data.money or 0) .. "  " .. VB.C_DIM .. agoStr .. "|r")
            end
        end
        return
    end

    if msg == "protect" then
        -- Protect the item currently under the cursor tooltip
        local _, itemLink = GameTooltip:GetItem()
        if itemLink then
            local itemID = C_Item.GetItemInfoInstant(itemLink)
            if itemID then
                VoidBagsDB.protected = VoidBagsDB.protected or {}
                if VoidBagsDB.protected[itemID] then
                    VoidBagsDB.protected[itemID] = nil
                    local name = C_Item.GetItemNameByID(itemID) or "item"
                    print(VB.C_CYAN .. "[VoidBags]|r Unprotected: " .. name)
                else
                    VoidBagsDB.protected[itemID] = true
                    local name = C_Item.GetItemNameByID(itemID) or "item"
                    print(VB.C_CYAN .. "[VoidBags]|r Protected: " .. name .. " — will never be marked T or auto-sold.")
                end
                if isOpen then DebouncedRefresh() end
            end
        else
            print(VB.C_CYAN .. "[VoidBags]|r Hover over an item first, then type /vb protect")
        end
        return
    end

    if msg == "help" then
        print(VB.C_CYAN .. "VoidBags Commands:|r")
        print("  /vb — Toggle bags")
        print("  /vb reset — Reset position/size")
        print("  /vb sell — Sell junk items")
        print("  /vb protect — Toggle protection on hovered item")
        print("  /vb threshold <gold> — Set AH value threshold")
        print("  /vb search <name> — Search other characters")
        print("  /vb chars — List tracked characters")
        return
    end

    print(VB.C_CYAN .. "[VoidBags]|r Unknown command. Type /vb help")
end

----------------------------------------------------------------------
-- Keybind support (B key opens bags via backpack functions)
-- Not hooked separately — ToggleAllBags already handles B key
----------------------------------------------------------------------
