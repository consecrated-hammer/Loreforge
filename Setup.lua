local _, ns = ...
local HC, UI = ns.HammerCore, ns.HammerCore.UI
local T = HC.Theme

-- Game setup lives in the Play tab, separate from general addon settings.
-- Presets cover most games; Advanced options stay folded away.

local PRESETS = {
    { name = 'Quick', hint = '1 round of 5 questions, 20 seconds each.', rounds = 1, perRound = 5, seconds = 20 },
    { name = 'Standard', hint = '3 rounds of 5 questions, 20 seconds each.', rounds = 3, perRound = 5, seconds = 20 },
    { name = 'Marathon', hint = '5 rounds of 10 questions, 25 seconds each.', rounds = 5, perRound = 10, seconds = 25 },
}
local LOBBY_ROWS = 5

local function plural(n, word) return n .. ' ' .. word .. (n == 1 and '' or 's') end

-- Rough length in minutes: each question is the answer time plus posting and
-- results (about 8 seconds) plus the gap; host-paced games assume a short
-- chat break.
function ns.EstimateMinutes(db)
    local questions = db.rounds * db.perRound
    local per = db.seconds + 8 + (db.autoMode and db.questionGap or 8)
    local total = questions * per + (db.readyCheck and (db.readySeconds + 4) or 0) + 10 + db.rounds * 4
    return math.max(1, math.floor(total / 60 + 0.5))
end

-- A labelled minus/value/plus control. The mouse wheel steps it too.
local function stepper(panel, labelText, hint, y, key, format, width)
    local limits = ns.LIMITS[key]
    local row = UI.Row(panel, y, 28, labelText, hint, width)
    local minus = UI.Button(row, 28, 24)
    minus:SetPoint('LEFT', row, 'LEFT', 190, 0); minus:SetText('-')
    local value = UI.FontString(row, 'GameFontHighlight', 'text')
    value:SetPoint('LEFT', minus, 'RIGHT', 0, 0); value:SetWidth(90); value:SetJustifyH('CENTER')
    local plus = UI.Button(row, 28, 24)
    plus:SetPoint('LEFT', value, 'RIGHT', 0, 0); plus:SetText('+')
    local function render()
        local v = ns.db[key]
        value:SetText(format and format(v) or tostring(v))
        local enabled = key ~= "readySeconds" or ns.db.readyCheck
        minus:SetEnabled(enabled and v > limits[1]); plus:SetEnabled(enabled and v < limits[2])
        T.Text(value, enabled and "text" or "muted")
    end
    local function change(direction)
        if key == "readySeconds" and not ns.db.readyCheck then return end
        local step = limits[3]
        local v = math.floor((ns.db[key] + direction * step) / step + 0.5) * step
        v = math.max(limits[1], math.min(limits[2], v))
        if v ~= ns.db[key] then
            ns.db[key] = v
            if panel.hcRefreshAll then panel.hcRefreshAll() end
        end
    end
    minus:SetScript('OnClick', function() change(-1) end)
    plus:SetScript('OnClick', function() change(1) end)
    if row.EnableMouseWheel then row:EnableMouseWheel(true) end
    row:SetScript('OnMouseWheel', function(_, delta) change(delta > 0 and 1 or -1) end)
    UI.OnRefresh(panel, render)
    render()
    row.minus, row.plus, row.value = minus, plus, value
    return row, y - 32
end

local function seconds(v) return v .. 's' end

local function section(panel, title, y, width)
    local text = UI.FontString(panel, 'GameFontNormal', 'flavour')
    text:SetPoint('TOPLEFT', 16, y); text:SetText(title)
    local line = T.Fill(panel:CreateTexture(nil, 'ARTWORK'), 'edge')
    line:SetPoint('TOPLEFT', 16, y - 20); line:SetSize(width or 374, 1)
    return y - 30
end

local function lobbyOpen() return ns.Party and ns.Party.host and not ns.Party.host.started or false end

