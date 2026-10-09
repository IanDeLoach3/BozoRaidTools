local ADDON_NAME, ns = ...

-- Blizzard moved GetItemInfo into the C_Item namespace (patch 10.2.6, 2024) and
-- this WoW Forever beta client doesn't keep the old global around at all (unlike
-- Classic Era, which still has it) -- use whichever is actually available.
-- Same positional return values either way (name, link, quality, ilvl, ...).
ns.GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- ===== Theme =====
-- A flat dark panel + thin accent border, instead of Blizzard's stone/parchment
-- DialogFrame skin -- this is the same visual language RCLootCouncil/Details-style
-- addons use: solid colors via a plain white texture, not custom art assets.
local WHITE_TEX = "Interface\\Buttons\\WHITE8x8"
local ACCENT = { 0.20, 0.65, 0.45 }
local ACCENT_DIM = { 0.16, 0.50, 0.35 }
local PANEL_BG = { 0.07, 0.07, 0.08, 0.97 }
local ROW_BG = { 0.12, 0.12, 0.13, 1 }
local ROW_BG_HOVER = { 0.15, 0.15, 0.17, 1 }
local BORDER = { 0.28, 0.28, 0.30 }

-- ===== Main window shell =====
local main = CreateFrame("Frame", "BozoRaidToolsFrame", UIParent, "BackdropTemplate")
main:SetSize(900, 760)
main:SetPoint("CENTER")
main:SetMovable(true)
main:EnableMouse(true)
main:SetClampedToScreen(true)
main:RegisterForDrag("LeftButton")
main:SetScript("OnDragStart", main.StartMoving)
main:SetScript("OnDragStop", main.StopMovingOrSizing)

-- Resizable, but only ever GROWS from the tested 900x760 default -- every
-- tab's internal layout assumes at least that much width (868px content
-- area after the 16px margins), so a smaller minimum risks clipping/overlap
-- I have no live client to test against. Growing just adds empty margin on
-- tabs that don't reflow (Attendance/Loot's two-column sections); tabs using
-- a single TOPLEFT+BOTTOMRIGHT list (Roster/Prep Check) reflow to fill it.
-- SetMinResize/SetMaxResize were deprecated in patch 10.0.0 (2022) in favor
-- of a single SetResizeBounds call -- confirmed via Warcraft Wiki, not
-- guessed, after this exact line threw "attempt to call a nil value" on
-- Forever. Classic Era still has the old pair, so try the modern call first
-- and fall back rather than assuming either one exists.
main:SetResizable(true)
if main.SetResizeBounds then
    main:SetResizeBounds(900, 760, 1500, 1150)
else
    main:SetMinResize(900, 760)
    main:SetMaxResize(1500, 1150)
end

local resizeGrip = CreateFrame("Button", nil, main)
resizeGrip:SetSize(16, 16)
resizeGrip:SetPoint("BOTTOMRIGHT", -2, 2)
resizeGrip:SetScript("OnMouseDown", function()
    main:StartSizing("BOTTOMRIGHT")
end)
resizeGrip:SetScript("OnMouseUp", function()
    main:StopMovingOrSizing()
end)
-- Three small diagonal dots as a resize-grip visual, built from our own
-- solid-color texture instead of a guessed Blizzard texture path.
for i = 1, 3 do
    local dot = resizeGrip:CreateTexture(nil, "OVERLAY")
    dot:SetSize(3, 3)
    dot:SetColorTexture(unpack(ACCENT))
    dot:SetPoint("BOTTOMRIGHT", -2 - (i - 1) * 5, 2 + (i - 1) * 5)
end
main:SetBackdrop({
    bgFile = WHITE_TEX,
    edgeFile = WHITE_TEX,
    edgeSize = 1,
})
main:SetBackdropColor(unpack(PANEL_BG))
main:SetBackdropBorderColor(unpack(ACCENT))
main:Hide()
tinsert(UISpecialFrames, "BozoRaidToolsFrame") -- lets Escape close it like a default Blizzard panel

local titleBar = main:CreateTexture(nil, "ARTWORK")
titleBar:SetPoint("TOPLEFT", 1, -1)
titleBar:SetPoint("TOPRIGHT", -1, -1)
titleBar:SetHeight(30)
titleBar:SetColorTexture(0.10, 0.10, 0.11, 1)

local title = main:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("LEFT", titleBar, "LEFT", 12, 0)
title:SetText("|cff33ff99Bozo|r Raid Tools")

local closeBtn = CreateFrame("Button", nil, main)
closeBtn:SetSize(24, 24)
closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -4, 0)
local closeLabel = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
closeLabel:SetPoint("CENTER")
closeLabel:SetText("x")
closeLabel:SetTextColor(0.6, 0.6, 0.6)
closeBtn:SetScript("OnEnter", function()
    closeLabel:SetTextColor(1, 0.35, 0.35)
end)
closeBtn:SetScript("OnLeave", function()
    closeLabel:SetTextColor(0.6, 0.6, 0.6)
end)
closeBtn:SetScript("OnClick", function()
    main:Hide()
end)

