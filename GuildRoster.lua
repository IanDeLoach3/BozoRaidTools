local ADDON_NAME, ns = ...

-- Same compat-shim approach as ns.GetItemInfo in UI.lua: the refresh trigger
-- moved to C_GuildInfo.GuildRoster() in patch 8.2.0 (2019), but fall back to
-- the older bare global just in case this client doesn't have the namespaced
-- version either. Still used here to keep guild notes/rank fresh for
-- whichever group members happen to also be guildmates -- the roster list
-- itself now comes from your current party/raid, not the full guild.
local RequestGuildRoster = (C_GuildInfo and C_GuildInfo.GuildRoster) or GuildRoster

local function ClassColorHex(classFile)
    local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if not c then
        return nil
    end
    if c.colorStr then
        return c.colorStr
    end
    return string.format("ff%02x%02x%02x", (c.r or 1) * 255, (c.g or 1) * 255, (c.b or 1) * 255)
end

local function ChatColorGray(text)
    return "|cff888888" .. text .. "|r"
end

-- ===== Gear inspect =====
-- Verified NotifyInspect / INSPECT_READY / GetInventoryItemLink are all
-- still current, unmoved globals (unlike GetItemInfo) via Warcraft Wiki
-- directly before building this.
local GEAR_SLOTS = {
    { INVSLOT_HEAD, "Head" },
    { INVSLOT_NECK, "Neck" },
    { INVSLOT_SHOULDER, "Shoulder" },
    { INVSLOT_BACK, "Back" },
    { INVSLOT_CHEST, "Chest" },
    { INVSLOT_WRIST, "Wrist" },
    { INVSLOT_HAND, "Hands" },
    { INVSLOT_WAIST, "Waist" },
    { INVSLOT_LEGS, "Legs" },
    { INVSLOT_FEET, "Feet" },
    { INVSLOT_FINGER1, "Ring 1" },
    { INVSLOT_FINGER2, "Ring 2" },
    { INVSLOT_TRINKET1, "Trinket 1" },
    { INVSLOT_TRINKET2, "Trinket 2" },
    { INVSLOT_MAINHAND, "Main Hand" },
    { INVSLOT_OFFHAND, "Off Hand" },
    { INVSLOT_RANGED, "Ranged" },
}

local pendingInspectName, pendingInspectUnit = nil, nil

local function BuildGearEntries(unit)
    local entries = {}
    for _, slot in ipairs(GEAR_SLOTS) do
        local slotID, label = slot[1], slot[2]
        local link = slotID and GetInventoryItemLink(unit, slotID)
        if link then
            local itemName, _, quality, ilvl, _, _, _, _, _, texture = ns.GetItemInfo(link)
            table.insert(entries, {
                label = label,
                name = itemName or link,
                quality = quality,
                ilvl = ilvl,
                texture = texture,
            })
        else
            table.insert(entries, { label = label })
        end
    end
    return entries
end

-- Unlike the old guild-wide version, the roster list is now built directly
-- from live party/raid units, so the unit token for a clicked row is already
-- known -- no more searching for it by name after the fact.
local function RequestGearInspect(unit, name)
    if not UnitExists(unit) then
        print("|cff33ff99[BRT]|r " .. name .. " isn't in your group anymore.")
        return
    end
    if CanInspect and not CanInspect(unit) then
        print("|cff33ff99[BRT]|r " .. name .. " can't be inspected right now (out of range?).")
        return
    end

    pendingInspectName, pendingInspectUnit = name, unit
    NotifyInspect(unit)

    -- The server can silently throttle inspect requests with no event at all
    -- (documented behavior since patch 3.3.5) -- without a timeout, a
    -- throttled request would just leave the addon "waiting" forever with no
    -- feedback.
    C_Timer.After(8, function()
        if pendingInspectUnit == unit then
            pendingInspectName, pendingInspectUnit = nil, nil
            print("|cff33ff99[BRT]|r Inspect request for " .. name .. " timed out -- try again.")
        end
    end)
end

local inspectFrame = CreateFrame("Frame")
inspectFrame:RegisterEvent("INSPECT_READY")
inspectFrame:SetScript("OnEvent", function(self, event, guid)
    if not pendingInspectUnit then
        return
    end
    -- Older clients fire INSPECT_READY with no guid arg at all; only check it
    -- when one is actually provided.
    if guid and UnitGUID(pendingInspectUnit) ~= guid then
        return
    end
    local unit, name = pendingInspectUnit, pendingInspectName
    pendingInspectUnit, pendingInspectName = nil, nil
    local entries = BuildGearEntries(unit)
    ClearInspectPlayer()
    ns.ShowGearDialog(name, entries)
end)

