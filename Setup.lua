local _, ns = ...
local HC, UI = ns.HammerCore, ns.HammerCore.UI
local T = HC.Theme

-- Game setup lives in the Play tab, separate from general addon settings.
-- Presets cover most games; the rest sits on sub-tabs across the top (Game,
-- Categories, Pacing & chat), each using the full window width.

local PRESETS = {
    { name = 'Quick', hint = '5 questions, 20 seconds each.', rounds = 1, perRound = 5, seconds = 20 },
    { name = 'Standard', hint = '15 questions, 20 seconds each.', rounds = 1, perRound = 15, seconds = 20 },
    { name = 'Marathon', hint = '50 questions, 25 seconds each.', rounds = 1, perRound = 50, seconds = 25 },
}
local LOBBY_ROWS = 5
-- Keep category choices reachable while the Party lobby is open.
-- Only the ordinary setup tabs are remembered.
local SUBTABS = { { 'game', 'Game' }, { 'categories', 'Categories' }, { 'lobby', 'Party lobby' }, { 'pacing', 'Pacing & chat' } }
local SAVED_TABS = { game = true, categories = true, pacing = true }
local MARGIN, GAP, TAB_H = 18, 24, 40
-- Room kept for a category's question count, left of its switch.
local COUNT_W = 36

-- HammerCore 0.3 rows take the settings page's width; the setup columns
-- are narrower, so each row is sized back to the width it asks for.
local function fit(row, width)
    if not width then return row end
    row:SetWidth(width)
    row.hcWidth = width
    if row.hcStripe then row.hcStripe:SetWidth(width) end
    return row
end
local function Row(panel, y, height, title, hint, width)
    return fit(UI.Row(panel, y, height, title, hint, width), width)
end
local function Check(panel, label, hint, y, get, set, width)
    local row, nextY = UI.Check(panel, label, hint, y, get, set, width)
    return fit(row, width), nextY
end
local function Dropdown(panel, label, hint, y, values, labels, get, set, width, offset, buttonWidth)
    local row, nextY, button = UI.Dropdown(panel, label, hint, y, values, labels, get, set, width, offset, buttonWidth)
    return fit(row, width), nextY, button
end

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

local MAX_THEMED_ROUND = 15

-- A labelled minus/value/plus control. The mouse wheel steps it too.
local function stepper(panel, labelText, hint, y, key, format, width)
    local limits = ns.LIMITS[key]
    local row = Row(panel, y, 28, labelText, hint, width)
    -- Right-aligned, like the dropdowns and switches beside it.
    local plus = UI.Button(row, 28, 24)
    plus:SetPoint('RIGHT', row, 'RIGHT', -UI.CELL_INSET, 0); plus:SetText('+')
    local value = UI.FontString(row, 'GameFontHighlight', 'text')
    value:SetPoint('RIGHT', plus, 'LEFT', 0, 0); value:SetWidth(90); value:SetJustifyH('CENTER')
    local minus = UI.Button(row, 28, 24)
    minus:SetPoint('RIGHT', value, 'LEFT', 0, 0); minus:SetText('-')
    if row.Title then row.Title:SetPoint('RIGHT', minus, 'LEFT', -12, 0) end
    -- A themed round stays short enough for a category to fill it.
    local function upper()
        if key == 'perRound' and ns.db.rounds > 1 then return MAX_THEMED_ROUND end
        return limits[2]
    end
    local function render()
        local v = ns.db[key]
        value:SetText(format and format(v) or tostring(v))
        local enabled = (key ~= "readySeconds" or ns.db.readyCheck)
            and ((key ~= "questionGap" and key ~= "idleLimit") or ns.db.autoMode)
        minus:SetEnabled(enabled and v > limits[1]); plus:SetEnabled(enabled and v < upper())
        T.Text(value, enabled and "text" or "muted")
    end
    local function change(direction)
        if (key == "readySeconds" and not ns.db.readyCheck)
            or ((key == "questionGap" or key == "idleLimit") and not ns.db.autoMode) then return end
        local step = limits[3]
        local v = math.floor((ns.db[key] + direction * step) / step + 0.5) * step
        v = math.max(limits[1], math.min(upper(), v))
        if v ~= ns.db[key] then
            -- Keep the game a similar length when themed rounds go on or off.
            if key == 'rounds' and ns.db[key] == 1 then
                ns.db.perRound = math.min(MAX_THEMED_ROUND, math.max(1, math.floor(ns.db.perRound / v)))
            elseif key == 'rounds' and v == 1 then
                ns.db.perRound = math.min(ns.LIMITS.perRound[2], ns.db.rounds * ns.db.perRound)
            end
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
    return row, row.hcNextY or (y - 44)
