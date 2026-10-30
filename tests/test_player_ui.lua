package.path = './tests/hammercore/?.lua;' .. package.path
local wow = require('wow')
local function eq(a, b, why) assert(a == b, why .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)) end

wow.Install({ Loreforge = { Version = '0.1.1' } })
LoreforgeDB = nil
local now, combat = 100, false
GetTime = function() return now end
InCombatLockdown = function() return combat end
GetBuildInfo = function() return '', '', '', 120105 end
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
GetNormalizedRealmName = function() return 'Realm' end
UnitFullName = function(unit) if unit == 'player' then return 'Guest', 'Realm' end end
UnitGUID = function(unit) return unit .. '-GUID' end
IsInGroup = function(category) return category == 1 end
IsInRaid = function() return false end
GetNumSubgroupMembers = function() return 1 end
GetNumGroupMembers = function() return 2 end
RegisterStateDriver, UnregisterStateDriver = function() end, function() end

-- Record any attempt to take keyboard focus from the player.
local focus = 0
local createFrame = CreateFrame
CreateFrame = function(...)
    local frame = createFrame(...)
    assert(frame.kind ~= 'EditBox', 'the player window creates no edit boxes')
    rawset(frame, 'EnableKeyboard', function(_, on) if on then focus = focus + 1 end end)
    rawset(frame, 'SetFocus', function() focus = focus + 1 end)
    return frame
end

assert(loadfile('tests/transport-libs.lua'))()()
local ns = wow.LoadHammerCore('Libs/HammerCore', 'Loreforge')
for _, file in ipairs({ 'Transport.lua', 'Codec.lua', 'PartyBus.lua', 'Game.lua', 'Core.lua', 'Setup.lua','History.lua', 'Host.lua', 'Options.lua', 'Party.lua', 'Probe.lua', 'Player.lua' }) do
    assert(loadfile(file))('Loreforge', ns)
end
local loader
for _, f in ipairs(wow.frames) do if f.scripts.OnEvent then loader = f end end
loader.scripts.OnEvent(loader, 'ADDON_LOADED', 'Loreforge')
ns.Restricted = function() return combat end

local P = ns.Player
assert(type(P.Render) == 'function' and type(P.Show) == 'function' and type(P.Hide) == 'function', 'contract API')
eq(P.frame, nil, 'the window is built lazily')
P.Initialise()