-- ===== Shared button style (used by every panel instead of UIPanelButtonTemplate) =====
function ns.CreateStyledButton(parent, text, width, height, isPrimary)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width, height or 24)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    btn.bg = bg

    local border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    border:SetAllPoints()
    border:SetBackdrop({ edgeFile = WHITE_TEX, edgeSize = 1 })
    border:SetBackdropBorderColor(unpack(BORDER))

    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.06)

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("CENTER")
    label:SetText(text)
    btn.label = label

    local function normalColor()
        if isPrimary then
            bg:SetColorTexture(unpack(ACCENT))
        else
            bg:SetColorTexture(unpack(ROW_BG))
        end
    end
    local function pressedColor()
        if isPrimary then
            bg:SetColorTexture(unpack(ACCENT_DIM))
        else
            bg:SetColorTexture(unpack(ROW_BG_HOVER))
        end
    end
    normalColor()

    btn:SetScript("OnMouseDown", pressedColor)
    btn:SetScript("OnMouseUp", normalColor)

    function btn:SetText(t)
        label:SetText(t)
    end
    function btn:GetText()
        return label:GetText()
    end
    function btn:SetActive(active)
        if active then
            bg:SetColorTexture(unpack(ACCENT))
        else
            normalColor()
        end
    end

    return btn
end

-- ===== Tab system =====
local tabs, panels, tabOrder = {}, {}, {}
local activeTab = nil

local function SelectTab(key)
    for k, panel in pairs(panels) do
        panel:SetShown(k == key)
    end
    for k, btn in pairs(tabs) do
        btn:SetActive(k == key)
        btn:EnableMouse(k ~= key)
    end
    activeTab = key
end
ns.SelectTab = SelectTab

-- Tab width/spacing is computed from the current tab count instead of a
-- fixed 170/180px (that was sized for exactly 5 tabs and silently ran the
-- 6th tab past the 868px content width when Auto Mark was added -- it never
-- overlapped anything, it just rendered off the edge of the window).
local TAB_CONTENT_WIDTH = 868
local TAB_GAP = 6

local function LayoutTabs()
    local n = #tabOrder
    if n == 0 then
        return
    end
    local width = math.floor((TAB_CONTENT_WIDTH - (n - 1) * TAB_GAP) / n)
    for i, key in ipairs(tabOrder) do
        local btn = tabs[key]
        btn:SetSize(width, 28)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", 16 + (i - 1) * (width + TAB_GAP), -44)
    end
end

function ns.RegisterTab(key, label)
    local panel = CreateFrame("Frame", nil, main)
    panel:SetPoint("TOPLEFT", 16, -80)
    panel:SetPoint("BOTTOMRIGHT", -16, 16)
    panel:Hide()
    panels[key] = panel

    table.insert(tabOrder, key)
    local btn = ns.CreateStyledButton(main, label, 170, 28, false)
    btn:SetScript("OnClick", function()
        SelectTab(key)
    end)
    tabs[key] = btn
    LayoutTabs()

    return panel
end

function ns.ToggleMainFrame()
    if main:IsShown() then
        main:Hide()
        return
    end
    main:Show()
    if not activeTab and tabOrder[1] then
        SelectTab(tabOrder[1])
    end
end

ns.mainFrame = main

-- ===== Small UI helpers reused by every tab panel =====

function ns.CreateEditBox(parent, width)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(width or 140, 22)
    box:SetAutoFocus(false)
    box:SetFontObject(GameFontHighlight)
    box:SetTextInsets(6, 6, 0, 0)
    box:SetBackdrop({ bgFile = WHITE_TEX, edgeFile = WHITE_TEX, edgeSize = 1 })
    box:SetBackdropColor(unpack(ROW_BG))
    box:SetBackdropBorderColor(unpack(BORDER))
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnEnterPressed", box.ClearFocus)
    return box
end