end

local function seconds(v) return v .. 's' end

-- A section heading with a rule, lined up with the rows below it.
local function section(panel, title, y, width)
    local text = UI.FontString(panel, 'GameFontNormal', 'flavour')
    text:SetPoint('TOPLEFT', UI.PAD, y); text:SetText(title)
    local line = T.Fill(panel:CreateTexture(nil, 'ARTWORK'), 'edge')
    line:SetPoint('TOPLEFT', UI.PAD, y - 20); line:SetSize(width, 1)
    UI.RestartStripes(panel)
    return y - 30
end

local function lobbyOpen() return ns.Party and ns.Party.host and not ns.Party.host.started or false end

-- The remembered sub-tab, or Game.
local function savedTab()
    local tab = ns.db and ns.db.setupTab
    return SAVED_TABS[tab] and tab or 'game'
end

function ns.BuildSetup(host)
    local L = ns.HostLayout
    local fullWidth = L.width - MARGIN * 2
    local colWidth = math.floor((fullWidth - GAP) / 2)
    local setup = CreateFrame('Frame', nil, host)
    setup:SetAllPoints()
    local panels = {}

    -- Presets sit on the title line, right-aligned.
    setup.presets = {}
    for i, preset in ipairs(PRESETS) do
        local b = UI.Button(setup, 96, 26)
        b:SetPoint('TOPRIGHT', -(MARGIN + (#PRESETS - i) * 102), -58); b:SetText(preset.name)
        b:SetScript('OnClick', function()
            ns.db.rounds, ns.db.perRound, ns.db.seconds = preset.rounds, preset.perRound, preset.seconds
            ns.setupError = nil
            setup.Refresh()
        end)
        UI.AttachHint(b, preset.name, preset.hint .. ' Changes question count and answer time only. Categories, difficulty and pacing stay as chosen.')
        setup.presets[i] = b
    end
    local presetLabel = UI.FontString(setup, 'GameFontHighlightSmall', 'muted')
    presetLabel:SetPoint('RIGHT', setup.presets[1], 'LEFT', -10, 0); presetLabel:SetText('Quick start')

    -- One banner for anything blocking the start, or an interrupted game.
    local banner = CreateFrame('Frame', nil, setup, 'BackdropTemplate')
    banner:SetSize(fullWidth, 44); banner:SetPoint('TOPLEFT', MARGIN, -112)
    T.Surface(banner, 'raised', 'danger')
    banner.text = UI.FontString(banner, 'GameFontHighlightSmall', 'text')
    banner.text:SetPoint('LEFT', 12, 0); banner.text:SetWidth(fullWidth - 330); banner.text:SetJustifyH('LEFT')
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

    -- Sub-tabs across the top, in the main tabs' style, over a quiet rule.
    local bar = CreateFrame('Frame', nil, setup)
    bar:SetSize(fullWidth, TAB_H)
    local rule = T.Fill(bar:CreateTexture(nil, 'BORDER'), 'edge')
    rule:SetPoint('BOTTOMLEFT'); rule:SetPoint('BOTTOMRIGHT'); rule:SetHeight(1)
    setup.tabBar = bar
    -- The first tab's text lines up with the content's left edge.
    local strip = ns.TabStrip(bar, TAB_H, function(first) first:SetPoint('BOTTOMLEFT', bar, 'BOTTOMLEFT', -15, 0) end)
    for _, spec in ipairs(SUBTABS) do
        local key = spec[1]
        strip.Add(key, spec[2], function() setup.SelectTab(key) end)
    end
    setup.tabStrip, setup.subtabs = strip, strip.buttons

    setup.pages, setup.columns = {}, {}
    local function page(key)
        local frame = CreateFrame('Frame', nil, setup)
        frame:SetSize(L.width, 1)
        setup.pages[key] = frame
        return frame
    end
    -- Rows sit UI.PAD into their panel, so each column panel starts that far
    -- left of where its rows should line up.
    local function column(parent, index, width)
        local panel = CreateFrame('Frame', nil, parent)
        panel:SetSize((width or colWidth) + UI.PAD, 1)
        panel:SetPoint('TOPLEFT', MARGIN - UI.PAD + (index - 1) * (colWidth + GAP), 0)
        panels[#panels + 1] = panel
        return panel
    end

    -- ── Game: where it's played, then how long ──
    local gamePage = page('game')
    local gameCol, lengthCol = column(gamePage, 1), column(gamePage, 2)
    setup.columns.game, setup.columns.length = gameCol, lengthCol
    local _, y
    y = section(gameCol, 'Game', 0, colWidth)
    _, y = Dropdown(gameCol, 'Output', 'Where questions are posted and players answer.', y,
        { 'PARTY', 'RAID', 'INSTANCE_CHAT', 'GUILD' }, { 'Party', 'Raid', 'Instance', 'Guild' },
        function() return ns.db.channel end, function(value) setup.SetOutput(value) end, colWidth, 190, 160)
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
    _, y = Check(gameCol, 'Host plays along', 'You answer and score like everyone else.', y,
        function() return ns.db.hostParticipates end, function(value) ns.db.hostParticipates = value end, colWidth)
    _, y = Dropdown(gameCol, 'Difficulty', 'Hard includes obscure lore, talents and procs.', y,
        { 'mixed', 'easy', 'hard' }, { 'Mixed', 'Easier', 'Hard' },
        function() return ns.db.difficulty end, function(value) ns.db.difficulty = value end, colWidth, 190, 160)

    y = section(lengthCol, 'Length', 0, colWidth)
    _, y = stepper(lengthCol, 'Themed rounds', 'Each round draws from one of your categories, named as it starts. Off mixes them all.', y, 'rounds',
        function(v) return v == 1 and 'Off' or tostring(v) end, colWidth)
    setup.questions, y = stepper(lengthCol, 'Questions', nil, y, 'perRound', nil, colWidth)
    _, y = stepper(lengthCol, 'Answer time', nil, y, 'seconds', seconds, colWidth)
    _, y = Check(lengthCol, 'Countdown before starting', 'Players can join and type ready before the first question.', y,
        function() return ns.db.readyCheck end, function(value) ns.db.readyCheck = value end, colWidth)
    setup.countdown, y = stepper(lengthCol, 'Start countdown', 'Seconds before the first question. You can start sooner; disable the countdown above to skip it.', y, 'readySeconds', seconds, colWidth)

    -- ── Categories: two columns of switches with their question counts ──
    local categoryPage = page('categories')
    local catLeft, catRight = column(categoryPage, 1), column(categoryPage, 2)
    setup.columns.categories = { catLeft, catRight }
    local top = section(catLeft, 'Categories', 0, fullWidth)
    local all = UI.Button(categoryPage, 50, 20); all:SetPoint('TOPRIGHT', categoryPage, 'TOPRIGHT', -(MARGIN + 54), 2); all:SetText('All')
    local none = UI.Button(categoryPage, 50, 20); none:SetPoint('TOPRIGHT', categoryPage, 'TOPRIGHT', -MARGIN, 2); none:SetText('None')
    local function setAll(value)
        for _, category in ipairs(ns.Game.CATEGORIES) do ns.db.categories[category[1]] = value end
        setup.Refresh()
    end
    all:SetScript('OnClick', function() setAll(true) end)
    none:SetScript('OnClick', function() setAll(false) end)
    setup.categoryRows = {}
    local half = math.ceil(#ns.Game.CATEGORIES / 2)
    local columnY = { [catLeft] = top, [catRight] = top }
    for i, category in ipairs(ns.Game.CATEGORIES) do
        local key = category[1]
        local panel = i <= half and catLeft or catRight
        local row
        row, columnY[panel] = Check(panel, category[2], nil, columnY[panel],
            function() return ns.db.categories[key] == true end,
            function(value) ns.db.categories[key] = value end, colWidth)
        row.count = UI.FontString(row, 'GameFontHighlightSmall', 'muted')
        row.count:SetWidth(COUNT_W); row.count:SetJustifyH('RIGHT')
        local check = row.hcCheckbox
        -- Left of the switch, or at the edge beside Classic's checkbox; the
        -- name stops short of the count so long names never run under it.
        if check.track then row.count:SetPoint('RIGHT', check.track, 'LEFT', -12, 0)
        else row.count:SetPoint('RIGHT', row, 'RIGHT', -UI.CELL_INSET, 0) end
        check.Text:SetPoint('RIGHT', row.count, 'LEFT', -8, 0)
        setup.categoryRows[key] = row
    end

    -- ── Party lobby ──
    local lobby = page('lobby')
    local lobbyCol = column(lobby, 1, fullWidth)
    local ly = section(lobbyCol, 'Party lobby', 0, fullWidth)
    lobby.timer = UI.FontString(lobbyCol, 'GameFontHighlightSmall', 'muted')
    lobby.timer:SetPoint('TOPRIGHT', lobbyCol, 'TOPLEFT', UI.PAD + fullWidth, 0)
    lobby.rows = {}
    for i = 1, LOBBY_ROWS do
        local row = CreateFrame('Frame', nil, lobbyCol)
        row:SetSize(fullWidth, 22); row:SetPoint('TOPLEFT', UI.PAD, ly - (i - 1) * 24)
        row.dot = row:CreateTexture(nil, 'ARTWORK'); row.dot:SetSize(6, 6); row.dot:SetPoint('LEFT', 0, 0)
        row.name = UI.FontString(row, 'GameFontHighlight', 'text'); row.name:SetPoint('LEFT', 12, 0)
        row.name:SetWidth(fullWidth - 200); row.name:SetJustifyH('LEFT')
        row.state = UI.FontString(row, 'GameFontHighlightSmall', 'muted'); row.state:SetPoint('RIGHT', 0, 0)
        lobby.rows[i] = row
    end
    lobby.note = UI.FontString(lobbyCol, 'GameFontHighlightSmall', 'muted')
    lobby.note:SetPoint('TOPLEFT', UI.PAD, ly - LOBBY_ROWS * 24 - 8); lobby.note:SetWidth(fullWidth); lobby.note:SetJustifyH('LEFT')
    lobby.note:SetText('Players without Loreforge can still answer in Party chat.')
    lobby.keep = UI.Button(lobbyCol, 150, 26)
    lobby.keep:SetPoint('TOPLEFT', UI.PAD, ly - LOBBY_ROWS * 24 - 36); lobby.keep:SetText('Keep lobby open')
    lobby.keep:SetScript('OnClick', function() if ns.Party then ns.Party.KeepLobbyOpen() end; setup.Refresh() end)
    UI.AttachHint(lobby.keep, 'Keep lobby open', 'Resets the lobby timer to 10 minutes.')
    setup.lobbyPanel = lobby

    -- ── Pacing & chat ──
    local pacingPage = page('pacing')
    local pacingCol, chatCol = column(pacingPage, 1), column(pacingPage, 2)
    setup.columns.pacing, setup.columns.chat = pacingCol, chatCol
    local a = section(pacingCol, 'Pacing', 0, colWidth)
    _, a = Check(pacingCol, 'Auto-advance questions', 'On: the next question starts after results and the Question gap. Off: host-paced, with Ask next question after every reveal.', a,
        function() return ns.db.autoMode end, function(value) ns.db.autoMode = value end, colWidth)
    _, a = stepper(pacingCol, 'Question gap', 'Seconds between questions with auto-advance.', a, 'questionGap', seconds, colWidth)
    _, a = stepper(pacingCol, 'Pause when quiet', 'Auto-advance pauses after this many questions with no answers.', a, 'idleLimit',
        function(v) return v == 0 and 'Off' or plural(v, 'question') end, colWidth)
    a = section(chatCol, 'Chat', 0, colWidth)
    _, a = Check(chatCol, 'Choices on one line', 'Posts the four choices on one line instead of four.', a,
        function() return ns.db.compactChoices end, function(value) ns.db.compactChoices = value end, colWidth)
    _, a = Check(chatCol, 'Announce top three records', 'After the final scores, post records for the top three players.', a,
        function() return ns.db.replayRecords end, function(value) ns.db.replayRecords = value end, colWidth)

    setup.pool = UI.FontString(setup, 'GameFontHighlightSmall', 'muted')
    setup.pool:SetPoint('BOTTOMLEFT', MARGIN, 62); setup.pool:SetWidth(fullWidth); setup.pool:SetJustifyH('LEFT')

    -- Footer: one primary action, with lobby actions beside it when a lobby is open.
    setup.start = UI.Button(setup, 200, 34, 'primary')
    setup.start:SetPoint('BOTTOMLEFT', MARGIN, 18); setup.start:SetText('Start game')
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
    setup.quick = UI.Button(setup, 130, 34)
    setup.quick:SetText('Quick play')
    setup.quick:SetScript('OnClick', function() if ns.QuickCard then ns.QuickCard.Show() end end)
    UI.AttachHint(setup.quick, 'Quick play', 'A small solo quiz card. No setup, nothing posted. /lf quick opens it too.')
    -- Solo, Quick play can lead: the same action as a primary button.
    setup.quickMain = UI.Button(setup, 200, 34, 'primary')
    setup.quickMain:SetPoint('BOTTOMLEFT', MARGIN, 18); setup.quickMain:SetText('Quick play')
    setup.quickMain:SetScript('OnClick', function() if ns.QuickCard then ns.QuickCard.Show() end end)
    UI.AttachHint(setup.quickMain, 'Quick play', 'A small solo quiz card. No setup, nothing posted. /lf quick opens it too.')
    setup.daily = UI.Button(setup, 150, 34)
    setup.daily:SetScript('OnClick', function() if ns.QuickCard then ns.QuickCard.Show('daily') end end)
    UI.AttachHint(setup.daily, 'Daily question', function()
        if ns.Daily and ns.Daily.Done() then return 'Done for today. ' .. ns.Daily.NextText() .. '.' end
        return 'Today\'s question, the same for everyone. One try, no timer. /lf daily opens it too.'
    end)
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
                row.name:SetText(ns.DisplayName(p.name))
                row.state:SetText(joined and 'Joined' or 'Chat only so far')
                T.Text(row.state, joined and 'accent' or 'muted')
                T.Fill(row.dot, joined and 'accent' or 'rail')
            end
        end
    end

    local function closeMenus()
        for _, panel in ipairs(panels) do
            for _, child in ipairs({ panel:GetChildren() }) do
                if child.hcCloseMenu then child.hcCloseMenu() end
            end
        end
    end

    -- An opening lobby comes to the front once; closing it returns to the remembered tab.
    local function showTab(isOpen)
        if isOpen and not setup.lobbyWasOpen then setup.current = 'lobby' end
        setup.lobbyWasOpen = isOpen
        local current = setup.current or savedTab()
        if current == 'lobby' and not isOpen then current = savedTab() end
        setup.current = current
        strip.Layout({ game = true, categories = true, lobby = isOpen, pacing = true })
        strip.Select(current)
        for key, frame in pairs(setup.pages) do frame:SetShown(key == current) end
    end
    function setup.SelectTab(key)
        if InCombatLockdown() then return end
        if SAVED_TABS[key] then ns.db.setupTab = key end
        closeMenus()
        setup.current = key
        setup.Refresh()
    end

    local function refresh(panel)
        if InCombatLockdown() then return end
        for _, run in ipairs(panel.hcRefresh or {}) do run() end
    end
    local function refreshAll()
        if InCombatLockdown() then return end
        for _, panel in ipairs(panels) do refresh(panel) end
        setup.questions.Title:SetText(ns.db.rounds > 1 and 'Questions per round' or 'Questions')
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
        local ticked = 0
        for _, category in ipairs(ns.Game.CATEGORIES) do if ns.db.categories[category[1]] then ticked = ticked + 1 end end
        setup.pool:SetText(available .. ' questions available for these categories and difficulty.'
            .. (ns.db.rounds > ticked and ticked > 0 and ' Fewer categories than rounds, so themes repeat.' or ''))

        local presetName = 'Custom'
        for i, preset in ipairs(PRESETS) do
            local on = ns.db.rounds == preset.rounds and ns.db.perRound == preset.perRound and ns.db.seconds == preset.seconds
            if on then presetName = preset.name end
            T.Border(setup.presets[i], on and 'selected' or 'edge')
            T.Text(setup.presets[i].Text, on and 'selected' or 'text')
        end
        host.tags:SetText(presetName .. ' · ' .. host.tags:GetText())
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
        -- The sub-tabs and their pages sit below the banner when it shows.
        local tabTop = banner:IsShown() and -164 or -108
        bar:ClearAllPoints(); bar:SetPoint('TOPLEFT', MARGIN, tabTop)
        for _, frame in pairs(setup.pages) do
            frame:ClearAllPoints(); frame:SetPoint('TOPLEFT', 0, tabTop - TAB_H - 14)
        end
        showTab(isOpen)
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
        -- Solo, Quick play leads unless Main button when solo says Practice
        -- game; Practice solo then takes the second spot. Grouped, the
        -- game's start button always leads.
        local quickFirst = setup.solo and not isOpen and ns.db.soloMain ~= 'PRACTICE'
        setup.start:SetShown(not quickFirst)
        setup.quickMain:SetShown(quickFirst)
        setup.practice:SetShown(quickFirst or (not setup.solo and not isOpen))
        setup.practice:ClearAllPoints()
        setup.practice:SetPoint('BOTTOMLEFT', 228, 18)
        setup.practice:SetEnabled(not restricted and not poolIssue and not (quickFirst and issue))
        setup.quick:ClearAllPoints()
        setup.quick:SetPoint('BOTTOMLEFT', setup.practice:IsShown() and 388 or 228, 18)
        setup.quick:SetShown(not isOpen and not quickFirst)
        -- Daily sits after the last of them, with a tick once it's done.
        local daily = ns.Daily and ns.Daily.Enabled() and not isOpen
        setup.daily:SetShown(daily and true or false)
        if daily then
            local x = quickFirst and 388 or (setup.quick:IsShown() and (setup.practice:IsShown() and 528 or 368)) or 228
            setup.daily:ClearAllPoints()
            setup.daily:SetPoint('BOTTOMLEFT', x, 18)
            local done = ns.Daily.Done()
            setup.daily:SetText(done and 'Daily question |TInterface\\RaidFrame\\ReadyCheck-Ready:14|t' or 'Daily question')
            setup.daily.done = done
        end
        setup.lobby:SetShown(isOpen)
        setup.closeLobby:SetShown(isOpen)
    end
    local function changed() ns.setupError = nil; refreshAll() end
    for _, panel in ipairs(panels) do panel.hcRefreshAll = changed end
    setup.Refresh = refreshAll
    setup:SetScript('OnHide', closeMenus)
    refreshAll()
    return setup
end
