local _, ns = ...
local HC, UI = ns.HammerCore, ns.HammerCore.UI
local T = HC.Theme

-- Game setup lives in Host game, separate from general addon settings.
function ns.BuildSetup(host)
    local setup = CreateFrame('Frame', nil, host)
    setup:SetAllPoints()
    local scroll = CreateFrame('ScrollFrame', nil, setup)
    scroll:SetPoint('TOPLEFT', 0, -98); scroll:SetSize(410, 378)
    local left, right = CreateFrame('Frame', nil, scroll), CreateFrame('Frame', nil, setup)
    left:SetSize(410, 1); scroll:SetScrollChild(left)
    local bar = CreateFrame('Slider', nil, setup)
    bar:SetPoint('TOPLEFT', 416, -98); bar:SetSize(6, 378); bar:SetOrientation('VERTICAL')
    T.Fill(bar:CreateTexture(nil, 'BACKGROUND'), 'rail'):SetAllPoints()
    local thumb = T.Fill(bar:CreateTexture(nil, 'ARTWORK'), 'selected')
    thumb:SetSize(6, 28); bar:SetThumbTexture(thumb)
    bar:SetScript('OnValueChanged', function(_, value)
        if not InCombatLockdown() then scroll:SetVerticalScroll(value) end
    end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript('OnMouseWheel', function(_, delta)
        if InCombatLockdown() then return end
        bar:SetValue(math.max(0, math.min(setup.scrollRange, (bar:GetValue() or 0) - delta * 38)))
    end)
    local sectionOffsets = {}
    local function section(panel, title, y)
        if panel == left then sectionOffsets[title] = -y end
        local text = UI.FontString(panel, 'GameFontNormal', 'accent')
        text:SetPoint('TOPLEFT', 16, y); text:SetText(title)
        local line = T.Fill(panel:CreateTexture(nil, 'ARTWORK'), 'edge')
        line:SetPoint('TOPLEFT', 16, y - 22); line:SetSize(panel == left and 374 or 274, 1)
        return y - 34
    end
    right:SetSize(310, 400); right:SetPoint('TOPLEFT', 430, -84)
    local count = UI.FontString(setup, 'GameFontHighlightSmall', 'muted')
    count:SetPoint('TOPLEFT', 18, -492); count:SetWidth(720); count:SetJustifyH('LEFT')
    count:SetHeight(36); count:SetWordWrap(true)
    local function refresh(panel)
        if InCombatLockdown() then return end
        for _, run in ipairs(panel.hcRefresh or {}) do run() end
        local available = #ns.Game.Pool(HC.QUIZ, ns.db, ns.era)
        local restricted = ns.Restricted()
        local roster, err, localOnly = {}, nil, false
        if not restricted then roster, err, localOnly = ns.Roster(ns.db.channel, ns.db.hostParticipates) end
        local issue = (restricted and 'Chat is restricted. Wait until the restriction ends.') or err
        if not issue and available < ns.db.rounds * ns.db.perRound then issue = 'Select more categories or reduce the game length.' end
        if not issue then ns.setupError = nil end
        host.status:SetText(issue and 'Game setup needs attention. See the message below.' or 'Choose a section, check your players, then Start game.')
        count:SetText(available .. ' questions | ' .. ns.db.rounds * ns.db.perRound .. ' needed | '
            .. #roster .. ' eligible players' .. (localOnly and ' | Local test: no broadcasting' or '')
            .. (issue and ('\n' .. issue) or ''))
        T.Text(count, issue and 'danger' or 'muted')
        setup.start:SetEnabled(not issue)
        if setup.lobby then
            local party = ns.Party and ns.db.channel == 'PARTY' and ns.Party.Available()
            setup.lobby:SetShown(party == true)
            setup.start:SetText(party and (not ns.Party.host or ns.Party.host.started) and 'Open Party lobby' or 'Start game')
            if setup.closeLobby then setup.closeLobby:SetShown(party and ns.Party.host and not ns.Party.host.started or false) end
            setup.lobby:SetText(ns.Party and ns.Party.host and 'Invite new arrivals' or 'Open Party lobby')
            if party and ns.Party.host then
                local joined = 0; for _ in pairs(ns.Party.host.joined) do joined = joined + 1 end
                count:SetText(count:GetText() .. ' | ' .. joined .. ' joined in addon')
            end
        end
        if setup.rosterButton then setup.rosterButton:SetText(ns.db.channel == 'GUILD' and 'Refresh guild roster' or 'Use current group') end
    end
    left.hcRefreshAll = function() ns.setupError = nil; refresh(left) end
    right.hcRefreshAll = function() ns.setupError = nil; refresh(right) end
    local _, y
    y = section(left, 'Game', 0)
    _, y = UI.Dropdown(left, 'Output', 'Players answer in the selected channel. Use Instance for a queued group.', y,
        { 'PARTY', 'RAID', 'INSTANCE_CHAT', 'GUILD' }, { 'Party', 'Raid', 'Instance', 'Guild' },
        function() return ns.db.channel end, function(value) ns.db.channel = value end, 390, 150, 170)
    _, y = UI.Check(left, 'Game Master participates', 'Include the host in scores and records. Without a group, preview the game locally.', y,
        function() return ns.db.hostParticipates end, function(value) ns.db.hostParticipates = value end, 390)
    y = section(left, 'Questions', y)
    _, y = UI.Dropdown(left, 'Difficulty', 'Hard includes obscure lore, talents and procs.', y,
        { 'mixed', 'easy', 'hard' }, { 'Mixed', 'Easier', 'Hard / obscure' },
        function() return ns.db.difficulty end, function(value) ns.db.difficulty = value end, 390, 150, 170)
    for _, spec in ipairs({ { 'rounds', 'Rounds', 1, 20 }, { 'perRound', 'Questions per round', 1, 50 },
        { 'seconds', 'Answer time', 5, 120 } }) do
        local key = spec[1]
        _, y = UI.Slider(left, spec[2], 'Applies to the next game.', y, spec[3], spec[4], 1,
            function() return ns.db[key] end, function(value) ns.db[key] = value end, nil, 390)
    end
    y = section(left, 'Pacing', y)
    _, y = UI.Check(left, 'Auto-advance questions', 'Both modes send announcements automatically. When off, the host clicks Ask next question between questions.', y,
        function() return ns.db.autoMode end, function(value) ns.db.autoMode = value end, 390)
    _, y = UI.Slider(left, 'Question gap', 'Seconds after results finish, in automatic mode.', y, 3, 30, 1,
        function() return ns.db.questionGap end, function(value) ns.db.questionGap = value end, nil, 390)
    _, y = UI.Slider(left, 'Inactivity limit', 'Automatic play pauses after this many questions without replies. Zero disables it.', y, 0, 10, 1,
        function() return ns.db.idleLimit end, function(value) ns.db.idleLimit = value end, nil, 390)
    y = section(left, 'Ready check', y)
    _, y = UI.Check(left, 'Ready check before starting', 'Announce the quiz, accept optional ready replies and count down before the first question.', y,
        function() return ns.db.readyCheck end, function(value) ns.db.readyCheck = value end, 390)
    _, y = UI.Slider(left, 'Countdown', 'Seconds after the ready announcement is confirmed. The host can start sooner.', y, 5, 60, 1,
        function() return ns.db.readySeconds end, function(value) ns.db.readySeconds = value end, nil, 390)
    y = section(left, 'Results', y)
    _, y = UI.Check(left, 'Announce closing player records', 'Include player records after the final scores.', y,
        function() return ns.db.replayRecords end, function(value) ns.db.replayRecords = value end, 390)
    left:SetHeight(-y + 10)
    setup.scrollRange = math.max(0, -y + 10 - 378)
    bar:SetMinMaxValues(0, setup.scrollRange); bar:SetValue(0)
    for i, spec in ipairs({ {'Game', 'Game'}, {'Questions', 'Questions'}, {'Pacing', 'Pacing'}, {'Ready', 'Ready check'}, {'Results', 'Results'} }) do
        local target = spec[2]
        local jump = UI.Button(setup, 76, 20)
        jump:SetPoint('TOPLEFT', 16 + (i - 1) * 80, -70); jump:SetText(spec[1])
        jump:SetScript('OnClick', function()
            if not InCombatLockdown() then bar:SetValue(math.min(setup.scrollRange, sectionOffsets[target])) end
        end)
    end
    y = section(right, 'Question categories', 0)
    for _, category in ipairs(ns.Game.CATEGORIES) do
        local key, label = category[1], category[2]
        _, y = UI.Check(right, label, 'Combine categories. Multi-tag questions still appear once per game.', y,
            function() return ns.db.categories[key] == true end,
            function(value) ns.db.categories[key] = value end, 290)
    end
    setup.start = UI.Button(setup, 180, 30, 'primary')
    setup.start:SetPoint('BOTTOMLEFT', 18, 18); setup.start:SetText('Start game')
    setup.start:SetScript('OnClick', function()
        if ns.Party and ns.db.channel == 'PARTY' and ns.Party.Available() and (not ns.Party.host or ns.Party.host.started) then
            ns.Party.OpenLobby()
        else ns.StartGame() end
    end)
    local roster = UI.Button(setup, 180, 30)
    roster:SetPoint('BOTTOMLEFT', 214, 18); roster:SetText('Refresh guild roster')
    roster:SetScript('OnClick', function()
        ns.setupError = nil
        if ns.db.channel == 'GUILD' then
            if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() elseif GuildRoster then GuildRoster() end
            HC.Print('Guild roster requested. Check the eligible-player count before starting.')
        else ns.db.channel = ns.SuggestChannel() end
        setup.Refresh()
    end)
    setup.rosterButton = roster
    local lobby = UI.Button(setup, 180, 30)
    lobby:SetPoint('BOTTOMLEFT', 410, 18); lobby:SetText('Open Party lobby')
    lobby:SetScript('OnClick', function() if ns.Party then ns.Party.OpenLobby() end end)
    setup.lobby = lobby
    local closeLobby=UI.Button(setup,132,30)
    closeLobby:SetPoint('BOTTOMLEFT',606,18);closeLobby:SetText('Close lobby')
    closeLobby:SetScript('OnClick',function() if ns.Party then ns.Party.CloseLobby() end end)
    setup.closeLobby=closeLobby
    setup.Refresh = function() refresh(left); refresh(right) end
    setup:SetScript('OnHide', function()
        for _, panel in ipairs({ left, right }) do
            for _, child in ipairs({ panel:GetChildren() }) do
                if child.hcCloseMenu then child.hcCloseMenu() end
            end
        end
    end)
    setup.left, setup.right, setup.pool = left, right, count
    setup.scroll, setup.scrollbar = scroll, bar
    setup.Refresh()
    return setup
end
