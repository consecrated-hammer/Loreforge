local _, ns = ...
local HC, UI = ns.HammerCore, ns.HammerCore.UI

function ns.ConfirmClearRecords()
    if ns.game:Active() then HC.Print('Stop or finish the game before clearing player records.'); return end
    local key = 'LOREFORGE_CLEAR_RECORDS'
    StaticPopupDialogs[key] = {
        text = 'Clear the ' .. (ns.era == 'classic' and 'WoW Forever' or 'Retail') .. ' Hall of Fame? This cannot be undone.',
        button1 = 'Clear records', button2 = 'Cancel', timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        OnAccept = function()
            if ns.game:Active() then HC.Print('Stop or finish the game before clearing player records.'); return end
            for key in pairs(ns.db.records[ns.era]) do ns.db.records[ns.era][key] = nil end
            HC.Print('Player records cleared for this client.')
            ns.RefreshHost()
        end,
    }
    StaticPopup_Show(key)
end

local function scale(v) return math.floor(v * 100 + 0.5) .. '%' end

local ICONS = {
    sound = 'Interface\\Icons\\INV_Misc_Bell_01',
    game = 'Interface\\Icons\\INV_Misc_Book_09',
    size = 'Interface\\Icons\\INV_Misc_Spyglass_03',
    records = 'Interface\\Icons\\Achievement_General',
    party = 'Interface\\Icons\\INV_Letter_15',
    flair = 'Interface\\Icons\\INV_Drink_05',
}

-- The settings the Interface page owns; its reset restores just these.
local INTERFACE_KEYS = { 'sound', 'hostAutoMinimise', 'questionArt', 'roundIntro', 'hostScale', 'playerScale', 'windowOpacity',
    'storybook', 'livelyAnimations', 'tavernBanter', 'streakFlair' }

local function redraw()
    ns.ApplyHostScale()
    if ns.ApplyWindowOpacity then ns.ApplyWindowOpacity() end
    if ns.ApplyFlair then ns.ApplyFlair() end
    if ns.RefreshHost then ns.RefreshHost() end
    if ns.Player then
        if ns.Player.ApplyScale then ns.Player.ApplyScale() end
        if ns.Player.Draw then ns.Player.Draw() end
    end
end

HC.Settings:NewPage({ name = 'Interface', description = 'Sound, art and window sizes. Set up games in the main window.' }, function(panel, y)
    _, y = UI.Header(panel, 'Sound', y, ICONS.sound)
    _, y = UI.Check(panel, 'Sound cues', 'Invitations, new questions, the last five seconds, results and the finish.', y,
        function() return ns.db.sound ~= false end, function(value) ns.db.sound = value end)
    y = UI.Flush(panel, y)
    _, y = UI.Header(panel, 'Game window', y, ICONS.game)
    _, y = UI.Check(panel, 'Theme art', 'A painting beside the question.', y,
        function() return ns.db.questionArt ~= false end, function(value)
            ns.db.questionArt = value
            if ns.Player and ns.Player.Draw then ns.Player.Draw() end
        end)
    _, y = UI.Check(panel, 'Round intros', 'Games you host open each themed round with its art for a few seconds.', y,
        function() return ns.db.roundIntro ~= false end, function(value) ns.db.roundIntro = value end)
    _, y = UI.Check(panel, 'Minimise when playing along', 'Hide the main window when a game you play in starts. It comes back for the results.', y,
        function() return ns.db.hostAutoMinimise ~= false end, function(value) ns.db.hostAutoMinimise = value end)
    y = UI.Flush(panel, y)
    _, y = UI.Header(panel, 'Flair', y, ICONS.flair)
    for _, spec in ipairs({
        { 'storybook', 'Storybook style', 'Fancy titles, parchment and numbered answers.' },
        { 'livelyAnimations', 'Lively animations', 'Pops, sparkles, shakes and a bouncing crown.' },
        { 'tavernBanter', 'Tavern banter', 'Quips after answers and results. Only you see them.' },
        { 'streakFlair', 'Streak flair', 'A flame beside your score from 3 in a row.' },
    }) do
        local key = spec[1]
        _, y = UI.Check(panel, spec[2], spec[3], y,
            function() return ns.db[key] ~= false end,
            function(value) ns.db[key] = value; redraw() end)
    end
    y = UI.Flush(panel, y)
    _, y = UI.Header(panel, 'Window size', y, ICONS.size)
    _, y = UI.Slider(panel, 'Main window', 'Scales the host window.', y, 0.7, 1.5, 0.05,
        function() return ns.db.hostScale or 1 end, function(value) ns.db.hostScale = value; ns.ApplyHostScale() end, scale)
    _, y = UI.Slider(panel, 'Player window', 'Scales the window you answer in when you join a Party game.', y, 0.7, 1.5, 0.05,
        function() return ns.db.playerScale or 1 end,
        function(value) ns.db.playerScale = value; if ns.Player then ns.Player.ApplyScale() end end, scale)
    -- Percent steps: the slider's fill assumes a range wider than 1.
    _, y = UI.Slider(panel, 'Window opacity', 'How solid the game windows are.', y, 50, 100, 5,
        function() return math.floor(ns.GetWindowOpacity() * 100 + 0.5) end,
        function(value) ns.SetWindowOpacity(value / 100) end,
        function(value) return math.floor(value + 0.5) .. '%' end)
    _, y = UI.PageReset(panel, y, function()
        for _, key in ipairs(INTERFACE_KEYS) do ns.db[key] = ns.DEFAULTS[key] end
        redraw()
    end)
    return y
end)

