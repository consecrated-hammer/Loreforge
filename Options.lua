local _, ns = ...
local HC, UI = ns.HammerCore, ns.HammerCore.UI

function ns.ConfirmClearRecords()
    if ns.game:Active() then HC.Print('Stop or finish the game before clearing player records.'); return end
    local key = 'LOREFORGE_CLEAR_RECORDS'
    StaticPopupDialogs[key] = {
        text = 'Clear all Loreforge player records for ' .. (ns.era == 'classic' and 'WoW Forever' or 'Retail') .. '? This cannot be undone.',
        button1 = 'Clear records', button2 = 'Cancel', timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        OnAccept = function()
            if ns.game:Active() then HC.Print('Stop or finish the game before clearing player records.'); return end
            for key in pairs(ns.db.records[ns.era]) do ns.db.records[ns.era][key] = nil end
            HC.Print('Player records cleared for this client.')
        end,
    }
    StaticPopup_Show(key)
end

HC.Settings:NewPage({ name = 'Player records', description = 'General record management. Set up games in Host game.' }, function(panel, y)
    _, y = UI.Header(panel, 'Player records', y)
    _, y = UI.Text(panel, 'Completed games save games, wins, correct answers, attempts and best streaks.', y)
    _, y = UI.Text(panel, 'Records are shared by host characters on this account, separately for each client.', y)
    _, y = UI.Text(panel, 'Reset settings keeps records. Clearing records requires a separate confirmation.', y)
    local row
    row, y = UI.Card(panel, y, 40)
    local show = UI.Button(row, 180, 24)
    show:SetPoint('LEFT', 8, 0); show:SetText('View / copy records'); show:SetScript('OnClick', ns.ShowRecords)
    local clear = UI.Button(row, 180, 24, 'danger')
    clear:SetPoint('LEFT', 208, 0); clear:SetText('Clear player records'); clear:SetScript('OnClick', ns.ConfirmClearRecords)
    return y
end)

HC.Settings:NewPage({name='Party player',description='Optional Party match invitations and saved matches.'},function(panel,y)
    _,y=UI.Header(panel,'Party invitations',y)
    _,y=UI.Check(panel,'Show Party match invitations','Ask before joining another player\'s match. Party UI is beta and currently limited to Retail outside instances.',y,
        function() return ns.db.partyInvites ~= false end,function(value) ns.db.partyInvites=value end)
    _,y=UI.Text(panel,'Joining enables clickable questions and sends your answers to the host. Party messages can be read by other addons in the group.',y)
    local row
    row,y=UI.Card(panel,y,40)
    local history=UI.Button(row,180,24)
    history:SetPoint('LEFT',8,0);history:SetText('Saved matches');history:SetScript('OnClick',function() if ns.Party then ns.Party.ShowHistory() end end)
    return y
end)
