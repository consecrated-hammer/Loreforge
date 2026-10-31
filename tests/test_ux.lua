package.path = './tests/hammercore/?.lua;' .. package.path
local wow = require('wow')
local function eq(a, b, why) assert(a == b, why .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)) end

-- The 0.3 UX pass: setup presets and steppers, practice, the lobby guard,
-- history, the Hall of Fame, interrupted games, chat output, the live host
-- table and the player window's new cues.

local now, members, grouped = 100, 2, true
local sounds, sent = {}, {}
local function load(db, partyEnabled)
    wow.Install({ Loreforge = { Version = '0.3.0' } })
    if partyEnabled then C_ChatInfo.RegisterAddonMessagePrefix = function() return 0 end end
    LoreforgeDB = db
    GetTime = function() return now end
    GetServerTime = function() return 1800000000 + math.floor(now) end
    InCombatLockdown = function() return false end
    GetBuildInfo = function() return '', '', '', 120105 end
    WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
    GetNormalizedRealmName = function() return 'Realm' end
    local names = { player = 'Host', party1 = 'Guest', party2 = 'Third' }
    UnitFullName = function(unit) if names[unit] then return names[unit], 'Realm' end end
    GetUnitName = function(unit) return names[unit] end
    UnitGUID = function(unit) return names[unit] and (unit .. '-GUID') end
    IsInGroup = function(category) return grouped and category == 1 end
    IsInRaid = function() return false end
    IsInInstance = function() return false end
    GetNumSubgroupMembers = function() return grouped and members or 0 end
    GetNumGroupMembers = function() return grouped and members + 1 or 0 end
    RegisterStateDriver, UnregisterStateDriver = function() end, function() end
    PlaySound = function(id) sounds[#sounds + 1] = id end
    GetBindingKey = function(name) return name == 'LOREFORGE_ANSWER2' and 'F2' or nil end
    date = os.date
    assert(loadfile('tests/transport-libs.lua'))()()
    local ns = wow.LoadHammerCore('Libs/HammerCore', 'Loreforge')
    for line in assert(io.open('Loreforge.toc')):read('*a'):gmatch('[^\r\n]+') do
        if line:match('^[%w]+%.lua$') then assert(loadfile(line))('Loreforge', ns) end
    end
    local loader
    for _, f in ipairs(wow.frames) do if f.scripts.OnEvent then loader = f end end
    loader.scripts.OnEvent(loader, 'ADDON_LOADED', 'Loreforge')
    sent = {}
    C_ChatInfo.InChatMessagingLockdown = function() return false end
    C_ChatInfo.SendChatMessage = function(text, channel)
        sent[#sent + 1] = { text = text, channel = channel }
        ns.events.scripts.OnEvent(ns.events, 'CHAT_MSG_PARTY', text, 'Host-Realm', nil, nil, nil, nil, nil, nil, nil, nil, nil, 'player-GUID')
    end
    return ns
end
local function tick(ns, seconds) now = now + seconds; ns.events.scripts.OnUpdate(ns.events, seconds) end
local function chat(ns, text, sender, guid)
    ns.events.scripts.OnEvent(ns.events, 'CHAT_MSG_PARTY', text, sender, nil, nil, nil, nil, nil, nil, nil, nil, nil, guid)
end

-- Real addon event -> transport -> Party bus -> player window, with setup open.
do
    local n = load({compactChoices = true}, true)
    eq(n.db.compactChoices, false, 'upgrade restores separate choice lines')
    n.db.compactChoices = true
    n = load(n.db, true)
    eq(n.db.compactChoices, true, 'later explicit compact preference is retained')
    IsInInstance = function() return true, 'party' end
    assert(n.Party.Available(), 'premade Party can use the player UI inside a dungeon')
    for _, kind in ipairs({'arena','pvp','raid','scenario','unknown'}) do
        IsInInstance = function() return true, kind end
        assert(not n.Party.Available(), 'other instance type stays excluded: ' .. kind)
    end
    IsInInstance = function() return true, 'party' end
    local group, raid, restrictions = IsInGroup, IsInRaid, C_ChatInfo.InChatMessagingLockdown
    IsInRaid = function() return true end
    now = now + 0.1
    assert(not n.Party.Available(), 'raid roster still rejected')
    IsInRaid = raid
    IsInGroup = function() return true end
    now = now + 0.1
    assert(not n.Party.Available(), 'dual or queued instance group still rejected')
    IsInGroup = function(category) return category == 2 end
    now = now + 0.1
    assert(not n.Party.Available(), 'queued instance group still rejected')
    IsInGroup = function() return false end
    now = now + 0.1
    assert(not n.Party.Available(), 'solo is still local only')
    IsInGroup = group
    now = now + 0.1
    C_ChatInfo.InChatMessagingLockdown = function() return true end
    assert(not n.Party.Available(), 'chat lockdown still blocks invitations')
    C_ChatInfo.InChatMessagingLockdown = restrictions
    assert(n.Party.Available(), 'restored unrestricted dungeon Party is eligible')
    n.OpenHost()
    local function invite(id)
        local packet = assert(n.Party.bus.Send({v=1, kind='invite', id=id, to='*', config={
            rounds=1, perRound=5, seconds=20, difficulty='mixed', categories='Lore', readyCheck=true}}, {}))
        local frames = n.Party.bus.outgoing[packet].frames
        n.Party.bus.outgoing[packet] = nil
        for _, frame in ipairs(frames) do
            n.Party.frame.scripts.OnEvent(n.Party.frame, 'CHAT_MSG_ADDON', 'LoreforgeM1',
                assert(n.Party.bus.transport.Pack(frame)), 'PARTY', 'Guest-Realm')
        end
        for _ = 1, #frames do now=now+0.1; n.Party.Tick() end
    end
    invite('guest-realm:1')
    local f = n.Player.frame
    assert(f and f:IsShown(), 'received wire invitation opens the real player window')
    eq(f:GetFrameStrata(), n.hostFrame:GetFrameStrata(), 'invitation shares the main window layer')
    assert(f:GetFrameLevel() > n.hostFrame:GetFrameLevel(), 'invitation sits above setup')
    assert(f.raised, 'opening an invitation raises it')
    eq(f.primary:GetText(), 'Join quiz', 'wire invitation offers join')
    n.Player.Hide()
    n.OpenMain()
    assert(f:IsShown(), 'slash command reopens an unanswered invitation')
    assert(n.Party.Report():find('Invitation received',1,true), 'diagnostics show invitation delivery')
    local render = n.Player.Render
    n.Player.Render = function() error('test drawing failure') end
    invite('guest-realm:2')
    assert(n.Party.Report():find('test drawing failure',1,true), 'drawing errors survive in diagnostics')
    local printed = #wow.printed
    invite('guest-realm:2')
    eq(#wow.printed, printed, 'the same drawing error does not spam chat')
    n.Player.Render = render
    invite('guest-realm:2')
    eq(n.Party.renderError, nil, 'repeated invitation retries a failed render')
    local wires = n.Party.wireReceived
    n.Party.frame.scripts.OnEvent(n.Party.frame, 'CHAT_MSG_ADDON', 'LoreforgeM1', 'bad', 'PARTY', 'Host-Realm')
    eq(n.Party.wireReceived, wires, 'self echoes do not count as remote prefix traffic')
    n.Party.Report = function() error('test report failure') end
    local report = n.HammerCore.spec.diagnostics()
    assert(report:find('Party diagnostics failed:',1,true), 'Party report failure leaves other diagnostics available')
    assert(report:find('Questions:',1,true), 'base diagnostics survive Party report failure')
end

-- The actual idle player's host-chat event reveals a prepared question without
-- waiting for an addon snapshot; a tiny SHOW is the reordered/missed-chat fallback.
do
    local n=load(nil,true)
    local config={rounds=1,perRound=1,seconds=20,difficulty='mixed',categories='Lore',readyCheck=false}
    n.Party.Receive({v=1,kind='invite',to='*',id='guest-realm:sync-test',config=config},'guest-realm')
    local c=n.Party.client
    c.joined=true;c.model.state='joining'
    local function payload(seq,revision,attempt)
        return {v=1,kind='snapshot',id=c.id,to='host-realm',seq=seq,preparationRevision=revision,
            state='preparing',config=config,index=1,round=1,attempt=attempt,remaining=0,status='',rows={},
            question='A shared question?',choices={'One','Two','Three','Four'},
            firstLine='[Loreforge #1] Round 1, question 1 (20s)'..(attempt>1 and (' (restart '..attempt..')') or '')..': A shared question?'}
    end
    local first=payload(1,1,1)
    n.Party.Receive(first,'guest-realm')
    eq(c.model.state,'preparing','cached question stays hidden')
    assert(not n.Player.frame.question:IsShown(),'player card has no early reading advantage')
    n.events.scripts.OnEvent(n.events,'CHAT_MSG_PARTY',first.firstLine,'Third-Realm')
    eq(c.model.state,'preparing','other party member cannot reveal the cache')
    n.events.scripts.OnEvent(n.events,'CHAT_MSG_PARTY_LEADER',first.firstLine,'Guest-Realm')
    eq(c.model.state,'announcing','selected host chat reveals cached question')
    assert(n.Player.frame.question:IsShown(),'question visible immediately from chat handler')
    eq(n.Player.frame.question:GetText(),'A shared question?','the prepared text is displayed')
    assert(not n.Player.frame.answers[1].enabled,'reading still cannot answer')
    -- A newer snapshot sequence does not replace the stable preparation identity.
    n.Party.Receive(payload(2,1,1),'guest-realm')
    eq(c.model.state,'announcing','duplicate prepare cannot hide a shown question')
    -- SHOW can overtake the fragmented payload, then reveal it on arrival.
    n.Party.Receive({v=1,kind='show',id=c.id,to='host-realm',index=1,attempt=2,revision=3},'guest-realm')
    n.Party.Receive(payload(4,3,2),'guest-realm')
    eq(c.model.state,'announcing','buffered SHOW reveals matching late payload')
    n.Party.Receive(payload(5,5,3),'guest-realm')
    eq(c.model.state,'preparing','new attempt starts hidden')
    n.events.scripts.OnEvent(n.events,'CHAT_MSG_PARTY',first.firstLine,'Guest-Realm')
    eq(c.model.state,'preparing','old chat cannot expose a later attempt')
    n.Party.Receive({v=1,kind='show',id=c.id,to='host-realm',index=1,attempt=2,revision=3},'guest-realm')
    eq(c.model.state,'preparing','old SHOW cannot expose a later attempt')
    n.events.scripts.OnEvent(n.events,'CHAT_MSG_PARTY',c.model.firstLine,'Guest-Realm')
    eq(c.model.state,'announcing','current restart chat reveals only current attempt')
end
-- Both automatic and secure/manual posting use the same first-line hold.
do
    local n=load(nil,true)
    n.db.readyCheck,n.db.rounds,n.db.perRound=false,1,1
    assert(n.Party.OpenLobby())
    n.Party.Receive({v=1,kind='join',id=n.Party.host.id,to='host-realm',earlyQuestions=true},'guest-realm')
    n.StartGame()
    local g=n.game
    local rules=g:NextMessage();g:Sent();g:Echo(rules)
    eq(g:NextMessage(),nil,'first question is withheld synchronously')
    g.config.manualSend=true;n.RefreshHost()
    local f=n.hostFrame
    assert(not f.question:GetText():find(g.run[1].text,1,true),'host question hidden while waiting')
    assert(not f.answerButtons[1]:IsShown(),'host choices hidden while waiting')
    assert(not f.preview:GetText():find(g.run[1].text,1,true),'posting preview cannot leak the question')
    eq(f.send:GetAttribute('macrotext'),nil,'secure macro has no line before preparation')
    eq(f.send.enabled,false,'secure button is disabled before preparation')
    local sequence=n.Party.host.seq
    for _=1,3 do g:NextMessage();n.RefreshHost() end
    eq(n.Party.host.seq,sequence,'getters and UI refreshes do not transmit preparation')
    g:Pause('pause before first public line');n.RefreshHost()
    assert(not f.question:GetText():find(g.run[1].text,1,true),'pause cannot expose hidden question')
    assert(not f.answerButtons[1]:IsShown(),'pause cannot expose hidden choices')
    assert(not f.preview:GetText():find(g.run[1].text,1,true),'pause cannot expose posting preview')
    assert(g:Resume())
    while g.cursor<g.questionCursor do local line=g:NextMessage();g:Sent();g:Echo(line) end
    local prep=n.Party.host.preparation
    n.Party.Receive({v=1,kind='prepared',id=n.Party.host.id,to='host-realm',index=1,attempt=prep.attempt,revision=prep.revision},'guest-realm')
    local first=assert(g:NextMessage());n.RefreshHost()
    assert(f.send:GetAttribute('macrotext'),'manual posting becomes available after preparation')
    assert(not g.questionVisible,'preparation alone cannot reveal to host')
    g:Sent();n.events.scripts.OnEvent(n.events,'CHAT_MSG_PARTY',first,'Host-Realm')
    eq(g.questionVisible,true,'first public echo reveals host question')
    eq(f.question:GetText(),g.run[1].text,'host card shows the shared current question')
    n.Party.Receive({v=1,kind='presented',id=n.Party.host.id,to='host-realm',index=1,attempt=prep.attempt,revision=prep.revision},'guest-realm')
    while g:NextMessage() do local line=g:NextMessage();g:Sent();g:Echo(line) end
    eq(g.phase,'presenting','answer gate still follows final choice echo')
    n.Party.Tick()
    eq(g.phase,'opening','early shown ACK survives into the answer-opening step')
    eq(g.deadline,nil,'opening announcement still controls the timer')
end

-- ── Engine: chat output ──
local ns = load(nil)
local Game = ns.Game
eq(Game.RulesText({ rounds = 1, perRound = 5, categories = { lore = true, murlocs = true } }),
    '1 round x 5 questions, General lore, Murlocs and Mischief.', 'opening line names a few categories')
local all = {}
for _, c in ipairs(Game.CATEGORIES) do all[c[1]] = true end
eq(Game.RulesText({ rounds = 3, perRound = 5, categories = all }), '3 rounds x 5 questions, all categories.', 'all categories')

local bank = {}
for i = 1, 8 do bank[i] = { 'Question ' .. i, 'Right', 'Wrong A', 'Wrong B', 'Wrong C', categories = { 'lore' }, id = 'q' .. i } end
local clock = 0
local g = Game.New(bank, function() return clock end, function(n) return 1 end, {})
local roster = {}
for i, name in ipairs({ 'A', 'B', 'C', 'D', 'E' }) do roster[i] = { key = name:lower(), name = name } end
assert(g:Start({ rounds = 1, perRound = 1, seconds = 5, channel = 'PARTY', readyCheck = false, difficulty = 'mixed',
    categories = { lore = true } }, 'retail', roster, 7))
local function flush()
    while g:NextMessage() do g:Sent(); g:Echo(g.pending.text) end
end
flush()
for _, p in ipairs(roster) do g:Answer(p.key, tostring(g.run[1].correct)) end
clock = 10; g:Tick(); flush()
eq(g.phase, 'finished', 'one-round game finishes')
local roundLines, recordLines = 0, 0
for _, line in ipairs(g.queue) do
    if line:find('Round 1 winner', 1, true) then roundLines = roundLines + 1 end
end
-- The queue is cleared once flushed; replay the announcement order instead.
local g2 = Game.New(bank, function() return clock end, function() return 1 end, {})
clock = 0
assert(g2:Start({ rounds = 1, perRound = 1, seconds = 5, channel = 'PARTY', readyCheck = false, difficulty = 'mixed',
    categories = { lore = true } }, 'retail', roster, 8))
while g2:NextMessage() do g2:Sent(); g2:Echo(g2.pending.text) end
for _, p in ipairs(roster) do g2:Answer(p.key, tostring(g2.run[1].correct)) end
clock = 10; g2:Tick()
for _, line in ipairs(g2.queue) do
    if line:find('Round 1', 1, true) then roundLines = roundLines + 1 end
    if line:find('Records:', 1, true) then recordLines = recordLines + 1 end
end
eq(roundLines, 0, 'a one-round game skips the round result')
eq(recordLines, 3, 'only the top three records are announced')
local five = 0
for _ in pairs(g2.pendingRecords) do five = five + 1 end
eq(five, 5, 'every player still gets a saved record')

-- Old default countdown upgrades once; custom durations and later choices survive.
ns = load({readySeconds=10})
eq(ns.db.readySeconds, 30, 'old countdown default upgrades')
ns.db.readySeconds = 10
ns = load(ns.db)
eq(ns.db.readySeconds, 10, 'explicit shorter countdown survives reload')
ns = load({readySeconds=45})
eq(ns.db.readySeconds, 45, 'custom countdown preserved')

-- ── Upgrade: old wider settings are clamped, not reset ──
ns = load({ rounds = 20, perRound = 50, seconds = 120, questionGap = 3 })
eq(ns.db.rounds, 10, 'rounds clamp to the new maximum')
eq(ns.db.perRound, 15, 'questions per round clamp')
eq(ns.db.seconds, 60, 'answer time clamps')
eq(ns.db.questionGap, 3, 'in-range values are kept')

-- ── Setup ──
ns = load(nil)
eq(ns.db.hostParticipates, true, 'the host plays along by default')
eq(ns.db.readySeconds, 30, 'default start countdown is thirty seconds')
eq(ns.db.compactChoices, false, 'separate choices by default')
ns.OpenHost()
local f = ns.hostFrame
local setup = f.setup
assert(setup:IsShown(), 'Play opens on setup')
eq(setup.countdown:GetParent(), setup.left, 'start countdown is outside folded advanced options')
wow.Click(setup.countdown.plus)
eq(ns.db.readySeconds, 35, 'start countdown can be configured')
wow.Click(setup.countdown.minus)
eq(ns.db.readySeconds, 30, 'start countdown steps back to default')
ns.db.readyCheck = false; setup.Refresh()
eq(setup.countdown.plus.enabled, false, 'disabled countdown cannot imply a delay')
wow.Click(setup.countdown.plus)
eq(ns.db.readySeconds, 30, 'disabled countdown ignores changes')
ns.db.readyCheck = true; setup.Refresh()
local registered = false
for _, name in ipairs(UISpecialFrames) do if name == 'LoreforgeHostTable' then registered = true end end
assert(registered, 'Escape closes the main window')
wow.Click(setup.presets[3])
eq(ns.db.rounds, 5, 'Marathon sets rounds'); eq(ns.db.perRound, 10, 'Marathon sets questions')
assert(f.tags:GetText():find('50 questions', 1, true), 'summary shows the question count')
assert(f.tags:GetText():find('about %d+ minutes'), 'summary estimates the length')
wow.Click(setup.presets[1])
eq(ns.db.rounds, 1, 'Quick sets one round')
eq(setup.start:GetText(), 'Start game', 'a group without Party lobby support starts directly')
eq(setup.practice:IsShown(), true, 'practice is offered beside the start')

-- Category counts, None and the blocking banner.
local lore = setup.categoryRows.lore
assert(tonumber(lore.count:GetText()) > 0, 'categories show their question counts')
local none
for _, frame in ipairs(wow.frames) do if rawget(frame, 'text') == 'None' then none = frame end end
wow.Click(none)
eq(setup.start.enabled, false, 'no categories blocks the start')
assert(setup.banner:IsShown() and setup.banner.text:GetText():find('Pick more categories', 1, true), 'the banner says why')
ns.db.categories.lore = true; setup.Refresh()

-- Steppers clamp to the setup range.
ns.db.seconds = 60; setup.Refresh()
local secondsRow
for _, frame in ipairs(wow.frames) do if rawget(frame, 'value') and frame.plus and frame.value.text == '60s' then secondsRow = frame end end
assert(secondsRow, 'answer time shows seconds')
eq(secondsRow.plus.enabled, false, 'the top of the range disables plus')
wow.Click(secondsRow.minus)
eq(ns.db.seconds, 55, 'minus steps answer time by five')

-- Practice runs locally while grouped, for the host only.
ns.StartGame(true)
eq(ns.game.config.localOnly, true, 'practice never posts to chat')
local count = 0
for _ in pairs(ns.game.players) do count = count + 1 end
eq(count, 1, 'practice is for the host alone')
eq(ns.db.activeGame, nil, 'practice is not tracked as interruptible')
ns.game:Stop(); ns.RefreshHost()

-- Output change while a lobby is open asks first.
local closed = false
ns.Party.host = { started = false, joined = {}, expires = now + 30 }
ns.Party.CloseLobby = function() closed = true; ns.Party.host = nil end
setup.Refresh()
eq(setup.lobbyPanel:IsShown(), true, 'an open lobby replaces the categories')
assert(setup.lobbyPanel.timer:GetText():find('Closes in 0:30', 1, true), 'the lobby shows its timer')
setup.SetOutput('GUILD')
eq(wow.popups[#wow.popups], 'LOREFORGE_CLOSE_LOBBY', 'switching output with a lobby open asks first')
eq(ns.db.channel, 'PARTY', 'nothing changes until confirmed')
StaticPopupDialogs.LOREFORGE_CLOSE_LOBBY.OnAccept()
eq(closed, true, 'confirming closes the lobby'); eq(ns.db.channel, 'GUILD', 'and switches output')
setup.SetOutput('PARTY')
ns.Party.host = nil; setup.Refresh()

-- ── Live host table ──
ns.db.readyCheck, ns.db.rounds, ns.db.perRound, ns.db.seconds = false, 1, 2, 20
ns.db.autoMode = false
ns.StartGame()
eq(ns.game.config.compactChoices, false, 'separate choices reach the game')
for _ = 1, 40 do if ns.game.phase == 'accepting' then break end; tick(ns, 0.5) end
eq(ns.game.phase, 'accepting', 'the question opens')
local questionLines = 0
for _, line in ipairs(sent) do if line.text:find('1) ', 1, true) then questionLines = questionLines + 1 end end
eq(questionLines, 1, 'choice one posts once')
for i = 1, 4 do
    local found = false
    for _, line in ipairs(sent) do
        if line.text:find('] ' .. i .. ') ', 1, true) then found = true end
    end
    assert(found, 'each choice gets its own chat message')
end
assert(ns.db.activeGame and ns.db.activeGame.done == 0, 'a live game is tracked for interruption')
assert(f.timer:IsShown(), 'the host sees a timer bar')
eq(f.answerButtons[2].badge:GetText(), 'Key F2', 'bound answer keys are shown')
eq(f.status:GetText(), 'Answers open', 'the phase is the heading')
assert(f.tags:GetText():find('Question 1 of 2', 1, true), 'progress uses the round numbering')
LoreforgeAnswer(ns.game.run[1].correct)
local host = ns.Person('player')
eq(ns.game.answers[host.key], ns.game.run[1].correct, 'the answer key binding answers for the host')
chat(ns, '1', 'Guest-Realm', 'party1-GUID')
assert(f.scoreTitle:GetText():find('2 of 3 answered', 1, true), 'the board counts answers')
now = now + 16; f.timer:SetTime(4, 20)
eq(f.timer.count.textColour[1], ns.HammerCore.Theme.Colour('danger')[1], 'the last seconds turn red')
for _ = 1, 80 do if ns.game.phase == 'between' then break end; tick(ns, 0.5) end
eq(ns.game.phase, 'between', 'results posted')
eq(ns.db.activeGame.done, 1, 'tracking follows each reveal')
eq(f.answerButtons[ns.game.run[1].correct].tint:IsShown(), true, 'the correct answer is tinted')
wow.Click(f.pacingAuto)
eq(ns.game.config.autoMode, true, 'the pacing switch changes mode')
wow.Click(f.pacingHost)
eq(ns.game.config.autoMode, false, 'and back')

-- A line that never echoes raises one banner with both choices.
local echo = C_ChatInfo.SendChatMessage
C_ChatInfo.SendChatMessage = function(text, channel) sent[#sent + 1] = { text = text, channel = channel } end
ns.hostFrame.next.scripts.OnClick()
for _ = 1, 40 do if ns.game.phase == 'paused' then break end; tick(ns, 0.5) end
eq(ns.game.phase, 'paused', 'a missing echo pauses')
assert(f.banner:IsShown() and f.banner.text:GetText():find('Did this line appear', 1, true), 'one banner asks the host')
assert(f.recover:IsShown() and f.retry:IsShown(), 'both answers are on the banner')
wow.Click(f.retry)
eq(ns.game.pending, nil, 'Post again prepares the line again')
assert(f.send:IsShown() and f.send:GetAttribute('macrotext'), 'the line is ready to post by hand')
C_ChatInfo.SendChatMessage = echo
ns.game:Stop(); ns.RefreshHost()

-- ── Interrupted game ──
local saved = LoreforgeDB
saved.activeGame = { era = 'retail', serial = 9, channel = 'PARTY', done = 4, total = 15, rows = { { name = 'Guest', total = 3 } } }
ns = load(saved)
ns.OpenHost()
f = ns.hostFrame
assert(f.setup.banner:IsShown() and f.setup.banner.text:GetText():find('after question 4 of 15', 1, true), 'setup reports the interrupted game')
wow.Click(f.setup.banner.first)
assert(sent[1] and sent[1].text:find('Game interrupted after question 4 of 15. Standings: Guest 3.', 1, true), 'standings are posted once')
eq(ns.db.activeGame, nil, 'posting clears the notice')
eq(f.setup.banner:IsShown(), false, 'the banner goes')

-- ── History and Hall of Fame ──
ns.db.readyCheck, ns.db.rounds, ns.db.perRound, ns.db.seconds = false, 1, 1, 5
ns.db.autoMode, ns.db.replayRecords = true, true
ns.StartGame()
for _ = 1, 200 do
    if ns.game.phase == 'finished' then break end
    if ns.game.phase == 'accepting' and not ns.game.answers['guest-realm'] then chat(ns, tostring(ns.game.run[1].correct), 'Guest-Realm', 'party1-GUID') end
    tick(ns, 0.5)
end
eq(ns.game.phase, 'finished', 'a short game finishes')
ns.RefreshHost()
assert(f.finale:IsShown() and f.finale:GetText() == 'Game complete', 'the host sees a large Game complete')
eq(f.status:GetText(), '', 'the small header does not repeat it')
eq(f.winnerLine:GetText(), 'Guest-Realm wins with 1 point.', 'the winner line')
for i, row in ipairs(f.answerButtons) do assert(not row:IsShown(), 'answer ' .. i .. ' is gone') end
assert(not f.question:IsShown(), 'the last question is gone')
if ns.game.config.hostParticipates then
    eq(f.finalYou:GetText(), "You didn't answer any questions in this game.", 'a host who sat out is told so')
else
    assert(not f.finalYou:IsShown(), 'a host who did not play has no result line')
end
assert(f.podium[1]:IsShown() and f.podium[1].name:GetText() == 'Guest-Realm' and not f.podium[2]:IsShown(), 'the podium lists players who answered')
assert(f.scoreTitle:GetText():find('Final standings', 1, true), 'the board is the final standings')
eq(#ns.db.games.retail, 1, 'finished games are kept')
eq(ns.db.games.retail[1].rows[1].name, 'Guest-Realm', 'with their standings')
ns.Party.SavedResults = function()
    return { { id = 'p1', host = 'Other-Realm', date = 1700000000, config = { rounds = 1, perRound = 3 },
        rows = { { key = 'host-realm', name = 'Host-Realm', total = 2, rank = 1 } } } }
end
ns.OpenHost('history')
assert(f.history:IsShown() and not f.setup:IsShown(), 'History replaces Play')
eq(#ns.HistoryEntries(), 2, 'hosted and Party games share one list')
assert(f.history.entries[1].sub:GetText():find('Winner: Guest-Realm', 1, true), 'the newest game first')
wow.Click(f.history.entries[2])
assert(f.history.detail.rows[1].name:GetText():find('(you)', 1, true), 'the detail marks you')
ns.db.records.retail['zed-realm'] = { name = 'Zed-Realm', games = 5, wins = 4, correct = 9, answered = 10, bestStreak = 3 }
ns.OpenHost('records')
assert(f.records:IsShown(), 'Hall of Fame tab')
eq(f.records.rows[1].cells[1]:GetText(), '1.  Zed-Realm', 'most wins first')
eq(f.records.rows[1].cells[5]:GetText(), '90%', 'accuracy is shown')

-- ── Player window ──
local P = ns.Player
local config = { rounds = 2, perRound = 3, seconds = 20, difficulty = 'mixed', categories = 'Lore', readyCheck = false }
local rows = { { key = 'host-realm', name = 'Host-Realm', total = 3, round = 1, streak = 0, rank = 1 },
    { key = 'guest-realm', name = 'Guest-Realm', total = 1, round = 0, streak = 0, rank = 2 } }
local function model(state, extra)
    local m = { id = 'pg', state = state, host = 'Guest-Realm', config = config, joined = true, me = 'host-realm', rows = rows,
        index = 5, round = 2, attempt = 1, totalQuestions = 6, question = 'Q?', choices = { 'a', 'b', 'c', 'd' } }
    for k, v in pairs(extra or {}) do m[k] = v end
    return m
end
sounds = {}
P.Render(model('invitation', { id = 'inv', joined = false }))
eq(P.frame.secondary:GetText(), 'Decline', 'invitations say Decline')
eq(sounds[#sounds], 880, 'an invitation plays a sound')
P.Render(model('accepting', { deadline = now + 20 }))
eq(P.frame.position:GetText(), 'Round 2 of 2 · Question 2 of 3', 'the player uses the host numbering')
eq(sounds[#sounds], 875, 'a new question plays a sound')
eq(P.frame.answers[2].badge:GetText(), 'Key F2', 'the player sees answer keys')
P.Render(model('between', { correct = 1, nextIn = 5000, nextAt = now + 5 }))
eq(P.frame.status:GetText(), 'Next question in 5s.', 'auto-advance counts down')
P.Render(model('between', { correct = 1, hostPaced = true }))
eq(P.frame.status:GetText(), 'The host will start the next question.', 'host pacing is explained')
P.Render(model('finished', { correct = 1, id = 'pg-final' }))
eq(P.frame.headline:GetText(), 'Game complete', 'the finish has a large headline')
eq(P.frame.winner:GetText(), 'Host-Realm wins with 3 points.', 'the winner is named under it')
eq(P.frame.you:GetText(), 'You won with 3 points', 'and the local result')
assert(not P.frame.question:IsShown() and not P.frame.answers[1]:IsShown() and not P.frame.reveal:IsShown(),
    'the last question, choices and reveal are gone')
eq(sounds[#sounds], 888, 'a win plays the fanfare')
io.write('loreforge UX tests passed\n')