local function ClampValue(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

-- Width reserved on the right of any scroll area for our slim custom bar.
ns.SCROLLBAR_CLEARANCE = 12

-- A slim, flat scrollbar (thin track + accent-colored thumb, no up/down arrow
-- buttons) instead of Blizzard's default chunky one -- wheel scrolling and
-- thumb dragging both work. Returns the ScrollFrame, its content frame, and an
-- Update function to call whenever the content's size changes.
function ns.CreateScrollFrame(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT")
    scroll:SetPoint("BOTTOMRIGHT", -ns.SCROLLBAR_CLEARANCE, 0)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    content:SetPoint("TOPLEFT")
    scroll:SetScrollChild(content)

    local track = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    track:SetPoint("TOPRIGHT", 0, 0)
    track:SetPoint("BOTTOMRIGHT", 0, 0)
    track:SetWidth(6)
    track:SetBackdrop({ bgFile = WHITE_TEX })
    track:SetBackdropColor(1, 1, 1, 0.06)

    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(6)
    thumb:SetPoint("TOP", track, "TOP", 0, 0)
    local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
    thumbTex:SetAllPoints()
    thumbTex:SetColorTexture(unpack(ACCENT))
    thumb:RegisterForDrag("LeftButton")

    local function GetMaxScroll()
        return math.max(0, content:GetHeight() - scroll:GetHeight())
    end

    local function Update()
        -- content's width was never being kept in sync with the viewport --
        -- it defaulted to the 1px placeholder from creation and nothing ever
        -- corrected it, which left every row's RIGHT anchor (content's right
        -- edge minus a few px) sitting to the LEFT of its own TOPLEFT anchor.
        -- That degenerate box is why row text never actually rendered.
        content:SetWidth(math.max(scroll:GetWidth(), 1))

        local maxScroll = GetMaxScroll()
        if maxScroll <= 0 then
            track:Hide()
            return
        end
        track:Show()
        local viewHeight = scroll:GetHeight()
        local contentHeight = math.max(content:GetHeight(), 1)
        local thumbHeight = ClampValue(viewHeight * (viewHeight / contentHeight), 20, viewHeight)
        thumb:SetHeight(thumbHeight)
        local travel = viewHeight - thumbHeight
        local scrollPct = scroll:GetVerticalScroll() / maxScroll
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -travel * scrollPct)
    end

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = GetMaxScroll()
        self:SetVerticalScroll(ClampValue(self:GetVerticalScroll() - delta * 30, 0, maxScroll))
        Update()
    end)

    thumb:SetScript("OnDragStart", function(self)
        self.dragging = true
        self.dragStartY = select(2, GetCursorPosition())
        self.dragStartOffset = scroll:GetVerticalScroll()
    end)
    thumb:SetScript("OnDragStop", function(self)
        self.dragging = false
    end)
    thumb:SetScript("OnUpdate", function(self)
        if not self.dragging then
            return
        end
        local maxScroll = GetMaxScroll()
        if maxScroll <= 0 then
            return
        end
        local scale = UIParent:GetEffectiveScale()
        local _, cursorY = GetCursorPosition()
        local deltaPixels = (self.dragStartY - cursorY) / scale
        local viewHeight = scroll:GetHeight()
        local travel = math.max(1, viewHeight - self:GetHeight())
        local deltaScroll = deltaPixels * (maxScroll / travel)
        scroll:SetVerticalScroll(ClampValue(self.dragStartOffset + deltaScroll, 0, maxScroll))
        Update()
    end)

    scroll:SetScript("OnSizeChanged", Update)

    return scroll, content, Update
end

-- A scrolling list of rows; call list:SetRows({ "line1", "line2", ... }) to
-- refresh. Optionally set list.onRowClick = function(index, button) ... end
-- to make rows clickable (e.g. click-to-remove, or click-for-detail) --
-- harmless to leave unset for read-only lists, which is most callers.
-- Optionally ALSO set list.onRowRemove = function(index) ... end to get a
-- separate small "x" button on each row for removal, independent of
-- whatever onRowClick does with a click on the row itself -- a child button
-- naturally sits above its parent in WoW's hit-testing, so the two don't
-- fight over the same click.
function ns.CreateRowList(parent)
    local scroll, content, UpdateScrollbar = ns.CreateScrollFrame(parent)

    local rows = {}
    local list = { onRowClick = nil, onRowRemove = nil }

    function list:SetRows(lines)
        for _, row in ipairs(rows) do
            row:Hide()
        end
        local height = 0
        for i, text in ipairs(lines) do
            local row = rows[i]
            if not row then
                row = CreateFrame("Button", nil, content)
                row:SetHeight(16)
                row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                row.text:SetPoint("LEFT", 4, 0)
                row.text:SetJustifyH("LEFT")
                local hl = row:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.05)

                local removeBtn = CreateFrame("Button", nil, row)
                removeBtn:SetSize(16, 16)
                removeBtn:SetPoint("RIGHT", -2, 0)
                local removeLabel = removeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                removeLabel:SetPoint("CENTER")
                removeLabel:SetText("x")
                removeLabel:SetTextColor(1, 0.35, 0.35)
                removeBtn:Hide()
                row.removeBtn = removeBtn

                rows[i] = row
            end
            -- Width comes from the stable scroll viewport, not content's own
            -- width -- content's width is derived FROM this same value inside
            -- Update(), so depending on it here would be an ordering hazard.
            row:SetWidth(math.max(scroll:GetWidth(), 1))
            row:SetPoint("TOPLEFT", 0, -(i - 1) * 16)
            row.text:SetText(text)
            row:SetScript("OnClick", function(_, button)
                if list.onRowClick then
                    list.onRowClick(i, button)
                end
            end)
            if list.onRowRemove then
                row.removeBtn:Show()
                row.removeBtn:SetScript("OnClick", function()
                    list.onRowRemove(i)
                end)
            else
                row.removeBtn:Hide()
            end
            row:Show()
            height = i * 16
        end
        content:SetSize(1, math.max(height, 1))
        UpdateScrollbar()
    end

    return scroll, list
end

-- ===== Loot toast popup =====
-- A small floating confirmation that pops up near the top of the screen
-- whenever loot gets logged (auto or manual), independent of whether the
-- main BozoRaidTools window is even open. Multiple toasts stack top-to-
-- bottom and auto-dismiss after a few seconds; ReflowToasts anchors each one
-- off the previous toast's actual (possibly taller, if it has roll info)
-- bottom edge, so variable height never needs to be tracked separately.
local activeToasts = {}
local TOAST_WIDTH = 300
local TOAST_LIFETIME = 6