-- ===== Panel =====
local panel = ns.RegisterTab("roster", "Roster")

local onlineOnly = true

local statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
statusText:SetPoint("TOPLEFT", 0, 0)
statusText:SetPoint("RIGHT")
statusText:SetJustifyH("LEFT")

local refreshBtn = ns.CreateStyledButton(panel, "Refresh", 100, 22, true)
refreshBtn:SetPoint("TOPLEFT", statusText, "BOTTOMLEFT", 0, -10)

local toggleBtn = ns.CreateStyledButton(panel, "Show: Online Only", 180, 22, false)
toggleBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 8, 0)

-- ===== Alt/main links =====
-- Pure local bookkeeping (ns.db.altLinks[altName] = mainName) -- there's no
-- API for "which characters belong to the same person", so this has to be
-- officer-entered. Shown as "(alt of X)" directly on the matching roster
-- row below, which doubles as the way to review existing links -- no
-- separate list needed. To unlink, enter the alt's name with Main left
-- blank and click Link.
local altBox = ns.CreateEditBox(panel, 160)
altBox:SetPoint("TOPLEFT", refreshBtn, "BOTTOMLEFT", 0, -12)

local altHint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
altHint:SetPoint("LEFT", altBox, "RIGHT", 6, 0)
altHint:SetText("Alt")

local mainBox = ns.CreateEditBox(panel, 160)
mainBox:SetPoint("LEFT", altHint, "RIGHT", 10, 0)

local mainHint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
mainHint:SetPoint("LEFT", mainBox, "RIGHT", 6, 0)
mainHint:SetText("Main (leave blank to unlink)")

local linkBtn = ns.CreateStyledButton(panel, "Link", 90, 22, true)
linkBtn:SetPoint("LEFT", mainHint, "RIGHT", 10, 0)

local listAnchor = CreateFrame("Frame", nil, panel)
listAnchor:SetPoint("TOPLEFT", altBox, "BOTTOMLEFT", 0, -14)
listAnchor:SetPoint("BOTTOMRIGHT", 0, 0)
local scroll, rowList = ns.CreateRowList(listAnchor)

-- Current party/raid units, always including "player" (so a solo "group" of
-- just you still shows something) -- same solo-fallback pattern already used
-- for attendance snapshots and loot's class-colored names elsewhere.
local function GetGroupUnits()
    local units = {}
    local total = GetNumGroupMembers()
    if total == 0 then
        table.insert(units, "player")
        return units
    end
    local inRaid = IsInRaid()
    if not inRaid then
        table.insert(units, "player")
    end
    local prefix = inRaid and "raid" or "party"
    for i = 1, total do
        local unit = prefix .. i
        if UnitExists(unit) then
            table.insert(units, unit)
        end
    end
    return units
end