function ns.BuildSetup(host)
    local L = ns.HostLayout
    local setup = CreateFrame('Frame', nil, host)
    setup:SetAllPoints()

    -- Presets
    local presetLabel = UI.FontString(setup, 'GameFontHighlightSmall', 'muted')
    presetLabel:SetPoint('TOPLEFT', 18, -116); presetLabel:SetText('Quick start')
    setup.presets = {}
    for i, preset in ipairs(PRESETS) do
        local b = UI.Button(setup, 104, 26)
        b:SetPoint('TOPLEFT', 96 + (i - 1) * 110, -110); b:SetText(preset.name)
        b:SetScript('OnClick', function()
            ns.db.rounds, ns.db.perRound, ns.db.seconds = preset.rounds, preset.perRound, preset.seconds
            ns.setupError = nil
            setup.Refresh()
        end)
        UI.AttachHint(b, preset.name, preset.hint)
        setup.presets[i] = b
    end

    -- One banner for anything blocking the start, or an interrupted game.
    local banner = CreateFrame('Frame', nil, setup, 'BackdropTemplate')
    banner:SetSize(L.width - 36, 44); banner:SetPoint('TOPLEFT', 18, -146)
    T.Surface(banner, 'raised', 'danger')
    banner.text = UI.FontString(banner, 'GameFontHighlightSmall', 'text')
    banner.text:SetPoint('LEFT', 12, 0); banner.text:SetWidth(L.width - 36 - 330); banner.text:SetJustifyH('LEFT')
    banner.first = UI.Button(banner, 150, 26)
    banner.first:SetPoint('RIGHT', -168, 0)
    banner.second = UI.Button(banner, 150, 26)
    banner.second:SetPoint('RIGHT', -12, 0)
    setup.banner = banner

    -- The roster fix: the current group's channel, or a guild roster refresh.
    local roster = UI.Button(banner, 150, 26)
    roster:SetPoint('RIGHT', -12, 0); roster:SetText('Use current group')
    roster:SetScript('OnClick', function()
        ns.setupError = nil
        if ns.db.channel == 'GUILD' then
            if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() elseif GuildRoster then GuildRoster() end
            HC.Print('Guild roster requested. Check the player count before starting.')
        else ns.db.channel = ns.SuggestChannel() end
        setup.Refresh()
    end)
    setup.rosterButton = roster

    -- Left: game options in a scrolling column.
    local scroll, left, setHeight = ns.ScrollArea(setup, 0, -196, 430, 330)
    setup.scroll, setup.scrollbar, setup.left = scroll, scroll.bar, left
    local _, y
    y = section(left, 'Game', 0)
    _, y = UI.Dropdown(left, 'Output', 'Where questions are posted and players answer.', y,
        { 'PARTY', 'RAID', 'INSTANCE_CHAT', 'GUILD' }, { 'Party', 'Raid', 'Instance', 'Guild' },
        function() return ns.db.channel end, function(value) setup.SetOutput(value) end, 400, 190, 150)
    -- Switching away from Party would close an open lobby; ask first.
    function setup.SetOutput(value)
        if value ~= 'PARTY' and lobbyOpen() then
            StaticPopupDialogs.LOREFORGE_CLOSE_LOBBY = {
                text = 'Close the Party lobby and switch output? Players who joined will be told it closed.',
                button1 = 'Close lobby', button2 = 'Keep lobby', timeout = 0, whileDead = true, hideOnEscape = true,
                preferredIndex = 3,
                OnAccept = function()
                    if ns.Party then ns.Party.CloseLobby() end
                    ns.db.channel = value
                    setup.Refresh()
                end,
            }
            StaticPopup_Show('LOREFORGE_CLOSE_LOBBY')
            return
        end
        ns.db.channel = value
        setup.Refresh()
    end
    _, y = UI.Check(left, 'Host plays along', 'You answer and score like everyone else.', y,
        function() return ns.db.hostParticipates end, function(value) ns.db.hostParticipates = value end, 400)
    y = section(left, 'Length', y - 6)
    _, y = stepper(left, 'Rounds', nil, y, 'rounds', nil, 400)
    _, y = stepper(left, 'Questions per round', nil, y, 'perRound', nil, 400)
    _, y = stepper(left, 'Answer time', nil, y, 'seconds', seconds, 400)
    _, y = UI.Check(left, 'Countdown before starting', 'Players can join and type ready before the first question.', y,
        function() return ns.db.readyCheck end, function(value) ns.db.readyCheck = value end, 400)
    setup.countdown, y = stepper(left, 'Start countdown', 'Seconds before the first question. You can start sooner; disable the countdown above to skip it.', y, 'readySeconds', seconds, 400)
    _, y = UI.Dropdown(left, 'Difficulty', 'Hard includes obscure lore, talents and procs.', y,
        { 'mixed', 'easy', 'hard' }, { 'Mixed', 'Easier', 'Hard' },
        function() return ns.db.difficulty end, function(value) ns.db.difficulty = value end, 400, 190, 150)

    local toggle = UI.Button(left, 200, 24)
    toggle:SetPoint('TOPLEFT', 16, y - 8)
    local advancedTop = y - 44
    local advanced = CreateFrame('Frame', nil, left)
    advanced:SetPoint('TOPLEFT', 0, advancedTop); advanced:SetSize(430, 1)
    local a = 0
    a = section(advanced, 'Pacing', a)
    _, a = UI.Check(advanced, 'Auto-advance questions', 'The next question starts after a short gap. Off: you start each one.', a,
        function() return ns.db.autoMode end, function(value) ns.db.autoMode = value end, 400)
    _, a = stepper(advanced, 'Question gap', 'Seconds between questions with auto-advance.', a, 'questionGap', seconds, 400)
    _, a = stepper(advanced, 'Pause when quiet', 'Auto-advance pauses after this many questions with no answers.', a, 'idleLimit',
        function(v) return v == 0 and 'Off' or plural(v, 'question') end, 400)
    a = section(advanced, 'Chat', a - 6)
    _, a = UI.Check(advanced, 'Choices on one line', 'Posts the four choices on one line instead of four.', a,
        function() return ns.db.compactChoices end, function(value) ns.db.compactChoices = value end, 400)
    _, a = UI.Check(advanced, 'Announce top three records', 'After the final scores, post records for the top three players.', a,
        function() return ns.db.replayRecords end, function(value) ns.db.replayRecords = value end, 400)
    advanced:SetHeight(-a)
    setup.advanced = advanced
    local function layoutLeft()
        local open = ns.showAdvanced == true
        advanced:SetShown(open)
        toggle:SetText(open and 'Hide advanced options' or 'Advanced options')
        setHeight(open and (-advancedTop - a + 10) or (-advancedTop + 4), true)
    end
    toggle:SetScript('OnClick', function() ns.showAdvanced = not ns.showAdvanced; layoutLeft() end)
    setup.advancedToggle = toggle

    -- Right: categories, or the lobby while one is open.
    local right = CreateFrame('Frame', nil, setup)
    right:SetSize(L.rightWidth + 30, 330); right:SetPoint('TOPLEFT', L.rightX - 30, -196)
    local r = section(right, 'Categories', 0, L.rightWidth)
    local all = UI.Button(right, 50, 20); all:SetPoint('TOPLEFT', L.rightWidth - 92, 2); all:SetText('All')
    local none = UI.Button(right, 50, 20); none:SetPoint('TOPLEFT', L.rightWidth - 38, 2); none:SetText('None')
    local function setAll(value)
        for _, category in ipairs(ns.Game.CATEGORIES) do ns.db.categories[category[1]] = value end
        setup.Refresh()
    end
    all:SetScript('OnClick', function() setAll(true) end)
    none:SetScript('OnClick', function() setAll(false) end)
    setup.categoryRows = {}
    for _, category in ipairs(ns.Game.CATEGORIES) do
        local key = category[1]
        local row
        row, r = UI.Check(right, category[2], nil, r,
            function() return ns.db.categories[key] == true end,
            function(value) ns.db.categories[key] = value end, L.rightWidth)
        row.count = UI.FontString(row, 'GameFontHighlightSmall', 'muted')
        row.count:SetPoint('RIGHT', row, 'RIGHT', 0, 0)
        setup.categoryRows[key] = row
    end
    setup.right = right

    local lobby = CreateFrame('Frame', nil, setup)
    lobby:SetSize(L.rightWidth + 30, 330); lobby:SetPoint('TOPLEFT', L.rightX - 30, -196)
    local ly = section(lobby, 'Party lobby', 0, L.rightWidth)
    lobby.timer = UI.FontString(lobby, 'GameFontHighlightSmall', 'muted')
    lobby.timer:SetPoint('TOPRIGHT', lobby, 'TOPLEFT', 16 + L.rightWidth, 0)
    lobby.rows = {}
    for i = 1, LOBBY_ROWS do
        local row = CreateFrame('Frame', nil, lobby)
        row:SetSize(L.rightWidth, 22); row:SetPoint('TOPLEFT', 16, ly - (i - 1) * 24)
        row.dot = row:CreateTexture(nil, 'ARTWORK'); row.dot:SetSize(6, 6); row.dot:SetPoint('LEFT', 0, 0)
        row.name = UI.FontString(row, 'GameFontHighlight', 'text'); row.name:SetPoint('LEFT', 12, 0)
        row.name:SetWidth(L.rightWidth - 110); row.name:SetJustifyH('LEFT')
        row.state = UI.FontString(row, 'GameFontHighlightSmall', 'muted'); row.state:SetPoint('RIGHT', 0, 0)
        lobby.rows[i] = row
    end
    lobby.note = UI.FontString(lobby, 'GameFontHighlightSmall', 'muted')
    lobby.note:SetPoint('TOPLEFT', 16, ly - LOBBY_ROWS * 24 - 8); lobby.note:SetWidth(L.rightWidth); lobby.note:SetJustifyH('LEFT')
    lobby.note:SetText('Players without Loreforge can still answer in Party chat.')
    lobby.keep = UI.Button(lobby, 150, 26)
    lobby.keep:SetPoint('TOPLEFT', 16, ly - LOBBY_ROWS * 24 - 52); lobby.keep:SetText('Keep lobby open')
    lobby.keep:SetScript('OnClick', function() if ns.Party then ns.Party.KeepLobbyOpen() end; setup.Refresh() end)
    UI.AttachHint(lobby.keep, 'Keep lobby open', 'Resets the lobby timer to 10 minutes.')
    setup.lobbyPanel = lobby

    setup.pool = UI.FontString(setup, 'GameFontHighlightSmall', 'muted')
    setup.pool:SetPoint('BOTTOMLEFT', 18, 62); setup.pool:SetWidth(L.width - 36); setup.pool:SetJustifyH('LEFT')

    -- Footer: one primary action, with lobby actions beside it when a lobby is open.
    setup.start = UI.Button(setup, 200, 34, 'primary')
    setup.start:SetPoint('BOTTOMLEFT', 18, 18); setup.start:SetText('Start game')
    UI.AttachHint(setup.start, function() return setup.start:GetText() end,
        function() return setup.issue or setup.startHint or 'Ready to go.' end)
    setup.start:SetScript('OnClick', function()
        if setup.solo then ns.StartGame()
        elseif ns.Party and ns.db.channel == 'PARTY' and ns.Party.Available() and not lobbyOpen() then ns.Party.OpenLobby()
        else ns.StartGame() end
    end)
    setup.practice = UI.Button(setup, 150, 34)
    setup.practice:SetPoint('BOTTOMLEFT', 228, 18); setup.practice:SetText('Practice solo')
    setup.practice:SetScript('OnClick', function() ns.StartGame(true) end)
    UI.AttachHint(setup.practice, 'Practice solo', 'A game just for you. Nothing is posted to chat.')
    setup.lobby = UI.Button(setup, 170, 34)
    setup.lobby:SetPoint('BOTTOMLEFT', 228, 18); setup.lobby:SetText('Invite new arrivals')
    setup.lobby:SetScript('OnClick', function() if ns.Party then ns.Party.OpenLobby() end end)
    UI.AttachHint(setup.lobby, 'Invite new arrivals', 'Sends the invitation again to anyone who joined the group since.')
    setup.closeLobby = UI.Button(setup, 130, 34)
    setup.closeLobby:SetPoint('BOTTOMLEFT', 408, 18); setup.closeLobby:SetText('Close lobby')
    setup.closeLobby:SetScript('OnClick', function() if ns.Party then ns.Party.CloseLobby() end end)

    local function categoryCounts()
        local counts, probe = {}, { difficulty = ns.db.difficulty, categories = {} }
        for _, category in ipairs(ns.Game.CATEGORIES) do
            probe.categories = { [category[1]] = true }
            counts[category[1]] = #ns.Game.Pool(HC.QUIZ, probe, ns.era)
        end
        return counts
    end

    local function drawLobby()
        local h = ns.Party.host
        local remaining = math.max(0, math.ceil((h.expires or 0) - GetTime()))
        lobby.timer:SetText('Closes in ' .. math.floor(remaining / 60) .. ':' .. string.format('%02d', remaining % 60))
        T.Text(lobby.timer, remaining <= 60 and 'danger' or 'muted')
        local members = ns.Roster('PARTY')
        for i, row in ipairs(lobby.rows) do
            local p = members[i]
            row:SetShown(p ~= nil)
            if p then
                local joined = h.joined[p.key] ~= nil
                row.name:SetText(p.name)
                row.state:SetText(joined and 'Joined' or 'Chat only so far')
                T.Text(row.state, joined and 'accent' or 'muted')
                T.Fill(row.dot, joined and 'accent' or 'rail')
            end
        end
    end

    local function refresh(panel)
        if InCombatLockdown() then return end
        for _, run in ipairs(panel.hcRefresh or {}) do run() end
    end
    local function refreshAll()
        if InCombatLockdown() then return end
        refresh(left); refresh(advanced); refresh(right)
        local available = #ns.Game.Pool(HC.QUIZ, ns.db, ns.era)
        local restricted = ns.Restricted()
        local rosterRows, err, localOnly = {}, nil, false
        if not restricted then rosterRows, err, localOnly = ns.Roster(ns.db.channel, ns.db.hostParticipates) end
        local needed = ns.db.rounds * ns.db.perRound
        local poolIssue = available < needed and ('Only ' .. available .. ' questions match. Pick more categories or a shorter game.') or nil
        local issue = (restricted and 'Chat is restricted. Wait until it ends.') or err or poolIssue
        if not issue then ns.setupError = nil end
        setup.issue, setup.solo = issue, localOnly == true
        local isOpen = lobbyOpen()
        local party = ns.Party and ns.db.channel == 'PARTY' and ns.Party.Available() or false

        host.status:SetText(isOpen and 'Lobby open' or 'Set up a game')
        host.tags:SetText(plural(needed, 'question') .. '  ·  about ' .. plural(ns.EstimateMinutes(ns.db), 'minute')
            .. '  ·  ' .. (localOnly and 'Practice, no group' or plural(math.max(0, #rosterRows - (ns.db.hostParticipates and 1 or 0)), 'other player')
                .. ' in ' .. ns.Game.CHANNELS[ns.db.channel].label))
        setup.pool:SetText(available .. ' questions available for these categories and difficulty.')

        for i, preset in ipairs(PRESETS) do
            local on = ns.db.rounds == preset.rounds and ns.db.perRound == preset.perRound and ns.db.seconds == preset.seconds
            T.Border(setup.presets[i], on and 'selected' or 'edge')
            T.Text(setup.presets[i].Text, on and 'selected' or 'text')
        end
        local counts = categoryCounts()
        for key, row in pairs(setup.categoryRows) do row.count:SetText(tostring(counts[key] or 0)) end

        -- Banner: a blocking issue first, else an interrupted game.
        local fixable = err and not restricted
        local interrupted = not issue and ns.interrupted
        banner:SetShown(issue ~= nil or interrupted ~= nil)
        roster:SetShown(fixable and true or false)
        roster:SetText(ns.db.channel == 'GUILD' and 'Refresh guild roster' or 'Use current group')
        banner.first:Hide(); banner.second:Hide()
        if issue then
            banner.text:SetText(issue); T.Border(banner, 'danger')
        elseif interrupted then
            local a = interrupted
            local done = tonumber(a.done) or 0
            banner.text:SetText(done > 0 and ('Your last game was interrupted after question ' .. done .. ' of ' .. tostring(a.total) .. '.')
                or 'Your last game was interrupted before the first question.')
            T.Border(banner, 'accent')
            if (tonumber(a.done) or 0) > 0 then
                banner.first:SetText('Post standings'); banner.first:SetScript('OnClick', ns.PostInterrupted); banner.first:Show()
            end
            banner.second:SetText('Dismiss'); banner.second:SetScript('OnClick', ns.DismissInterrupted); banner.second:Show()
        end
        local top = banner:IsShown() and -196 or -150
        scroll:ClearAllPoints(); scroll:SetPoint('TOPLEFT', 0, top)
        local height = L.height - 86 + top
        scroll:SetHeight(height); scroll.bar:SetHeight(height)
        right:ClearAllPoints(); right:SetPoint('TOPLEFT', L.rightX - 30, top)
        lobby:ClearAllPoints(); lobby:SetPoint('TOPLEFT', L.rightX - 30, top)
        layoutLeft()

        right:SetShown(not isOpen)
        lobby:SetShown(isOpen)
        if isOpen then drawLobby() end

        if setup.solo then
            setup.start:SetText('Practice solo')
            setup.startHint = 'You are not in a group, so this is a practice game. Nothing is posted to chat.'
        elseif party and not isOpen then
            setup.start:SetText('Open lobby')
            setup.startHint = 'Invites Party members with Loreforge. Everyone else answers in chat.'
        else
            setup.start:SetText('Start game')
            setup.startHint = isOpen and 'Starts with everyone who joined. Others answer in chat.' or nil
        end
        setup.start:SetEnabled(not issue)
        setup.practice:SetShown(not setup.solo and not isOpen)
        setup.practice:SetEnabled(not restricted and not poolIssue)
        setup.lobby:SetShown(isOpen)
        setup.closeLobby:SetShown(isOpen)
    end
    left.hcRefreshAll = function() ns.setupError = nil; refreshAll() end
    advanced.hcRefreshAll = left.hcRefreshAll
    right.hcRefreshAll = left.hcRefreshAll
    setup.Refresh = refreshAll
    setup:SetScript('OnHide', function()
        for _, panel in ipairs({ left, advanced, right }) do
            for _, child in ipairs({ panel:GetChildren() }) do
                if child.hcCloseMenu then child.hcCloseMenu() end
            end
        end
    end)
    layoutLeft()
    refreshAll()
    return setup
end