local function ReflowToasts()
    for i, toast in ipairs(activeToasts) do
        toast:ClearAllPoints()
        if i == 1 then
            toast:SetPoint("TOP", UIParent, "TOP", 0, -160)
        else
            toast:SetPoint("TOP", activeToasts[i - 1], "BOTTOM", 0, -6)
        end
    end
end

local function RemoveToast(toast)
    for i, t in ipairs(activeToasts) do
        if t == toast then
            table.remove(activeToasts, i)
            break
        end
    end
    toast:Hide()
    ReflowToasts()
end

-- rollInfo (optional) is { need={names}, greed={names}, pass={names}, disenchant={names} }
-- -- see the caveat in Loot.lua: the need/selected/pass line-parsing this
-- depends on is NOT verified against a live client, unlike the base
-- item+winner popup which reuses the already-confirmed "receives loot" text.
function ns.ShowLootPopup(itemText, winner, rollInfo)
    local toast = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    toast:SetSize(TOAST_WIDTH, 54)
    toast:SetFrameStrata("HIGH")
    toast:SetBackdrop({ bgFile = WHITE_TEX, edgeFile = WHITE_TEX, edgeSize = 1 })
    toast:SetBackdropColor(unpack(PANEL_BG))
    toast:SetBackdropBorderColor(unpack(ACCENT))

    local closeBtn = CreateFrame("Button", nil, toast)
    closeBtn:SetSize(16, 16)
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    local closeLabel = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeLabel:SetPoint("CENTER")
    closeLabel:SetText("x")
    closeLabel:SetTextColor(0.6, 0.6, 0.6)
    closeBtn:SetScript("OnClick", function()
        RemoveToast(toast)
    end)

    local name, _, quality, _, _, _, _, _, _, texture = ns.GetItemInfo(itemText)

    local icon = toast:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("TOPLEFT", 8, -8)
    icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")

    local nameText = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, 0)
    nameText:SetPoint("RIGHT", -24, 0)
    nameText:SetJustifyH("LEFT")
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    nameText:SetText(((color and color.hex) or "") .. (name or itemText) .. "|r")

    local statusText = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -4)
    statusText:SetPoint("RIGHT", -8, 0)
    statusText:SetJustifyH("LEFT")
    statusText:SetText("|cff33ff99Logged:|r " .. winner)

    if rollInfo then
        local parts = {}
        local order = { { rollInfo.need, "Need" }, { rollInfo.greed, "Greed" }, { rollInfo.disenchant, "DE" }, { rollInfo.pass, "Pass" } }
        for _, entry in ipairs(order) do
            local names, label = entry[1], entry[2]
            if names and #names > 0 then
                table.insert(parts, label .. ": " .. table.concat(names, ", "))
            end
        end
        if #parts > 0 then
            local rollText = toast:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            rollText:SetPoint("TOPLEFT", statusText, "BOTTOMLEFT", 0, -3)
            rollText:SetPoint("RIGHT", -8, 0)
            rollText:SetJustifyH("LEFT")
            rollText:SetWordWrap(true)
            rollText:SetText(table.concat(parts, "   "))
            toast:SetHeight(54 + 14 * math.ceil(#table.concat(parts, "   ") / 45))
        end
    end

    table.insert(activeToasts, toast)
    ReflowToasts()

    C_Timer.After(TOAST_LIFETIME, function()
        if toast:IsShown() then
            RemoveToast(toast)
        end
    end)
end

-- ===== Loot detail dialog (structured info card, not a repurposed copy box) =====
-- Reuses the same icon+quality-colored-name visual language as the toast
-- popup, instead of dumping plain text into the generic Export dialog (which
-- also had an irrelevant "Ctrl+A to copy" hint for something you're not
-- exporting). Height is computed after laying out content, since the rolls
-- section can be 0-4 lines depending on the item.
local lootDetailFrame

function ns.ShowLootDetailDialog(itemText, winner, dateText, rollInfo, note)
    if not lootDetailFrame then
        local f = CreateFrame("Frame", "BozoRaidToolsLootDetailFrame", UIParent, "BackdropTemplate")
        f:SetSize(380, 120)
        f:SetPoint("TOP", UIParent, "TOP", 0, -180)
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetBackdrop({ bgFile = WHITE_TEX, edgeFile = WHITE_TEX, edgeSize = 1 })
        f:SetBackdropColor(unpack(PANEL_BG))
        f:SetBackdropBorderColor(unpack(ACCENT))
        f:Hide()
        tinsert(UISpecialFrames, "BozoRaidToolsLootDetailFrame")

        local titleBar = f:CreateTexture(nil, "ARTWORK")
        titleBar:SetPoint("TOPLEFT", 1, -1)
        titleBar:SetPoint("TOPRIGHT", -1, -1)
        titleBar:SetHeight(26)
        titleBar:SetColorTexture(0.10, 0.10, 0.11, 1)

        local titleLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleLabel:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
        titleLabel:SetText("Loot Details")

        local closeX = CreateFrame("Button", nil, f)
        closeX:SetSize(20, 20)
        closeX:SetPoint("RIGHT", titleBar, "RIGHT", -2, 0)
        local closeXLabel = closeX:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        closeXLabel:SetPoint("CENTER")
        closeXLabel:SetText("x")
        closeXLabel:SetTextColor(0.6, 0.6, 0.6)
        closeX:SetScript("OnEnter", function()
            closeXLabel:SetTextColor(1, 0.35, 0.35)
        end)
        closeX:SetScript("OnLeave", function()
            closeXLabel:SetTextColor(0.6, 0.6, 0.6)
        end)
        closeX:SetScript("OnClick", function()
            f:Hide()
        end)

        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetSize(40, 40)
        icon:SetPoint("TOPLEFT", 14, -38)
        f.icon = icon

        local nameText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        nameText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
        nameText:SetPoint("RIGHT", -14, 0)
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(true)
        f.nameText = nameText

        local infoText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        infoText:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -12)
        infoText:SetPoint("RIGHT", -14, 0)
        infoText:SetJustifyH("LEFT")
        infoText:SetWordWrap(true)
        f.infoText = infoText

        local divider = f:CreateTexture(nil, "ARTWORK")
        divider:SetPoint("TOPLEFT", infoText, "BOTTOMLEFT", 0, -10)
        divider:SetPoint("RIGHT", -14, 0)
        divider:SetHeight(1)
        divider:SetColorTexture(unpack(BORDER))

        local rollsHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        rollsHeader:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -10)
        rollsHeader:SetText("|cff33ff99Rolls|r")

        local rollsText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rollsText:SetPoint("TOPLEFT", rollsHeader, "BOTTOMLEFT", 0, -6)
        rollsText:SetPoint("RIGHT", -14, 0)
        rollsText:SetJustifyH("LEFT")
        rollsText:SetWordWrap(true)
        f.rollsText = rollsText

        -- Anchored off rollsText's own bottom (not a fixed frame offset) so
        -- the close button -- and the frame height computed from it below --
        -- naturally follows however many roll lines got rendered.
        local closeBtn = ns.CreateStyledButton(f, "Close", 100, 22, true)
        closeBtn:SetPoint("TOP", rollsText, "BOTTOM", 0, -16)
        closeBtn:SetScript("OnClick", function()
            f:Hide()
        end)
        f.closeBtn = closeBtn

        lootDetailFrame = f
    end

    local f = lootDetailFrame
    local name, _, quality, _, _, _, _, _, _, texture = ns.GetItemInfo(itemText)
    f.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    f.nameText:SetText(((color and color.hex) or "") .. (name or itemText) .. "|r")
    f.infoText:SetText("|cff33ff99Winner:|r " .. winner .. "   |cff888888" .. (dateText or "") .. "|r")

    local rollLines = {}
    if rollInfo then
        local order = {
            { rollInfo.need, "|cffff5555Need|r" },
            { rollInfo.greed, "|cffffaa00Greed|r" },
            { rollInfo.disenchant, "|cff66ccffDisenchant|r" },
            { rollInfo.pass, "|cff888888Pass|r" },
        }
        for _, entry in ipairs(order) do
            local names, label = entry[1], entry[2]
            if names and #names > 0 then
                table.insert(rollLines, label .. ": " .. table.concat(names, ", "))
            end
        end
    end
    f.rollsText:SetText(#rollLines > 0 and table.concat(rollLines, "\n") or (note or "No roll data recorded for this item."))

    f:Show()
    local height = (f:GetTop() - f.closeBtn:GetBottom()) + 16
    f:SetHeight(math.max(height, 130))
end

-- ===== Gear inspect dialog (structured, icon per slot) =====
-- 17 equipment slots is a fixed, known count -- unlike the loot log (which
-- can have any number of entries and needs a real scrolling list), this can
-- just be a static grid of rows sized once. Same icon+quality-colored-name
-- visual language as the loot toast/detail dialog.
local gearDialogFrame

function ns.ShowGearDialog(charName, gearEntries)
    if not gearDialogFrame then
        local f = CreateFrame("Frame", "BozoRaidToolsGearFrame", UIParent, "BackdropTemplate")
        -- Always exactly 17 fixed rows (every equipment slot, empty or not),
        -- so unlike the loot detail dialog's variable roll list, height never
        -- needs to be measured/recomputed after layout -- a plain CENTER
        -- anchor is safe here since nothing changes size after creation.
        f:SetSize(360, 560)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetBackdrop({ bgFile = WHITE_TEX, edgeFile = WHITE_TEX, edgeSize = 1 })
        f:SetBackdropColor(unpack(PANEL_BG))
        f:SetBackdropBorderColor(unpack(ACCENT))
        f:Hide()
        tinsert(UISpecialFrames, "BozoRaidToolsGearFrame")

        local titleBar = f:CreateTexture(nil, "ARTWORK")
        titleBar:SetPoint("TOPLEFT", 1, -1)
        titleBar:SetPoint("TOPRIGHT", -1, -1)
        titleBar:SetHeight(30)
        titleBar:SetColorTexture(0.10, 0.10, 0.11, 1)

        local nameText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        nameText:SetPoint("LEFT", titleBar, "LEFT", 12, 0)
        f.nameText = nameText

        local closeX = CreateFrame("Button", nil, f)
        closeX:SetSize(24, 24)
        closeX:SetPoint("RIGHT", titleBar, "RIGHT", -4, 0)
        local closeXLabel = closeX:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        closeXLabel:SetPoint("CENTER")
        closeXLabel:SetText("x")
        closeXLabel:SetTextColor(0.6, 0.6, 0.6)
        closeX:SetScript("OnEnter", function()
            closeXLabel:SetTextColor(1, 0.35, 0.35)
        end)
        closeX:SetScript("OnLeave", function()
            closeXLabel:SetTextColor(0.6, 0.6, 0.6)
        end)
        closeX:SetScript("OnClick", function()
            f:Hide()
        end)

        f.rows = {}
        local ROW_HEIGHT = 26
        local prevRow = nil
        for i = 1, 17 do
            local row = CreateFrame("Frame", nil, f)
            row:SetHeight(ROW_HEIGHT)
            if prevRow then
                row:SetPoint("TOPLEFT", prevRow, "BOTTOMLEFT", 0, 0)
                row:SetPoint("TOPRIGHT", prevRow, "BOTTOMRIGHT", 0, 0)
            else
                row:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 14, -10)
                row:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", -14, -10)
            end

            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(20, 20)
            icon:SetPoint("LEFT", 0, 0)
            row.icon = icon

            local label = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
            label:SetWidth(70)
            label:SetJustifyH("LEFT")
            row.label = label

            local itemText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            itemText:SetPoint("LEFT", label, "RIGHT", 4, 0)
            itemText:SetPoint("RIGHT", 0, 0)
            itemText:SetJustifyH("LEFT")
            row.itemText = itemText

            f.rows[i] = row
            prevRow = row
        end

        local closeBtn = ns.CreateStyledButton(f, "Close", 100, 22, true)
        closeBtn:SetPoint("TOP", prevRow, "BOTTOM", 0, -16)
        closeBtn:SetScript("OnClick", function()
            f:Hide()
        end)
        f.closeBtn = closeBtn

        gearDialogFrame = f
    end

    local f = gearDialogFrame
    f.nameText:SetText(charName .. "'s Gear")

    for i, row in ipairs(f.rows) do
        local entry = gearEntries[i]
        if entry then
            row.icon:SetTexture(entry.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.label:SetText(entry.label)
            if entry.name then
                local color = entry.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[entry.quality]
                local text = ((color and color.hex) or "") .. entry.name .. "|r"
                if entry.ilvl then
                    text = text .. "  |cff888888(ilvl " .. entry.ilvl .. ")|r"
                end
                row.itemText:SetText(text)
            else
                row.itemText:SetText("|cff555555(empty)|r")
            end
            row:Show()
        else
            row:Hide()
        end
    end

    f:Show()
end

-- ===== Confirm dialog (shared "are you sure?" for every destructive action) =====
-- A custom-styled equivalent of Blizzard's StaticPopup -- built to match this
-- addon's flat dark theme instead of the default stone/parchment skin, same
-- reasoning as every other dialog here. Fixed size, since the message is
-- always short (1-3 lines), so no dynamic height measurement is needed.
local confirmFrame

function ns.ShowConfirmDialog(message, onConfirm)
    if not confirmFrame then
        local f = CreateFrame("Frame", "BozoRaidToolsConfirmFrame", UIParent, "BackdropTemplate")
        f:SetSize(360, 160)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({ bgFile = WHITE_TEX, edgeFile = WHITE_TEX, edgeSize = 1 })
        f:SetBackdropColor(unpack(PANEL_BG))
        f:SetBackdropBorderColor(unpack(ACCENT))
        f:Hide()
        tinsert(UISpecialFrames, "BozoRaidToolsConfirmFrame")

        local titleBar = f:CreateTexture(nil, "ARTWORK")
        titleBar:SetPoint("TOPLEFT", 1, -1)
        titleBar:SetPoint("TOPRIGHT", -1, -1)
        titleBar:SetHeight(26)
        titleBar:SetColorTexture(0.10, 0.10, 0.11, 1)

        local titleLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleLabel:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
        titleLabel:SetText("Confirm")

        local msgText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        msgText:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 20, -22)
        msgText:SetPoint("RIGHT", -20, 0)
        msgText:SetJustifyH("CENTER")
        msgText:SetWordWrap(true)
        f.msgText = msgText

        local confirmBtn = ns.CreateStyledButton(f, "Remove", 110, 24, true)
        confirmBtn:SetPoint("BOTTOM", -60, 16)
        f.confirmBtn = confirmBtn

        local cancelBtn = ns.CreateStyledButton(f, "Cancel", 110, 24, false)
        cancelBtn:SetPoint("BOTTOM", 60, 16)
        cancelBtn:SetScript("OnClick", function()
            f:Hide()
        end)

        confirmFrame = f
    end

    local f = confirmFrame
    f.msgText:SetText(message)
    f.confirmBtn:SetScript("OnClick", function()
        f:Hide()
        onConfirm()
    end)
    f:Show()
