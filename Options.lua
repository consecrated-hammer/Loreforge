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

local function resetInterface(panel, y, keys, label)
    local _
    _, y = UI.PageReset(panel, y, function()
        for _, key in ipairs(keys) do ns.db[key] = ns.DEFAULTS[key] end
        redraw()
    end, label)
    return y
end

HC.Settings:NewPage({ name = 'Interface', description = 'Make the quiz your own. Quick play has separate card controls.', tabs = {
    { name = 'Presentation', build = function(panel, y)
    _, y = UI.Header(panel, 'Sound', y, ICONS.sound)
    _, y = UI.Check(panel, 'Sound cues', 'Invitations, new questions, the last five seconds, results and the finish.', y,
        function() return ns.db.sound ~= false end, function(value) ns.db.sound = value end)
    y = UI.Flush(panel, y)
    _, y = UI.Header(panel, 'Game window', y, ICONS.game)
    _, y = UI.Check(panel, 'Artwork', 'A painting beside the question.', y,
        function() return ns.db.questionArt ~= false end, function(value)
            ns.db.questionArt = value
            redraw()
        end)
    _, y = UI.Check(panel, 'Round intros', 'Games you host open each themed round with its art for a few seconds.', y,
        function() return ns.db.roundIntro ~= false end, function(value) ns.db.roundIntro = value end)
    y = UI.Flush(panel, y)
    _, y = UI.Header(panel, 'Flair', y, ICONS.flair)
    for _, spec in ipairs({
        { 'storybook', 'Storybook style', 'Fancy titles, parchment and numbered answers.' },
        { 'livelyAnimations', 'Animations', 'Pops, sparkles, shakes and a bouncing crown.' },
        { 'tavernBanter', 'Tavern banter', 'Quips after answers and results. Only you see them.' },
        { 'streakFlair', 'Streak flair', 'A flame beside your score from 3 in a row.' },
    }) do
        local key = spec[1]
        _, y = UI.Check(panel, spec[2], spec[3], y,
            function() return ns.db[key] ~= false end,
            function(value) ns.db[key] = value; redraw() end)
    end
    y = UI.Flush(panel, y)
    return resetInterface(panel, y, { 'sound', 'questionArt', 'roundIntro', 'storybook', 'livelyAnimations', 'tavernBanter', 'streakFlair' }, 'Reset presentation')
    end },
    { name = 'Windows', build = function(panel, y)
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
    _, y = UI.Check(panel, 'Minimise when playing along', 'Hide the main window when a game you play in starts. It comes back for the results.', y,
        function() return ns.db.hostAutoMinimise ~= false end, function(value) ns.db.hostAutoMinimise = value end)
    return resetInterface(panel, y, { 'hostScale', 'playerScale', 'windowOpacity', 'hostAutoMinimise' }, 'Reset windows')
    end },
} })

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

