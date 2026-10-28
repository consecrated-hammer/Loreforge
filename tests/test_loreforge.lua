package.path = "./tests/hammercore/?.lua;" .. package.path
local wow = require("wow")
local function eq(a, b, why) assert(a == b, why .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
for _, toc in ipairs({ "Loreforge.toc", "Loreforge_Camelot.toc" }) do
    wow.Install({ Loreforge = { Version = "0.1.0" } })
    LoreforgeDB = nil
    local time, combat = 100, false
    GetTime = function() return time end
    InCombatLockdown = function() return combat end
    GetBuildInfo = function() return "version", "build", "date", toc:find("Camelot") and 16001 or 120105 end
    WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
    GetNormalizedRealmName = function() return "Realm" end
    UnitFullName = function(unit) return unit == "player" and "Host" or unit == "party1" and "Guest" or nil, "Realm" end
    GetUnitName = function(unit) return (UnitFullName(unit)) end
    UnitGUID = function(unit) return unit == "player" and "hostGUID" or "guestGUID" end
    IsInRaid = function() return false end
    GetNumSubgroupMembers = function() return 1 end
    RegisterStateDriver = function() end
    UnregisterStateDriver = function() end
    assert(loadfile('tests/transport-libs.lua'))()()
    local ns = wow.LoadHammerCore("Libs/HammerCore", "Loreforge")
    for file in assert(io.open(toc)):read("*a"):gmatch("([^\r\n]+)") do
        if file:match("^[%w]+%.lua$") then assert(loadfile(file))("Loreforge", ns) end
    end
    local loader
    for _, f in ipairs(wow.frames) do if f.scripts.OnEvent then loader = f end end
    loader.scripts.OnEvent(loader, "ADDON_LOADED", "Loreforge")
    eq(ns.era, toc:find("Camelot") and "classic" or "retail", "actual client")
    eq(wow.LastPrint(), "Loreforge v0.1.0 loaded - type /loreforge for Host game, /loreforge help for commands", "main-action login")
    SlashCmdList.LOREFORGE("")
    eq(ns.hostFrame.setup:IsShown(), true, "main command opens game setup")
    eq(ns.hostFrame.play:IsShown(), false, "game controls wait for a game")
    ns.HammerCore.Minimap.button.scripts.OnClick(ns.HammerCore.Minimap.button, "RightButton")
    eq(ns.HammerCore.Settings:IsShown(), true, "minimap right-click opens general settings")
    ns.HammerCore.Minimap.button.scripts.OnClick(ns.HammerCore.Minimap.button, "LeftButton")
    eq(ns.hostFrame.setup:IsShown(), true, "minimap left-click opens main setup")
    SlashCmdList.LOREFORGE("settings")
    eq(ns.HammerCore.Settings:IsShown(), true, "HammerCore settings")
    for _, name in ipairs({ "Player records", "Visibility", "Commands", "Troubleshooting", "About" }) do
        ns.HammerCore.Settings:Show(name)
    end
    eq(next(ns.HammerCore.Settings.errors), nil, "every page builds")
    eq(ns.HammerCore.Settings.pages.Game, nil, "game setup is not a settings page")
    eq(ns.HammerCore.Settings.pages.Hosting, nil, "hosting is not a settings page")
    ns.db.readyCheck = false
    ns.db.rounds, ns.db.perRound, ns.db.seconds = 1, 1, 10
    ns.StartGame()
    ns.game.config.manualSend = true; ns.RefreshHost()
    eq(ns.game.phase, "announcing", "game started")
    eq(ns.hostFrame.setup:IsShown(), false, "game replaces setup in the same window")
    eq(ns.hostFrame.play:IsShown(), true, "game table visible")
    local popups = #wow.popups
    ns.ConfirmClearRecords()
    eq(#wow.popups, popups, "active game refuses record clearing")
    eq(ns.hostFrame.send:GetAttribute("useOnKeyDown"), false, "secure click matches mouse-up")
    local function chat(text, sender, guid, event)
        ns.events.scripts.OnEvent(ns.events, event or "CHAT_MSG_PARTY", text, sender, nil, nil, nil, nil, nil, nil, nil, nil, nil, guid)
    end
    while ns.game:NextMessage() do
        local line = ns.game:NextMessage()
        eq(ns.hostFrame.send:GetAttribute("macrotext"), "/p " .. line, "armed chat line")
        assert(#ns.hostFrame.send:GetAttribute("macrotext") < 255, "macro byte limit")
        ns.hostFrame.send.scripts.PostClick(ns.hostFrame.send)
        chat(line, "Other-Realm", "otherGUID")
        assert(ns.game.pending, "other sender cannot acknowledge")
        chat(line, "Host-Realm", "hostGUID")
    end
    eq(ns.game.phase, "accepting", "host echoes open answer window")
    ns.events.scripts.OnEvent(ns.events, "GROUP_ROSTER_UPDATE")
    eq(ns.game.phase, "accepting", "unchanged membership does not void answers")
    local answer = tostring(ns.game.run[1].correct)
    chat(answer, "Guest-Realm", "guestGUID", "CHAT_MSG_GUILD")
    eq(next(ns.game.answers), nil, "wrong channel ignored")
    chat(answer, "Guest-Realm", "guestGUID")
    eq(ns.game.answers["guest-realm"], tonumber(answer), "participant recorded")
    local armed = ns.hostFrame.send:GetAttribute("macrotext")
    local oldSet = ns.hostFrame.send.SetAttribute
    ns.hostFrame.send.SetAttribute = function() error("protected attribute changed in combat") end
    combat = true
    ns.events.scripts.OnEvent(ns.events, "PLAYER_REGEN_DISABLED")
    ns.events.scripts.OnUpdate(ns.events, 1)
    eq(ns.game.phase, "paused", "combat voids and pauses")
    ns.hostFrame.send.SetAttribute = oldSet
    combat = false
    ns.events.scripts.OnEvent(ns.events, "PLAYER_REGEN_ENABLED")
    eq(ns.game.phase, "paused", "host deliberately resumes")
    eq(#wow.sentMessages, 0, "addon never directly calls a chat sender")
    SlashCmdList.LOREFORGE("records")
    ns.game:Stop()
    -- Exercise the actual guild adapter, secure /g output and saved results.
    IsInGuild = function() return true end
    GetNumGuildMembers = function() return 4 end
    GetGuildRosterInfo = function(index)
        local members = { "Host-Realm", "Guest-Realm", "Bystander-Realm", "Offline-Realm" }
        return members[index], nil, nil, nil, nil, nil, nil, nil, index ~= 4
    end
    ns.db.channel = "GUILD"
    ns.StartGame()
    ns.game.config.manualSend = true; ns.RefreshHost()
    eq(ns.game.phase, "announcing", "guild game started")
    eq(ns.game.players["host-realm"], nil, "guild host excluded")
    eq(ns.game.players["offline-realm"], nil, "offline guild member excluded")
    local function guildFlush()
        while ns.game:NextMessage() do
            local line = ns.game:NextMessage()
            eq(ns.hostFrame.send:GetAttribute("macrotext"), "/g " .. line, "configured guild output")
            ns.hostFrame.send.scripts.PostClick(ns.hostFrame.send)
            chat(line, "Host-Realm", "hostGUID", "CHAT_MSG_GUILD")
        end
    end
    guildFlush()
    answer = tostring(ns.game.run[1].correct)
    chat(answer, "Guest-Realm", "guestGUID", "CHAT_MSG_PARTY")
    eq(next(ns.game.answers), nil, "party reply cannot enter guild game")
    chat(answer, "Guest-Realm", "guestGUID", "CHAT_MSG_GUILD")
    time = time + 10
    ns.events.scripts.OnUpdate(ns.events, 1)
    eq(ns.db.records[ns.era]["guest-realm"], nil, "records wait for result announcements")
    guildFlush()
    eq(ns.game.phase, "finished", "guild game finished")
    local record = ns.db.records[ns.era]["guest-realm"]
    eq(record.games, 1, "guild games persist")
    eq(record.wins, 1, "guild win persists")
    eq(record.bestStreak, 1, "guild streak persists")
    eq(ns.db.records[ns.era]["bystander-realm"], nil, "guild bystanders receive no record")
    local otherEra = ns.era == "classic" and "retail" or "classic"
    ns.db.records[otherEra] = { untouched = { games = 9 } }
    ns.ConfirmClearRecords()
    eq(wow.popups[#wow.popups], "LOREFORGE_CLEAR_RECORDS", "clearing asks for product confirmation")
    eq(record.games, 1, "showing confirmation leaves records intact")
    StaticPopupDialogs.LOREFORGE_CLEAR_RECORDS.OnAccept()
    eq(next(ns.db.records[ns.era]), nil, "confirmation clears this client's records")
    eq(ns.db.records[otherEra].untouched.games, 9, "clearing preserves the other client")
    ns.hostFrame.newGame.scripts.OnClick()
    eq(ns.hostFrame.setup:IsShown(), true, "new game returns to setup")
    ns.db.records[ns.era]["guest-realm"] = { games = 7, wins = 3 }
    local savedRecords = ns.db.records
    ns.HammerCore.ResetSettings()
    eq(LoreforgeDB.records, savedRecords, "reset settings preserves player records")
    eq(LoreforgeDB.records[ns.era]["guest-realm"].games, 7, "saved history survives reset")
end
io.write("loreforge addon tests passed\n")
