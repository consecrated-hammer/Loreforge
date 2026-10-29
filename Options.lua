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

HC.Settings:NewPage({ name = 'Interface', description = 'Sound and window size. Set up games in the main window.' }, function(panel, y)
    _, y = UI.Header(panel, 'Interface', y)
    _, y = UI.Check(panel, 'Sound cues', 'Invitations, new questions, the last five seconds, results and the finish.', y,
        function() return ns.db.sound ~= false end, function(value) ns.db.sound = value end)
    _, y = UI.Slider(panel, 'Main window size', 'Scales the host window.', y, 0.7, 1.5, 0.05,
        function() return ns.db.hostScale or 1 end, function(value) ns.db.hostScale = value; ns.ApplyHostScale() end, scale)
    _, y = UI.Slider(panel, 'Player window size', 'Scales the window you answer in when you join a Party game.', y, 0.7, 1.5, 0.05,
        function() return ns.db.playerScale or 1 end,
        function(value) ns.db.playerScale = value; if ns.Player then ns.Player.ApplyScale() end end, scale)
    _, y = UI.Text(panel, 'Answer keys: set Answer 1 to 4 under Key Bindings > AddOns > Loreforge.', y)
    return y
end)

HC.Settings:NewPage({ name = 'Player records', description = 'The Hall of Fame tab in the main window shows these.' }, function(panel, y)
    _, y = UI.Header(panel, 'Player records', y)
    _, y = UI.Text(panel, 'Games you host save each player\'s games, wins, correct answers and best streak.', y)
    _, y = UI.Text(panel, 'Records are shared by your characters on this account, separately for each client.', y)
    _, y = UI.Text(panel, 'Reset settings keeps records. Clearing them asks first.', y)
    local row
    row, y = UI.Card(panel, y, 40)
    local show = UI.Button(row, 180, 24)
    show:SetPoint('LEFT', 8, 0); show:SetText('Open Hall of Fame')
    show:SetScript('OnClick', function() HC.Settings:Hide(); ns.OpenHost('records') end)
    local clear = UI.Button(row, 180, 24, 'danger')
    clear:SetPoint('LEFT', 208, 0); clear:SetText('Clear player records'); clear:SetScript('OnClick', ns.ConfirmClearRecords)
    return y
end)

HC.Settings:NewPage({ name = 'Party games', description = 'Invitations to other hosts\' Party games.' }, function(panel, y)
    _, y = UI.Header(panel, 'Party invitations', y)
    _, y = UI.Check(panel, 'Show Party game invitations', 'Ask before joining another player\'s game. Party games work in Retail, outside instances.', y,
        function() return ns.db.partyInvites ~= false end, function(value) ns.db.partyInvites = value end)
    _, y = UI.Text(panel, 'Joining gives you clickable questions and sends your answers to the host. Other addons in the group can read Party addon messages.', y)
    local row
    row, y = UI.Card(panel, y, 40)
    local history = UI.Button(row, 180, 24)
    history:SetPoint('LEFT', 8, 0); history:SetText('Open History')
    history:SetScript('OnClick', function() HC.Settings:Hide(); ns.OpenHost('history') end)
    return y
end)
