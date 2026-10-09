local ADDON_NAME, ns = ...

local function AnnounceChannel()
    if IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    end
    return nil
end

local function Announce(msg)
    local channel = AnnounceChannel()
    if channel then
        SendChatMessage(msg, channel)
    else
        print("|cff33ff99[BRT]|r " .. msg .. " (not in a group, local only)")
    end
end

-- Resolves either a real item link or a plain typed name/text into a
-- quality-colored display string, the canonical link (if resolvable), and an
-- icon texture -- falls back to the raw text with no icon if the item isn't
-- in the client's local cache yet (still fully usable, just plainer).
local function ResolveItem(text)
    local name, link, quality = ns.GetItemInfo(text)
    if not name then
        return text, nil
    end
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    local displayText = (color and color.hex) and (color.hex .. name .. "|r") or name
    return displayText, link or text
end
ns.ResolveItem = ResolveItem -- shared with Roster.lua for the post-raid summary

-- ===== Test data generator (/brt testloot) =====
-- Pulls REAL items straight out of your own bags rather than fabricating
-- item IDs -- guessing at item IDs risks wrong/nonexistent items (icons,
-- names, quality would all be wrong), whereas whatever's actually in your
-- bags is guaranteed correct. Lets you exercise the whole Loot tab (icons,
-- roll breakdowns, detail popup, export) without waiting for a real raid.
local function GetAnyBagItemLink(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        return info and info.hyperlink or nil
    elseif _G.GetContainerItemInfo then
        local _, _, _, _, _, _, link = _G.GetContainerItemInfo(bag, slot)
        return link
    end
    return nil
end

local function CollectBagItemLinks(maxCount)
    local links = {}
    local getNumSlots = (C_Container and C_Container.GetContainerNumSlots) or _G.GetContainerNumSlots
    if not getNumSlots then
        return links
    end
    local maxBag = NUM_BAG_SLOTS or 4
    for bag = 0, maxBag do
        local slots = getNumSlots(bag) or 0
        for slot = 1, slots do
            local link = GetAnyBagItemLink(bag, slot)
            if link then
                table.insert(links, link)
                if #links >= maxCount then
                    return links
                end
            end
        end
    end
    return links
end

-- Real party/raid names if you're grouped (more realistic to test with),
-- otherwise plain placeholder names.
local function CollectTestNames(maxCount)
    local names = {}
    local total = GetNumGroupMembers()
    if total > 0 then
        local prefix = IsInRaid() and "raid" or "party"
        for i = 1, total do
            local unit = prefix .. i
            if UnitExists(unit) then
                local n = UnitName(unit)
                if n then
                    table.insert(names, n)
                end
            end
            if #names >= maxCount then
                break
            end
        end
    end
    if #names == 0 then
        names = { "Testyface", "Rollmcgee", "Greedchugger" }
    end
    return names
end

function ns.GenerateTestLoot()
    local links = CollectBagItemLinks(8)
    if #links == 0 then
        print("|cff33ff99[BRT]|r No items found in your bags to use as test loot -- carry a few items and try again.")
        return
    end
    local names = CollectTestNames(4)

    local added = 0
    for i, link in ipairs(links) do
        local winnerName = names[((i - 1) % #names) + 1]
        local entry = {
            date = date("%Y-%m-%d %H:%M"),
            item = link,
            winner = winnerName,
            auto = true,
        }
        -- A couple of entries get fake roll data too, so the roll-breakdown
        -- section of the detail popup has something to show.
        if i <= 2 and #names >= 2 then
            entry.rolls = {
                need = { names[1] },
                greed = { names[2] },
                pass = names[3] and { names[3] } or {},
                disenchant = {},
            }
        end
        table.insert(ns.db.lootLog, entry)
        added = added + 1
    end

    -- One pending item too, so the Master Loot "assign it" workflow can be
    -- tested without waiting for a real drop.
    table.insert(ns.db.pendingLoot, {
        date = date("%Y-%m-%d %H:%M"),
        item = links[#links],
    })

    if ns.RefreshLootLog then
        ns.RefreshLootLog()
    end
    if ns.RefreshPendingLoot then
        ns.RefreshPendingLoot()
    end
    print(
        "|cff33ff99[BRT]|r Added "
            .. added
            .. " test loot log entr"
            .. (added == 1 and "y" or "ies")
            .. " and 1 pending item, using real items pulled from your own bags. Type /brt cleartestloot to remove it all."
    )
end

function ns.ClearTestLoot()
    -- Test entries aren't tagged separately from real ones, so this just
    -- clears the loot log and pending queue outright -- fine for a dev
    -- utility, just don't run it mid-raid.
    ns.db.lootLog = {}
    ns.db.pendingLoot = {}
    if ns.RefreshLootLog then
        ns.RefreshLootLog()
    end
    if ns.RefreshPendingLoot then
        ns.RefreshPendingLoot()
    end
    print("|cff33ff99[BRT]|r Cleared the loot log and pending loot.")
end

-- Prints a clickable/hoverable item link to your OWN chat window whenever an
-- item gets loaded into itemBox (Grab Open Loot, a Pending Loot click, or
-- shift-click) -- local only, not broadcast to the group, since an item
-- getting loaded doesn't necessarily mean you've decided to roll it yet
-- (Announce already covers the real group-facing link once Start Roll is
-- actually clicked).
local function PrintLoadedItemLink(itemText)
    local _, link = ResolveItem(itemText)
    print("|cff33ff99[BRT]|r Loaded: " .. (link or itemText))
end

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

-- Class-colors a name if that player is currently in your party/raid (the
-- only time we can actually know their class) -- otherwise just the name.
local function GetClassColoredName(playerName)
    local units = { "player" }
    local total = GetNumGroupMembers()
    if total > 0 then
        local prefix = IsInRaid() and "raid" or "party"
        for i = 1, total do
            table.insert(units, prefix .. i)
        end
    end
    for _, unit in ipairs(units) do
        if UnitExists(unit) and UnitName(unit) == playerName then
            local _, classFile = UnitClass(unit)
            local hex = ClassColorHex(classFile)
            if hex then
                return "|c" .. hex .. playerName .. "|r"
            end
        end
    end
    return playerName
end

-- ===== Class-eligibility check =====
-- Armor-type class restrictions are hard game rules, well-established and
-- unchanged since Vanilla in every Classic re-release -- reliable to
-- hardcode. Deliberately NOT attempting stat-based ("who wants Int/Agi")
-- matching: GetItemStats has long-standing reliability complaints on
-- Classic, and its replacement C_Item.GetItemStats is retail-only (added in
-- The War Within), so there's no trustworthy stats API to build that on.
-- Weapon-type restrictions are skipped for the same reason -- the full
-- 9-class weapon-skill matrix is large enough that getting it wrong without
-- a live client to verify against felt riskier than it was worth; the
-- weapon's own subtype is shown instead so you can judge for yourself.
local ARMOR_CLASS_ELIGIBILITY = {
    Cloth = { "MAGE", "PRIEST", "WARLOCK" },
    Leather = { "DRUID", "ROGUE" },
    Mail = { "HUNTER", "SHAMAN" },
    Plate = { "WARRIOR", "PALADIN" },
}

local CLASS_DISPLAY = {
    MAGE = "Mage",
    PRIEST = "Priest",
    WARLOCK = "Warlock",
    DRUID = "Druid",
    ROGUE = "Rogue",
    HUNTER = "Hunter",
    SHAMAN = "Shaman",
    WARRIOR = "Warrior",
    PALADIN = "Paladin",
}

-- Same solo/party/raid unit-listing pattern as FindEligibleGroupMembers below,
-- minus the class filter -- used for items with NO class restriction
-- (weapons, trinkets, rings, necks, cloaks, consumables), where every current
-- group member is a legitimate candidate roller.
local function GetAllGroupMembers()
    local units = {}
    local total = GetNumGroupMembers()
    if total == 0 then
        table.insert(units, "player")
    else
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
    end

    local matches = {}
    for _, unit in ipairs(units) do
        local name = UnitName(unit)
        if name then
            table.insert(matches, { name = name, isOnline = UnitIsConnected(unit) })
        end
    end
    table.sort(matches, function(a, b)
        if a.isOnline ~= b.isOnline then
            return a.isOnline
        end
        return a.name < b.name
    end)
    return matches
end

-- Cross-references against your CURRENT party/raid group, not the whole
-- guild -- a targeted roll only makes sense for people actually present
-- right now, so pulling from every guild member (including offline/absent
-- ones) was a real mismatch. Class is read straight off the live unit, so
-- this still works even though nobody else in the group has this addon.
local function FindEligibleGroupMembers(classFileSet)
    if not classFileSet then
        return {}
    end
    local wanted = {}
    for _, c in ipairs(classFileSet) do
        wanted[c] = true
    end

    -- Same solo/party/raid unit-listing pattern used elsewhere in this addon
    -- (Roster.lua's GetGroupMembers, GuildRoster.lua's GetGroupUnits) --
    -- partyN units exclude yourself, raidN units include yourself, so
    -- "player" is only added separately when NOT in a raid.
    local units = {}
    local total = GetNumGroupMembers()
    if total == 0 then
        table.insert(units, "player")
    else
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
    end

    local matches = {}
    for _, unit in ipairs(units) do
        local name = UnitName(unit)
        local _, classFile = UnitClass(unit)
        if name and classFile and wanted[classFile] then
            table.insert(matches, { name = name, isOnline = UnitIsConnected(unit) })
        end
    end
    table.sort(matches, function(a, b)
        if a.isOnline ~= b.isOnline then
            return a.isOnline
        end
        return a.name < b.name
    end)
    return matches
end

-- ===== Auto-logging from real loot events =====
-- CHAT_MSG_LOOT fires for your own loot, other raid members' loot, and
-- Need/Greed roll selections alike. Rather than hand-typing a guess at the
-- literal wording (which already missed one real case -- see below), these
-- patterns are BUILT FROM Blizzard's own format-string globals at runtime,
-- e.g. _G.LOOT_ITEM_SELF = "You receive loot: %s." -- so they can't drift
-- from whatever the client actually says, and there's nothing to verify
-- against a live client in the first place. BuildPatternFromFormat turns
-- each %s/%d placeholder into a capture group and escapes everything else.
local function BuildPatternFromFormat(fmt)
    if not fmt or fmt == "" then
        return nil
    end
    local protected = fmt:gsub("%%s", "\1"):gsub("%%d", "\2")
    local escaped = protected:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    escaped = escaped:gsub("\1", "(.+)"):gsub("\2", "(%%d+)")
    return "^" .. escaped .. "$"
end

-- The bug that prompted this rewrite: a Tigerseye dropped and never got
-- logged. Root cause -- some drops (rare-mob/quest-tied rewards especially)
-- get pushed straight into your bag without opening a loot window, which
-- uses a COMPLETELY DIFFERENT chat string (LOOT_ITEM_PUSHED_SELF, "You
-- receive item: %s.") than normal corpse/container loot (LOOT_ITEM_SELF,
-- "You receive loot: %s.") -- the old pattern only ever matched the latter.
local PATTERN_SELF_MULTIPLE = BuildPatternFromFormat(_G.LOOT_ITEM_SELF_MULTIPLE) -- item, count
local PATTERN_PUSHED_SELF_MULTIPLE = BuildPatternFromFormat(_G.LOOT_ITEM_PUSHED_SELF_MULTIPLE) -- item, count
local PATTERN_SELF = BuildPatternFromFormat(_G.LOOT_ITEM_SELF) -- item
local PATTERN_PUSHED_SELF = BuildPatternFromFormat(_G.LOOT_ITEM_PUSHED_SELF) -- item
local PATTERN_OTHER_MULTIPLE = BuildPatternFromFormat(_G.LOOT_ITEM_MULTIPLE) -- player, item, count
local PATTERN_OTHER = BuildPatternFromFormat(_G.LOOT_ITEM) -- player, item

local function TryParseLootMessage(message)
    for _, pattern in ipairs({ PATTERN_SELF_MULTIPLE, PATTERN_PUSHED_SELF_MULTIPLE, PATTERN_SELF, PATTERN_PUSHED_SELF }) do
        if pattern then
            local item = message:match(pattern)
            if item then
                return UnitName("player"), item
            end
        end
    end
    for _, pattern in ipairs({ PATTERN_OTHER_MULTIPLE, PATTERN_OTHER }) do
        if pattern then
            local player, item = message:match(pattern)
            if player then
                return player, item
            end
        end
    end
    return nil, nil
end

-- Need/Greed/Pass/Disenchant roll selections also come through CHAT_MSG_LOOT.
-- Same global-string-derived approach as above where the names exist; falls
-- back to a best-effort literal guess (unverified against a live client)
-- only if a given global isn't found, so this degrades gracefully instead of
-- silently matching the wrong text.
local ROLL_PATTERNS = {
    { BuildPatternFromFormat(_G.LOOT_ROLL_NEED), "need" },
    { BuildPatternFromFormat(_G.LOOT_ROLL_GREED), "greed" },
    { BuildPatternFromFormat(_G.LOOT_ROLL_DISENCHANT), "disenchant" },
    { BuildPatternFromFormat(_G.LOOT_ROLL_PASS), "pass" },
}

local function TryParseRollMessage(message)
    for _, entry in ipairs(ROLL_PATTERNS) do
        local pattern, choice = entry[1], entry[2]
        if pattern then
            local player, item = message:match(pattern)
            if player then
                return player, choice, item
            end
        end
    end
    local player, item = message:match("^(%S+) has selected Need for: (.+)%.$")
    if player then
        return player, "need", item
    end
    player, item = message:match("^(%S+) has selected Greed for: (.+)%.$")
    if player then
        return player, "greed", item
    end
    player, item = message:match("^(%S+) has selected Disenchant for: (.+)%.$")
    if player then
        return player, "disenchant", item
    end
    player, item = message:match("^(%S+) has passed on: (.+)%.$")
    if player then
        return player, "pass", item
    end
    return nil, nil, nil
end

-- itemText -> { need={names}, greed={names}, pass={names}, disenchant={names} },
-- accumulated as roll-choice messages arrive, consumed and cleared once the
-- final "receives loot" message for that same item text shows up.
local pendingRolls = {}

local lootWatcher = CreateFrame("Frame")
lootWatcher:RegisterEvent("CHAT_MSG_LOOT")
lootWatcher:SetScript("OnEvent", function(self, event, message)
    -- No raid in progress -- don't touch casual/world loot at all, not even
    -- roll-message accumulation, so nothing leaks into the raid loot log.
    if not ns.IsRaidActive() then
        return
    end
    local rollPlayer, choice, rollItem = TryParseRollMessage(message)
    if rollPlayer and choice then
        pendingRolls[rollItem] = pendingRolls[rollItem] or { need = {}, greed = {}, pass = {}, disenchant = {} }
        table.insert(pendingRolls[rollItem][choice], rollPlayer)
        return
    end

    local player, item = TryParseLootMessage(message)
    if not player or not item then
        return
    end

    local name, _, quality = ns.GetItemInfo(item)
    local rollInfo = pendingRolls[item]
    pendingRolls[item] = nil

    if quality and quality < 2 then
        return -- Poor/Common trash -- not worth logging, no popup either
    end

    -- Under Master Loot, items YOU receive usually aren't actually yours --
    -- you're just holding them until you assign them to the real recipient.
    -- Queue those separately instead of auto-logging "winner = you", which
    -- would be wrong. Items that land on other raid members directly (native
    -- master-loot assignment, or any other loot method) are already
    -- correctly resolved and log normally below.
    if player == UnitName("player") then
        table.insert(ns.db.pendingLoot, {
            date = date("%Y-%m-%d %H:%M"),
            item = item,
            rolls = rollInfo,
        })
        if ns.RefreshPendingLoot then
            ns.RefreshPendingLoot()
        end
        print("|cff33ff99[BRT]|r Received: " .. (name or item) .. " -- open the Loot tab to assign it.")
        return
    end

    table.insert(ns.db.lootLog, {
        date = date("%Y-%m-%d %H:%M"),
        item = item,
        winner = player,
        auto = true,
        rolls = rollInfo,
    })
    if ns.RefreshLootLog then
        ns.RefreshLootLog()
    end
    if ns.ShowLootPopup then
        ns.ShowLootPopup(item, player, rollInfo)
    end
    print("|cff33ff99[BRT]|r Auto-logged: " .. player .. " - " .. (name or item))
end)

-- ===== Auto-logging from trades =====
-- Covers the "I won it on the roll, now I'm handing it to the actual
-- recipient" workflow. UnitName("NPC") for the trade partner's name is
-- confirmed straight from Blizzard's own FrameXML (TradeFrame.lua sets
-- TradeFrameRecipientNameText via exactly this call) -- not a guess.
-- GetTradePlayerItemLink(1-6) reads YOUR OWN outgoing trade slots; the
-- other side's items aren't logged, since those aren't loot you're handing
-- out. Snapshotting happens at TRADE_ACCEPT_UPDATE the moment BOTH sides
-- have accepted (not at TRADE_CLOSED) -- by the time the window actually
-- closes, the trade slots are already cleared and there's nothing left to
-- read.
local tradeLoggedThisTrade = false

local tradeWatcher = CreateFrame("Frame")
tradeWatcher:RegisterEvent("TRADE_SHOW")
tradeWatcher:RegisterEvent("TRADE_ACCEPT_UPDATE")
tradeWatcher:SetScript("OnEvent", function(self, event, playerAccepted, targetAccepted)
    if event == "TRADE_SHOW" then
        tradeLoggedThisTrade = false
        return
    end

    -- TRADE_ACCEPT_UPDATE -- no raid in progress means no auto-logging,
    -- same reasoning as the loot watcher above.
    if not ns.IsRaidActive() or tradeLoggedThisTrade or playerAccepted ~= 1 or targetAccepted ~= 1 then
        return
    end
    tradeLoggedThisTrade = true

    local partner = UnitName("NPC")
    if not partner then
        return
    end

    for slot = 1, 6 do
        local link = GetTradePlayerItemLink(slot)
        if link then
            local name, _, quality = ns.GetItemInfo(link)
            if not quality or quality >= 2 then
                table.insert(ns.db.lootLog, {
                    date = date("%Y-%m-%d %H:%M"),
                    item = link,
                    winner = partner,
                    traded = true,
                })
                if ns.ShowLootPopup then
                    ns.ShowLootPopup(link, partner, nil)
                end
                print("|cff33ff99[BRT]|r Auto-logged (traded): " .. partner .. " - " .. (name or link))
            end
        end
    end
    if ns.RefreshLootLog then
        ns.RefreshLootLog()
    end
end)

-- ===== Panel =====
local panel = ns.RegisterTab("loot", "Loot")

local grabBtn = ns.CreateStyledButton(panel, "Grab Open Loot", 160, 22, false)
grabBtn:SetPoint("TOPLEFT", 0, 0)

-- ===== Loot method display (read-only) =====
-- GetLootMethod's return shape differs between the bare global (string, e.g.
-- "master", "group") and its C_PartyInfo twin (numeric Enum.LootMethod,
-- 0-5) -- confirmed via Warcraft Wiki, not guessed -- so both are normalized
-- to the same string set below rather than assuming either shape.
local LOOT_METHOD_ENUM_NAMES = { [0] = "freeforall", [1] = "roundrobin", [2] = "master", [3] = "group", [4] = "needbeforegreed", [5] = "personalloot" }
local LOOT_METHOD_DISPLAY = {
    freeforall = "Free for All",
    roundrobin = "Round Robin",
    master = "Master Looter",
    group = "Group Loot",
    needbeforegreed = "Need Before Greed",
    personalloot = "Personal Loot",
}

local lootMethodText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
lootMethodText:SetPoint("LEFT", grabBtn, "RIGHT", 10, 0)
lootMethodText:SetJustifyH("LEFT")
lootMethodText:SetText(" ")

local function GetCurrentLootMethod()
    local method, mlParty, mlRaid
    if C_PartyInfo and C_PartyInfo.GetLootMethod then
        method, mlParty, mlRaid = C_PartyInfo.GetLootMethod()
    elseif GetLootMethod then
        method, mlParty, mlRaid = GetLootMethod()
    end
    if type(method) == "number" then
        method = LOOT_METHOD_ENUM_NAMES[method]
    end
    return method, mlParty, mlRaid
end

local function ResolveMasterLooterName(mlParty, mlRaid)
    if mlRaid then
        return UnitName("raid" .. mlRaid)
    elseif mlParty then
        if mlParty == 0 then
            return UnitName("player")
        else
            return UnitName("party" .. mlParty)
        end
    end
    return nil
end

local function RefreshLootMethodText()
    if not IsInGroup() then
        lootMethodText:SetText("|cff888888Not in a group.|r")
        return
    end
    local method, mlParty, mlRaid = GetCurrentLootMethod()
    local display = LOOT_METHOD_DISPLAY[method] or method or "Unknown"
    if method == "master" then
        local mlName = ResolveMasterLooterName(mlParty, mlRaid)
        display = display .. (mlName and (" (" .. mlName .. ")") or "")
    end
    lootMethodText:SetText("Loot Method: |cff33ff99" .. display .. "|r")
end

local lootMethodWatcher = CreateFrame("Frame")
lootMethodWatcher:RegisterEvent("PARTY_LOOT_METHOD_CHANGED")
lootMethodWatcher:SetScript("OnEvent", RefreshLootMethodText)

-- ===== Pending loot (items Master Loot dropped on YOU, awaiting assignment) =====
-- Widgets created here for layout; the refresh/click logic that references
-- rollersBox is wired up further down, after rollersBox actually exists.
local pendingLootLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
pendingLootLabel:SetPoint("TOPLEFT", grabBtn, "BOTTOMLEFT", 0, -10)
pendingLootLabel:SetText("Pending loot -- received by you, awaiting assignment (click to load, x to discard):")

-- Single TOPLEFT anchor + explicit SetSize -- NOT a second bare RIGHT point,
-- which would conflict with the explicit height (the same mismatched-anchor
-- bug class caught repeatedly elsewhere in this addon).
local pendingLootAnchor = CreateFrame("Frame", nil, panel)
pendingLootAnchor:SetPoint("TOPLEFT", pendingLootLabel, "BOTTOMLEFT", 0, -4)
pendingLootAnchor:SetSize(868, 64)
local pendingLootScroll, pendingLootRows = ns.CreateRowList(pendingLootAnchor)

local itemBox = ns.CreateEditBox(panel, 220)
itemBox:SetPoint("TOPLEFT", pendingLootAnchor, "BOTTOMLEFT", 0, -10)

-- Quick non-player destinations for whatever's currently in itemBox (grabbed
-- from an open loot window, or loaded from a Pending Loot click) -- logs it
-- directly with that destination as "winner", no player name needed.
local disenchantBtn = ns.CreateStyledButton(panel, "Disenchanted", 110, 22, false)
disenchantBtn:SetPoint("LEFT", itemBox, "RIGHT", 8, 0)

local bankedBtn = ns.CreateStyledButton(panel, "Banked", 90, 22, false)
bankedBtn:SetPoint("LEFT", disenchantBtn, "RIGHT", 6, 0)

local deletedBtn = ns.CreateStyledButton(panel, "Deleted", 90, 22, false)
deletedBtn:SetPoint("LEFT", bankedBtn, "RIGHT", 6, 0)

local function LogItemWithDestination(destText)
    local itemText = itemBox:GetText()
    if itemText == "" then
        print("|cff33ff99[BRT]|r No item loaded -- grab loot or click a pending item first.")
        return
    end
    local displayName, link = ResolveItem(itemText)
    table.insert(ns.db.lootLog, {
        date = date("%Y-%m-%d %H:%M"),
        item = link or itemText,
        winner = destText,
    })
    if ns.ShowLootPopup then
        ns.ShowLootPopup(link or itemText, destText, nil)
    end
    itemBox:SetText("")
    ns.RefreshLootLog()
end

for _, entry in ipairs({ { disenchantBtn, "Disenchanted" }, { bankedBtn, "Banked" }, { deletedBtn, "Deleted" } }) do
    local btn, destText = entry[1], entry[2]
    btn:SetScript("OnClick", function()
        LogItemWithDestination(destText)
    end)
end

-- Visual confirmation of whatever's currently loaded into itemBox -- icon +
-- quality-colored name, same visual language as the loot toast/detail
-- dialog. Refreshed inside UpdateEligibility below since that already fires
-- on every itemBox text change (typing, Grab Open Loot, or a Pending Loot
-- click all funnel through it).
local loadedItemIcon = panel:CreateTexture(nil, "ARTWORK")
loadedItemIcon:SetSize(20, 20)
loadedItemIcon:SetPoint("TOPLEFT", itemBox, "BOTTOMLEFT", 0, -8)
loadedItemIcon:Hide()

local loadedItemText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
loadedItemText:SetPoint("LEFT", loadedItemIcon, "RIGHT", 6, 0)
loadedItemText:SetJustifyH("LEFT")
loadedItemText:SetText(" ")

local hintText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hintText:SetPoint("TOPLEFT", loadedItemIcon, "BOTTOMLEFT", 0, -6)
hintText:SetText("Uncommon+ loot auto-logs itself from real loot rolls and trades while a raid is active (Attendance tab). Grab or load an item above, then either Start Roll below or mark it Disenchanted/Banked/Deleted.")

-- ===== Targeted roll selection =====
-- Only the officer has this addon, so there's no way to put a restricted
-- Need/Greed popup on anyone else's screen -- this announces who's eligible
-- to chat instead and tracks their normal native /roll results, ignoring
-- anyone not on the list (nothing stops them rolling anyway, it just doesn't
-- count). Not the RCLootCouncil voting/response system, just "pick people,
-- announce it, track the highest roll among them."
local rollersBox = ns.CreateEditBox(panel, 340)
rollersBox:SetPoint("TOPLEFT", hintText, "BOTTOMLEFT", 0, -10)

local startRollBtn = ns.CreateStyledButton(panel, "Start Roll", 100, 22, true)
startRollBtn:SetPoint("LEFT", rollersBox, "RIGHT", 8, 0)

local declareWinnerBtn = ns.CreateStyledButton(panel, "Declare Winner", 130, 22, true)
declareWinnerBtn:SetPoint("LEFT", startRollBtn, "RIGHT", 8, 0)
declareWinnerBtn:Hide()

local cancelRollBtn = ns.CreateStyledButton(panel, "Cancel Roll", 100, 22, false)
cancelRollBtn:SetPoint("LEFT", declareWinnerBtn, "RIGHT", 8, 0)
cancelRollBtn:Hide()

local rollersHint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
rollersHint:SetPoint("TOPLEFT", rollersBox, "BOTTOMLEFT", 0, -3)
rollersHint:SetText("Rollers (comma-separated -- auto-filled from class-eligible group members below, edit freely)")

local rollStatusText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
rollStatusText:SetPoint("TOPLEFT", rollersHint, "BOTTOMLEFT", 0, -4)
rollStatusText:SetPoint("RIGHT", 0, 0)
rollStatusText:SetJustifyH("LEFT")
rollStatusText:SetText(" ")

-- RANDOM_ROLL_RESULT/CHAT_MSG_SYSTEM confirmed as the right global/event for
-- native /roll results; pattern built from the live string via
-- BuildPatternFromFormat (same technique as the loot-message fix above), not
-- a guessed literal.
local ROLL_RESULT_PATTERN = BuildPatternFromFormat(_G.RANDOM_ROLL_RESULT) -- player, roll, min, max

local activeRoll = nil -- { item, order = {name,...}, rolls = {[name]=value} }

local function UpdateRollDisplay()
    if not activeRoll then
        rollStatusText:SetText(" ")
        declareWinnerBtn:Hide()
        cancelRollBtn:Hide()
        return
    end
    declareWinnerBtn:Show()
    cancelRollBtn:Show()
    local bestName, bestRoll = nil, -1
    local parts = {}
    for _, name in ipairs(activeRoll.order) do
        local value = activeRoll.rolls[name]
        if value then
            table.insert(parts, name .. ": " .. value)
            if value > bestRoll then
                bestRoll, bestName = value, name
            end
        else
            table.insert(parts, name .. ": |cff888888--|r")
        end
    end
    local status = table.concat(parts, "   ")
    if bestName then
        status = status .. "   |cff33ff99(leading: " .. bestName .. ")|r"
    end
    if activeRoll.ignored and #activeRoll.ignored > 0 then
        status = status .. "\n|cffff5555Ignored (not on Rollers list):|r " .. table.concat(activeRoll.ignored, ", ")
    end
    rollStatusText:SetText(status)
end

-- Resolves a plain name to a live unit token (target/party/raid), same
-- solo/party/raid enumeration pattern used throughout this addon. Returns
-- nil if the person isn't currently a valid nearby unit.
local function FindGroupUnitByName(name)
    if UnitExists("target") and UnitName("target") == name then
        return "target"
    end
    local total = GetNumGroupMembers()
    if total > 0 then
        local prefix = IsInRaid() and "raid" or "party"
        for i = 1, total do
            local unit = prefix .. i
            if UnitExists(unit) and UnitName(unit) == name then
                return unit
            end
        end
    end
    return nil
end

-- Trade range is CheckInteractDistance index 2 (~11 yards) -- a long-standing,
-- stable global, unchanged since Vanilla.
local function TryAutoTrade(name)
    local unit = FindGroupUnitByName(name)
    if not unit then
        return false
    end
    if not (CheckInteractDistance and CheckInteractDistance(unit, 2)) then
        return false
    end
    InitiateTrade(unit)
    return true
end

local function FinishDeclareRollWinner()
    local winner, bestRoll = nil, -1
    for name, value in pairs(activeRoll.rolls) do
        if value > bestRoll then
            bestRoll, winner = value, name
        end
    end
    if not winner then
        print("|cff33ff99[BRT]|r No rolls recorded yet -- can't declare a winner.")
        return
    end
    local displayName, link = ResolveItem(activeRoll.item)
    local itemText = link or activeRoll.item

    -- Auto-trade only ever succeeds if the winner happens to already be
    -- standing next to you -- there's no way to open a trade with someone
    -- across the raid, WoW requires physical proximity. The chat message
    -- goes out either way, since even a successful trade window still needs
    -- them to notice and accept it.
    local traded = TryAutoTrade(winner)
    if traded then
        Announce(winner .. " wins " .. itemText .. " with a roll of " .. bestRoll .. "! Trade window opened.")
    else
        Announce(winner .. " wins " .. itemText .. " with a roll of " .. bestRoll .. "! " .. winner .. ", please come trade me for it.")
    end

    table.insert(ns.db.lootLog, {
        date = date("%Y-%m-%d %H:%M"),
        item = itemText,
        winner = winner,
    })
    if ns.ShowLootPopup then
        ns.ShowLootPopup(itemText, winner, nil)
    end
    activeRoll = nil
    UpdateRollDisplay()
    ns.RefreshLootLog()
    itemBox:SetText("")
    rollersBox:SetText("")
end

local function DeclareRollWinner()
    if not activeRoll then
        return
    end
    -- Warn if someone eligible hasn't rolled yet -- declaring too early was
    -- one of the two likely causes of a real "wrong winner" bug (the higher
    -- roll hadn't been recorded yet when Declare Winner was clicked).
    local missing = {}
    for _, n in ipairs(activeRoll.order) do
        if not activeRoll.rolls[n] then
            table.insert(missing, n)
        end
    end
    if #missing > 0 then
        ns.ShowConfirmDialog(
            "These rollers haven't rolled yet: " .. table.concat(missing, ", ") .. ".\nDeclare the highest roll so far anyway?",
            FinishDeclareRollWinner
        )
        return
    end
    FinishDeclareRollWinner()
end

local rollWatcher = CreateFrame("Frame")
rollWatcher:RegisterEvent("CHAT_MSG_SYSTEM")
rollWatcher:SetScript("OnEvent", function(self, event, message)
    if not activeRoll or not ROLL_RESULT_PATTERN then
        return
    end
    local player, roll = message:match(ROLL_RESULT_PATTERN)
    if not player then
        return
    end
    -- Trimmed/case-insensitive match -- cheap insurance against a name typed
    -- into Rollers not matching the roll message byte-for-byte. Stores under
    -- the CANONICAL name from activeRoll.order (not the roll message's own
    -- casing), so later lookups by that same canonical name always find it.
    local playerKey = player:gsub("^%s*(.-)%s*$", "%1"):lower()
    local eligibleName = nil
    for _, n in ipairs(activeRoll.order) do
        if n:lower() == playerKey then
            eligibleName = n
            break
        end
    end
    if not eligibleName then
        -- Recorded but not counted -- shown in the status line so a roll
        -- from someone off the list is visible instead of silently vanishing,
        -- which made a real bug (wrong winner declared) much harder to spot.
        activeRoll.ignored = activeRoll.ignored or {}
        table.insert(activeRoll.ignored, player .. " (" .. roll .. ")")
        UpdateRollDisplay()
        return
    end
    activeRoll.rolls[eligibleName] = tonumber(roll)
    UpdateRollDisplay()
end)

startRollBtn:SetScript("OnClick", function()
    local item = itemBox:GetText()
    local rollersText = rollersBox:GetText()
    if item == "" then
        print("|cff33ff99[BRT]|r Enter or grab an item first.")
        return
    end
    if rollersText == "" then
        print("|cff33ff99[BRT]|r Enter at least one name in Rollers first.")
        return
    end
    local order = {}
    for name in rollersText:gmatch("[^,]+") do
        name = name:match("^%s*(.-)%s*$")
        if name ~= "" then
            table.insert(order, name)
        end
    end
    if #order == 0 then
        print("|cff33ff99[BRT]|r Couldn't parse any names out of Rollers.")
        return
    end
    activeRoll = { item = item, order = order, rolls = {} }
    local displayName, link = ResolveItem(item)
    Announce("Roll for " .. (link or item) .. "! Eligible: " .. table.concat(order, ", ") .. " -- type /roll now!")
    UpdateRollDisplay()
end)

declareWinnerBtn:SetScript("OnClick", DeclareRollWinner)

cancelRollBtn:SetScript("OnClick", function()
    activeRoll = nil
    UpdateRollDisplay()
    rollersBox:SetText("")
    print("|cff33ff99[BRT]|r Roll cancelled.")
end)

-- Row position -> real index into ns.db.pendingLoot, rebuilt every refresh
-- (shown newest-first, same reasoning as the main loot log's row mapping).
local pendingLootRowIndex = {}

function ns.RefreshPendingLoot()
    local lines = {}
    pendingLootRowIndex = {}
    for i = #ns.db.pendingLoot, 1, -1 do
        local entry = ns.db.pendingLoot[i]
        table.insert(lines, "[" .. entry.date .. "] " .. ResolveItem(entry.item))
        table.insert(pendingLootRowIndex, i)
    end
    if #lines == 0 then
        lines = { "Nothing pending." }
    end
    pendingLootRows:SetRows(lines)
end

-- Click loads the item into itemBox (clearing Rollers first so the existing
-- class-eligibility auto-fill picks it back up for the NEW item) -- ready to
-- either Start Roll or type a player and Log Loot directly.
pendingLootRows.onRowClick = function(rowIndex)
    local idx = pendingLootRowIndex[rowIndex]
    local entry = idx and ns.db.pendingLoot[idx]
    if not entry then
        return
    end
    table.remove(ns.db.pendingLoot, idx)
    rollersBox:SetText("")
    itemBox:SetText(entry.item)
    PrintLoadedItemLink(entry.item)
    ns.RefreshPendingLoot()
    print("|cff33ff99[BRT]|r Loaded into the item box -- Start Roll, or type a player and Log Loot.")
end

pendingLootRows.onRowRemove = function(rowIndex)
    local idx = pendingLootRowIndex[rowIndex]
    local entry = idx and ns.db.pendingLoot[idx]
    if not entry then
        return
    end
    local displayName = ResolveItem(entry.item)
    ns.ShowConfirmDialog("Discard " .. displayName .. " without logging it?", function()
        table.remove(ns.db.pendingLoot, idx)
        ns.RefreshPendingLoot()
    end)
end

-- Live class-eligibility readout -- updates on every itemBox text change
-- (typing, shift-click, or Grab Open Loot all funnel through OnTextChanged).
local eligibleText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
eligibleText:SetPoint("TOPLEFT", rollStatusText, "BOTTOMLEFT", 0, -10)
eligibleText:SetPoint("RIGHT", 0, 0)
eligibleText:SetJustifyH("LEFT")
eligibleText:SetText(" ")

local function UpdateEligibility()
    local text = itemBox:GetText()
    if text == "" then
        eligibleText:SetText(" ")
        loadedItemIcon:Hide()
        loadedItemText:SetText(" ")
        return
    end
    local name, _, quality, _, _, itemType, itemSubType, _, _, texture = ns.GetItemInfo(text)
    if not name then
        eligibleText:SetText("|cff888888Type or shift-click a real item to check class eligibility.|r")
        loadedItemIcon:Hide()
        loadedItemText:SetText("|cff888888(item not recognized yet -- may need a moment to cache)|r")
        return
    end

    loadedItemIcon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    loadedItemIcon:Show()
    local loadedColor = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    loadedItemText:SetText(((loadedColor and loadedColor.hex) or "") .. name .. "|r")

    -- Shared by both branches below: renders up to 8 names (online in green,
    -- offline in gray, "+N more" beyond that), and fills Rollers with them
    -- ONLY when it's empty -- never clobbers an officer's own edits (e.g.
    -- after trimming the list down to specific people).
    local function ApplyMatches(matches)
        local matchParts = {}
        for i, m in ipairs(matches) do
            if i > 8 then
                table.insert(matchParts, "+" .. (#matches - 8) .. " more")
                break
            end
            table.insert(matchParts, (m.isOnline and "|cff33ff99" or "|cff888888") .. m.name .. "|r")
        end
        local matchText = #matchParts > 0 and table.concat(matchParts, ", ") or "|cff888888none in your group|r"

        if rollersBox:GetText() == "" and #matches > 0 then
            local names = {}
            for _, m in ipairs(matches) do
                table.insert(names, m.name)
            end
            rollersBox:SetText(table.concat(names, ", "))
        end
        return matchText
    end

    local eligible = ARMOR_CLASS_ELIGIBILITY[itemSubType]
    if itemType ~= "Armor" or not eligible then
        -- No class restriction on this item (weapon, trinket, ring, neck,
        -- cloak, consumable, etc.) -- everyone currently in the group is a
        -- legitimate candidate, so fill Rollers with the whole group instead
        -- of leaving it blank.
        local matchText = ApplyMatches(GetAllGroupMembers())
        local restrictionNote
        if itemType == "Weapon" then
            restrictionNote = (itemSubType or "Weapon") .. " -- weapon skill varies by class, check in-game."
        else
            restrictionNote = "No armor-type restriction (usable by any class)."
        end
        eligibleText:SetText("|cff888888" .. restrictionNote .. "|r\nGroup: " .. matchText)
        return
    end

    local classNames = {}
    for _, c in ipairs(eligible) do
        table.insert(classNames, CLASS_DISPLAY[c] or c)
    end

    local matchText = ApplyMatches(FindEligibleGroupMembers(eligible))

    eligibleText:SetText(
        itemSubType .. " -- Eligible: " .. table.concat(classNames, ", ") .. "\nGroup matches: " .. matchText
    )
end

itemBox:SetScript("OnTextChanged", UpdateEligibility)

-- Content area is the 900px main frame minus UI.lua's 16px margin each side.
local PANEL_CONTENT_WIDTH = 868
local COLUMN_GAP = 20
local COLUMN_WIDTH = (PANEL_CONTENT_WIDTH - COLUMN_GAP) / 2

local logLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
logLabel:SetPoint("TOPLEFT", eligibleText, "BOTTOMLEFT", 0, -18)
logLabel:SetText("Loot log:")

local exportBtn = ns.CreateStyledButton(panel, "Export Loot Log", 150, 22, false)
exportBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -1)

local importBtn = ns.CreateStyledButton(panel, "Import Loot Log", 150, 22, false)
importBtn:SetPoint("RIGHT", exportBtn, "LEFT", -8, 0)

-- Left column: full history. TOPLEFT + BOTTOMLEFT (both pinned to the same x)
-- plus an explicit SetWidth -- the safe anchor pattern used throughout this
-- addon, avoiding the mismatched-edge bug caught earlier in several tabs.
-- 34px reserved at the bottom for the Clear All Loot row.
local logListAnchor = CreateFrame("Frame", nil, panel)
logListAnchor:SetPoint("TOPLEFT", logLabel, "BOTTOMLEFT", 0, -6)
logListAnchor:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 34)
logListAnchor:SetWidth(COLUMN_WIDTH)
local logScroll, logRows = ns.CreateRowList(logListAnchor)

-- Right column: per-player totals (borrowed from RCLootCouncil's loot
-- statistics) -- counts entries in the same lootLog, no separate data needed.
local totalsLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
totalsLabel:SetPoint("TOPLEFT", eligibleText, "BOTTOMLEFT", COLUMN_WIDTH + COLUMN_GAP, -18)
totalsLabel:SetText("Loot totals:")

local totalsAnchor = CreateFrame("Frame", nil, panel)
totalsAnchor:SetPoint("TOPLEFT", totalsLabel, "BOTTOMLEFT", 0, -6)
totalsAnchor:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", COLUMN_WIDTH + COLUMN_GAP, 34)
totalsAnchor:SetWidth(COLUMN_WIDTH)
local totalsScroll, totalsRows = ns.CreateRowList(totalsAnchor)

local clearAllLootBtn = ns.CreateStyledButton(panel, "Clear All Loot", 180, 24, false)
clearAllLootBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
clearAllLootBtn:SetScript("OnClick", function()
    ns.ShowConfirmDialog("Clear ALL loot log data? This cannot be undone.", function()
        ns.db.lootLog = {}
        ns.RefreshLootLog()
        print("|cff33ff99[BRT]|r All loot log data cleared.")
    end)
end)

local function RefreshLootTotals()
    local counts = {}
    for _, entry in ipairs(ns.db.lootLog) do
        counts[entry.winner] = (counts[entry.winner] or 0) + 1
    end
    local sorted = {}
    for winner, count in pairs(counts) do
        table.insert(sorted, { winner = winner, count = count })
    end
    table.sort(sorted, function(a, b)
        return a.count > b.count
    end)
    local lines = {}
    for _, entry in ipairs(sorted) do
        table.insert(lines, GetClassColoredName(entry.winner) .. ": " .. entry.count)
    end
    if #lines == 0 then
        lines = { "No loot logged yet." }
    end
    totalsRows:SetRows(lines)
end

-- Row position -> real index into ns.db.lootLog, rebuilt every refresh since
-- the log is shown newest-first (reversed) and capped at 30 rows, so row
-- position never lines up with storage index directly.
local logRowIndex = {}

function ns.RefreshLootLog()
    local lines = {}
    logRowIndex = {}
    for i = #ns.db.lootLog, 1, -1 do
        local entry = ns.db.lootLog[i]
        local displayItem = ResolveItem(entry.item)
        table.insert(lines, "[" .. entry.date .. "] " .. GetClassColoredName(entry.winner) .. " - " .. displayItem)
        table.insert(logRowIndex, i)
        if #lines >= 30 then
            break
        end
    end
    if #lines == 0 then
        lines = { "No loot logged yet." }
    end
    logRows:SetRows(lines)
    RefreshLootTotals()
end

-- Click the row itself to see the Need/Greed/Pass/Disenchant breakdown (only
-- recorded for auto-logged items where a roll actually happened -- manual
-- entries and non-roll loot methods have nothing to show). Click the
-- separate [x] button to remove the entry -- the two no longer share a
-- click handler now that CreateRowList supports onRowRemove.
local function ShowLootDetail(entry)
    local note = "No roll data -- this was a manual log entry."
    if entry.traded then
        note = "No roll data -- this item was handed over by trade, not rolled on."
    elseif entry.auto then
        note = "No roll data recorded (item wasn't rolled on, or the roll messages weren't recognized)."
    end
    ns.ShowLootDetailDialog(entry.item, entry.winner, entry.date, entry.rolls, note)
end

logRows.onRowClick = function(rowIndex)
    local idx = logRowIndex[rowIndex]
    local entry = idx and ns.db.lootLog[idx]
    if entry then
        ShowLootDetail(entry)
    end
end

logRows.onRowRemove = function(rowIndex)
    local idx = logRowIndex[rowIndex]
    local entry = idx and ns.db.lootLog[idx]
    if not entry then
        return
    end
    local displayName = ResolveItem(entry.item)
    ns.ShowConfirmDialog("Remove this loot log entry (" .. displayName .. ")?", function()
        table.remove(ns.db.lootLog, idx)
        ns.RefreshLootLog()
    end)
end

local function BuildLootExport()
    local lines = { "Date,Winner,Item" }
    for _, entry in ipairs(ns.db.lootLog) do
        local displayItem = ResolveItem(entry.item):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        local escapedItem = displayItem:gsub('"', '""')
        table.insert(lines, string.format('%s,%s,"%s"', entry.date, entry.winner, escapedItem))
    end
    return table.concat(lines, "\n")
end

exportBtn:SetScript("OnClick", function()
    ns.ShowExportDialog("Loot Log Export (CSV)", BuildLootExport())
end)

-- Loot's CSV (date,winner,item) captures everything needed to fully
-- reconstruct entries, unlike Attendance's -- so this appends real log rows,
-- not just a totals summary. Skips the header row automatically since it
-- won't parse as a valid "date,winner,item" data row.
local function ImportLootCSV(text)
    local imported = 0
    for line in text:gmatch("[^\r\n]+") do
        local fields = ns.ParseCSVLine(line)
        local entryDate, winner, item = fields[1], fields[2], fields[3]
        if entryDate and winner and item and entryDate:match("^%d%d%d%d%-%d%d%-%d%d") then
            table.insert(ns.db.lootLog, { date = entryDate, winner = winner, item = item })
            imported = imported + 1
        end
    end
    ns.RefreshLootLog()
    print("|cff33ff99[BRT]|r Imported " .. imported .. " loot log entr" .. (imported == 1 and "y" or "ies") .. ".")
end

importBtn:SetScript("OnClick", function()
    ns.ShowImportDialog("Import Loot Log (CSV)", ImportLootCSV)
end)

grabBtn:SetScript("OnClick", function()
    if not (LootFrame and LootFrame:IsShown()) then
        print("|cff33ff99[BRT]|r Open a lootable corpse/container first.")
        return
    end
    local links = {}
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        if link then
            table.insert(links, link)
        end
    end
    if #links == 0 then
        print("|cff33ff99[BRT]|r No items found in the open loot window.")
        return
    end
    itemBox:SetText(links[1])
    PrintLoadedItemLink(links[1])
    if #links > 1 then
        print("|cff33ff99[BRT]|r Filled in the first item. Others in this loot window (shift-click to grab a different one):")
        for i = 2, #links do
            print("  " .. links[i])
        end
    end
end)

panel:SetScript("OnShow", function()
    ns.RefreshLootLog()
    RefreshLootMethodText()
    ns.RefreshPendingLoot()
end)

-- Shift-click support: lets you shift-click an item from your bags or an open
-- loot window straight into itemBox, instead of typing the item name from
-- memory. This overrides the global Blizzard hook that normally only inserts
-- into chat edit boxes.
local originalChatEditInsertLink = ChatEdit_InsertLink
function ChatEdit_InsertLink(link)
    if itemBox:IsShown() and itemBox:HasFocus() then
        itemBox:SetText(link)
        PrintLoadedItemLink(link)
        return true
    end
    return originalChatEditInsertLink(link)
end
