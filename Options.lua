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

-- ── Key Bindings ───────────────────────────────────────────────────────────

-- The four answer keys are Blizzard bindings (Bindings.xml); this page is
-- HammerCore's shared editor over them.
local ANSWERS = {}
for i = 1, 4 do
    ANSWERS[i] = { id = 'LOREFORGE_ANSWER' .. i, name = 'Answer ' .. i,
        icon = 'Interface\\Icons\\INV_Misc_Book_09', detail = 'Picks answer ' .. i .. ' in the game window.' }
end

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