-- ── Quick play ─────────────────────────────────────────────────────────────

local QUICK_ICONS = {
    play = 'Interface\\Icons\\INV_Misc_PocketWatch_01',
    look = 'Interface\\Icons\\INV_Misc_Spyglass_03',
    flights = 'Interface\\Icons\\Ability_Mount_Gryphon_01',
    daily = 'Interface\\Icons\\INV_Misc_Note_06',
}

local function quickChanged()
    if ns.QuickCard then
        if ns.QuickCard.Layout then ns.QuickCard.Layout() end
        if ns.QuickCard.IsShown() then ns.QuickCard.Render() end
        if ns.QuickCard.RefreshOptions then ns.QuickCard.RefreshOptions() end
    end
end

local function seconds(value) return value .. ' s' end

HC.Settings:NewPage({ name = 'Quick play', description = 'A solo quiz card for flights and idle moments. /lf quick opens it.' }, function(panel, y)
    local db, Quick = ns.db, ns.Quick
    local dependants = {}
    local function hideWhen(row, test) dependants[#dependants + 1] = { row = row, test = test } end
    _, y = UI.Header(panel, 'Play', y, QUICK_ICONS.play)
    _, y = UI.Dropdown(panel, 'Timer', 'Quick play and Streak. Lightning and Flight challenge are always against the clock.', y,
        { 'CLOCK', 'RELAXED' }, { 'Against the clock', 'Relaxed' },
        function() return db.qpRelaxed and 'RELAXED' or 'CLOCK' end,
        function(value) db.qpRelaxed = value == 'RELAXED'; quickChanged() end)
    local row
    row, y = UI.Slider(panel, 'Seconds per question', 'Time for each question when against the clock.', y, 5, 30, 1,
        function() return db.qpSeconds end, function(value) db.qpSeconds = value end, seconds)
    hideWhen(row, function() return not db.qpRelaxed end)
    _, y = UI.Check(panel, 'Next question automatically', 'Off: click Next after each answer.', y,
        function() return db.qpAutoNext end, function(value) db.qpAutoNext = value end)
    row, y = UI.Slider(panel, 'Wait before next', 'Seconds the answer shows before the next question.', y, 1, 5, 1,
        function() return db.qpNextDelay end, function(value) db.qpNextDelay = value end, seconds)
    hideWhen(row, function() return db.qpAutoNext end)
    _, y = UI.Slider(panel, 'Lightning length', 'How long a Lightning round lasts.', y, 30, 180, 10,
        function() return db.qpLightning end, function(value) db.qpLightning = value end, seconds)
    _, y = UI.Dropdown(panel, 'Main button when solo', 'The big button on the Play tab when you\'re not in a group.', y,
        { 'QUICK', 'PRACTICE' }, { 'Quick play', 'Practice game' },
        function() return db.soloMain end, function(value) db.soloMain = value; if ns.RefreshHost then ns.RefreshHost() end end,
        nil, nil, 140)
    y = UI.Flush(panel, y)
    _, y = UI.ActionButton(panel, y, 'Categories & difficulty', function() HC.Settings:Hide(); ns.QuickCard.OpenCategories() end,
        'Quick play uses the categories and difficulty from game setup.', nil, 180)
    y = UI.Flush(panel, y)
    _, y = UI.Header(panel, 'Look', y, QUICK_ICONS.look)
    _, y = UI.Check(panel, 'Artwork', 'The category painting beside the question.', y,
        function() return db.qpArt ~= false end, function(value) db.qpArt = value; quickChanged() end)
    _, y = UI.Check(panel, 'Animations', 'Painting fades and the Touchdown! bounce.', y,
        function() return db.qpAnimations ~= false end, function(value) db.qpAnimations = value end)
    _, y = UI.Dropdown(panel, 'Card size', 'The Quick play card and the takeoff prompt.', y,
        { 'SMALL', 'MEDIUM', 'LARGE' }, { 'Small', 'Medium', 'Large' },
        function() return db.qpSize end, function(value) db.qpSize = value; quickChanged() end)
    y = UI.Flush(panel, y)
    _, y = UI.Header(panel, 'Flights', y, QUICK_ICONS.flights)
    _, y = UI.Dropdown(panel, 'On flights', 'What happens when you take a flight path.', y,
        Quick.ON_FLIGHTS, { Quick.ON_FLIGHTS_LABELS.OFFER, Quick.ON_FLIGHTS_LABELS.START, Quick.ON_FLIGHTS_LABELS.NONE },
        function() return db.qpOnFlights end, function(value) db.qpOnFlights = value; quickChanged() end)
    row, y = UI.Slider(panel, 'Shortest flight', 'Flights expected to be shorter than this don\'t start a challenge.', y, 0, 60, 5,
        function() return db.qpShortest end, function(value) db.qpShortest = value end, seconds)
    hideWhen(row, function() return db.qpOnFlights == 'START' end)
    _, y = UI.Check(panel, 'Close on landing', 'After the last question and Touchdown!, the card closes.', y,
        function() return db.qpCloseOnLanding ~= false end, function(value) db.qpCloseOnLanding = value; quickChanged() end)
    _, y = UI.Slider(panel, 'Flight answer pause', 'Seconds each answer shows during a Flight challenge.', y, 1, 8, 1,
        function() return db.qpFlightReveal end, function(value) db.qpFlightReveal = value end, seconds)
    _, y = UI.Slider(panel, 'Landing grace', 'Seconds to finish the open question after you land. 0 ends it on landing.', y, 0, 30, 1,
        function() return db.qpLandingGrace end, function(value) db.qpLandingGrace = value end, seconds)
    if ns.era == 'retail' then
        _, y = UI.Check(panel, 'Loremaster lines', 'Extra takeoff lines for characters with the Loremaster title.', y,
            function() return db.qpLoremaster ~= false end, function(value) db.qpLoremaster = value end)
    end
    y = UI.Flush(panel, y)
    _, y = UI.Header(panel, 'Daily question', y, QUICK_ICONS.daily)
    _, y = UI.Check(panel, 'Daily question', 'One question a day, the same for everyone. Off hides it from the menu and the Play tab.', y,
        function() return db.dailyOn ~= false end, function(value) db.dailyOn = value; if ns.RefreshHost then ns.RefreshHost() end end)
    row, y = UI.Check(panel, 'Offer at login', 'Once a day, a few seconds after you log in. Never in combat or an instance.', y,
        function() return db.dailyOffer ~= false end, function(value) db.dailyOffer = value end)
    hideWhen(row, function() return db.dailyOn ~= false end)
    UI.OnRefresh(panel, function()
        for _, item in ipairs(dependants) do item.row:SetShown(item.test()) end
    end)
    for _, item in ipairs(dependants) do item.row:SetShown(item.test()) end
    _, y = UI.PageReset(panel, y, function()
        for key, value in pairs(Quick.DEFAULTS) do db[key] = value end
        for key, value in pairs(ns.Daily.DEFAULTS) do db[key] = value end
        quickChanged()
        if ns.RefreshHost then ns.RefreshHost() end
    end)
    return y
end)

-- ── Key Bindings ───────────────────────────────────────────────────────────

-- The four answer keys are Blizzard bindings (Bindings.xml); this page is
-- HammerCore's shared editor over them.
local ANSWERS = {}
for i = 1, 4 do
    ANSWERS[i] = { id = 'LOREFORGE_ANSWER' .. i, name = 'Answer ' .. i,
        icon = 'Interface\\Icons\\INV_Misc_Book_09', detail = 'Picks answer ' .. i .. ' in the game window.' }
end

ANSWERS[5] = { id = 'LOREFORGE_QUICKPLAY', name = 'Quick play', icon = 'Interface\\Icons\\INV_Misc_Book_09',
    detail = 'Opens or closes the Quick play card.' }

local function saveBindings()
    if SaveBindings and GetCurrentBindingSet then SaveBindings(GetCurrentBindingSet()) end
end

local function bindingName(action)
    local label = _G['BINDING_NAME_' .. action]
    return type(label) == 'string' and label or action
end

local function setAnswer(item, key)
    if not SetBinding then return false, 'Key bindings are unavailable.' end
    if InCombatLockdown and InCombatLockdown() then return false, 'Key bindings can\'t change in combat.' end
    local function apply()
        local old = GetBindingKey and GetBindingKey(item.id)
        if old then SetBinding(old) end
        if not SetBinding(key, item.id) then return false, 'That key can\'t be bound.' end
        saveBindings()
        HC.Print(item.name .. ' bound to ' .. HC.Bindings.Label(key) .. '.')
        return true
    end
    local current = GetBindingAction and GetBindingAction(key)
    if current and current ~= '' and current ~= item.id then
        return false, HC.Bindings.Label(key) .. ' already does ' .. bindingName(current) .. '.', apply
    end
    return apply()
end

HC.Settings:NewPage({ name = 'Key Bindings', columns = 1, description = 'Answer with a key instead of a click.' }, function(panel, y)
    y = HC.Bindings.Page(panel, y, {
        inputs = { keys = true, mouse = true },
        empty = 'No answer keys yet. Pick one on the right.',
        poolHint = 'Click an answer, then press a key or mouse button.',
        pool = function() return { { title = 'Loreforge', items = ANSWERS } } end,
        bound = function()
            local list = {}
            for _, item in ipairs(ANSWERS) do
                local key = GetBindingKey and GetBindingKey(item.id)
                if key then list[#list + 1] = { id = item.id, name = item.name, icon = item.icon, key = key } end
            end
            return list
        end,
        bind = setAnswer,
        unbind = function(id)
            if InCombatLockdown and InCombatLockdown() then HC.Print('Key bindings can\'t change in combat.'); return end
            local key = GetBindingKey and GetBindingKey(id)
            while key do SetBinding(key); key = GetBindingKey(id) end
            saveBindings()
        end,
    })
    return y
end)

HC.Settings:NewPage({ name = 'Player records', columns = 1, description = 'The Hall of Fame tab in the main window shows these.' }, function(panel, y)
    _, y = UI.Header(panel, 'Player records', y, ICONS.records)
    _, y = UI.Text(panel, 'Games you host save each player\'s games, wins, correct answers and best streak.', y)
    _, y = UI.Text(panel, 'Records are shared by your characters on this account, separately for each client.', y)
    _, y = UI.Text(panel, 'Reset settings keeps records. Clearing them asks first.', y)
    _, y = UI.ActionButton(panel, y, 'Open Hall of Fame', function() HC.Settings:Hide(); ns.OpenHost('records') end,
        'The Hall of Fame tab in the main window.', 'primary', 180)
    _, y = UI.ActionButton(panel, y, 'Clear player records', ns.ConfirmClearRecords,
        'Removes this client\'s records. Asks first.', 'danger', 180)
    return y
end)

HC.Settings:NewPage({ name = 'Party games', columns = 1, description = 'Invitations to other hosts\' Party games.' }, function(panel, y)
    _, y = UI.Header(panel, 'Party invitations', y, ICONS.party)
    _, y = UI.Check(panel, 'Show Party game invitations', 'Ask before joining another player\'s game. Party games work in Retail home Parties, including dungeons when activity restrictions are inactive.', y,
        function() return ns.db.partyInvites ~= false end, function(value) ns.db.partyInvites = value end)
    _, y = UI.Text(panel, 'Joining gives you clickable questions and sends your answers to the host. Other addons in the group can read Party addon messages.', y)
    _, y = UI.ActionButton(panel, y, 'Open History', function() HC.Settings:Hide(); ns.OpenHost('history') end,
        'Past games, hosted and joined.', 'primary', 180)
    _, y = UI.PageReset(panel, y, function() ns.db.partyInvites = true end)
    return y
end)
