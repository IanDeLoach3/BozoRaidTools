local ADDON_NAME, ns = ...

local activeSession = nil -- { name, members = { [name] = true } }

-- Exposed so Loot.lua can gate auto-logging (loot/trades) behind an active
-- raid -- casual solo/world loot shouldn't pollute the raid loot log.
function ns.IsRaidActive()
    return activeSession ~= nil
end

-- Content area is the 900px main frame minus UI.lua's 16px margin each side.
local PANEL_CONTENT_WIDTH = 868
local COLUMN_GAP = 20
local COLUMN_WIDTH = (PANEL_CONTENT_WIDTH - COLUMN_GAP) / 2

local function GetGroupMembers()
    local members = {}
    local total = GetNumGroupMembers()
    if total == 0 then
        members[UnitName("player")] = true
        return members
    end
    local inRaid = IsInRaid()
    if not inRaid then
        members[UnitName("player")] = true
    end
    local prefix = inRaid and "raid" or "party"
    for i = 1, total do
        local unit = prefix .. i
        if UnitExists(unit) then
            local name = UnitName(unit)
            if name then
                members[name] = true
            end
        end
    end
    return members
end

-- ===== Panel =====
local panel = ns.RegisterTab("attendance", "Attendance")

local statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
statusText:SetPoint("TOPLEFT", 0, 0)
statusText:SetPoint("RIGHT")
statusText:SetJustifyH("LEFT")

local nameBox = ns.CreateEditBox(panel, 180)
nameBox:SetPoint("TOPLEFT", statusText, "BOTTOMLEFT", 0, -10)

local startBtn = ns.CreateStyledButton(panel, "Start Raid", 110, 22, true)
startBtn:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)

local snapshotBtn = ns.CreateStyledButton(panel, "Snapshot Group", 140, 22, true)
snapshotBtn:SetPoint("TOPLEFT", nameBox, "TOPLEFT", 0, 0)

local endBtn = ns.CreateStyledButton(panel, "End Raid", 110, 22, false)
endBtn:SetPoint("LEFT", snapshotBtn, "RIGHT", 8, 0)

-- Fixed top-right position, independent of startBtn/endBtn -- those two swap
-- places depending on session state and (despite sharing nameBox/snapshotBtn's
-- top-left corner) land at different X offsets since nameBox and snapshotBtn
-- aren't the same width, so anchoring off just one of them doesn't work.
local exportBtn = ns.CreateStyledButton(panel, "Export Attendance", 160, 22, false)
exportBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -1)

local importBtn = ns.CreateStyledButton(panel, "Import Attendance", 160, 22, false)
importBtn:SetPoint("RIGHT", exportBtn, "LEFT", -8, 0)

local summaryBtn = ns.CreateStyledButton(panel, "Post-Raid Summary", 160, 22, true)
summaryBtn:SetPoint("RIGHT", importBtn, "LEFT", -8, 0)

-- Left column: per-player totals.
-- TOPLEFT + BOTTOMLEFT (both pinned to the same x, via panel's own left edge)
-- plus an explicit SetWidth is the safe pattern -- no point that implies a
-- RIGHT/center position conflicting with the explicit width (the same
-- mismatched-anchor bug caught earlier in Loot.lua and Wishlist.lua).
local reportLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
reportLabel:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", 0, -14)
reportLabel:SetText("Attendance totals (click an entry to remove it):")

-- 34px reserved at the bottom for the Clear All row.
local listAnchor = CreateFrame("Frame", nil, panel)
listAnchor:SetPoint("TOPLEFT", reportLabel, "BOTTOMLEFT", 0, -6)
listAnchor:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 34)
listAnchor:SetWidth(COLUMN_WIDTH)
local scroll, rowList = ns.CreateRowList(listAnchor)

-- Right column: last 10 saved sessions. Anchored off nameBox (x=0 relative to
-- panel) with an explicit column offset, NOT off reportLabel's own right edge
-- -- a FontString with no RIGHT point auto-sizes to its text, so its width has
-- nothing to do with COLUMN_WIDTH and would misalign the second column.
local recentLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
recentLabel:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", COLUMN_WIDTH + COLUMN_GAP, -14)
recentLabel:SetText("Recent sessions, last 10 (click to view summary, x to remove):")