end

-- ===== Export dialog (copy-to-clipboard text box) =====
-- WoW addons have no filesystem/network access -- there's no real "download"
-- or "upload" from inside the game. The standard workaround every addon uses
-- is a selectable text box: Ctrl+A, Ctrl+C, then paste it wherever you want
-- (Discord, a spreadsheet, a text file) outside the game.
local exportFrame

function ns.ShowExportDialog(title, text)
    if not exportFrame then
        exportFrame = CreateFrame("Frame", "BozoRaidToolsExportFrame", UIParent, "BackdropTemplate")
        exportFrame:SetSize(600, 420)
        exportFrame:SetPoint("CENTER")
        exportFrame:SetFrameStrata("DIALOG")
        exportFrame:SetMovable(true)
        exportFrame:EnableMouse(true)
        exportFrame:RegisterForDrag("LeftButton")
        exportFrame:SetScript("OnDragStart", exportFrame.StartMoving)
        exportFrame:SetScript("OnDragStop", exportFrame.StopMovingOrSizing)
        exportFrame:SetBackdrop({ bgFile = WHITE_TEX, edgeFile = WHITE_TEX, edgeSize = 1 })
        exportFrame:SetBackdropColor(unpack(PANEL_BG))
        exportFrame:SetBackdropBorderColor(unpack(ACCENT))
        exportFrame:Hide()
        tinsert(UISpecialFrames, "BozoRaidToolsExportFrame")

        local titleText = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        titleText:SetPoint("TOP", 0, -14)
        exportFrame.titleText = titleText

        local hint = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("TOP", titleText, "BOTTOM", 0, -6)
        hint:SetText("Ctrl+A to select all, Ctrl+C to copy -- then paste it into Discord, a spreadsheet, wherever.")

        local scrollAnchor = CreateFrame("Frame", nil, exportFrame, "BackdropTemplate")
        scrollAnchor:SetPoint("TOPLEFT", 16, -60)
        scrollAnchor:SetPoint("BOTTOMRIGHT", -16, 46)
        scrollAnchor:SetBackdrop({ bgFile = WHITE_TEX, edgeFile = WHITE_TEX, edgeSize = 1 })
        scrollAnchor:SetBackdropColor(unpack(ROW_BG))
        scrollAnchor:SetBackdropBorderColor(unpack(BORDER))

        local scroll, content, UpdateScrollbar = ns.CreateScrollFrame(scrollAnchor)

        local editBox = CreateFrame("EditBox", nil, content)
        editBox:SetMultiLine(true)
        editBox:SetFontObject(ChatFontNormal)
        editBox:SetAutoFocus(false)
        editBox:SetPoint("TOPLEFT", 6, -6)
        editBox:SetWidth(scrollAnchor:GetWidth() - ns.SCROLLBAR_CLEARANCE - 12)
        editBox:SetScript("OnEscapePressed", function()
            exportFrame:Hide()
        end)
        editBox:SetScript("OnTextChanged", function(self)
            content:SetSize(math.max(self:GetWidth(), 1), math.max(self:GetHeight() + 12, 1))
            UpdateScrollbar()
        end)
        exportFrame.editBox = editBox

        local closeBtn = ns.CreateStyledButton(exportFrame, "Close", 100, 24, true)
        closeBtn:SetPoint("BOTTOM", 0, 14)
        closeBtn:SetScript("OnClick", function()
            exportFrame:Hide()
        end)
    end

    exportFrame.titleText:SetText(title)
    exportFrame.editBox:SetText(text)
    exportFrame:Show()
    exportFrame.editBox:SetFocus()
    exportFrame.editBox:HighlightText()
