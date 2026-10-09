local ADDON_NAME, ns = ...

local defaults = {
    attendance = { sessions = {}, totals = {} },
    lootLog = {},
    pendingLoot = {},
    altLinks = {},
    minimapAngle = 215,
}

local function CopyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
            end
            CopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        BozoRaidToolsDB = BozoRaidToolsDB or {}
        CopyDefaults(BozoRaidToolsDB, defaults)
        ns.db = BozoRaidToolsDB
        ns.UpdateMinimapPosition()
    elseif event == "PLAYER_LOGIN" then
        -- Prints exactly what was loaded from SavedVariables, right when the
        -- addon starts -- lets you tell at a glance whether missing data is a
        -- save/load problem (this count is already wrong/zero right here) or
        -- a display problem (this count looks right, but the tab shows
        -- nothing until you click into it).
        local lootCount = #ns.db.lootLog
        local sessionCount = #ns.db.attendance.sessions
        local pendingCount = #ns.db.pendingLoot
        print(
            "|cff33ff99[BRT]|r loaded -- "
                .. lootCount
                .. " loot log entr"
                .. (lootCount == 1 and "y" or "ies")
                .. ", "
                .. sessionCount
                .. " attendance session"
                .. (sessionCount == 1 and "" or "s")
                .. (pendingCount > 0 and (", " .. pendingCount .. " loot item(s) still pending assignment") or "")
                .. " restored. Click the minimap icon (or type /brt) to open it."
        )
        -- If a logout snapshot survived the save, this tells us what was
        -- ACTUALLY in memory at the exact moment of the last logout/reload --
        -- a plain print() during PLAYER_LOGOUT wouldn't survive into this new
        -- chat window, but a value written into ns.db does, since it's the
        -- same table that gets serialized to disk either way.
        if ns.db.lastLogoutSnapshot then
            local s = ns.db.lastLogoutSnapshot
            print(
                "|cff33ff99[BRT]|r At last logout ("
                    .. s.time
                    .. "): "
                    .. s.lootCount
                    .. " loot entries, "
                    .. s.sessionCount
                    .. " sessions were in memory right before saving."
            )
        end
    elseif event == "PLAYER_LOGOUT" then
        ns.db.lastLogoutSnapshot = {
            time = date("%Y-%m-%d %H:%M:%S"),
            lootCount = #ns.db.lootLog,
            sessionCount = #ns.db.attendance.sessions,
        }
    end
end)

-- /brt with no argument just toggles the window -- everything else happens
-- by clicking in it, except the dev/test-data helpers below.
SLASH_BOZORAIDTOOLS1 = "/brt"
SlashCmdList["BOZORAIDTOOLS"] = function(msg)
    local cmd = (msg or ""):gsub("^%s*(.-)%s*$", "%1"):lower()

    if cmd == "testloot" then
        if ns.GenerateTestLoot then
            ns.GenerateTestLoot()
        end
    elseif cmd == "cleartestloot" then
        if ns.ClearTestLoot then
            ns.ClearTestLoot()
        end
    else
        ns.ToggleMainFrame()
    end
end