local calls = {}
local function record(name) return function(...) calls[#calls + 1] = { name, ... } end end
ns.Party = {}
for _, name in ipairs({ 'Join', 'Decline', 'Ready', 'Answer', 'RetryAnswer', 'Leave', 'RequestSync', 'ShowHistory', 'OpenHistory' }) do
    ns.Party[name] = record(name)
end
local function last() return calls[#calls] or {} end

local config = { rounds = 2, perRound = 3, seconds = 20, difficulty = 'mixed', categories = 'Lore, Murlocs', readyCheck = true }
local rows = {
    { key = 'host-realm', name = 'Host-Realm', total = 0, round = 0, streak = 0, rank = 1 },
    { key = 'guest-realm', name = 'Guest-Realm', total = 0, round = 0, streak = 0, rank = 1 },
    { key = 'chatonly-realm', name = 'Chatonly-Realm', total = 0, round = 0, streak = 0, rank = 1 },
}
local function model(state, extra)
    local m = { id = 'game-1', state = state, host = 'Host-Realm', config = config, joined = true, me = 'guest-realm', rows = rows }
    for k, v in pairs(extra or {}) do m[k] = v end
    return m
end
local function question(extra)
    local m = model('accepting', { index = 1, round = 1, totalQuestions = 6, attempt = 1,
        question = 'Who rules Quel\'Thalas?', choices = { 'Anasterian', 'Kael', 'Lor\'themar', 'Sylvanas' },
        deadline = now + 20, answeredCount = 0 })
    for k, v in pairs(extra or {}) do m[k] = v end
    return m
end
local f

-- Invitation: shown once per session, non-modal, Join and Not now.
P.Render(model('invitation', { joined = false }))
f = P.frame
assert(f and f:IsShown(), 'an invitation opens the window')
eq(f.primary:GetText(), 'Join quiz', 'invitation offers Join quiz')
eq(f.secondary:GetText(), 'Decline', 'invitation offers Decline')
assert(not f.leave:IsShown(), 'Leave is not offered before joining')
assert(f.detail:GetText():find('2 rounds of 3 questions', 1, true), 'invitation shows the game length')
assert(f.detail:GetText():find('20s to answer', 1, true), 'invitation shows the answer time')
wow.Click(f.secondary)
eq(last()[1], 'Decline', 'Decline declines')
assert(not f:IsShown(), 'Decline closes the invitation')
for _ = 1, 5 do P.Render(model('invitation', { joined = false })) end
assert(not f:IsShown(), 'a declined invitation never reopens on later renders')

-- A new invitation in combat waits until combat ends.
combat = true
P.Render(model('invitation', { id = 'game-2', joined = false }))
assert(not f:IsShown(), 'an invitation is deferred during combat')
combat = false
P.events.scripts.OnEvent(P.events, 'PLAYER_REGEN_ENABLED')
assert(f:IsShown(), 'the deferred invitation appears after combat')
wow.Click(f.primary)
eq(last()[1], 'Join', 'Join quiz joins')

local function as(m) m.id = 'game-2'; return m end
P.Render(as(model('joining')))
eq(f.primary:GetText(), 'Joining...', 'joining waits for host confirmation')
eq(f.primary.enabled, false, 'joining is not clickable')
P.Render(as(model('lobby')))
assert(f.status:GetText():find('Waiting for Host-Realm', 1, true), 'lobby names the host')
eq(f.standTitle:GetText(), 'Players', 'lobby lists players')
assert(f.leave:IsShown(), 'Leave is available once joined')
assert(f.rows[3]:IsShown() and f.rows[3].name:GetText():find('Chatonly', 1, true), 'chat-only players stay in the list')

-- Ready check.
P.Render(as(model('ready', { ready = false, remaining = 30000, deadline = now + 30 })))
assert(f.timer:IsShown(), 'ready countdown is visible to the player')
eq(f.timer.count:GetText(), '30s', 'player starts with thirty seconds')
now = now + 29; P.UpdateTimer()
eq(f.timer.count:GetText(), '1s', 'player countdown ticks without a redraw')
now = now + 1; P.UpdateTimer()
eq(f.primary.enabled, false, 'readiness closes after the countdown expires')
local readyCalls = #calls
P.Primary()
eq(#calls, readyCalls, 'expired readiness cannot be submitted')
now = now - 30
P.Render(as(model('ready', { ready = false, remaining = 30000, deadline = now + 30 })))
eq(f.primary:GetText(), "I'm ready", 'ready check asks for readiness')
wow.Click(f.primary)
eq(last()[1], 'Ready', "I'm ready reports readiness")
P.Render(as(model('ready', { ready = true })))
eq(f.primary.enabled, false, 'readiness is not sent twice')

-- Every answer row sends its own number once and shows Sending at once.
for i = 1, 4 do
    P.Render(as(question({ index = i, attempt = 1 })))
    for _, b in ipairs(f.answers) do assert(b:IsShown() and b.enabled, 'choices open while accepting') end
    eq(f.answers[i].Text:GetText():sub(1, 1), tostring(i), 'rows are numbered')
    wow.Click(f.answers[i])
    eq(last()[1], 'Answer', 'click sends an answer'); eq(last()[2], i, 'click sends its own choice')
    local count = #calls
    wow.Click(f.answers[i % 4 + 1])
    eq(#calls, count, 'a second click is ignored')
    eq(f.answers[i].badge:GetText(), 'Sending...', 'the clicked row responds immediately')
    for j, b in ipairs(f.answers) do eq(b.enabled, false, 'choices close after a click ' .. j) end
end

P.Render(as(question({ index = 5, selected = 2, pending = true })))
eq(f.answers[2].badge:GetText(), 'Sending...', 'pending model shows Sending')
eq(f.primary:IsShown(), false, 'no retry while still sending')
P.Render(as(question({ index = 5, selected = 2, locked = 2, correct = 3 })))
eq(f.answers[2].badge:GetText(), 'Locked', 'only host confirmation shows Locked')
eq(f.answers[3].badge:GetText(), '', 'a correct index is ignored before the reveal')
assert(f.answerStatus:GetText():find('Locked: 2', 1, true), 'locked answer is spelled out')
P.Render(as(question({ index = 6, selected = 4, pending = false })))
eq(f.answers[4].badge:GetText(), 'Not confirmed', 'unconfirmed answer is marked')
eq(f.answerStatus:GetText(), 'Answer not confirmed; use Party chat', 'timeout points to Party chat')
eq(f.primary:GetText(), 'Retry answer', 'timeout offers a retry')
wow.Click(f.primary)
eq(last()[1], 'RetryAnswer', 'retry resends the same answer')
eq(last()[2], nil, 'retry never picks a new answer')
for _, b in ipairs(f.answers) do eq(b.enabled, false, 'choices stay closed while retrying') end

-- The deadline closes the choices without a model change.
P.Render(as(question({ index = 7, deadline = now + 2 })))
assert(f.answers[1].enabled, 'open before the deadline')
eq(f.timer.count:GetText(), '2s', 'timer shows seconds left')
now = now + 3
f.scripts.OnUpdate(f, 0.2)
eq(f.answers[1].enabled, false, 'choices close at the deadline')
eq(f.answerStatus:GetText(), "Time's up. Waiting for the answer.", 'deadline explains the wait')
local count = #calls
wow.Click(f.answers[1])
eq(#calls, count, 'a late click sends nothing')

-- Reveal shows the answer, the choice, the result, streak and scores.
rows[2].total, rows[2].streak, rows[2].round, rows[2].rank = 3, 2, 1, 1
rows[1].total, rows[1].rank = 1, 2
P.Render(as(question({ state = 'revealing', index = 7, selected = 2, locked = 2, correct = 2, correctText = 'Kael' })))
assert(f.reveal:GetText():find('Answer: 2 · Kael', 1, true), 'reveal names the correct answer')
assert(f.reveal:GetText():find('You chose 2', 1, true) and f.reveal:GetText():find('Correct!', 1, true), 'reveal shows the result')
assert(f.reveal:GetText():find('Streak 2', 1, true), 'reveal shows the streak')
eq(f.answers[2].badge:GetText(), 'Your answer · Correct', 'reveal marks the chosen correct row')
assert(f.you:GetText():find('3 points', 1, true), 'personal score shows')
assert(f.rows[2].score:GetText():find('+1 this round', 1, true), 'standings show round points')

-- Long text grows the rows instead of overlapping them.
local long = string.rep('A very long answer that wraps ', 6)
P.Render(as(question({ index = 8, choices = { long, long, long, long }, question = string.rep('Long question ', 12) })))
local short = f:GetHeight()
for _, b in ipairs(f.answers) do rawset(b.Text, 'GetStringHeight', function() return 60 end) end
rawset(f.question, 'GetStringHeight', function() return 48 end)
P.Render(as(question({ index = 8, choices = { long, long, long, long }, question = string.rep('Long question ', 12) })))
eq(f.answers[1]:GetHeight(), 76, 'answer rows grow with wrapped text')
assert(f:GetHeight() > short + 150, 'the window grows to fit long content')
for i = 1, 3 do
    local top, nextTop = f.answers[i].points[1][5], f.answers[i + 1].points[1][5]
    assert(nextTop <= top - f.answers[i]:GetHeight(), 'answer rows never overlap ' .. i)
end
assert(f.answers[1].points[1][5] <= f.question.points[1][5] - 48, 'choices start below the question')

-- Content taller than the screen scrolls inside a bounded body, with the
-- title and the action footer always in place.
UIParent:SetHeight(600)
rawset(f.question, 'GetStringHeight', function() return 400 end)
local tall = as(question({ index = 9, selected = 1, pending = false, choices = { long, long, long, long } }))
P.Render(tall)
assert(f:GetHeight() <= 510, 'the window fits 85% of a 600px screen: ' .. f:GetHeight())
assert(P.scrollRange > 0 and f.bar:IsShown(), 'overflowing content scrolls')
eq(f.scroll:GetHeight() + 44 + 48, f:GetHeight(), 'body, title and footer make up the window')
eq(f.body:GetHeight() - f.scroll:GetHeight(), P.scrollRange, 'scroll range covers the hidden content')
eq(f.primary:GetText(), 'Retry answer', 'the footer action is still there')
eq(f.primary.points[1][1], 'BOTTOMLEFT', 'footer actions are pinned to the window bottom')
eq(f.primary.points[1][2], f, 'footer actions sit outside the scrolling body')
eq(f.hide.parent, f, 'Hide stays in the fixed title bar')
P.Scroll(-1000)
eq(P.scrollOffset, P.scrollRange, 'scrolling stops at the bottom')
eq(f.bar:GetValue(), P.scrollRange, 'the scroll bar follows the wheel')
P.Scroll(1000)
eq(P.scrollOffset, 0, 'scrolling stops at the top')
f.bar:SetValue(30)
eq(P.scrollOffset, 30, 'dragging the bar scrolls the body')
f.scroll.scripts.OnMouseWheel(f.scroll, -1)
eq(P.scrollOffset, 70, 'the mouse wheel scrolls the body')
P.Render(tall)
eq(P.scrollOffset, 70, 'ticks keep the scroll position')
P.Render(as(question({ index = 10, choices = { long, long, long, long } })))
eq(P.scrollOffset, 0, 'a new question starts at the top')
local normal = f:GetHeight()
rawset(f, 'GetScale', function() return 1.5 end)
P.Render(as(question({ index = 10, choices = { long, long, long, long } })))
assert(f:GetHeight() * 1.5 <= 510, 'a larger scale still fits the screen')
assert(f:GetHeight() < normal, 'a larger scale gets a shorter body')
rawset(f, 'GetScale', nil)
UIParent:SetHeight(0)
rawset(f.question, 'GetStringHeight', function() return 48 end)
P.Render(as(question({ index = 11 })))
eq(P.scrollRange, 0, 'short content needs no scrolling')
assert(not f.bar:IsShown(), 'the scroll bar hides when everything fits')

-- Hide keeps the session; ticks never reopen it; restore does.
wow.Click(f.hide)
assert(not f:IsShown(), 'Hide closes the window')
assert(P.restore:IsShown(), 'a restore button appears')
eq(P.restore:GetText(), 'Loreforge: answer now', 'restore prompts for an open question')
for _ = 1, 10 do P.Render(as(question({ index = 8 }))) end
assert(not f:IsShown(), 'ticks do not reopen a hidden window')
wow.Click(P.restore)
assert(f:IsShown() and not P.restore:IsShown(), 'restore brings the window back')
f:Hide() -- Escape takes the same path
assert(P.restore:IsShown(), 'Escape also leaves the restore button')
P.Show()

-- Up to five standings plus the local player pinned below.
local big = {}
for i = 1, 8 do big[i] = { key = 'p' .. i, name = 'Player' .. i, total = 9 - i, streak = 0, rank = i } end
big[7].key, big[7].name = 'guest-realm', 'Guest-Realm'
P.Render(as(model('between', { rows = big })))
eq(f.rows[5].name:GetText():sub(1, 3), '5. ', 'five leaders show')
assert(f.rows[6]:IsShown() and f.rows[6].name:GetText():find('Guest-Realm (you)', 1, true), 'the local player is pinned')
assert(f.you:GetText():find('7th', 1, true), 'personal rank shows')

-- Final results open once even after hiding, with shared winners.
wow.Click(f.hide)
local final = {
    { key = 'guest-realm', name = 'Guest-Realm', total = 4, bestStreak = 3, rank = 1, winner = true },
    { key = 'chatonly-realm', name = 'Chatonly-Realm', total = 4, bestStreak = 2, rank = 1, winner = true },
    { key = 'host-realm', name = 'Host-Realm', total = 1, rank = 3 },
}
P.Render(as(model('finished', { rows = final })))
assert(f:IsShown(), 'final results open once')
eq(f.standTitle:GetText(), 'Final standings', 'final standings heading')
assert(f.rows[1].name:GetText():find('Shared win', 1, true) and f.rows[2].name:GetText():find('Shared win', 1, true), 'tied winners share the win')
assert(f.rows[1].score:GetText():find('best streak 3', 1, true), 'final rows show best streak')
assert(not f.roundBar:IsShown(), 'no round scores without round data')

-- Saved round standings sit under the final standings.
local rounds = {
    { round = 1, rows = { { key = 'chatonly-realm', round = 3, total = 3, rank = 1 },
        { key = 'guest-realm', round = 1, total = 1, rank = 2 } } },
    { round = 2, rows = { { key = 'guest-realm', round = 3, total = 4, rank = 1 } } },
}
P.Render(as(model('finished', { rows = final, rounds = rounds })))
assert(f.roundBar:IsShown(), 'round scores are offered')
eq(f.roundButtons[1]:GetText(), 'Round 1', 'a button per round')
assert(f.roundButtons[2]:IsShown() and not f.roundButtons[3]:IsShown(), 'only rounds that exist')
assert(not f.roundRows[1]:IsShown(), 'round rows wait for a click')
wow.Click(f.roundButtons[1])
eq(f.roundTitle:GetText(), 'Round scores · Round 1', 'the selected round is named')
assert(f.roundRows[1].name:GetText():find('1.  Chatonly-Realm', 1, true), 'round names come from the final rows')
eq(f.roundRows[1].score:GetText(), '+3 this round · total 3', 'round and running totals show')
assert(f.roundRows[2].name:GetText():find('Guest-Realm (you)', 1, true), 'the local player is marked')
assert(f.rows[1]:IsShown() and f.rows[1].name:GetText():find('Shared win', 1, true), 'final standings stay visible')
assert(f.roundRows[1].points[1][5] < f.rows[3].points[1][5], 'round rows sit below the final standings')
wow.Click(f.roundButtons[2])
assert(f.roundRows[1].name:GetText():find('Guest-Realm', 1, true) and not f.roundRows[2]:IsShown(), 'switching rounds redraws')
wow.Click(f.roundButtons[2])
assert(not f.roundRows[1]:IsShown(), 'clicking the open round closes it')
P.Render(as(model('between', { rows = final, rounds = rounds })))
assert(not f.roundBar:IsShown(), 'round history is only for finished games')
P.Render(as(model('finished', { rows = final })))
assert(not f.leave:IsShown() and not P.restore:IsShown(), 'nothing to leave after the game')
wow.Click(f.primary)
eq(last()[1], 'ShowHistory', 'Saved games opens history')
P.Render({ state = 'history', history = {
    { id = 'game-2', host = 'Host-Realm', date = '29 Oct 20:15', rank = 1, score = 4, totalQuestions = 6 },
    { id = 'game-0', host = 'Other-Realm', date = '28 Oct 19:00', rank = 2, score = 3, totalQuestions = 5 },
} })
assert(f:IsShown() and f.history[2]:IsShown(), 'history lists saved games')
assert(f.history[1].Text:GetText():find('Host-Realm · 1st · 4/6 correct', 1, true), 'history row summary')
assert(not f.history[3]:IsShown(), 'unused history rows stay hidden')
wow.Click(f.history[2])
eq(last()[1], 'OpenHistory', 'history entry click'); eq(last()[2], 'game-0', 'opening an entry asks for that game')
P.Render(as(model('finished', { id = 'game-0', rows = final })))
assert(f:IsShown() and f.rows[1]:IsShown(), 'an opened entry shows its results')
P.Render({ state = 'history', history = {} })
assert(f.detail:GetText():find('No saved games yet', 1, true), 'empty history explains itself')
wow.Click(f.secondary)
assert(not f:IsShown(), 'Close shuts the history view')

-- Leave ends window participation for that session.
P.Render(model('lobby', { id = 'game-3' }))
assert(f:IsShown(), 'a joined session opens once')
local before = #calls
wow.Click(f.leave)
eq(wow.popups[#wow.popups], 'LOREFORGE_LEAVE_GAME', 'Leave asks first')
eq(#calls, before, 'nothing is sent until Leave is confirmed')
StaticPopupDialogs.LOREFORGE_LEAVE_GAME.OnAccept()
eq(last()[1], 'Leave', 'Leave reports leaving')
assert(not f:IsShown() and not P.restore:IsShown(), 'Leave closes without a restore button')
P.Render(model('accepting', { id = 'game-3' }))
assert(not f:IsShown(), 'a left session stays closed')

-- Missing actions are harmless, and no model clears everything.
ns.Party = nil
P.Render(model('invitation', { id = 'game-4', joined = false }))
wow.Click(f.primary)
P.Render(nil)
assert(not f:IsShown() and not P.restore:IsShown(), 'no model hides the window and restore button')
eq(focus, 0, 'the window never takes keyboard focus')
io.write('loreforge player UI tests passed\n')
