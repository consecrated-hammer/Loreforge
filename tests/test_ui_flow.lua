package.path = './tests/hammercore/?.lua;' .. package.path
local wow = require('wow')
local function eq(a, b, why) assert(a == b, why .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)) end
for _, forever in ipairs({ false, true }) do
    wow.Install({ Loreforge = { Version = '0.1.0' } })
    LoreforgeDB = nil
    local now, members = 100, 1
    GetTime = function() return now end
    InCombatLockdown = function() return false end
    GetBuildInfo = function() return '', '', '', forever and 16001 or 120105 end
    WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
    GetNormalizedRealmName = function() return 'Realm' end
    local names = { player = {'Host', 'Smith'}, party1 = {'Guest', 'Jones'}, party2 = {'Late', 'New'} }
    UnitFullName = function(unit)
        local p = names[unit]
        if p then return p[1], forever and p[2] or 'Realm' end
    end
    GetUnitName = function(unit)
        local p = names[unit]
        return p and (p[1] .. (forever and (' ' .. p[2]) or ''))
    end
    UnitGUID = function(unit) return names[unit] and (unit .. '-GUID') end
    IsInGroup = function(category) return category == 2 end
    IsInRaid = function() return false end
    GetNumSubgroupMembers = function() return members end
    GetNumGroupMembers = function() return members + 1 end
    RegisterStateDriver, UnregisterStateDriver = function() end, function() end
    assert(loadfile('tests/transport-libs.lua'))()()
    local ns = wow.LoadHammerCore('Libs/HammerCore', 'Loreforge')
    for _, file in ipairs({'Transport.lua','Codec.lua','PartyBus.lua','Game.lua','Core.lua','Setup.lua','History.lua','Host.lua','Options.lua','Party.lua','Player.lua','Probe.lua'}) do assert(loadfile(file))('Loreforge', ns) end
    local loader
    for _, f in ipairs(wow.frames) do if f.scripts.OnEvent then loader = f end end
    loader.scripts.OnEvent(loader, 'ADDON_LOADED', 'Loreforge')
    eq(ns.db.channel, 'INSTANCE_CHAT', 'fresh setup selects active instance group')
    local hostName, guestName = GetUnitName('player'), GetUnitName('party1')
    local guestKey = ns.Identity(guestName)
    eq(ns.Roster('INSTANCE_CHAT')[1].key, guestKey, 'full chat name matches enrolled identity')
    if forever then
        eq(guestKey, 'guest jones-realm', 'surname is preserved and never treated as realm')
        GetUnitName = nil
        eq(ns.Roster('INSTANCE_CHAT')[1].key, guestKey, 'tuple fallback joins Forever surname correctly')
        GetUnitName = function(unit) local p = names[unit]; return p and (p[1] .. ' ' .. p[2]) end
        assert(ns.Identity('First Last') ~= ns.Identity('FirstLast'), 'spaces in character names must not collapse')
    else
        assert(ns.Identity('Guest-OtherRealm') ~= ns.Identity('Guest-Realm'), 'Retail realm identities stay separate')
    end
    ns.OpenHost()
    ns.db.channel = 'PARTY'
    ns.StartGame()
    eq(ns.game.phase, 'setup', 'bad destination keeps setup visible')
    assert(ns.hostFrame.setup.banner.text:GetText():find('Use Instance', 1, true), 'setup error is visible in window')
    assert(ns.hostFrame.setup.rosterButton:IsShown(), 'the fix sits beside the problem')
    ns.hostFrame.setup.rosterButton.scripts.OnClick()
    eq(ns.db.channel, 'INSTANCE_CHAT', 'Use current group fixes destination')
    ns.db.rounds, ns.db.perRound, ns.db.seconds = 2, 1, 5
    ns.db.autoMode, ns.db.readySeconds = false, 5
    ns.db.hostParticipates = true
    local blocked, sent = false, 0
    local function chat(text, sender, guid)
        ns.events.scripts.OnEvent(ns.events, 'CHAT_MSG_INSTANCE_CHAT_LEADER', text, sender, nil, nil, nil, nil, nil, nil, nil, nil, nil, guid)
    end
    C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = function() return true end
    C_ChatInfo.InChatMessagingLockdown = function() return false end
    C_ChatInfo.SendChatMessage = function(text, channel)
        if blocked then return end -- message sent, but its echo is unavailable
        eq(channel, 'INSTANCE_CHAT', 'selected destination')
        sent = sent + 1
        chat(text, hostName, 'player-GUID')
    end
    local function tick(seconds) now = now + seconds; ns.events.scripts.OnUpdate(ns.events, seconds) end
    local function untilPhase(phase)
        for _ = 1, 500 do if ns.game.phase == phase then return end; tick(0.25) end
        error('never reached ' .. phase .. '; actual ' .. ns.game.phase)
    end
    ns.StartGame()
    ns.hostFrame.readyButton.scripts.OnClick()
    eq(#ns.game:ReadyPlayers(), 1, 'Game Master ready button works before the notice finishes')
    chat("I'm ready!", 'Different Chat Formatting', 'party1-GUID')
    eq(#ns.game:ReadyPlayers(), 2, 'GUID fallback accepts natural ready replies despite different sender formatting')
    untilPhase('ready')
    members = 2
    ns.events.scripts.OnEvent(ns.events, 'GROUP_ROSTER_UPDATE')
    eq(ns.game.phase, 'ready', 'lobby roster change refreshes enrolment without stalling')
    ns.hostFrame.rosterRefresh.scripts.OnClick()
    assert(ns.game.players[ns.Identity(GetUnitName('party2'))], 'explicit ready roster refresh adds missing player')
    eq(ns.hostFrame.next:GetText(), 'Start questions now', 'ready phase has explicit primary action')
    ns.hostFrame.next.scripts.OnClick()
    untilPhase('accepting')
    assert(sent >= 3, 'host-paced question sends its lines without per-line clicks')
    chat(tostring(ns.game.run[1].correct), guestName, 'party1-GUID')
    untilPhase('between')
    eq(ns.hostFrame.next:GetText(), 'Ask next question', 'host sees the next required action')
    tick(100); eq(ns.game.phase, 'between', 'host pacing leaves a chat break')
    eq(ns.game:AddReadyPlayers({{key='outsider-r',name='Outsider-R'}}), nil, 'enrolment freezes when questions begin')
    ns.hostFrame.next.scripts.OnClick()
    untilPhase('accepting')
    chat(tostring(ns.game.run[2].correct), guestName, 'party1-GUID')
    blocked = true
    untilPhase('paused')
    eq(ns.hostFrame.next:GetText(), 'Resume game', 'failed send exposes recovery action')
    eq(ns.hostFrame.mode:GetText(), 'Retry automatic posting', 'automatic delivery can be retried explicitly')
    assert(ns.game.pending, 'timed-out line stays available for direct human confirmation')
    assert(ns.hostFrame.recover:IsShown(), 'paused timeout exposes visible-line confirmation without a resend')
    ns.hostFrame.recover.scripts.OnClick()
    while ns.game:NextMessage() do
        local line = ns.game:NextMessage()
        ns.hostFrame.send.scripts.PostClick(ns.hostFrame.send)
        chat(line, hostName, 'player-GUID')
    end
    eq(ns.game.phase, 'finished', 'human-confirmed recovery can finish results')
    local record = ns.db.records[ns.era][guestKey]
    eq(record.correct, 2, 'surname player answers are scored')
    eq(record.bestStreak, 2, 'surname player streak is saved')
    eq(ns.db.records[ns.era][ns.Identity(hostName)], nil, 'ready-only Game Master receives no player record')
    eq(ns.hostFrame.next:GetText(), 'New game', 'completed quiz has clear primary action')
    ns.hostFrame.next.scripts.OnClick()
    eq(ns.hostFrame.setup:IsShown(), true, 'New game returns to setup')
    blocked = false
    ns.StartGame()
    C_ChatInfo.InChatMessagingLockdown = function() return true end
    ns.hostFrame.newGame.scripts.OnClick()
    eq(wow.popups[#wow.popups], 'LOREFORGE_STOP_GAME', 'active stop requests confirmation')
    assert(ns.game:Active(), 'requesting stop has not discarded results')
    StaticPopupDialogs.LOREFORGE_STOP_GAME.OnAccept()
    eq(ns.game.phase, 'stopped', 'confirmed stop ends the quiz')
end
io.write('loreforge UI flow and client identity tests passed\n')