local function quickTab(name, build, keys)
    return { name = name, build = function(panel, y)
        local dependants = {}
        local function hideWhen(row, parent, test)
            row.hcParentRow = parent
            dependants[#dependants + 1] = { row = row, test = test }
        end
        y = build(panel, y, ns.db, ns.Quick, hideWhen)
        local function refresh()
            for _, item in ipairs(dependants) do item.row:SetShown(item.test()) end
        end
        UI.OnRefresh(panel, refresh)
        refresh()
        local _
        _, y = UI.PageReset(panel, y, function()
            for _, key in ipairs(keys) do
                local value = ns.Quick.DEFAULTS[key]
                if value == nil then value = ns.Daily.DEFAULTS[key] end
                ns.db[key] = value
            end
            quickChanged()
            if ns.RefreshHost then ns.RefreshHost() end
        end, 'Reset ' .. name:sub(1, 1):lower() .. name:sub(2))
        return y
    end }
end

HC.Settings:NewPage({ name = 'Quick play', description = 'Solo quiz timing, card appearance, flights and the daily.', tabs = {
    quickTab('Play', function(panel, y, db, Quick, hideWhen)
    local _, row
    _, y = UI.Header(panel, 'Play', y, QUICK_ICONS.play)
    local timer
    timer, y = UI.Dropdown(panel, 'Timer', 'Quick play and Streak. Lightning and Flight challenge are always against the clock.', y,
        { 'CLOCK', 'RELAXED' }, { 'Against the clock', 'Relaxed' },
        function() return db.qpRelaxed and 'RELAXED' or 'CLOCK' end,
        function(value) ns.QuickCard.SetRelaxed(value == 'RELAXED'); quickChanged() end)
    local row
    row, y = UI.Slider(panel, 'Seconds per question', 'Time for each question when against the clock.', y, 5, 30, 1,
        function() return db.qpSeconds end, function(value) db.qpSeconds = value end, seconds)
    hideWhen(row, timer, function() return not db.qpRelaxed end)
    local automatic
    automatic, y = UI.Check(panel, 'Next question automatically', 'Off: click Next after each answer.', y,
        function() return db.qpAutoNext end, function(value) db.qpAutoNext = value end)
    row, y = UI.Slider(panel, 'Wait before next', 'Seconds the answer shows before the next question.', y, 1, 5, 1,
        function() return db.qpNextDelay end, function(value) db.qpNextDelay = value end, seconds)
    hideWhen(row, automatic, function() return db.qpAutoNext end)
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
    return y
    end, { 'qpMode', 'qpRelaxed', 'qpSeconds', 'qpAutoNext', 'qpNextDelay', 'qpLightning', 'soloMain' }),
    quickTab('Card', function(panel, y, db, Quick, hideWhen)
    local _, row
    _, y = UI.Header(panel, 'Look', y, QUICK_ICONS.look)
    _, y = UI.Check(panel, 'Artwork', 'The category painting beside the question.', y,
        function() return db.qpArt ~= false end, function(value) db.qpArt = value; quickChanged() end)
    _, y = UI.Check(panel, 'Animations', 'Painting fades and the Touchdown! bounce.', y,
        function() return db.qpAnimations ~= false end, function(value) db.qpAnimations = value; quickChanged() end)
    _, y = UI.Dropdown(panel, 'Card size', 'The Quick play card and the takeoff prompt.', y,
        { 'SMALL', 'MEDIUM', 'LARGE' }, { 'Small', 'Medium', 'Large' },
        function() return db.qpSize end, function(value) db.qpSize = value; quickChanged() end)
    y = UI.Flush(panel, y)
    return y
    end, { 'qpArt', 'qpAnimations', 'qpSize' }),
    quickTab('Flights', function(panel, y, db, Quick, hideWhen)
    local _, row
    _, y = UI.Header(panel, 'Flights', y, QUICK_ICONS.flights)
    local onFlights
    onFlights, y = UI.Dropdown(panel, 'On flights', 'What happens when you take a flight path.', y,
        Quick.ON_FLIGHTS, { Quick.ON_FLIGHTS_LABELS.OFFER, Quick.ON_FLIGHTS_LABELS.START, Quick.ON_FLIGHTS_LABELS.NONE },
        function() return db.qpOnFlights end, function(value) db.qpOnFlights = value; quickChanged() end)
    row, y = UI.Slider(panel, 'Shortest flight', 'Flights expected to be shorter than this don\'t start a challenge.', y, 0, 60, 5,
        function() return db.qpShortest end, function(value) db.qpShortest = value end, seconds)
    hideWhen(row, onFlights, function() return db.qpOnFlights == 'START' end)
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
    return y
    end, { 'qpOnFlights', 'qpShortest', 'qpCloseOnLanding', 'qpFlightReveal', 'qpLandingGrace', 'qpLoremaster' }),
    quickTab('Daily question', function(panel, y, db, Quick, hideWhen)
    local _, row
    _, y = UI.Header(panel, 'Daily question', y, QUICK_ICONS.daily)
    local enabled
    enabled, y = UI.Check(panel, 'Daily question', 'One question a day, the same for everyone. Off hides it from the menu and the Play tab.', y,
        function() return db.dailyOn ~= false end, function(value) db.dailyOn = value; if ns.RefreshHost then ns.RefreshHost() end end)
    row, y = UI.Check(panel, 'Offer at login', 'Once a day, a few seconds after you log in. Never in combat or an instance.', y,
        function() return db.dailyOffer ~= false end, function(value) db.dailyOffer = value end)
    hideWhen(row, enabled, function() return db.dailyOn ~= false end)
    return y
    end, { 'dailyOn', 'dailyOffer' }),
} })

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
        if InCombatLockdown and InCombatLockdown() then return false, 'Key bindings can\'t change in combat.' end
        local old = GetBindingKey and GetBindingKey(item.id)
        if old then SetBinding(old) end
        if not SetBinding(key, item.id) then return false, 'That key can\'t be bound.' end
        saveBindings()
        HC.Print(item.name .. ' bound to ' .. HC.Bindings.Label(key) .. '.')
        return true
    end
    local current = GetBindingAction and GetBindingAction(key)
    if current and current ~= '' and current ~= item.id then
        return false, HC.Bindings.Label(key) .. ' is bound to ' .. bindingName(current) .. '.', apply
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
    -- Index the shared editor's live tiles and active rows locally. Pooled rows
    -- change after binding/unbinding, so replace our registrations on refresh.
    local indexed = {}
    local function indexBindings()
        local owner = panel.hcHeaderOwner or panel
        for label, row in pairs(indexed) do
            if owner.hcRows and owner.hcRows[label] == row then owner.hcRows[label] = nil end
        end
        indexed = {}
        local function add(widget, label, hint)
            UI.RegisterRow(panel, widget, label)
            if not widget.lfBindingHint then
                UI.AttachHint(widget, label, hint)
                widget.lfBindingHint = true
            else
                widget.hcHintTitle, widget.hcHint = label, hint
            end
            indexed[label] = widget
        end
        local function visit(parent)
            for _, widget in ipairs({ parent:GetChildren() }) do
                if widget.item and widget.item.name and widget:IsShown() then
                    local name = widget.item.name
                    add(widget, (widget.remove and 'Change ' or 'Bind ') .. name,
                        'Keyboard or mouse shortcut. ' .. (widget.item.detail or name))
                    if widget.remove then add(widget.remove, 'Remove ' .. name, 'Unbind this shortcut.') end
                else visit(widget) end
            end
        end
        visit(panel)
    end
    UI.OnRefresh(panel, indexBindings)
    indexBindings()
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
    _, y = UI.PageReset(panel, y, function() ns.db.partyInvites = true end, 'Reset party games')
    return y
end)