end

-- ===== Import dialog (paste CSV back in) =====
-- Same no-filesystem-access reasoning as export -- this is a plain editable
-- text box, not a real file picker. Each caller supplies its own onImport
-- parser since Attendance's and Loot's CSV shapes are different.
local importFrame

function ns.ShowImportDialog(title, onImport)
    if not importFrame then
        importFrame = CreateFrame("Frame", "BozoRaidToolsImportFrame", UIParent, "BackdropTemplate")
        importFrame:SetSize(600, 420)
        importFrame:SetPoint("CENTER")
        importFrame:SetFrameStrata("DIALOG")
        importFrame:SetMovable(true)
        importFrame:EnableMouse(true)
        importFrame:RegisterForDrag("LeftButton")
        importFrame:SetScript("OnDragStart", importFrame.StartMoving)
        importFrame:SetScript("OnDragStop", importFrame.StopMovingOrSizing)
        importFrame:SetBackdrop({ bgFile = WHITE_TEX, edgeFile = WHITE_TEX, edgeSize = 1 })
        importFrame:SetBackdropColor(unpack(PANEL_BG))
        importFrame:SetBackdropBorderColor(unpack(ACCENT))
        importFrame:Hide()
        tinsert(UISpecialFrames, "BozoRaidToolsImportFrame")

        local titleText = importFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        titleText:SetPoint("TOP", 0, -14)
        importFrame.titleText = titleText

        local hint = importFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("TOP", titleText, "BOTTOM", 0, -6)
        hint:SetText("Paste CSV text below (from a matching Export), then click Import. This adds to existing data, it doesn't replace it.")

        local scrollAnchor = CreateFrame("Frame", nil, importFrame, "BackdropTemplate")
        scrollAnchor:SetPoint("TOPLEFT", 16, -60)
        scrollAnchor:SetPoint("BOTTOMRIGHT", -16, 46)
        scrollAnchor:SetBackdrop({ bgFile = WHITE_TEX, edgeFile = WHITE_TEX, edgeSize = 1 })
        scrollAnchor:SetBackdropColor(unpack(ROW_BG))
        scrollAnchor:SetBackdropBorderColor(unpack(BORDER))

        local scroll, content, UpdateScrollbar = ns.CreateScrollFrame(scrollAnchor)

        local editBox = CreateFrame("EditBox", nil, content)
        editBox:SetMultiLine(true)
        editBox:SetFontObject(ChatFontNormal)
        editBox:SetAutoFocus(true)
        editBox:SetPoint("TOPLEFT", 6, -6)
        editBox:SetWidth(scrollAnchor:GetWidth() - ns.SCROLLBAR_CLEARANCE - 12)
        editBox:SetScript("OnEscapePressed", function()
            importFrame:Hide()
        end)
        editBox:SetScript("OnTextChanged", function(self)
            content:SetSize(math.max(self:GetWidth(), 1), math.max(self:GetHeight() + 12, 1))
            UpdateScrollbar()
        end)
        importFrame.editBox = editBox

        local importBtn = ns.CreateStyledButton(importFrame, "Import", 100, 24, true)
        importBtn:SetPoint("BOTTOM", -56, 14)
        importBtn:SetScript("OnClick", function()
            local text = importFrame.editBox:GetText()
            if importFrame.onImport and text ~= "" then
                importFrame.onImport(text)
            end
            importFrame:Hide()
        end)

        local cancelBtn = ns.CreateStyledButton(importFrame, "Cancel", 100, 24, false)
        cancelBtn:SetPoint("BOTTOM", 56, 14)
        cancelBtn:SetScript("OnClick", function()
            importFrame:Hide()
        end)
    end

    importFrame.titleText:SetText(title)
    importFrame.editBox:SetText("")
    importFrame.onImport = onImport
    importFrame:Show()
    importFrame.editBox:SetFocus()
