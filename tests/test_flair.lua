package.path = './tests/hammercore/?.lua;' .. package.path
local wow = require('wow')
assert(loadfile('tests/flair-harness.lua'))()(wow)
local function eq(a, b, why) assert(a == b, why .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)) end

-- Storybook style, Animations, Tavern banter and Streak flair: on by
-- default, each one off on its own, banter never sent anywhere.
for _, toc in ipairs({ 'Loreforge.toc', 'Loreforge_Camelot.toc' }) do
    for _, theme in ipairs({ 'modern', 'classic' }) do
        wow.Install({ Loreforge = { Version = '0.1.1' } })
        wow.groups = {}
        LoreforgeDB = nil
        local now = 100
        GetTime = function() return now end
        InCombatLockdown = function() return false end
        GetBuildInfo = function() return '', '', '', toc:find('Camelot') and 16001 or 120105 end
        WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
        GetNormalizedRealmName = function() return 'Realm' end
        UnitFullName = function(unit) if unit == 'player' then return 'Guest', 'Realm' end end
        GetUnitName = function(unit) return (UnitFullName(unit)) end
        UnitGUID = function(unit) return unit .. '-GUID' end
        IsInGroup = function() return false end
        IsInRaid = function() return false end
        GetNumSubgroupMembers = function() return 0 end
        GetNumGroupMembers = function() return 1 end
        RegisterStateDriver, UnregisterStateDriver = function() end, function() end
        -- Every outgoing path is recorded so banter can be checked against it.
        local outgoing = {}
        local function spy(name) return function(text, ...) outgoing[#outgoing + 1] = { name, tostring(text), ... } return 0 end end
        C_ChatInfo.SendChatMessage = spy('C_ChatInfo.SendChatMessage')
        C_ChatInfo.SendAddonMessage = spy('C_ChatInfo.SendAddonMessage')
        C_ChatInfo.SendAddonMessageLogged = spy('C_ChatInfo.SendAddonMessageLogged')
        SendChatMessage = spy('SendChatMessage')
        SendAddonMessage = spy('SendAddonMessage')

        assert(loadfile('tests/transport-libs.lua'))()()
        local ns = wow.LoadHammerCore('Libs/HammerCore', 'Loreforge')
        local T = ns.HammerCore.Theme
        if theme == 'classic' then T.Active = function() return T.registry.classic, 'classic' end end
        local flairLoaded = false
        for file in assert(io.open(toc)):read('*a'):gmatch('([^\r\n]+)') do
            if file:match('^[%w]+%.lua$') then
                if file == 'Flair.lua' then flairLoaded = true end
                if file == 'Host.lua' or file == 'Player.lua' then assert(flairLoaded, toc .. ' loads Flair.lua before ' .. file) end
                assert(loadfile(file))('Loreforge', ns)
            end
        end
        assert(flairLoaded, toc .. ' lists Flair.lua')
        local loader
        for _, f in ipairs(wow.frames) do if f.scripts.OnEvent then loader = f end end
        loader.scripts.OnEvent(loader, 'ADDON_LOADED', 'Loreforge')
        local F = ns.Flair
        local label = toc .. '/' .. theme .. ': '

        for _, key in ipairs({ 'storybook', 'livelyAnimations', 'tavernBanter', 'streakFlair' }) do
            eq(ns.db[key], true, label .. key .. ' defaults on')
        end
        LoreforgeDB.tavernBanter = 'junk'
        loader.scripts.OnEvent(loader, 'ADDON_LOADED', 'Loreforge')
        eq(ns.db.tavernBanter, true, label .. 'an unreadable switch falls back on')

        -- ── Player window ──
        local P = ns.Player
        P.Initialise()
        local calls = {}
        local partyAnswer, partySync = ns.Party.Answer, ns.Party.RequestSync
        ns.Party.Answer = function(i) calls[#calls + 1] = i end
        ns.Party.RequestSync = function() end
        local rows = {
            { key = 'host-realm', name = 'Host-Realm', total = 0, streak = 0, rank = 2 },
            { key = 'guest-realm', name = 'Guest-Realm', total = 0, streak = 0, rank = 1 },
        }
        local function question(extra)
            local m = { id = 'g', state = 'accepting', host = 'Host-Realm', joined = true, me = 'guest-realm', rows = rows,
                config = { rounds = 1, perRound = 12, seconds = 20, difficulty = 'mixed' },
                index = 1, round = 1, totalQuestions = 12, attempt = 1, question = 'Who?', choices = { 'A1', 'B1', 'C1', 'D1' },
                deadline = now + 20, answeredCount = 0 }
            for k, v in pairs(extra or {}) do m[k] = v end
            return m
        end
        P.Render(question())
        local f = P.frame
        assert(f:IsShown(), label .. 'the player window opens')

        -- Storybook: header icon, title and question face, parchment, 1 to 4 badges.
        assert(f.lfIcon:IsShown(), label .. 'the player bar has its icon')
        eq(f.lfIcon.texture, 'Interface\\GossipFrame\\AvailableQuestIcon', label .. 'the quest icon')
        eq(f.title.font[1], 'Fonts\\MORPHEUS.TTF', label .. 'the title is in the storybook face')
        eq(f.question.font[1], 'Fonts\\MORPHEUS.TTF', label .. 'and the question')
        eq(f.answers[1].Text.font, nil, label .. 'answers keep the readable face')
        assert(f.lfParchment:IsShown(), label .. 'the parchment tint shows')
        eq(f.lfParchment.colour[4], F.PARCHMENT[4], label .. 'at full strength when solid')
        for i, b in ipairs(f.answers) do
            assert(b.lfBadge and b.lfBadge:IsShown(), label .. 'answer ' .. i .. ' has a badge')
            eq(b.lfBadge.text:GetText(), tostring(i), label .. 'badges are numbered like the Answer keys')
        end
        ns.OpenHost('play')
        local host = ns.hostFrame
        assert(host.lfIcon:IsShown(), label .. 'the main window bar has its icon')
        eq(host.lfIcon.texture, 'Interface\\Icons\\INV_Misc_Book_09', label .. 'the book icon')
        eq(host.title.font[1], 'Fonts\\MORPHEUS.TTF', label .. 'the main title is in the storybook face')
        ns.SetWindowOpacity(0.5)
        eq(host.lfParchment.colour[4], F.PARCHMENT[4] * 0.5, label .. 'the tint follows Window opacity')
        eq(f.question.alpha, nil, label .. 'text never fades')
        ns.SetWindowOpacity(1)
        host:Hide()

        ns.db.storybook = false
        ns.ApplyFlair(); P.Draw()
        assert(not f.lfIcon:IsShown() and not host.lfIcon:IsShown(), label .. 'Storybook off hides the icons')
        eq(f.title.font[1], 'Fonts\\FRIZQT__.TTF', label .. 'and restores the title face')
        eq(f.question.font[1], 'Fonts\\FRIZQT__.TTF', label .. 'and the question face')
        assert(not f.lfParchment:IsShown(), label .. 'and the parchment')
        for _, b in ipairs(f.answers) do assert(not b.lfBadge:IsShown(), label .. 'and the badges') end
        eq(f.answers[1].Text:GetWidth(), 460 - 32 - 24, label .. 'answer text takes the full row again')
        ns.db.storybook = true
        ns.ApplyFlair(); P.Draw()
        assert(f.lfIcon:IsShown() and f.answers[1].lfBadge:IsShown(), label .. 'and back on, live')

        -- Lively: a pick pops its button.
        wow.Click(f.answers[2])
        eq(calls[#calls], 2, label .. 'the click still answers')
        assert(f.answers[2].lfPop and f.answers[2].lfPop.playing, label .. 'the picked answer pops')
        -- The last five seconds pulse the timer, and only then.
        P.Render(question({ deadline = now + 12 }))
        f.scripts.OnUpdate(f, 0.2)
        assert(not (f.timer.lfPulse and f.timer.lfPulse.playing), label .. 'no pulse with time to spare')
        now = now + 8
        f.scripts.OnUpdate(f, 0.2)
        assert(f.timer.lfPulse.playing, label .. 'the timer pulses in the last five seconds')
        eq(f.timer.lfPulse.looping, 'BOUNCE', label .. 'as a looping group, not an OnUpdate')
        now = now + 5
        f.scripts.OnUpdate(f, 0.2)
        assert(not f.timer.lfPulse.playing, label .. 'and stops at the deadline')

        -- A correct reveal sparkles; banter has a line; a wrong one shakes.
        rows[2].total, rows[2].streak = 1, 1
        P.Render(question({ state = 'revealing', index = 1, selected = 2, locked = 2, correct = 2 }))
        assert(f.lfSparkle, label .. 'a correct answer makes a sparkle')
        for _, star in ipairs(f.lfSparkle.stars) do
            eq(star.texture, 'Interface\\Cooldown\\star4', label .. 'from the star texture')
            assert(star:IsShown(), label .. 'each star shows')
        end
        for _, g in ipairs(f.lfSparkle.groups) do assert(g.playing, label .. 'each star animates') end
        local plays = f.lfSparkle.groups[1].plays
        P.Render(question({ state = 'between', index = 1, selected = 2, locked = 2, correct = 2 }))
        eq(f.lfSparkle.groups[1].plays, plays, label .. 'the same reveal sparkles once')
        local function member(bucket, line)
            for _, l in ipairs(F.BANTER[bucket]) do if l == line or l:format(rows[2].streak) == line then return true end end
        end
        assert(member('correct', f.quip:GetText()), label .. 'correct banter: ' .. tostring(f.quip:GetText()))
        eq(f.feedback:GetText(), 'Correct!', label .. 'the result line is unchanged')
        local first = f.quip:GetText()
        P.Render(question({ state = 'between', index = 1, selected = 2, locked = 2, correct = 2 }))
        eq(f.quip:GetText(), first, label .. 'a redraw keeps its quip')
        P.Render(question({ index = 2, deadline = now + 20 }))
        assert(not f.quip:IsShown(), label .. 'no quip while answering')
        rows[2].streak = 0
        P.Render(question({ state = 'revealing', index = 2, selected = 1, locked = 1, correct = 3 }))
        assert(f.answers[1].lfShake and f.answers[1].lfShake.playing, label .. 'a wrong answer shakes')
        assert(member('wrong', f.quip:GetText()), label .. 'wrong banter')
        P.Render(question({ state = 'revealing', index = 3, correct = 3 }))
        assert(member('timeout', f.quip:GetText()), label .. 'out of time banter')
        P.Render(question({ index = 4, deadline = now + 20 }))
        P.Render(question({ index = 5, deadline = now + 20 }))
        rows[2].streak = 5
        P.Render(question({ state = 'revealing', index = 5, selected = 1, locked = 1, correct = 1 }))
        assert(f.quip:GetText():find('^5 in a row!'), label .. 'a streak call-out: ' .. f.quip:GetText())

        -- Streak flair: a flame at 3, bigger at 5 and 10, gone after a miss.
        local function streakAt(n)
            rows[2].streak = n
            P.Render(question({ state = 'between', index = 6, selected = 1, locked = 1, correct = 1 }))
            return f.streak
        end
        assert(not streakAt(2):IsShown(), label .. 'no flame at 2')
        local badge = streakAt(3)
        assert(badge:IsShown(), label .. 'a flame at 3')
        eq(badge.tier, 1, label .. 'first tier'); eq(badge.count:GetText(), '3', label .. 'with the count')
        local small = badge.icon:GetWidth()
        eq(streakAt(4).tier, 1, label .. 'still first tier at 4')
        badge = streakAt(5)
        eq(badge.tier, 2, label .. 'second tier at 5')
        assert(badge.icon:GetWidth() > small, label .. 'the flame grows')
        assert(badge.icon.texture ~= F.TIERS[1].icon, label .. 'and changes')
        eq(streakAt(9).tier, 2, label .. 'second tier at 9')
        eq(streakAt(10).tier, 3, label .. 'third tier at 10')
        assert(badge.icon:GetWidth() > F.TIERS[2].size, label .. 'the biggest flame')
        assert(not f.you:GetText():find('streak', 1, true), label .. 'the flame carries the count')
        assert(not streakAt(0):IsShown(), label .. 'a miss puts the flame out')
        eq(f.streak.tier, 0, label .. 'and resets the tier')
        assert(f.you:GetText():find('You:', 1, true), label .. 'the score line stays')

        -- Game complete: the crown bounces in with a winner's cheer.
        rows[2].total, rows[1].total = 5, 2
        P.Render({ id = 'g', state = 'finished', host = 'Host-Realm', joined = true, me = 'guest-realm', rows = rows,
            config = { rounds = 1, perRound = 12 } })
        assert(f.trophy:IsShown(), label .. 'the winner gets a crown')
        assert(f.trophy.lfBounce and f.trophy.lfBounce.playing, label .. 'which bounces in')
        assert(member('winner', f.cheer:GetText()), label .. 'and a winner quip')
        assert(not f.streak:IsShown(), label .. 'no flame on the results')
        rows[1].total = 5
        P.Render({ id = 'g2', state = 'finished', host = 'Host-Realm', joined = true, me = 'guest-realm', rows = rows,
            config = { rounds = 1, perRound = 12 } })
        assert(member('tie', f.cheer:GetText()), label .. 'a tie has its own quip')

        -- Hiding the window stops every animation.
        P.Render(question({ index = 7, deadline = now + 3 }))
        f.scripts.OnUpdate(f, 0.2)
        wow.Click(f.answers[3])
        assert(#wow.Playing() > 0, label .. 'something is playing before the hide')
        f:Hide()
        eq(#wow.Playing(), 0, label .. 'hiding stops every animation')
        for _, star in ipairs(f.lfSparkle.stars) do assert(not star:IsShown(), label .. 'and hides the stars') end
        P.Show()
        f.scripts.OnUpdate(f, 0.2)
        assert(f.timer.lfPulse.playing, label .. 'the pulse restarts when shown again')

        -- The hidden-quiz restore pulse follows the same animation switch.
        P.Render(question({ index = 80, deadline = now + 20 }))
        P.Hide()
        assert(P.restore:IsShown() and P.restore.pulsing, label .. 'unanswered hidden quiz offers restore')
        P.restore.scripts.OnUpdate(P.restore, 0.2)
        assert(P.restore:GetAlpha() < 1, label .. 'restore pulses with animations on')
        ns.db.livelyAnimations = false
        P.restore.scripts.OnUpdate(P.restore, 0.2)
        eq(P.restore:GetAlpha(), 1, label .. 'turning animations off stops restore immediately')
        P.RefreshRestore()
        assert(not P.restore.pulsing, label .. 'refresh keeps restore still with animations off')
        P.Show()

        -- Each switch off suppresses its own effect.
        ns.db.livelyAnimations = false
        ns.ApplyFlair()
        eq(#wow.Playing(), 0, label .. 'Lively off stops what was playing')
        local before = 0
        for _, g in ipairs(wow.groups) do before = before + g.plays end
        P.Render(question({ index = 8, deadline = now + 3 }))
        f.scripts.OnUpdate(f, 0.2)
        wow.Click(f.answers[4])
        rows[2].streak = 1
        P.Render(question({ state = 'revealing', index = 8, selected = 4, locked = 4, correct = 4 }))
        P.Render(question({ state = 'revealing', index = 9, selected = 1, locked = 1, correct = 4 }))
        local after = 0
        for _, g in ipairs(wow.groups) do after = after + g.plays end
        eq(after, before, label .. 'Lively off plays nothing')
        ns.db.livelyAnimations = true

        ns.db.tavernBanter = false
        P.Render(question({ state = 'revealing', index = 10, selected = 4, locked = 4, correct = 4 }))
        assert(not f.quip:IsShown(), label .. 'Banter off: no quip')
        P.Render({ id = 'g3', state = 'finished', host = 'Host-Realm', joined = true, me = 'guest-realm', rows = rows,
            config = { rounds = 1, perRound = 12 } })
        assert(not f.cheer:IsShown(), label .. 'and no cheer')
        ns.db.tavernBanter = true

        ns.db.streakFlair = false
        assert(not streakAt(10):IsShown(), label .. 'Streak flair off: no flame')
        assert(f.you:GetText():find('streak 10', 1, true), label .. 'the plain streak text is back')
        ns.db.streakFlair = true

        -- The Interface page owns the four switches and resets them.
        local Settings = ns.HammerCore.Settings
        Settings:Show('Interface')
        eq(next(Settings.errors or {}), nil, label .. 'the Interface page builds')
        for _, name in ipairs({ 'FLAIR', 'Storybook style', 'Animations', 'Tavern banter', 'Streak flair' }) do
            assert(wow.FindText(name), label .. 'Interface shows ' .. name)
        end
        Settings:Hide()

        -- ── A practice game end to end through the host console ──
        ns.db.hostAutoMinimise, ns.db.roundIntro, ns.db.readyCheck = false, false, false
        ns.db.rounds, ns.db.perRound, ns.db.seconds, ns.db.autoMode, ns.db.questionGap = 1, 12, 5, true, 3
        ns.Party.Answer, ns.Party.RequestSync = partyAnswer, partySync
        ns.StartGame(true)
        local tiers = {}
        local answered = {}
        for _ = 1, 4000 do
            local g = ns.game
            if g.phase == 'finished' then break end
            if g.phase == 'accepting' and not answered[g.index] then
                answered[g.index] = true
                local right = g.run[g.index].correct
                ns.SubmitHostAnswer(tostring(g.index == 11 and right % 4 + 1 or right))
            end
            if (g.phase == 'revealing' or g.phase == 'between') and P.frame:IsShown() and P.model and P.model.handlers then
                tiers[g.index] = P.frame.streak.tier
            end
            now = now + 0.25
            ns.events.scripts.OnUpdate(ns.events, 0.25)
        end
        eq(ns.game.phase, 'finished', label .. 'the practice game finishes')
        eq(tiers[2], 0, label .. 'no flame at 2'); eq(tiers[3], 1, label .. 'a flame at 3')
        eq(tiers[5], 2, label .. 'bigger at 5'); eq(tiers[10], 3, label .. 'biggest at 10')
        eq(tiers[11], 0, label .. 'a miss resets it'); eq(tiers[12], 0, label .. 'and it builds again from nothing')
        ns.OpenHost('play')
        assert(host.trophy:IsShown(), label .. 'the console crowns the winner')
        assert(host.trophy.lfBounce.playing, label .. 'with a bounce')
        assert(member('winner', host.finaleQuip:GetText()), label .. 'and a winner quip')
        eq(host.finale.font[1], 'Fonts\\MORPHEUS.TTF', label .. 'Game complete in the storybook face')
        host:Hide()
        eq(#wow.Playing(), 0, label .. 'hiding the console stops its animations')

        -- Banter stays local: never sent, never printed.
        for _, line in ipairs(outgoing) do
            for _, lines in pairs(F.BANTER) do
                for _, quip in ipairs(lines) do
                    local plain = quip:gsub('%%d', ''):gsub('^ ', '')
                    assert(not line[2]:find(plain, 1, true), label .. 'banter reached ' .. line[1] .. ': ' .. line[2])
                end
            end
        end
        for _, printed in ipairs(wow.printed) do
            for _, lines in pairs(F.BANTER) do
                for _, quip in ipairs(lines) do
                    assert(not printed:find(quip:gsub('%%d', ''), 1, true), label .. 'banter printed: ' .. printed)
                end
            end
        end
    end
end
io.write('loreforge flair tests passed\n')