local recentAnchor = CreateFrame("Frame", nil, panel)
recentAnchor:SetPoint("TOPLEFT", recentLabel, "BOTTOMLEFT", 0, -6)
recentAnchor:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", COLUMN_WIDTH + COLUMN_GAP, 34)
recentAnchor:SetWidth(COLUMN_WIDTH)
local recentScroll, recentRows = ns.CreateRowList(recentAnchor)

local clearAllBtn = ns.CreateStyledButton(panel, "Clear All Attendance Data", 220, 24, false)
clearAllBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)

-- Row index -> data key, rebuilt every refresh, read by the click-to-remove
-- handlers below (row order can change between refreshes, e.g. re-sorting
-- totals by count, so this can't be computed once and cached).
local totalsRowNames = {}
local sessionsRowIndex = {}

local function RefreshReport()
    local sorted = {}
    for name, count in pairs(ns.db.attendance.totals) do
        table.insert(sorted, { name = name, count = count })
    end
    table.sort(sorted, function(a, b)
        return a.count > b.count
    end)
    local lines = {}
    totalsRowNames = {}
    for _, entry in ipairs(sorted) do
        table.insert(lines, entry.name .. ": " .. entry.count)
        table.insert(totalsRowNames, entry.name)
    end
    if #lines == 0 then
        lines = { "No attendance data yet." }
    end
    rowList:SetRows(lines)
end

local function RefreshRecentSessions()
    local sessions = ns.db.attendance.sessions
    local lines = {}
    sessionsRowIndex = {}
    for i = #sessions, math.max(1, #sessions - 9), -1 do
        local s = sessions[i]
        local line = "[" .. s.date .. "] " .. s.name .. " -- " .. s.memberCount .. " present"
        if s.runBy then
            line = line .. " |cff888888(run by " .. s.runBy .. ")|r"
        end
        table.insert(lines, line)
        table.insert(sessionsRowIndex, i)
    end
    if #lines == 0 then
        lines = { "No sessions saved yet." }
    end
    recentRows:SetRows(lines)
end

rowList.onRowClick = function(rowIndex)
    local name = totalsRowNames[rowIndex]
    if not name then
        return
    end
    ns.ShowConfirmDialog("Remove " .. name .. " from attendance totals?", function()
        ns.db.attendance.totals[name] = nil
        RefreshReport()
    end)
end

-- Combines a session's attendance with whatever loot was logged during its
-- time window into one paste-ready block. Sessions saved before startDate
-- existed (older data) fall back to matching loot by calendar day instead of
-- a precise time window -- looser, but still useful rather than empty.
-- Uses Discord markdown (bold, bullets, a code fence for the totals table)
-- since this text's whole purpose is to be pasted into Discord -- it'll
-- render properly there, even though WoW's own EditBox just shows the
-- literal ** and ``` characters in the local preview, which is expected.
local function BuildPostRaidSummary(session)
    local lines = { "**" .. session.name .. "**" }
    local subline = session.date
    if session.startDate and session.startDate ~= session.date then
        subline = session.startDate .. " to " .. session.date
    end
    if session.runBy then
        subline = subline .. " - Run by " .. session.runBy
    end
    table.insert(lines, subline)
    table.insert(lines, "")

    local names = {}
    for name in pairs(session.members) do
        table.insert(names, name)
    end
    table.sort(names)
    table.insert(lines, "**Attendance (" .. session.memberCount .. ")**")
    table.insert(lines, table.concat(names, ", "))
    table.insert(lines, "")

    local lootLines, lootCounts = {}, {}
    for _, entry in ipairs(ns.db.lootLog) do
        local inWindow
        if session.startDate then
            inWindow = entry.date >= session.startDate and entry.date <= session.date
        else
            inWindow = entry.date:sub(1, 10) == session.date:sub(1, 10)
        end
        if inWindow then
            local displayName = entry.item
            if ns.ResolveItem then
                local resolved = ns.ResolveItem(entry.item)
                displayName = (resolved or entry.item):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            end
            table.insert(lootLines, "- " .. entry.date:sub(12) .. " " .. entry.winner .. " - " .. displayName)
            lootCounts[entry.winner] = (lootCounts[entry.winner] or 0) + 1
        end
    end

    table.insert(lines, "**Loot (" .. #lootLines .. ")**")
    if #lootLines == 0 then
        table.insert(lines, "(none logged)")
    else
        for _, l in ipairs(lootLines) do
            table.insert(lines, l)
        end
    end

    local sortedCounts = {}
    for name, count in pairs(lootCounts) do
        table.insert(sortedCounts, { name = name, count = count })
    end
    if #sortedCounts > 0 then
        table.sort(sortedCounts, function(a, b)
            return a.count > b.count
        end)
        table.insert(lines, "")
        table.insert(lines, "**Loot by Player**")
        table.insert(lines, "```")
        for _, entry in ipairs(sortedCounts) do
            table.insert(lines, entry.name .. "  " .. entry.count)
        end
        table.insert(lines, "```")
    end

    return table.concat(lines, "\n")
end

-- Click a session to view its full summary (item + attendance detail, ready
-- to copy into Discord). Click the separate [x] to remove it -- the two no
-- longer share a click handler now that CreateRowList supports onRowRemove.
recentRows.onRowClick = function(rowIndex)
    local sessionIndex = sessionsRowIndex[rowIndex]
    local session = sessionIndex and ns.db.attendance.sessions[sessionIndex]
    if not session then
        return
    end
    ns.ShowExportDialog("Raid Summary: " .. session.name, BuildPostRaidSummary(session))
end

recentRows.onRowRemove = function(rowIndex)
    local sessionIndex = sessionsRowIndex[rowIndex]
    local session = sessionIndex and ns.db.attendance.sessions[sessionIndex]
    if not session then
        return
    end
    ns.ShowConfirmDialog("Remove the session \"" .. session.name .. "\"?", function()
        -- Undo this session's contribution to the totals column too, so
        -- removing a session and the totals list don't silently drift apart.
        for name in pairs(session.members) do
            local count = ns.db.attendance.totals[name]
            if count then
                if count <= 1 then
                    ns.db.attendance.totals[name] = nil
                else
                    ns.db.attendance.totals[name] = count - 1
                end
            end
        end
        table.remove(ns.db.attendance.sessions, sessionIndex)
        RefreshReport()
        RefreshRecentSessions()
    end)
end

clearAllBtn:SetScript("OnClick", function()
    ns.ShowConfirmDialog("Clear ALL attendance data? This cannot be undone.", function()
        ns.db.attendance.totals = {}
        ns.db.attendance.sessions = {}
        RefreshReport()
        RefreshRecentSessions()
        print("|cff33ff99[BRT]|r All attendance data cleared.")
    end)
end)

local function RefreshStatus()
    if activeSession then
        local count = 0
        for _ in pairs(activeSession.members) do
            count = count + 1
        end
        statusText:SetText("Raid in progress: |cffffff00" .. activeSession.name .. "|r — " .. count .. " recorded. Loot and trades log automatically -- just play. Click End Raid when done.")
        nameBox:Hide()
        startBtn:Hide()
        snapshotBtn:Show()
        endBtn:Show()
    else
        statusText:SetText("No raid in progress. Click Start Raid, then close this window -- attendance, loot, and trades all save automatically.")
        nameBox:Show()
        startBtn:Show()
        snapshotBtn:Hide()
        endBtn:Hide()
    end
end

startBtn:SetScript("OnClick", function()
    local name = nameBox:GetText()
    if name == "" then
        name = "Raid " .. date("%Y-%m-%d %H:%M")
    end
    -- Just the officer's own character name, read locally off their own
    -- client -- not any kind of login/auth, there's no such thing available
    -- to a WoW addon. Lets each officer's own log say who ran it once
    -- multiple officers are each running their own separate copy.
    activeSession = { name = name, members = {}, startDate = date("%Y-%m-%d %H:%M"), runBy = UnitName("player") }
    nameBox:SetText("")
    RefreshStatus()
end)

snapshotBtn:SetScript("OnClick", function()
    if not activeSession then
        return
    end
    for name in pairs(GetGroupMembers()) do
        activeSession.members[name] = true
    end
    RefreshStatus()
end)

endBtn:SetScript("OnClick", function()
    if not activeSession then
        return
    end
    -- Always take a final snapshot on end, so Start -> End still saves real
    -- data even if Snapshot Group was never clicked mid-raid -- otherwise the
    -- session gets saved with zero members and looks like nothing happened.
    for name in pairs(GetGroupMembers()) do
        activeSession.members[name] = true
    end
    local memberCount = 0
    for name in pairs(activeSession.members) do
        memberCount = memberCount + 1
        ns.db.attendance.totals[name] = (ns.db.attendance.totals[name] or 0) + 1
    end
    table.insert(ns.db.attendance.sessions, {
        name = activeSession.name,
        date = date("%Y-%m-%d %H:%M"),
        startDate = activeSession.startDate,
        runBy = activeSession.runBy,
        memberCount = memberCount,
        members = activeSession.members,
    })
    activeSession = nil
    RefreshStatus()
    RefreshReport()
    RefreshRecentSessions()
end)

-- CSV export: one row per saved session (all of them, not just the last 10
-- shown on screen), plus a totals block underneath so both views travel
-- together in a single paste.
local function BuildAttendanceExport()
    local lines = { "Session Name,Date,Members Present" }
    for _, s in ipairs(ns.db.attendance.sessions) do
        local escapedName = s.name:gsub('"', '""')
        table.insert(lines, string.format('"%s",%s,%d', escapedName, s.date, s.memberCount))
    end

    table.insert(lines, "")
    table.insert(lines, "Player,Sessions Attended")
    local sorted = {}
    for name, count in pairs(ns.db.attendance.totals) do
        table.insert(sorted, { name = name, count = count })
    end
    table.sort(sorted, function(a, b)
        return a.count > b.count
    end)
    for _, entry in ipairs(sorted) do
        table.insert(lines, entry.name .. "," .. entry.count)
    end

    return table.concat(lines, "\n")
end

exportBtn:SetScript("OnClick", function()
    ns.ShowExportDialog("Attendance Export (CSV)", BuildAttendanceExport())
end)

-- Only the "Player,Sessions Attended" section is reimportable -- the session
-- history rows don't include per-session member names in the export (just a
-- count), so there's not enough detail to reconstruct real session records.
-- Imported totals ADD to whatever's already there, they don't replace it.
local function ImportAttendanceCSV(text)
    local inTotalsSection = false
    local imported = 0
    for line in text:gmatch("[^\r\n]+") do
        local fields = ns.ParseCSVLine(line)
        if fields[1] == "Player" and fields[2] == "Sessions Attended" then
            inTotalsSection = true
        elseif inTotalsSection and fields[1] and fields[1] ~= "" and tonumber(fields[2]) then
            ns.db.attendance.totals[fields[1]] = (ns.db.attendance.totals[fields[1]] or 0) + tonumber(fields[2])
            imported = imported + 1
        end
    end
    RefreshReport()
    print(
        "|cff33ff99[BRT]|r Imported attendance totals for "
            .. imported
            .. " player(s). (Session history isn't preserved by export/import, only totals.)"
    )
end

importBtn:SetScript("OnClick", function()
    ns.ShowImportDialog("Import Attendance (CSV)", ImportAttendanceCSV)
end)

summaryBtn:SetScript("OnClick", function()
    local sessions = ns.db.attendance.sessions
    local last = sessions[#sessions]
    if not last then
        print("|cff33ff99[BRT]|r No saved sessions yet -- end a session first.")
        return
    end
    ns.ShowExportDialog("Raid Summary: " .. last.name, BuildPostRaidSummary(last))
end)

panel:SetScript("OnShow", function()
    RefreshStatus()
    RefreshReport()
    RefreshRecentSessions()
end)
