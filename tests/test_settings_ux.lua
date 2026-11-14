package.path = './tests/hammercore/?.lua;' .. package.path
local wow = require('wow')
local function eq(a, b, why) assert(a == b, why .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)) end

local function load(era)
    wow.Install({ Loreforge = { Version = '1.3.0' } })
    LoreforgeDB = nil
    -- GetChildren is intentionally minimal in HammerCore's stand-in; model it
    -- here to exercise custom binding tile registration without editing it.
    local createFrame = CreateFrame
    CreateFrame = function(...)
        local f = createFrame(...)
        f.SetScale = function(self, value) self.testScale = value end
        f.GetScale = function(self) return self.testScale or 1 end
        f.GetChildren = function(self)
            local children = {}
            for _, child in ipairs(wow.frames) do if child:GetParent() == self then children[#children + 1] = child end end
            return unpack(children)
        end
        return f
    end
    local bindings = {}
    GetBindingKey = function(id) return bindings[id] end
    SetBinding = function(key, id)
        if id then bindings[id] = key else
            for action, bound in pairs(bindings) do if bound == key then bindings[action] = nil end end
        end
        return true
    end

    GetTime = function() return 100 end
    GetServerTime = function() return 1800000000 end
    InCombatLockdown = function() return false end
    GetBuildInfo = function() return '', '', '', era == 'classic' and 16001 or 120105 end
    WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
    GetNormalizedRealmName = function() return 'Realm' end
    UnitFullName = function(unit) if unit == 'player' then return 'Tester', 'Realm' end end
    GetUnitName = function(unit) return (UnitFullName(unit)) end
    UnitGUID = function(unit) return unit == 'player' and 'testGUID' end
    IsInGroup, IsInRaid, IsInInstance, UnitOnTaxi = function() return false end, function() return false end, function() return false end, function() return false end
    GetNumSubgroupMembers = function() return 0 end
    RegisterStateDriver, UnregisterStateDriver = function() end, function() end
    assert(loadfile('tests/transport-libs.lua'))()()
    local ns = wow.LoadHammerCore('Libs/HammerCore', 'Loreforge')
    -- Detect overwritten labels before they disappear from the search index.
    local UI = ns.HammerCore.UI
    local register = UI.RegisterRow
    UI.RegisterRow = function(parent, row, label)
        local name = type(label) == 'function' and label() or label
        local owner = parent.hcHeaderOwner or parent
        assert(not owner.hcRows or not owner.hcRows[name] or owner.hcRows[name] == row, 'duplicate settings label: ' .. tostring(name))
        return register(parent, row, label)
    end
    local toc = era == 'classic' and 'Loreforge_Camelot.toc' or 'Loreforge.toc'
    for file in assert(io.open(toc)):read('*a'):gmatch('[^\r\n]+') do
        if file:match('^[%w]+%.lua$') then assert(loadfile(file))('Loreforge', ns) end
    end
    local loader
    for _, f in ipairs(wow.frames) do if f.scripts.OnEvent then loader = f end end
    loader.scripts.OnEvent(loader, 'ADDON_LOADED', 'Loreforge')
    ns.HammerCore.Settings:Show()
    return ns, bindings
end

for _, era in ipairs({ 'retail', 'classic' }) do
    local ns, bindings = load(era)
    local S = ns.HammerCore.Settings
    local function rows(page, tab) return S.pages[page].bodies[tab].hcRows end
    local interface = rows('Interface', 'Presentation')
    assert(interface['Animations'] and interface['Artwork'] and interface['Sound cues'])
    assert(rows('Interface', 'Windows')['Player window'])
    for _, tab in ipairs({ 'Play', 'Card', 'Flights', 'Daily question' }) do assert(S.pages['Quick play'].bodies[tab]) end
    -- Every registered control can be found and focused, across all tabs and pages.
    local checked = 0
    for pageName, page in pairs(S.pages) do
        for tab, body in pairs(page.bodies or {}) do
            for label in pairs(body.hcRows or {}) do
                local match
                for _, item in ipairs(S:Search(label, 1000)) do
                    if item.page == pageName and item.tab == tab and item.label == label then match = item end
                end
                assert(match, era .. ': unreachable search control ' .. pageName .. '/' .. tab .. '/' .. label)
                assert(S:Focus(pageName, label, tab), era .. ': cannot focus ' .. label)
                checked = checked + 1
            end
        end
    end
    assert(checked >= 50, 'settings inventory unexpectedly small')
    local play, flights, daily = rows('Quick play', 'Play'), rows('Quick play', 'Flights'), rows('Quick play', 'Daily question')
    local bookPoint = { 'CENTER', 'CENTER', 33, -44 }
    ns.db.qpFlightBookPoint = bookPoint
    assert(flights['Reset flight book position'], 'flight book reset is registered for search')
    wow.Click(flights['Reset flight book position'])
    eq(ns.db.qpFlightBookPoint, nil, 'flight book reset clears saved point')

    ns.db.qpRelaxed, ns.db.qpAutoNext, ns.db.qpOnFlights, ns.db.dailyOn = true, false, 'OFFER', false
    S:Show('Quick play', 'Play')
    assert(not play['Seconds per question']:IsShown() and not play['Wait before next']:IsShown())
    eq(S:Focus('Quick play', 'Seconds per question', 'Play'), play.Timer, 'hidden timer search focuses enabling control')
    eq(S:Focus('Quick play', 'Wait before next', 'Play'), play['Next question automatically'], 'hidden next delay focuses switch')
    eq(S:Focus('Quick play', 'Shortest flight', 'Flights'), flights['On flights'], 'hidden shortest flight stays discoverable')
    eq(S:Focus('Quick play', 'Offer at login', 'Daily question'), daily['Daily question'], 'hidden daily offer stays discoverable')
    eq(flights['Loremaster lines'] ~= nil, era == 'retail', 'Loremaster control remains Retail only')
    -- Settings and card share the same timer setter; no restart or invented deadline.
    ns.QuickCard.Show('quick')
    ns.db.qpRelaxed = false
    ns.Quick.state.questionDeadline = 120
    local calls, setRelaxed = 0, ns.QuickCard.SetRelaxed
    ns.QuickCard.SetRelaxed = function(value) calls = calls + 1; return setRelaxed(value) end
    S:Show('Quick play', 'Play')
    -- Select Relaxed from the Timer dropdown through its real menu.
    local timerButton
    for _, child in ipairs(wow.frames) do if child:GetParent() == play.Timer and child.scripts.OnClick then timerButton = child; break end end
    assert(timerButton, 'Timer dropdown button')
    wow.Click(timerButton)
    local picked
    for _, f in ipairs(wow.frames) do
        if f.label and f.label:GetText() == 'Relaxed' and f.scripts.OnClick and f:IsShown() then wow.Click(f); picked = true; break end
    end
    assert(picked and calls == 1, 'settings Timer uses the card setter')
    eq(ns.Quick.state.questionDeadline, nil, 'Relaxed clears existing per-question deadline consistently')
    -- Binding search follows the live pool and clears removed active rows.
    S:Show('Key Bindings')
    local bindingRows = rows('Key Bindings', 'Key Bindings')
    assert(bindingRows['Bind: Answer 1'] and bindingRows['Bind: Quick play'], 'all binding tiles searchable')
    eq(bindingRows['Bind: Answer 1'].lfAnswerNumber:GetText(), '1', 'answer tiles show their number')
    local function searchCount(term)
        local count, seen = 0, {}
        for _, match in ipairs(S:Search(term, 100)) do
            if match.page == 'Key Bindings' then
                local row = bindingRows[match.label]
                assert(row and not seen[row], 'binding search registers each widget once')
                seen[row] = true
                count = count + 1
            end
        end
        return count
    end
    eq(searchCount('Answer 1'), 1, 'one unbound answer search result')
    -- A tile reused for another action restores its icon and clears stale search.
    local answerTile = bindingRows['Bind: Answer 1']
    local item, id, name = answerTile.item, answerTile.item.id, answerTile.item.name
    item.id, item.name = 'LOREFORGE_TEST_SLOT', 'Temporary action'
    S:Show('Key Bindings')
    assert(not answerTile.lfAnswerNumber:IsShown() and answerTile.icon:IsShown(), 'reused non-answer tile restores icon')
    assert(not bindingRows['Bind: Answer 1'], 'renamed item leaves no stale registration')
    eq(searchCount('Temporary action'), 1, 'reused tile has one current search entry')
    item.id, item.name = id, name
    S:Show('Key Bindings')
    assert(answerTile.lfAnswerNumber:IsShown() and not answerTile.icon:IsShown(), 'answer decoration returns without overlap')
    eq(searchCount('Temporary action'), 0, 'removed action is absent from search')
    local originalEnter = bindingRows['Bind: Answer 1'].scripts.OnEnter
    S:Show('Key Bindings'); S:Show('Key Bindings')
    eq(bindingRows['Bind: Answer 1'].scripts.OnEnter, originalEnter, 'refresh does not accumulate tooltip hooks')
    bindings.LOREFORGE_ANSWER1 = 'F9'
    S:Show('Key Bindings')
    assert(bindingRows['Change binding: Answer 1'] and bindingRows['Remove binding: Answer 1'], 'active binding actions searchable')
    eq(searchCount('Answer 1'), 3, 'one result per bind/change/remove action')
    wow.Click(bindingRows['Remove binding: Answer 1'])
    assert(not bindingRows['Change binding: Answer 1'] and not bindingRows['Remove binding: Answer 1'], 'removed binding registrations cleared')
    eq(searchCount('Answer 1'), 1, 'unbinding removes active search actions')
    assert(S:Focus('Key Bindings', 'Bind: Answer 1'), 'pool tile remains reachable after unbinding')
    -- A conflicting key stays unchanged until explicit Replace, including
    -- combat beginning while the confirmation prompt is open.
    bindings.SYNTHETIC_ACTION = 'F10'
    GetBindingAction = function(key)
        for action, bound in pairs(bindings) do if bound == key then return action end end
        return ''
    end
    wow.Click(bindingRows['Bind: Answer 1'])
    local capture = ns.HammerCore.Bindings.Capture
    local problem, replace = capture.spec.onKey('F10')
    assert(problem and replace, 'conflict offers explicit replacement')
    eq(bindings.SYNTHETIC_ACTION, 'F10', 'conflict does not change the existing action')
    InCombatLockdown = function() return true end
    assert(replace(), 'replacement refuses after combat begins')
    eq(bindings.LOREFORGE_ANSWER1, nil, 'combat refusal does not bind')
    InCombatLockdown = function() return false end
    eq(replace(), nil, 'explicit replacement succeeds outside combat')
    eq(bindings.LOREFORGE_ANSWER1, 'F10', 'confirmed key is bound')
    capture:Stop()
    for _, scale in ipairs({ 0.7, 1, 1.3 }) do
        ns.HammerCore.State().settingsScale = scale
        S:ApplyScale()
        eq(S.window:GetScale(), scale, 'settings scale applies')
    end
    ns.OpenHost()
    ns.Player.Render({ id = 'scale-fixture', state = 'invitation', host = 'TestHost-Realm', joined = false, rows = {},
        config = { rounds = 1, perRound = 5, seconds = 20, categories = 'Lore', difficulty = 'mixed' } })
    for _, scale in ipairs({ 0.7, 1, 1.5 }) do
        ns.db.hostScale, ns.db.playerScale = scale, scale
        ns.ApplyHostScale(); ns.Player.Initialise(); ns.Player.ApplyScale()
        eq(ns.hostFrame:GetScale(), scale, 'host scale applies')
        eq(ns.Player.frame:GetScale(), scale, 'player scale applies')
    end
    -- Changing one tab's defaults must preserve the other tabs and all records.
    local records, matches, dailyStore = ns.db.records, ns.db.matches, ns.db.daily
    ns.db.qpSize, ns.db.qpOnFlights, ns.db.qpSeconds = 'LARGE', 'NONE', 29
    S:Show('Quick play', 'Card')
    assert(rows('Quick play', 'Card')['Banter frequency'], 'banter frequency is searchable')
    local frequencyRow = rows('Quick play', 'Card')['Banter frequency']
    local frequencyButton
    for _, frame in ipairs(wow.frames) do
        if frame:GetParent() == frequencyRow and frame.scripts.OnClick then frequencyButton = frame; break end
    end
    local beforeMenu = #wow.frames
    wow.Click(assert(frequencyButton))
    local labels, randomOption = {}, nil
    for index = beforeMenu + 1, #wow.frames do
        local frame = wow.frames[index]
        if frame.label and frame.scripts.OnClick then
            labels[#labels + 1] = frame.label:GetText()
            if frame.label:GetText() == 'Random' then randomOption = frame end
        end
    end
    eq(table.concat(labels, '|'), 'Off|Every answer|Random', 'banter offers exactly the requested choices')
    wow.Click(assert(randomOption))
    eq(ns.db.qpBanterEvery, -1, 'Random preserves a numeric saved preference')

    ns.db.qpBanterEvery = 1
    ns.db.qpFlightBookPoint = bookPoint
    local reset = rows('Quick play', 'Card')['Reset card']
    assert(reset, 'tab reset is searchable')
    wow.Click(reset)
    eq(ns.db.qpSize, 'LARGE', 'Card reset waits for confirmation')
    wow.Click(ns.HammerCore.Dialog.frame.cancel)
    eq(ns.db.qpSize, 'LARGE', 'cancel keeps card preferences')
    wow.Click(reset)
    wow.Click(ns.HammerCore.Dialog.frame.accept)
    eq(ns.db.qpSize, ns.Quick.DEFAULTS.qpSize, 'Card reset restores card size')
    eq(ns.db.qpBanterEvery, -1, 'Card reset restores Random banter')
    eq(ns.db.qpOnFlights, 'NONE', 'Card reset preserves flight preference')
    eq(ns.db.qpFlightBookPoint, bookPoint, 'Card reset preserves book position')
    S:Show('Quick play', 'Flights')
    wow.Click(flights['Reset flights'])
    wow.Click(ns.HammerCore.Dialog.frame.accept)
    eq(ns.db.qpFlightBookPoint, nil, 'Flights reset also resets book position')
    eq(ns.db.qpSeconds, 29, 'Card reset preserves play timing')
    eq(ns.db.records, records, 'Card reset preserves records')
    eq(ns.db.matches, matches, 'Card reset preserves history')
    eq(ns.db.daily, dailyStore, 'Card reset preserves daily attempts')
    ns.db.qpMode = 'lightning'
    S:Show('Quick play', 'Play')
    wow.Click(rows('Quick play', 'Play')['Reset play'])
    eq(ns.db.qpMode, 'lightning', 'Play reset waits for confirmation')
    wow.Click(ns.HammerCore.Dialog.frame.accept)
    eq(ns.db.qpMode, 'quick', 'Play reset includes the saved solo mode')
    assert(S.pages['Games and records'] and not S.pages['Player records'] and not S.pages['Party games'], 'records and invitations share one page')
    ns.db.partyInvites = false
    S:Show('Games and records')
    wow.Click(rows('Games and records', 'Games and records')['Reset party games'])
    eq(ns.db.partyInvites, false, 'invitation reset waits for confirmation')
    wow.Click(ns.HammerCore.Dialog.frame.accept)
    eq(ns.db.partyInvites, true, 'invitation reset restores only its own preference')
    eq(ns.db.records, records, 'merged-page reset preserves records')
    eq(ns.db.matches, matches, 'merged-page reset preserves history')
    eq(ns.db.daily, dailyStore, 'merged-page reset preserves daily data')

end
io.write('test_settings_ux: ok\n')