end

-- Minimal CSV line parser -- handles quoted fields with embedded commas and
-- escaped ("") double-quotes, matching what our own export dialogs produce.
function ns.ParseCSVLine(line)
    local fields = {}
    local pos = 1
    local len = #line
    while pos <= len do
        if line:sub(pos, pos) == '"' then
            local value = ""
            local scan = pos + 1
            while scan <= len do
                if line:sub(scan, scan) == '"' then
                    if line:sub(scan + 1, scan + 1) == '"' then
                        value = value .. '"'
                        scan = scan + 2
                    else
                        scan = scan + 1
                        break
                    end
                else
                    value = value .. line:sub(scan, scan)
                    scan = scan + 1
                end
            end
            table.insert(fields, value)
            pos = (line:find(",", scan) or len) + 1
        else
            local commaPos = line:find(",", pos) or (len + 1)
            table.insert(fields, line:sub(pos, commaPos - 1))
            pos = commaPos + 1
        end
    end
    return fields
end

-- ===== Minimap button (self-contained, no external libraries) =====
local mmButton = CreateFrame("Button", "BozoRaidToolsMinimapButton", Minimap)
mmButton:SetSize(31, 31)
mmButton:SetFrameStrata("MEDIUM")
mmButton:SetFrameLevel(8)
mmButton:RegisterForClicks("LeftButtonUp")
mmButton:RegisterForDrag("LeftButton")
mmButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local icon = mmButton:CreateTexture(nil, "BACKGROUND")
icon:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")
icon:SetSize(20, 20)
icon:SetPoint("CENTER", 0, 1)
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

local border = mmButton:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetSize(54, 54)
border:SetPoint("TOPLEFT")

function ns.UpdateMinimapPosition()
    local angle = math.rad((ns.db and ns.db.minimapAngle) or 215)
    local radius = 80
    mmButton:ClearAllPoints()
    mmButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end
ns.UpdateMinimapPosition()

mmButton:SetScript("OnDragStart", function(self)
    self.dragging = true
end)
mmButton:SetScript("OnDragStop", function(self)
    self.dragging = false
end)
mmButton:SetScript("OnUpdate", function(self)
    if not self.dragging then
        return
    end
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale
    local angle = math.deg(math.atan2(py - my, px - mx))
    if ns.db then
        ns.db.minimapAngle = angle
    end
    ns.UpdateMinimapPosition()
end)
mmButton:SetScript("OnClick", function()
    ns.ToggleMainFrame()
end)
mmButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Bozo Raid Tools")
    GameTooltip:AddLine("Click to open", 1, 1, 1)
    GameTooltip:Show()
end)
mmButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)
