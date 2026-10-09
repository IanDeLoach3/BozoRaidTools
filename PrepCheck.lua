local ADDON_NAME, ns = ...

-- Buff-based readiness check -- looks at actual auras on each raid/party
-- member, not a wishlist or self-report. "Well Fed" is the single generic
-- buff name Classic uses for every food buff regardless of which food (long
-- stable, unchanged since Vanilla). There's no equivalent single generic name
-- for flasks/elixirs/weapon oils, so those are detected via a substring match
-- against common consumable buff naming (Flask/Elixir/Oil/Stone) -- a
-- reasonable heuristic, not an exhaustive database, so it can miss unusual
-- items. Enchants are NOT checked: that needs inspecting each player's
-- equipped gear via /inspect, which is async, rate-limited, and range-gated
-- -- too unreliable to build without a live client to verify against.
--
-- Least-certain part of this addon: aura-reading APIs are exactly the kind of
-- thing that's been migrating namespaces (same story as GetItemInfo -> C_Item
-- earlier), and I have no live client to confirm UnitBuff still works here.
local function GetAuraName(unit, index)
    if UnitBuff then
        return UnitBuff(unit, index)
    elseif C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
        local data = C_UnitAuras.GetBuffDataByIndex(unit, index)
        return data and data.name
    end
    return nil
end

local function ScanUnitReadiness(unit)
    local hasFood, hasConsumable = false, false
    for i = 1, 40 do
        local name = GetAuraName(unit, i)
        if not name then
            break
        end
        if name == "Well Fed" then
            hasFood = true
        elseif name:find("Flask") or name:find("Elixir") or name:find("Oil") or name:find("Stone") then
            hasConsumable = true
        end
    end
    return hasFood, hasConsumable
end

local function GetRaidUnits()
    local units = {}
    local total = GetNumGroupMembers()
    if total == 0 then
        table.insert(units, { unit = "player", name = UnitName("player") })
        return units
    end
    local inRaid = IsInRaid()
    if not inRaid then
        table.insert(units, { unit = "player", name = UnitName("player") })
    end
    local prefix = inRaid and "raid" or "party"
    for i = 1, total do
        local unit = prefix .. i
        if UnitExists(unit) then
            table.insert(units, { unit = unit, name = UnitName(unit) })
        end
    end
    return units
end

-- ===== Panel =====
local panel = ns.RegisterTab("prep", "Prep Check")

local hintText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hintText:SetPoint("TOPLEFT", 0, 0)
hintText:SetPoint("RIGHT")
hintText:SetJustifyH("LEFT")
hintText:SetText(
    "Checks who's missing food or a flask/elixir/oil before a pull. Approximate -- matches common consumable buff names, not an exhaustive database. Can't check enchants (needs /inspect per player, too unreliable to build without a live client to test against)."
)

local checkBtn = ns.CreateStyledButton(panel, "Check Raid", 140, 24, true)
checkBtn:SetPoint("TOPLEFT", hintText, "BOTTOMLEFT", 0, -12)

local statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
statusText:SetPoint("LEFT", checkBtn, "RIGHT", 12, 0)
statusText:SetText("Click Check Raid to scan your current group.")

local listAnchor = CreateFrame("Frame", nil, panel)
listAnchor:SetPoint("TOPLEFT", checkBtn, "BOTTOMLEFT", 0, -14)
listAnchor:SetPoint("BOTTOMRIGHT", 0, 0)
local scroll, rowList = ns.CreateRowList(listAnchor)

checkBtn:SetScript("OnClick", function()
    local units = GetRaidUnits()
    local missing, ready = {}, {}
    for _, u in ipairs(units) do
        if u.name then
            local hasFood, hasConsumable = ScanUnitReadiness(u.unit)
            local parts = {
                hasFood and "|cff33ff99Food|r" or "|cffff5555No Food|r",
                hasConsumable and "|cff33ff99Flask/Elixir|r" or "|cffff5555No Flask/Elixir|r",
            }
            local line = u.name .. " - " .. table.concat(parts, ", ")
            table.insert(hasFood and hasConsumable and ready or missing, line)
        end
    end

    local lines = {}
    for _, line in ipairs(missing) do
        table.insert(lines, line)
    end
    for _, line in ipairs(ready) do
        table.insert(lines, line)
    end
    if #lines == 0 then
        lines = { "Nobody found -- are you in a group?" }
    end
    rowList:SetRows(lines)
    statusText:SetText(#units .. " checked, " .. #missing .. " missing something (shown first)")
end)