-- Cross-references group members against the real guild roster for rank and
-- notes -- only meaningful for members who are ALSO guildmates (a PUG in
-- your raid just won't have an entry here, and shows without that detail).
local function BuildGuildInfoLookup()
    local lookup = {}
    if not IsInGuild() then
        return lookup
    end
    for i = 1, GetNumGuildMembers() do
        local name, rankName, _, _, _, _, publicNote, officerNote = GetGuildRosterInfo(i)
        if name then
            local shortName = name:match("^[^-]+") or name
            lookup[shortName] = { rankName = rankName, publicNote = publicNote, officerNote = officerNote }
        end
    end
    return lookup
end

-- Zone isn't available for party members via a clean API, but GetRaidRosterInfo
-- returns it directly for raid members (7th return value).
local function GetRaidZone(unit)
    if not IsInRaid() then
        return nil
    end
    local idx = tonumber(unit:match("^raid(%d+)$"))
    if not idx then
        return nil
    end
    local _, _, _, _, _, _, zone = GetRaidRosterInfo(idx)
    return zone
end

local function BuildRosterLines()
    local units = GetGroupUnits()
    local guildInfo = BuildGuildInfoLookup()
    local entries = {}
    local onlineCount = 0

    for _, unit in ipairs(units) do
        local name = UnitName(unit)
        if name then
            local isOnline = UnitIsConnected(unit)
            if isOnline then
                onlineCount = onlineCount + 1
            end
            if not onlineOnly or isOnline then
                local className, classFile = UnitClass(unit)
                table.insert(entries, {
                    unit = unit,
                    name = name,
                    className = className,
                    classFile = classFile,
                    level = UnitLevel(unit),
                    isOnline = isOnline,
                    zone = GetRaidZone(unit),
                    info = guildInfo[name],
                })
            end
        end
    end

    table.sort(entries, function(a, b)
        if a.isOnline ~= b.isOnline then
            return a.isOnline
        end
        return a.name < b.name
    end)

    local lines, units_out = {}, {}
    for _, e in ipairs(entries) do
        local hex = ClassColorHex(e.classFile)
        local coloredName = hex and ("|c" .. hex .. e.name .. "|r") or e.name
        local dot = e.isOnline and "|cff33ff99*|r" or ChatColorGray("o")
        local rankPart = (e.info and e.info.rankName) and (", " .. e.info.rankName) or ""
        local line = dot
            .. " "
            .. coloredName
            .. " "
            .. ChatColorGray("(Lv" .. (e.level or "?") .. " " .. (e.className or "?") .. rankPart .. ")")
        if e.isOnline and e.zone and e.zone ~= "" then
            line = line .. ChatColorGray(" - " .. e.zone)
        end
        if e.info and e.info.publicNote and e.info.publicNote ~= "" then
            line = line .. ChatColorGray(" | Note: ") .. e.info.publicNote
        end
        if e.info and e.info.officerNote and e.info.officerNote ~= "" then
            line = line .. ChatColorGray(" | Officer: ") .. "|cffff8800" .. e.info.officerNote .. "|r"
        end
        local mainName = ns.db.altLinks[e.name]
        if mainName then
            line = line .. ChatColorGray(" | alt of " .. mainName)
        end
        table.insert(lines, line)
        table.insert(units_out, { unit = e.unit, name = e.name })
    end

    return lines, #entries, onlineCount, units_out
end

-- Row position -> { unit, name }, used by the click-to-inspect handler
-- below. Rebuilt on every refresh since sort order (online-first, then
-- alphabetical) can shuffle row positions between refreshes.
local rosterRowUnits = {}

local function RefreshRoster()
    -- Defensive: if this specific WoW Forever client turns out to have moved
    -- or removed one of these group/unit functions (same surprise as
    -- GetItemInfo), fail visibly in the tab instead of spamming a Lua error
    -- every refresh.
    local ok, linesOrErr, total, onlineCount, unitsOut = pcall(BuildRosterLines)
    if not ok then
        statusText:SetText("Couldn't read your group (API error) -- tell Bozo about this.")
        print("|cff33ff99[BRT]|r Roster error: " .. tostring(linesOrErr))
        rowList:SetRows({})
        return
    end

    rosterRowUnits = unitsOut
    statusText:SetText(total .. " in your group, " .. onlineCount .. " online -- click a name to inspect their gear")
    if #linesOrErr == 0 then
        linesOrErr = { onlineOnly and "No one online." or "Not in a group." }
    end
    rowList:SetRows(linesOrErr)
end

rowList.onRowClick = function(rowIndex)
    local entry = rosterRowUnits[rowIndex]
    if entry then
        RequestGearInspect(entry.unit, entry.name)
    end
end

linkBtn:SetScript("OnClick", function()
    local altName = altBox:GetText()
    local mainName = mainBox:GetText()
    if altName == "" then
        print("|cff33ff99[BRT]|r Enter the alt's name first.")
        return
    end
    if mainName == "" then
        if ns.db.altLinks[altName] then
            ns.db.altLinks[altName] = nil
            print("|cff33ff99[BRT]|r Unlinked " .. altName .. ".")
        else
            print("|cff33ff99[BRT]|r " .. altName .. " wasn't linked to anything.")
        end
    else
        ns.db.altLinks[altName] = mainName
        print("|cff33ff99[BRT]|r " .. altName .. " marked as an alt of " .. mainName .. ".")
    end
    altBox:SetText("")
    mainBox:SetText("")
    RefreshRoster()
end)

refreshBtn:SetScript("OnClick", function()
    RequestGuildRoster()
    RefreshRoster()
end)

toggleBtn:SetScript("OnClick", function()
    onlineOnly = not onlineOnly
    toggleBtn:SetText(onlineOnly and "Show: Online Only" or "Show: Everyone")
    RefreshRoster()
end)

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
eventFrame:SetScript("OnEvent", function()
    if panel:IsShown() then
        RefreshRoster()
    end
end)

panel:SetScript("OnShow", function()
    RequestGuildRoster()
    RefreshRoster()
end)
