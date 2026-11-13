package.path = './tests/hammercore/?.lua;' .. package.path
local wow = require('wow')
assert(loadfile('tests/flair-harness.lua'))()(wow)
local function eq(a, b, why) assert(a == b, why .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)) end

local function load(toc)
    wow.Install({ Loreforge = { Version = '1.3.0' } })
    wow.groups = {}
    LoreforgeDB = nil
    GetTime = function() return 100 end
    GetServerTime = function() return 1762740000 end
    date = os.date
    InCombatLockdown = function() return false end
    GetBuildInfo = function() return '', '', '', toc:find('Camelot') and 16001 or 120105 end
    WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
    GetNormalizedRealmName = function() return 'TestRealm' end
    UnitFullName = function(unit) if unit == 'player' then return 'TestPlayer', 'TestRealm' end end
    GetUnitName = function(unit) return (UnitFullName(unit)) end
    UnitGUID = function(unit) return unit .. '-GUID' end
    IsInGroup, IsInRaid, UnitOnTaxi = function() return false end, function() return false end, function() return false end
    GetNumSubgroupMembers = function() return 0 end
    GetNumGroupMembers = function() return 1 end
    RegisterStateDriver, UnregisterStateDriver = function() end, function() end
    assert(loadfile('tests/transport-libs.lua'))()()
    local ns = wow.LoadHammerCore('Libs/HammerCore', 'Loreforge')
    for file in assert(io.open(toc)):read('*a'):gmatch('([^\r\n]+)') do
        if file:match('^[%w]+%.lua$') then assert(loadfile(file))('Loreforge', ns) end
    end
    local loader
    for _, f in ipairs(wow.frames) do if f.scripts.OnEvent then loader = f end end
    loader.scripts.OnEvent(loader, 'ADDON_LOADED', 'Loreforge')
    ns.QuickCard.Show('quick')
    return ns
end

