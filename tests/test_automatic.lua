package.path = './tests/hammercore/?.lua;' .. package.path
local wow = require('wow')
local function eq(a, b, why) assert(a == b, why .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)) end
for _, toc in ipairs({ 'Loreforge.toc', 'Loreforge_Camelot.toc' }) do
    for _, channel in ipairs({ 'PARTY', 'RAID', 'INSTANCE_CHAT', 'GUILD' }) do
        wow.Install({ Loreforge = { Version = '0.1.0' } })
        LoreforgeDB = nil
        local time, combat, instanceRaid = 100, false, false
        GetTime = function() return time end
        InCombatLockdown = function() return combat end
        GetBuildInfo = function() return '', '', '', toc:find('Camelot') and 16001 or 120105 end
        WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
        LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = 1, 2
        GetNormalizedRealmName = function() return 'Realm' end
        local names = { player = 'Host', party1 = 'Guest', raid1 = 'Host', raid2 = 'Guest', raid3 = 'Bystander' }
        UnitFullName = function(unit) return names[unit], 'Realm' end
        GetUnitName = function(unit) return (UnitFullName(unit)) end
        UnitGUID = function(unit) return names[unit] and names[unit] .. 'GUID' end
        IsInGroup = function(category) return category == 2 and channel == 'INSTANCE_CHAT' or category == 1 and channel ~= 'INSTANCE_CHAT' end
        IsInRaid = function(category) return category == 1 and channel == 'RAID' or category == 2 and instanceRaid end
        GetNumGroupMembers = function() return 3 end
        GetNumSubgroupMembers = function() return 1 end
        IsInGuild = function() return true end
        GetNumGuildMembers = function() return 3 end
        GetGuildRosterInfo = function(index)
            return ({ 'Host-Realm', 'Guest-Realm', 'Bystander-Realm' })[index], nil, nil, nil, nil, nil, nil, nil, true
        end
        RegisterStateDriver = function() end
        UnregisterStateDriver = function() end
        local ns = wow.LoadHammerCore('Libs/HammerCore', 'Loreforge')
        for line in assert(io.open(toc)):read('*a'):gmatch('[^\r\n]+') do
            if line:match('^[%w]+%.lua$') then assert(loadfile(line))('Loreforge', ns) end
        end
        local loader
        for _, f in ipairs(wow.frames) do if f.scripts.OnEvent then loader = f end end
        loader.scripts.OnEvent(loader, 'ADDON_LOADED', 'Loreforge')
        ns.db.channel, ns.db.rounds, ns.db.perRound, ns.db.seconds = channel, 2, 2, 5
        ns.db.readyCheck = false
        ns.db.questionGap, ns.db.autoMode = 3, false
        local event = ({ PARTY = 'CHAT_MSG_PARTY_LEADER', RAID = 'CHAT_MSG_RAID_LEADER', INSTANCE_CHAT = 'CHAT_MSG_INSTANCE_CHAT_LEADER', GUILD = 'CHAT_MSG_GUILD' })[channel]
        local function chat(text, sender, destination)
            ns.events.scripts.OnEvent(ns.events, destination or event, text, sender, nil, nil, nil, nil, nil, nil, nil, nil, nil,
                sender == 'Host-Realm' and 'HostGUID' or 'GuestGUID')
        end
        local function tick(seconds)
            time = time + seconds
            ns.events.scripts.OnUpdate(ns.events, seconds)
        end
        -- All four manual destinations use their own secure macro and echo event.
        ns.StartGame()
        ns.game.config.manualSend = true; ns.RefreshHost()
        eq(ns.game.phase, 'announcing', channel .. ' manual start')
        eq(ns.game.players['host-realm'], nil, 'host excluded from roster')
        while ns.game:NextMessage() do
            local line = ns.game:NextMessage()
            eq(ns.hostFrame.send:GetAttribute('macrotext'), ns.Game.CHANNELS[channel].macro .. line, 'selected secure macro')
            ns.hostFrame.send.scripts.PostClick(ns.hostFrame.send)
            chat(line, 'Host-Realm', 'CHAT_MSG_SAY')
            assert(ns.game.pending, 'unselected echo must not advance')
            chat(line, 'Host-Realm')
        end
        eq(ns.game.phase, 'accepting', 'leader or guild echoes open answers')
        ns.game:Stop()
        if channel == 'INSTANCE_CHAT' then
            instanceRaid = true
            eq(#ns.Roster(channel), 2, 'instance raid uses raid units, excluding host')
            local _, err = ns.Roster('PARTY')
            assert(err, 'dual group cannot enrol instance units for home party')
            _, err = ns.Roster('RAID')
            assert(err, 'dual group cannot enrol instance units for home raid')
            instanceRaid = false
        end
        -- A complete automatic game needs no announcement or next-question clicks.
        local sent = {}
        C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = function() return true end
        C_ChatInfo.InChatMessagingLockdown = function() return false end
        C_ChatInfo.SendChatMessage = function(text, destination)
            eq(destination, channel, 'automatic destination')
            sent[#sent + 1] = { text = text, at = time, rapid = ns.game.phase == 'announcing'
                and ns.game.questionCursor and ns.game.cursor >= ns.game.questionCursor }
            chat(text, 'Host-Realm') -- immediate echoes must also be safe
        end
        ns.db.autoMode = true
        ns.StartGame()
        eq(ns.hostFrame.send:GetAttribute('macrotext'), nil, 'automatic game disarms manual macro')
        for _ = 1, 1500 do
            if ns.game.phase == 'finished' then break end
            assert(ns.game.phase ~= 'paused', ns.game.reason)
            if ns.game.phase == 'accepting' then
                chat(tostring(ns.game.run[ns.game.index].correct), 'Guest-Realm')
            end
            tick(0.25)
        end
        eq(ns.game.phase, 'finished', 'automatic game completes')
        local record = ns.db.records[ns.era]['guest-realm']
        eq(record.games, 1, 'automatic result saved once')
        eq(record.correct, 4, 'all questions scored')
        eq(record.bestStreak, 4, 'streak spans rounds')
        local recaps, milestones = 0, 0
        for i, line in ipairs(sent) do
            if i > 1 then assert(line.at - sent[i-1].at >= (sent[i-1].rapid and 0.35 or 2), 'automatic lines respect their pacing') end
            if line.text:find('Correct: Guest%-Realm') then recaps = recaps + 1 end
            if line.text:find('new personal best!', 1, true) then milestones = milestones + 1 end
        end
        eq(recaps, 4, 'every answer has a named recap')
        eq(milestones, 1, 'first streak milestone announced once')
        ns.db.readyCheck, ns.db.readySeconds = true, 5
        ns.StartGame()
        chat('ready', 'Guest-Realm', 'CHAT_MSG_SAY')
        eq(#ns.game:ReadyPlayers(), 0, 'ready from another channel is ignored')
        chat(' READY ', 'Guest-Realm')
        eq(#ns.game:ReadyPlayers(), 1, 'ready during announcement is accepted in selected channel')
        for _ = 1, 100 do
            if ns.game.phase == 'ready' then break end
            tick(0.25)
        end
        eq(ns.game.phase, 'ready', 'ready notice delivered in selected channel')
        chat('ready', 'Guest-Realm')
        eq(#ns.game:ReadyPlayers(), 1, 'chat ready reply reaches ready check')
        eq(ns.game.players['guest-realm'].total, 0, 'ready reply earns no score')
        ns.hostFrame.next.scripts.OnClick()
        eq(ns.game.phase, 'announcing', 'host can start questions early')
        ns.game:Stop()
        ns.db.readyCheck = false
        -- Refusal, absent echoes and realm restrictions stop without retry loops.
        local calls = 0
        C_ChatInfo.SendChatMessage = function() calls = calls + 1; error('blocked') end
        ns.StartGame(); tick(1)
        eq(ns.game.phase, 'paused', 'send errors pause')
        eq(ns.game.config.autoMode, false, 'send errors enable manual controls')
        tick(20); eq(calls, 1, 'failed automatic send is never retried')
        ns.hostFrame.pause.scripts.OnClick()
        assert(ns.hostFrame.send:GetAttribute('macrotext'), 'resume arms manual fallback')
        ns.game:Stop()
        C_ChatInfo.SendChatMessage = function() calls = calls + 1 end
        ns.StartGame(); tick(1)
        assert(ns.game.pending, 'unconfirmed output stays pending')
        tick(8)
        eq(ns.game.phase, 'paused', 'missing echo pauses')
        eq(ns.game.config.autoMode, false, 'missing echo switches to manual')
        eq(calls, 2, 'no automatic echo retry')
        ns.game:Stop()
        C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = function() return true end
        ns.StartGame(); tick(1)
        eq(ns.game.phase, 'announcing', 'realm flag alone does not block ordinary chat')
        eq(calls, 3, 'realm flag does not prevent a send attempt')
        assert(ns.game.pending, 'realm-flag send still requires exact echo')
        ns.game:Stop()
        ns.StartGame()
        C_ChatInfo.InChatMessagingLockdown = function() return true end
        tick(1)
        eq(ns.game.phase, 'paused', 'actual messaging lockdown pauses')
        eq(ns.game.config.autoMode, true, 'temporary lockdown keeps automatic mode selected')
        eq(calls, 3, 'actual lockdown never invokes sender')
        C_ChatInfo.InChatMessagingLockdown = function() return false end
        tick(10)
        eq(ns.game.phase, 'paused', 'ending lockdown requires deliberate resume')
        ns.game:Stop()
        ns.StartGame(); combat = true; tick(1)
        eq(ns.game.phase, 'paused', 'combat pauses automatic game')
        eq(calls, 3, 'combat never invokes sender')
        combat = false; tick(10)
        eq(ns.game.phase, 'paused', 'ending combat cannot resume automatically')
        eq(record.games, 1, 'interrupted runs do not change history')
        ns.game:Stop()
        -- A participating Game Master can answer their own channel messages.
        ns.db.hostParticipates, ns.db.autoMode = true, false
        ns.db.rounds, ns.db.perRound = 1, 1
        ns.StartGame()
        assert(ns.game.players['host-realm'], 'participating host is enrolled')
        eq(ns.game.config.localOnly, false, 'real group game keeps selected channel')
        ns.game.config.manualSend = true; ns.RefreshHost()
        local function manualFlush()
            while ns.game:NextMessage() do
                local line = ns.game:NextMessage()
                ns.hostFrame.send.scripts.PostClick(ns.hostFrame.send)
                if not ns.game.config.localOnly then chat(line, 'Host-Realm') end
            end
        end
        manualFlush()
        eq(next(ns.game.answers), nil, 'announcement echoes cannot become Game Master answers')
        local right = ns.game.run[1].correct
        chat(tostring(right), 'Host-Realm')
        chat(tostring(right % 4 + 1), 'Host-Realm')
        eq(ns.game.answers['host-realm'], right, 'Game Master chat answer locks first attempt')
        tick(5); manualFlush()
        eq(ns.db.records[ns.era]['host-realm'].wins, 1, 'Game Master earns a normal win')
        -- With no group or guild, local testing uses no outbound chat API.
        IsInGroup, IsInRaid, IsInGuild = function() return false end, function() return false end, function() return false end
        GetNumGroupMembers, GetNumSubgroupMembers = function() return 0 end, function() return 0 end
        C_ChatInfo.SendChatMessage = function() error('local game attempted outbound chat') end
        C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = function() return true end
        ns.db.readyCheck, ns.db.readySeconds = true, 5
        for _, automatic in ipairs({ false, true }) do
            ns.db.autoMode = automatic
            ns.StartGame()
            eq(ns.game.config.localOnly, true, 'ungrouped Game Master gets local preview')
            for _ = 1, 500 do
                if ns.game.phase == 'finished' then break end
                if ns.game.config.manualSend then manualFlush() end
                if ns.game.phase == 'ready' then
                    ns.hostFrame.answerButtons[1].scripts.OnClick()
                    eq(#ns.game:ReadyPlayers(), 1, 'Game Master can check in by button')
                    ns.hostFrame.next.scripts.OnClick()
                elseif ns.game.phase == 'accepting' then
                    ns.hostFrame.answerButtons[ns.game.run[1].correct].scripts.OnClick()
                    assert(ns.hostFrame.preview:GetText():find('Answer locked:', 1, true), 'click gives immediate locked feedback')
                    eq(ns.hostFrame.answerButtons[ns.game.run[1].correct].enabled, false, 'first answer disables further choices')
                    assert(not ns.SubmitHostAnswer(tostring(ns.game.run[1].correct % 4 + 1)), 'Game Master cannot change a locked answer')
                end
                eq(ns.hostFrame.send:GetAttribute('macrotext'), nil, 'local mode never arms an outbound macro')
                tick(0.25)
            end
            eq(ns.game.phase, 'finished', 'one-player test completes')
        end
        eq(ns.db.records[ns.era]['host-realm'].games, 3, 'local and group Game Master games persist')
        eq(ns.db.records[ns.era]['host-realm'].bestStreak, 1, 'Game Master streak persists')
        ns.db.hostParticipates = false
        ns.StartGame()
        eq(ns.game.phase, 'finished', 'host-only start remains unavailable when Game Master participation is off')
    end
end
io.write('loreforge automatic/channel tests passed\n')