-- Model wrapped text locally; this checks ordering and allocated room, not
-- native WoW font metrics or rendering.
local function measured(fs)
    rawset(fs, 'GetStringHeight', function(self)
        local lines = 0
        local plain = (self:GetText() or ''):gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '')
        for line in (plain .. '\n'):gmatch('(.-)\n') do
            lines = lines + math.max(1, math.ceil(#line * 7 / math.max(1, self:GetWidth())))
        end
        return lines * 16
    end)
end
local function y(region)
    local p = region.points[1]
    return -p[#p]
end
local function below(lower, upper, height, why)
    assert(y(lower) >= y(upper) + (height or upper:GetStringHeight()), why)
end

for _, toc in ipairs({ 'Loreforge.toc', 'Loreforge_Camelot.toc' }) do
    local ns = load(toc)
    local card, f, s = ns.QuickCard, ns.QuickCard.frame, ns.Quick.state
    for _, fs in ipairs({ f.question, f.feedback, f.footer, f.heading, f.clock, f.streak,
        f.overTitle, f.overLines, f.overNote, f.feedbackProbe, f.timeoutProbe, f.quip }) do measured(fs) end
    for _, b in ipairs(f.answers) do measured(b.Text) end
    local q = s.question
    q.text = string.rep('A long but readable Warcraft question. ', 8)
    q.categoryLabel = string.rep('Long category ', 6)
    for i = 1, 4 do q.choices[i] = string.rep('Answer ' .. i .. ' with more detail. ', 4) end
    local deadline = s.questionDeadline
    for _, size in ipairs({ 'SMALL', 'MEDIUM', 'LARGE' }) do
        for _, art in ipairs({ true, false }) do
            ns.db.qpSize, ns.db.qpArt = size, art
            card.Render()
            eq(s.questionDeadline, deadline, 'layout leaves the deadline unchanged')
            if not art then below(f.clock, f.heading, nil, 'category clears clock without artwork') end
            below(f.question, f.clock, nil, 'question clears clock')
            below(f.answers[1], f.question, nil, 'answers clear the whole question')
            eq(y(f.answers[1]), y(f.answers[2]), 'first answer row is aligned')
            eq(f.answers[1]:GetHeight(), f.answers[2]:GetHeight(), 'first row shares height')
            below(f.answers[3], f.answers[1], f.answers[1]:GetHeight(), 'rows do not overlap')
            below(f.feedback, f.answers[3], f.answers[3]:GetHeight(), 'feedback clears answers')
            below(f.footer, f.feedback, nil, 'footer clears feedback')
            below(f.timer, f.clock, nil, 'timer follows clock')
            below(f.question, f.timer, f.timer:GetHeight(), 'question clears timer')
            assert(f.body:GetHeight() >= y(f.footer) + f.footer:GetStringHeight(), 'all question content fits body')
            eq(f.art:GetWidth(), 250, 'painting remains square at every card size')
            eq(f.art:GetHeight(), 250, 'painting remains square')
        end
    end
    ns.db.qpAutoNext = false
    ns.Quick.Answer(q.correct % 4 + 1)
    card.Render()
    assert(f.feedback:GetText():find(q.choices[q.correct], 1, true), 'full answer retained in feedback')
    below(f.footer, f.feedback, nil, 'manual Next reveal reserves every feedback line')
    assert(f.feedback:GetWidth() < 348 and f.next:IsShown(), 'manual Next retains its own space')

    -- Summary content and its actions reserve space before the best-score footer.
    s.phase = 'over'
    s.summary = { kind = 'streak', title = 'A new personal best', newBest = true,
        lines = { '12 correct answers', '12 in a row' }, note = 'It was ' .. q.choices[q.correct] .. '.' }
    ns.db.qpAnimations, ns.db.livelyAnimations = true, true
    card.Render()
    below(f.overLines, f.overTitle, nil, 'summary title clears score')
    below(f.overNote, f.overLines, nil, 'score clears full answer note')
    below(f.primary, f.overNote, nil, 'summary actions clear note')
    below(f.footer, f.primary, f.primary:GetHeight(), 'footer clears summary actions')
    assert(f.body:GetHeight() >= y(f.footer) + f.footer:GetStringHeight(), 'summary fits body')
    local bounce = assert(f.overTitle.lfBounce, 'personal best animates')
    local plays = bounce.plays
    card.Render(); card.Render()
    eq(bounce.plays, plays, 'redrawing a personal best never restarts its celebration')
    eq(bounce.playing, true, 'bounce started')
    ns.db.qpAnimations = false
    card.Layout()
    eq(bounce.playing, false, 'disabling card animations stops active celebration')

    -- A hidden render must not consume a best that the player hasn't seen.
    card.OnCombat('PLAYER_REGEN_DISABLED')
    s.summary = { kind = 'streak', title = 'Another best', newBest = true, lines = { '13 correct' }, note = '' }
    ns.db.qpAnimations = true
    local hiddenSummary = s.summary
    local previousPlays = bounce.plays
    card.Render()
    assert(f.celebratedSummary ~= hiddenSummary, 'hidden summary is not consumed')
    eq(bounce.plays, previousPlays, 'hidden render starts no celebration')
    card.OnCombat('PLAYER_REGEN_ENABLED')
    eq(f.celebratedSummary, hiddenSummary, 'showing the summary celebrates it')
    eq(bounce.plays, previousPlays + 1, 'new visible best celebrates exactly once')

    -- An active painting fade settles immediately when disabled or hidden,
    -- including a combat hide which must preserve the live quiz.
    s.phase = 'question'
    s.summary = nil
    ns.db.qpAnimations = true
    q.category = 'goblins'
    card.Render()
    assert(f.fading ~= nil, 'changing category starts painting fade')
    ns.db.qpAnimations = false
    card.Update(0)
    eq(f.fading, nil, 'disabling animations settles art fade')
    eq(f.art.texture, f.artPath, 'settled art is current category')
    ns.db.qpAnimations = true
    q.category = 'lore'
    card.Render()
    assert(f.fading ~= nil, 'second fade starts')
    ns.Flair.BounceIn(f, f.overTitle)
    card.OnCombat('PLAYER_REGEN_DISABLED')
    eq(f.fading, nil, 'combat hide settles fade')
    eq(bounce.playing, false, 'combat hide stops celebration')
    eq(ns.Quick.state, s, 'combat hide preserves quiz')
    card.OnCombat('PLAYER_REGEN_ENABLED')
    eq(f:IsShown(), true, 'combat restore remains available')

    card.SetRelaxed(true)
    eq(ns.db.qpRelaxed, true, 'shared Timer setter changes saved preference')
    eq(s.questionDeadline, nil, 'shared Timer setter preserves existing relaxed switch behavior')
    card.SetRelaxed(false)
    eq(ns.db.qpRelaxed, false, 'shared setter restores clock preference')

    card.ToggleOptions()
    local o = card.options
    rawset(UIParent, 'GetWidth', function() return 1920 end)
    rawset(f, 'GetRight', function() return 1800 end)
    rawset(f, 'GetEffectiveScale', function() return 1 end)
    card.PlaceOptions()
    eq(o.points[1][1], 'TOPRIGHT', 'Options opens left at right screen edge')
    rawset(f, 'GetRight', function() return 700 end)
    card.PlaceOptions()
    eq(o.points[1][1], 'TOPLEFT', 'Options opens right when it fits')
    rawset(f, 'GetEffectiveScale', function() return 2 end)
    rawset(o, 'GetEffectiveScale', function() return 2 end)
    rawset(f, 'GetRight', function() return 800 end)
    card.PlaceOptions()
    eq(o.points[1][1], 'TOPRIGHT', 'Options edge calculation respects effective scale')
    rawset(f, 'GetEffectiveScale', function() return 1 end)
    rawset(o, 'GetEffectiveScale', function() return 1 end)
    card.ToggleOptions() -- close
    rawset(f, 'GetRight', function() return 1800 end)
    card.ToggleOptions() -- reopen after moving
    eq(o.points[1][1], 'TOPRIGHT', 'reopening Options recomputes the side')
    rawset(f, 'GetRight', function() return 700 end)
    f.hcMoving = true
    f.header.scripts.OnDragStop(f.header)
    eq(o.points[1][1], 'TOPLEFT', 'dragging recomputes Options placement')
    ns.Flair.BounceIn(f, f.overTitle)
    card.Hide()
    eq(bounce.playing, false, 'closing card stops effects')
    eq(o:IsShown(), false, 'closing card hides Options')
end
-- Ordinary question lengths retain fixed click targets; overflow still grows.
for _, toc in ipairs({ 'Loreforge.toc', 'Loreforge_Camelot.toc' }) do
    local ns = load(toc)
    local card, f = ns.QuickCard, ns.QuickCard.frame
    local s = ns.Quick.state
    for _, fs in ipairs({ f.question, f.feedback, f.feedbackProbe, f.timeoutProbe, f.quip, f.clock, f.streak, f.footer }) do measured(fs) end
    for _, b in ipairs(f.answers) do measured(b.Text) end
    local q, deadline = s.question, s.questionDeadline
    q.correct = 1
    local baselineY, baselineHeight
    for _, count in ipairs({ 10, 60, 110 }) do
        q.text = string.rep('a', count)
        for i = 1, 4 do q.choices[i] = string.rep('b', count == 110 and 30 or 10) end
        card.Render()
        baselineY, baselineHeight = baselineY or y(f.answers[1]), baselineHeight or f:GetHeight()
        eq(y(f.answers[1]), baselineY, 'one to three question lines keep answer targets stable')
        eq(f:GetHeight(), baselineHeight, 'ordinary answer wraps keep card height stable')
    end
    ns.db.livelyAnimations = false
    wow.Click(f.answers[1])
    eq(f:GetHeight(), baselineHeight, 'reveal uses its reserved reading space')
    eq(s.questionDeadline, deadline, 'effects and reveal layout do not restart timer')
    assert(f.answers[1].lfPop and f.answers[1].lfPop.playing, 'card click pops independently of Interface animations')
    assert(f.lfSparkle and f.lfSparkle.groups[1].playing, 'correct card answer sparkles')
    assert(f.answers[1].num:GetText():find('ReadyCheck-Ready', 1, true), 'correct answer has a tick')
    eq(f.quip:GetText(), '', 'default skips first quip')
    local plays = f.lfSparkle.groups[1].plays
    card.Render()
    eq(f.lfSparkle.groups[1].plays, plays, 'same reveal never repeats effect')
    ns.Quick.Next(); ns.Quick.Answer(ns.Quick.state.question.correct)
    eq(f.quip:GetText(), '', 'default skips second quip')
    ns.Quick.Next(); ns.Quick.Answer(ns.Quick.state.question.correct)
    assert(f.quip:GetText() ~= '', 'default includes every third quip')
    ns.db.qpBanterEvery = 0
    card.Render(); eq(f.quip:GetText(), '', 'zero disables card quips')
    ns.db.qpBanterEvery = 1
    card.Render(); assert(f.quip:GetText() ~= '', 'frequency can show every quip')
    ns.db.qpBanterEvery = 3
    for streak = 4, 10 do
        ns.Quick.Next(); ns.Quick.Answer(ns.Quick.state.question.correct)
        if streak == 5 or streak == 10 then
            assert(f.quip:GetText():find(tostring(streak) .. ' in a row!', 1, true), 'milestone bypasses ordinary cadence')
            ns.db.qpBanterEvery = 0
            card.Render(); eq(f.quip:GetText(), '', 'Off suppresses milestones too')
            ns.db.qpBanterEvery = 3
        elseif streak == 4 then eq(f.quip:GetText(), '', 'ordinary answers still follow cadence') end
    end
    ns.Quick.Next()
    local wrong = ns.Quick.state.question.correct % 4 + 1
    wow.Click(f.answers[wrong])
    assert(f.answers[wrong].lfShake and f.answers[wrong].lfShake.playing, 'wrong card answer shakes')
    assert(f.answers[wrong].num:GetText():find('ReadyCheck-NotReady', 1, true), 'wrong answer has a cross')
    ns.db.qpAnimations = false
    card.Layout()
    for _, group in ipairs(f.lfGroups or {}) do eq(group.playing, false, 'card switch stops all effects') end
    ns.db.livelyAnimations = true
    ns.Quick.Next(); wow.Click(f.answers[ns.Quick.state.question.correct])
    for _, group in ipairs(f.lfGroups or {}) do eq(group.playing, false, 'Interface switch never overrides card off') end
    ns.db.qpAnimations = true
    card.Show('lightning')
    ns.Quick.Answer(ns.Quick.state.question.correct)
    eq(f.quip:GetText(), '', 'Lightning never shows a quip')
    ns.Quick.state.streak, ns.Quick.state.answered = 5, 5
    card.Render()
    eq(f.quip:GetText(), '', 'Lightning suppresses milestone quips too')
    card.Show('quick')
    ns.Quick.state.questionDeadline = 104
    card.Update(0)
    assert(f.timer.fill.lfPulsing, 'last five seconds pulse')
    card.Hide()
    for _, group in ipairs(f.lfGroups or {}) do eq(group.playing, false, 'hiding stops all card effects') end
    card.Show('quick')
    ns.Quick.state.phase, ns.Quick.state.summary = 'over', { kind = 'empty', title = 'No questions', lines = {} }
    card.Render()
    eq(f.primary:GetText(), 'Categories & difficulty', 'empty pool offers a way to fix it')
    eq(f.secondary:GetText(), 'Close', 'empty pool can be closed')
    for _, streak in ipairs({ 3, 5, 10, 15, 20 }) do eq(ns.Flair.RevealBucket(1, 1, streak), 'streak', 'milestone quip') end
    for _, streak in ipairs({ 4, 6, 9, 11 }) do eq(ns.Flair.RevealBucket(1, 1, streak), 'correct', 'ordinary quip between milestones') end
end
io.write('test_quick_card_layout: ok\n')
