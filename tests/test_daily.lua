package.path = "./tests/hammercore/?.lua;" .. package.path
local wow = require("wow")
local function eq(a, b, why) assert(a == b, why .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local function has(text, needle, why) assert(tostring(text):find(needle, 1, true), why .. ": " .. tostring(text)) end

-- The daily question: selection, streaks, the account-wide record, the login
-- offer, the Play tab, the minimap and the welcome window.

local clock, combat, instance, grouped, today, hour, minute, timers
local function setDay(number, h, m)
    today, hour, minute = number, h or 10, m or 0
end

local function load(options)
    options = options or {}
    local era = options.era or "retail"
    local toc = era == "classic" and "Loreforge_Camelot.toc" or "Loreforge.toc"
    wow.Install({ Loreforge = { Version = options.version or "1.3.0" } })
    ConsecratedHammerWelcome = nil
    LoreforgeDB = options.saved
    clock, combat, instance, grouped, timers = 100, false, false, options.grouped or false, {}
    if not options.keepDay then setDay(options.day or 3, options.hour, options.minute) end
    GetTime = function() return clock end
    GetServerTime = function() return 1762740000 + clock end
    date = os.date
    InCombatLockdown = function() return combat end
    IsInInstance = function() return instance, instance and "party" or "none" end
    IsInGroup = function() return grouped end
    C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end }
    GetBuildInfo = function() return "version", "build", "date", era == "classic" and 16001 or 120105 end
    WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
    GetNormalizedRealmName = function() return "Realm" end
    UnitFullName = function(unit)
        if unit == "player" then return options.name or "Host", "Realm" end
        if grouped and unit == "party1" then return "Guest", "Realm" end
        return nil
    end
    GetUnitName = function(unit) return (UnitFullName(unit)) end
    UnitGUID = function(unit) return unit == "player" and "hostGUID" or "guestGUID" end
    IsInRaid = function() return false end
    GetNumSubgroupMembers = function() return grouped and 1 or 0 end
    RegisterStateDriver = function() end
    UnregisterStateDriver = function() end
    UnitOnTaxi = function() return false end
    assert(loadfile('tests/transport-libs.lua'))()()
    hooksecurefunc = function() end
    local ns = wow.LoadHammerCore("Libs/HammerCore", "Loreforge")
    for file in assert(io.open(toc)):read("*a"):gmatch("([^\r\n]+)") do
        if file:match("^[%w]+%.lua$") then assert(loadfile(file))("Loreforge", ns) end
    end
    -- The calendar: day `today` of the daily, at hour:minute server time.
    C_DateAndTime = { GetCurrentCalendarTime = function()
        local y, m, d = ns.Daily.DateOf(ns.Daily.DayIndex(2026, 11, 10) + today - 1)
        return { year = y, month = m, monthDay = d, hour = hour, minute = minute }
    end }
    local loader
    for _, f in ipairs(wow.frames) do if f.scripts.OnEvent then loader = f end end
    loader.scripts.OnEvent(loader, "ADDON_LOADED", "Loreforge")
    return ns
end

-- Runs the timers that are due, including any they queue.
local function runTimers()
    local guard = 0
    while #timers > 0 and guard < 20 do
        local due = timers
        timers = {}
        for _, t in ipairs(due) do t.fn() end
        guard = guard + 1
    end
end

local function tick(ns, seconds)
    clock = clock + (seconds or 0)
    ns.QuickCard.Update(1)
end

local function answer(ns, right)
    local q = ns.Quick.state.question
    local index = right and q.correct or (q.correct % 4 + 1)
    ns.QuickCard.frame.answers[index].scripts.OnClick(ns.QuickCard.frame.answers[index])
    return index
end

-- Plays today's daily on the card and closes it.
local function playDaily(ns, right)
    ns.QuickCard.Show("daily")
    answer(ns, right)
    tick(ns, 2.1)
    ns.QuickCard.Hide()
end

local function point(frame) return frame.points[1] and frame.points[1][2] end

-- The hash: pure Lua, 32-bit, the cached ID part matches hashing the joined string.
do
    local ns = load()
    local D = ns.Daily
    for _, id in ipairs({ "lore-thrall-father", "quote-onyxia-fortuitous", "x", "" }) do
        for _, key in ipairs({ "2026-11-10", "2027-02-28", "2031-12-31" }) do
            local h = D.Hash(id .. key)
            eq(D.Score(id, key), h, "Score is Hash(id .. date) for " .. id .. key)
            assert(h >= 0 and h < 4294967296 and h == math.floor(h), "a 32-bit integer")
        end
    end
    eq(D.Hash("abc"), D.Hash("abc"), "deterministic")
    assert(D.Hash("abc") ~= D.Hash("abd"), "one byte changes it")
    -- Dates: the epoch is #1 and every date round-trips.
    eq(D.Number(D.DayIndex(2026, 11, 10)), 1, "launch day is Daily #1")
    eq(D.Number(D.DayIndex(2026, 12, 1)), 22, "three weeks later")
    for index = D.DayIndex(2026, 1, 1), D.DayIndex(2030, 12, 31), 7 do
        eq(D.DayIndex(D.DateOf(index)), index, "date round trip")
    end
    eq(D.KeyFor(1), "2026-11-10", "date key for #1")
    eq(D.KeyFor(113), "2027-03-02", "across a February")
    -- Server calendar, then the UTC fallback.
    setDay(3, 16, 48)
    eq(D.Today().number, 3, "today from the calendar")
    eq(D.NextText(), "Next question in 7h 12m", "time to the next question")
    setDay(3, 23, 45)
    eq(D.NextText(), "Next question in 15m", "under an hour")
    C_DateAndTime = nil
    GetServerTime = function() return os.time({ year = 2026, month = 11, day = 12, hour = 12 }) end
    eq(D.Today().key, "2026-11-12", "UTC date without the calendar API")
end

-- Selection: same date, same question; the clients never clash; no repeats in 60 days.
do
    local ns = load()
    local D = ns.Daily
    local DAYS = 400
    local schedule = D.Schedule(DAYS)
    local retail, classic = {}, {}
    for n = 1, DAYS do retail[n], classic[n] = schedule.retail[n], schedule.classic[n] end
    local byId = {}
    for _, entry in ipairs(ns.HammerCore.QUIZ) do byId[entry.id] = entry end
    for n = 1, DAYS do
        assert(retail[n] and classic[n], "a question both clients, day " .. n)
        assert(retail[n] ~= classic[n], "Retail and Forever differ on day " .. n)
        local r, c = byId[retail[n]].era or "both", byId[classic[n]].era or "both"
        assert(r == "retail" or r == "both", "Retail's pick is a Retail question")
        assert(c == "classic" or c == "both", "Forever's pick is a Forever question")
        for back = math.max(1, n - 60), n - 1 do
            for _, id in ipairs({ retail[back], classic[back] }) do
                assert(id ~= retail[n] and id ~= classic[n], "no repeat within 60 days, day " .. n .. " and " .. back)
            end
        end
    end
    -- A fresh copy, no saved schedule: the same answers.
    D.cache = nil
    ns.db.dailySchedule = nil
    for _, n in ipairs({ 1, 50, 399 }) do
        eq(D.PickId("retail", n), retail[n], "the same date gives the same Retail question")
        eq(D.PickId("classic", n), classic[n], "and the same Forever question")
    end
    -- Forever works out the same schedule from the same bank.
    local forever = load({ era = "classic" })
    eq(forever.Daily.PickId("retail", 77), retail[77], "Forever knows Retail's pick")
    eq(forever.Daily.PickId("classic", 77), classic[77], "Forever's own pick")
    -- The schedule is saved and picked up again; a new bank recomputes it.
    local saved = forever.db.dailySchedule
    assert(saved and saved.signature and #saved.retail >= 77, "schedule saved")
    D.cache = nil
    ns.db.dailySchedule = saved
    eq(D.PickId("classic", 77), classic[77], "from the saved schedule")
    ns.db.dailySchedule = { signature = "stale", retail = { "nope" }, classic = { "nope" } }
    D.cache = nil
    eq(D.PickId("retail", 1), retail[1], "a stale saved schedule is ignored")
end

-- Adding a question only changes the days it wins, and the days those
-- changes knock on to within the 60-day lookback.
do
    local ns = load()
    local D = ns.Daily
    local DAYS = 300
    local bank = {}
    for i, entry in ipairs(ns.HammerCore.QUIZ) do bank[i] = entry end
    local wins, knocks = 0, 0
    for trial = 1, 6 do
        local grown = {}
        for i, entry in ipairs(bank) do grown[i] = entry end
        local newId = "test-new-question-" .. trial
        grown[#grown + 1] = { "New?", "a", "b", "c", "d", id = newId, era = trial % 2 == 0 and "both" or "classic" }
        D.cache = nil
        local before = D.Schedule(DAYS, bank)
        local r0, c0 = {}, {}
        for n = 1, DAYS do r0[n], c0[n] = before.retail[n], before.classic[n] end
        D.cache = nil
        local after = D.Schedule(DAYS, grown)
        local lastChange
        for n = 1, DAYS do
            local changed = r0[n] ~= after.retail[n] or c0[n] ~= after.classic[n]
            if changed then
                local won = after.retail[n] == newId or after.classic[n] == newId
                if won then wins = wins + 1
                else
                    assert(lastChange and n - lastChange <= 60, "a change with no cause on day " .. n)
                    knocks = knocks + 1
                end
                lastChange = n
            end
        end
    end
    assert(wins > 0, "the new questions win some days")
    assert(knocks <= wins, "knock-on changes stay rare: " .. knocks .. " for " .. wins)
    D.cache = nil
end

-- Retired questions never come up.
do
    local ns = load()
    local D = ns.Daily
    local first = D.PickId("retail", 1)
    local bank = {}
    for i, entry in ipairs(ns.HammerCore.QUIZ) do
        if entry.id == first then
            local copy = {}
            for k, v in pairs(entry) do copy[k] = v end
            copy.retired = true
            entry = copy
        end
        bank[i] = entry
    end
    D.cache = nil
    assert(D.Schedule(1, bank).retail[1] ~= first, "a retired question is skipped")
    D.cache = nil
end

-- The card: one question, no timer, then the summary; again that day, the summary.
do
    local ns = load({ day = 3 })
    ns.QuickCard.Show("daily")
    local old = ns.Quick.state.question
    setDay(4)
    eq(ns.Daily.Record(old, old.correct, true), false, "expired questions cannot consume today's attempt")
    ns.Quick.Answer(old.correct)
    eq(ns.Daily.Done(), false, "the midnight click records no answer")
    eq(ns.Quick.state.day, 4, "the card refreshes to today")
    eq(ns.Quick.state.phase, "question", "today's question waits for a new answer")
    answer(ns, true)
    eq(ns.Daily.Done(), true, "a fresh click answers today's question")
    eq(ns.Daily.Streak(), 1, "the stale click did not grow the streak")
end

do
    local ns = load()
    local D = ns.Daily
    local before = D.PickId("retail", 1)
    local _, originalSignature = D.Bank()
    local bank = {}
    for i, entry in ipairs(ns.HammerCore.QUIZ) do
        local copy = {}
        for k, v in pairs(entry) do copy[k] = v end
        if copy.id == before then copy.era = "classic" end
        bank[i] = copy
    end
    local _, updatedSignature = D.Bank(bank)
    assert(originalSignature ~= updatedSignature, "era changes invalidate the saved bank signature")
    assert(D.Schedule(1, bank).retail[1] ~= before, "cached picks respect changed client eligibility")
end

do
    local ns = load({ day = 3, hour = 16, minute = 48 })
    SlashCmdList.LOREFORGE("daily")
    local card, s = ns.QuickCard.frame, ns.Quick.state
    eq(card:IsShown(), true, "/lf daily opens the card")
    eq(s.mode, "daily", "in daily mode")
    eq(s.phase, "question", "today's question")
    eq(card.title.text, "Loreforge · Daily question", "card title")
    local id = ns.Daily.PickId("retail", 3)
    eq(s.question.id, id, "today's pick")
    eq(card.clock.text, "Daily #3", "only the daily number on the card")
    eq(s.questionDeadline, nil, "no timer")
    eq(card.timer.shown, false, "no timer bar")
    has(card.art.texture, "theme-", "category painting")
    eq(card.caption.text, s.question.categoryLabel, "category caption")
    eq(card.footer.text, "Daily streak: 0 (best 0)", "streak footer")
    tick(ns, 120)
    eq(s.phase, "question", "it waits as long as you like")
    local order = table.concat(s.question.choices, "|")
    answer(ns, true)
    eq(s.phase, "reveal", "the answer shows")
    tick(ns, 2.1)
    eq(s.phase, "over", "then the summary")
    eq(card.overTitle.text, "Correct!", "summary title")
    has(card.overLines.text, "Daily #3", "summary names the daily")
    has(card.overLines.text, "Daily streak: 1", "summary streak")
    eq(card.overNote.text, "Next question in 7h 12m", "next question time")
    eq(card.primary.text, "Quick play", "carry on in Quick play")
    eq(card.secondary.text, "Close", "or close")
    eq(card.footer.text, "Daily streak: 1 (best 1)", "footer after answering")
    has(ns.HammerCore.DiagnosticReport(), "Daily: Daily #3", "diagnostics show the daily")
    ns.QuickCard.Hide()
    -- Again that day: the summary, and no second try.
    ns.QuickCard.Show("daily")
    eq(ns.Quick.state.phase, "over", "the summary again")
    eq(card.overTitle.text, "Correct!", "same result")
    eq(ns.Daily.Record(s.question, 1, false), false, "one try a day")
    ns.QuickCard.Hide()
    -- Everyone sees the answers in the same order.
    local other = load({ day = 3, saved = nil })
    other.QuickCard.Show("daily")
    eq(table.concat(other.Quick.state.question.choices, "|"), order, "same answer order for everyone")
    -- A wrong answer shows the right one.
    answer(other, false)
    tick(other, 2.1)
    eq(other.QuickCard.frame.overTitle.text, "Not this time", "wrong answer title")
    has(other.QuickCard.frame.overLines.text, "It was " .. other.Daily.Find(other.Quick.state.dailyId)[2], "the right answer")
end

-- Streaks: consecutive right answers count up; a miss or a missed day resets.
do
    local ns = load({ day = 1 })
    local D = ns.Daily
    playDaily(ns, true); eq(D.Streak(), 1, "day 1 right")
    setDay(2); playDaily(ns, true); eq(D.Streak(), 2, "day 2 right")
    setDay(3); playDaily(ns, true); eq(D.Streak(), 3, "day 3 right")
    setDay(4); eq(D.Streak(), 3, "the streak holds until today's is answered")
    playDaily(ns, false); eq(D.Streak(), 0, "a wrong answer resets it")
    eq(D.Best(), 3, "best streak kept")
    setDay(5); playDaily(ns, true); eq(D.Streak(), 1, "starts again")
    setDay(7); eq(D.Streak(), 0, "a missed day resets it")
    playDaily(ns, true); eq(D.Streak(), 1, "and it starts from one")
    eq(D.FooterText(), "Daily streak: 1 (best 3)", "footer streak and best")
    -- Hall of Fame: the fourth personal best.
    SlashCmdList.LOREFORGE("records")
    local cell = ns.hostFrame.records.bests[4]
    eq(cell.value.text, "1", "Hall of Fame daily streak")
    eq(cell.detail.text, "Best 3", "Hall of Fame best daily streak")
    cell.scripts.OnEnter(cell)
    local fresh = load()
    SlashCmdList.LOREFORGE("records")
    eq(fresh.hostFrame.records.bests[4].value.text, "0", "no daily yet")
end

-- Account-wide: one character's answer counts for the others; clients apart.
do
    local saved = {}
    local alice = load({ saved = saved, name = "Alice", day = 4 })
    playDaily(alice, true)
    eq(type(saved.daily.retail), "table", "kept in LoreforgeDB.daily per client")
    local bob = load({ saved = saved, name = "Bob", keepDay = true })
    eq(bob.Daily.Done(), true, "done on another character")
    eq(bob.Daily.Streak(), 1, "the same streak")
    bob.QuickCard.Show("daily")
    eq(bob.Quick.state.phase, "over", "the summary on the other character")
    eq(bob.Daily.CanOffer(), false, "no login offer once done")
    local forever = load({ saved = saved, era = "classic", keepDay = true })
    eq(forever.Daily.Done(), false, "Forever keeps its own daily")
    -- Reset settings keeps the daily and the personal bests.
    bob.HammerCore.spec.resetSettings()
    eq(LoreforgeDB.daily, saved.daily, "reset settings keeps the daily")
end

-- The login offer: once a day, after loading in, never in combat or an instance.
do
    local ns = load()
    local D = ns.Daily
    D.OnEvent("PLAYER_ENTERING_WORLD")
    eq(timers[1] and timers[1].seconds, D.OFFER_DELAY, "a few seconds after loading in")
    -- The welcome window is waiting on a new install, so the offer waits too.
    eq(ns.HammerCore.Welcome.Busy(), true, "a new install's welcome is queued")
    local welcomeFrame = ns.HammerCore.Welcome.eventFrame
    welcomeFrame.scripts.OnEvent(welcomeFrame, "PLAYER_ENTERING_WORLD")
    runTimers()
    eq(ns.HammerCore.Welcome:IsShown(), true, "the welcome opens")
    eq(ns.QuickCard.dailyPrompt == nil or not ns.QuickCard.dailyPrompt:IsShown(), true, "no daily offer beside the welcome")
    eq(select(2, D.CanOffer()), "busy", "held back by the welcome")
    ns.HammerCore.Welcome:Hide()
    runTimers()
    local prompt = ns.QuickCard.dailyPrompt
    eq(prompt and prompt:IsShown(), true, "offered once the welcome closes")
    has(prompt.title.text, "Daily #3", "the offer names the daily")
    eq(prompt.dontOffer:GetChecked(), false, "offering")
    prompt.later.scripts.OnClick(prompt.later)
    eq(prompt:IsShown(), false, "Not today closes it")
    D.OnEvent("PLAYER_ENTERING_WORLD"); runTimers()
    eq(prompt:IsShown(), false, "once a day")
    eq(select(2, D.CanOffer()), "offered", "already offered today")
    -- The next day: combat waits, an instance skips until the next loading screen.
    setDay(4)
    combat = true
    D.OnEvent("PLAYER_ENTERING_WORLD"); runTimers()
    eq(prompt:IsShown(), false, "not in combat")
    combat = false
    D.OnEvent("PLAYER_REGEN_ENABLED"); runTimers()
    eq(prompt:IsShown(), true, "after combat")
    prompt.play.scripts.OnClick(prompt.play)
    eq(prompt:IsShown(), false, "Play closes the offer")
    eq(ns.Quick.state.mode, "daily", "and opens the daily")
    ns.QuickCard.Hide()
    setDay(5)
    instance = true
    D.OnEvent("PLAYER_ENTERING_WORLD"); runTimers()
    eq(prompt:IsShown(), false, "not in an instance")
    instance = false
    D.OnEvent("PLAYER_ENTERING_WORLD"); runTimers()
    eq(prompt:IsShown(), true, "after leaving it")
    -- Don't offer at login, from the prompt.
    prompt.dontOffer.scripts.OnClick(prompt.dontOffer)
    eq(ns.db.dailyOffer, false, "Don't offer at login")
    eq(prompt.dontOffer:GetChecked(), true, "ticked")
    prompt.dontOffer.scripts.OnClick(prompt.dontOffer)
    eq(ns.db.dailyOffer, true, "and back")
    prompt.later.scripts.OnClick(prompt.later)
    setDay(6)
    ns.db.dailyOffer = false
    eq(select(2, D.CanOffer()), "off", "Offer at login off")
    ns.db.dailyOffer, ns.db.dailyOn = true, false
    eq(select(2, D.CanOffer()), "off", "Daily question off")
    ns.db.dailyOn = true
    playDaily(ns, true)
    eq(select(2, D.CanOffer()), "done", "not once it's answered")
end

-- Updating players: no welcome rows to hold it back, so the offer just comes.
do
    local saved = { hammerCore = { whatsNewSeen = "1.3.0", welcomeSeen = "1.3.0", welcomeKeys = { "flights", "daily" } } }
    local ns = load({ saved = saved })
    eq(ns.HammerCore.Welcome.Busy(), false, "no welcome after it's been seen")
    ns.Daily.OnEvent("PLAYER_ENTERING_WORLD"); runTimers()
    eq(ns.QuickCard.dailyPrompt:IsShown(), true, "the offer shows")
    -- Combat hides it and brings it back.
    combat = true
    ns.QuickCard.OnCombat("PLAYER_REGEN_DISABLED")
    eq(ns.QuickCard.dailyPrompt:IsShown(), false, "hidden in combat")
    combat = false
    ns.QuickCard.OnCombat("PLAYER_REGEN_ENABLED")
    eq(ns.QuickCard.dailyPrompt:IsShown(), true, "back after combat")
end

-- Play tab: Quick play leads when solo, Practice solo second, Daily beside them.
do
    local function resumeGuard(change, why)
        local ns = load({ saved = { hammerCore = { whatsNewSeen = "1.3.0", welcomeSeen = "1.3.0", welcomeKeys = { "flights", "daily" } } } })
        ns.Daily.OnEvent("PLAYER_ENTERING_WORLD"); runTimers()
        local prompt = ns.QuickCard.dailyPrompt
        eq(prompt:IsShown(), true, "offer before " .. why)
        combat = true
        ns.QuickCard.OnCombat("PLAYER_REGEN_DISABLED")
        local afterCombat = change(ns)
        combat = false
        if afterCombat then afterCombat() end
        ns.QuickCard.OnCombat("PLAYER_REGEN_ENABLED")
        eq(prompt:IsShown(), false, "no combat resume " .. why)
    end
    resumeGuard(function() instance = true end, "inside an instance")
    resumeGuard(function(ns) ns.db.dailyOn = false end, "with Daily question off")
    resumeGuard(function(ns) ns.db.dailyOffer = false end, "with Offer at login off")
    resumeGuard(function(ns) return function() ns.HammerCore.Welcome:Show() end end, "behind the welcome")
    local ns = load({ saved = { hammerCore = { whatsNewSeen = "1.3.0", welcomeSeen = "1.3.0", welcomeKeys = { "flights", "daily" } } } })
    ns.Daily.OnEvent("PLAYER_ENTERING_WORLD"); runTimers()
    instance = true
    ns.Daily.OnEvent("PLAYER_ENTERING_WORLD")
    eq(ns.QuickCard.dailyPrompt:IsShown(), false, "entering an instance hides an existing offer")
    ns = load({ day = 3, saved = { hammerCore = { whatsNewSeen = "1.3.0", welcomeSeen = "1.3.0", welcomeKeys = { "flights", "daily" } } } })
    ns.Daily.OnEvent("PLAYER_ENTERING_WORLD"); runTimers()
    local prompt = ns.QuickCard.dailyPrompt
    combat = true
    ns.QuickCard.OnCombat("PLAYER_REGEN_DISABLED")
    setDay(4)
    combat = false
    ns.QuickCard.OnCombat("PLAYER_REGEN_ENABLED")
    eq(prompt:IsShown(), true, "midnight combat resume shows today's offer")
    has(prompt.title.text, "Daily #4", "resumed offer refreshes its date")
    eq(ns.Daily.State().offered, 4, "the displayed offer counts for the new day")
    prompt.later.scripts.OnClick(prompt.later)
    ns.Daily.OnEvent("PLAYER_ENTERING_WORLD"); runTimers()
    eq(prompt:IsShown(), false, "a loading screen cannot offer the same day again")
end

do
    local ns = load()
    SlashCmdList.LOREFORGE("")
    local setup = ns.hostFrame.setup
    eq(setup.solo, true, "solo")
    local choices = setup.playChoices
    eq(setup.soloChoices:IsShown(), true, "solo play choices lead")
    eq(point(choices.quick), 0, "Quick play leads by default")
    eq(setup.start:IsShown(), true, "configured practice remains under the hosting form")
    eq(setup.formScroll:IsShown(), true, "solo hosting form can scroll")
    eq(setup.quickMain:IsShown(), false, "no duplicate Quick play footer action")
    choices.quick.scripts.OnClick(choices.quick)
    eq(ns.Quick.state.mode, "quick", "the first choice opens Quick play")
    ns.QuickCard.Hide()
    choices.practice.scripts.OnClick(choices.practice)
    eq(ns.game.phase ~= "setup", true, "practice choice starts a private game")
    ns.game:Stop()
    SlashCmdList.LOREFORGE("")
    choices.daily.scripts.OnClick(choices.daily)
    eq(ns.Quick.state.mode, "daily", "Daily opens the daily")
    answer(ns, true); tick(ns, 2.1)
    ns.QuickCard.Hide()
    ns.RefreshHost()
    has(choices.daily.record.text, "Done today", "daily choice shows completion")
    ns.db.soloMain = "PRACTICE"
    ns.RefreshHost()
    eq(point(choices.practice), 0, "saved preference puts practice first")
    eq(choices.quick:IsShown(), true, "Quick play remains available")
    ns.db.dailyOn = false
    ns.RefreshHost()
    eq(choices.daily:IsShown(), false, "no Daily choice with the daily off")

end
-- Physical solo layout must not change the selected channel's hosting action.
do
    local ns = load()
    IsInGuild = function() return true end
    GetNumGuildMembers = function() return 1 end
    GetGuildRosterInfo = function() return 'GuildGuest-Realm', nil, nil, nil, nil, nil, nil, nil, true end
    ns.db.channel = 'GUILD'
    local action
    ns.StartGame = function(practice) action = practice and 'practice' or 'normal' end
    SlashCmdList.LOREFORGE("")
    local setup = ns.hostFrame.setup
    eq(setup.soloScreen, true, 'ungrouped guild host keeps solo play choices')
    eq(setup.solo, false, 'guild channel still has a broadcast roster')
    eq(setup.start.text, 'Start game', 'guild hosting action keeps its label')
    eq(setup.start.enabled, true, 'guild hosting remains available')
    setup.start.scripts.OnClick(setup.start)
    eq(action, 'normal', 'hosting form does not force guild games into practice')
    setup.playChoices.practice.scripts.OnClick(setup.playChoices.practice)
    eq(action, 'practice', 'explicit practice choice remains private')
    grouped = true
    ns.db.channel = 'PARTY'
    ns.Party.Available = function() return false end
    ns.RefreshHost()
    eq(setup.soloScreen, false, 'joining a group restores the grouped layout')
    eq(setup.start.text, 'Start game', 'joining restores the hosting label')
    setup.start.scripts.OnClick(setup.start)
    eq(action, 'normal', 'grouped action uses normal hosting route')
    grouped = false
    ns.RefreshHost()
    eq(setup.start.text, 'Practice a full game', 'ungrouped Party channel is local practice')
    ns.db.channel = 'GUILD'
    ns.RefreshHost()
    eq(setup.start.text, 'Start game', 'returning to Guild leaves no stale practice label')
    setup.start.scripts.OnClick(setup.start)
    eq(action, 'normal', 'returning to Guild leaves no stale practice callback')
end
do
    local ns = load({ grouped = true })
    SlashCmdList.LOREFORGE("")
    local setup = ns.hostFrame.setup
    eq(setup.solo, false, "in a group")
    eq(setup.start:IsShown(), true, "the game start button leads in a group")
    eq(setup.quickMain:IsShown(), false, "no main Quick play in a group")
    eq(point(setup.practice), 228, "Practice solo where it was")
    eq(point(setup.quick), 388, "Quick play where it was")
    eq(point(setup.daily), 528, "Daily after them")
end

-- Minimap left-click when solo.
do
    local ns = load()
    local button = ns.HammerCore.Minimap.button
    eq(ns.db.soloLeftClick, "WINDOW", "the window by default")
    eq(tostring(ns.HammerCore.spec.minimap.leftClickLabel), "open Loreforge", "tooltip says the window")
    wow.Click(button, "LeftButton")
    eq(ns.hostFrame:IsShown(), true, "left-click opens the window")
    ns.hostFrame:Hide()
    ns.db.soloLeftClick = "QUICK"
    eq(tostring(ns.HammerCore.spec.minimap.leftClickLabel), "Quick play", "tooltip follows the setting")
    wow.Click(button, "LeftButton")
    eq(ns.QuickCard.IsShown(), true, "left-click opens Quick play when solo")
    wow.Click(button, "LeftButton")
    eq(ns.QuickCard.IsShown(), false, "and closes it")
    grouped = true
    eq(tostring(ns.HammerCore.spec.minimap.leftClickLabel), "open Loreforge", "grouped: the window")
    wow.Click(button, "LeftButton")
    eq(ns.QuickCard.IsShown(), false, "grouped, no Quick play")
    eq(ns.hostFrame:IsShown(), true, "grouped, the window")
end

-- Settings: the rows exist and the pages build.
do
    local ns = load()
    ns.HammerCore.Settings:Show("Quick play")
    ns.HammerCore.Settings:Show("Visibility")
    eq(next(ns.HammerCore.Settings.errors or {}), nil, "pages build")
    for _, text in ipairs({ "Daily question", "Offer at login", "Main button when solo", "Minimap left-click when solo",
        "Setup on new features", "Run setup again" }) do
        assert(wow.FindText(text), text .. " row exists")
    end
    eq(ns.db.dailyOn, true, "Daily question on by default")
    eq(ns.db.dailyOffer, true, "Offer at login on by default")
    eq(ns.db.soloMain, "QUICK", "Quick play leads when solo by default")
    eq(ns.Quick.ON_FLIGHTS_LABELS.OFFER, "Ask me", "On flights: Ask me")
    eq(ns.Quick.ON_FLIGHTS_LABELS.START, "Auto-start", "On flights: Auto-start")
    eq(ns.Quick.ON_FLIGHTS_LABELS.NONE, "Off", "On flights: Off")
    ns.QuickCard.Show("quick")
    ns.QuickCard.ToggleOptions()
    local found
    for _, control in ipairs(ns.QuickCard.options.controls) do
        if control.text == "On flights: Ask me" then found = true end
    end
    eq(found, true, "the card's Options tab uses the new names")
end

-- The welcome window: rows apply settings, /lf setup reopens it.
do
    local ns = load()
    local W = ns.HammerCore.Welcome
    eq(W.spec.tagline, "You read the quest text, right?", "tagline")
    eq(W.spec.bannerSize[1], 1024, "banner size")
    eq(W.queued and W.queued.mode, "intro", "a new install gets the intro")
    eq(#W.queued.rows, 2, "with both rows")
    local rows = {}
    for _, row in ipairs(W.spec.rows) do rows[row.key] = row end
    eq(rows.flights.get(), "OFFER", "flights row reads On flights")
    rows.flights.set("START")
    eq(ns.db.qpOnFlights, "START", "Auto-start from the welcome")
    rows.flights.set("NONE")
    eq(ns.db.qpOnFlights, "NONE", "Off from the welcome")
    eq(rows.daily.get(), "on", "daily row reads Offer at login")
    rows.daily.set("off")
    eq(ns.db.dailyOffer, false, "Off: no login offer")
    eq(ns.db.dailyOn, true, "but the daily stays")
    eq(rows.daily.get(), "off", "reads back off")
    ns.db.dailyOn = false
    rows.daily.set("on")
    eq(ns.db.dailyOffer and ns.db.dailyOn, true, "On turns both on")
    -- /lf setup, and the clicks in the window.
    assert(ns.HammerCore.Commands.byName.setup, "setup command")
    assert(ns.HammerCore.Commands.byName.daily, "daily command")
    assert(ns.HammerCore.Commands.byName.quick, "quick command still there")
    SlashCmdList.LOREFORGE("setup")
    eq(W:IsShown(), true, "/lf setup opens it")
    eq(W.frame.tagline.text, "You read the quest text, right?", "tagline shows")
    eq(W.frame.intro.text, W.spec.intro, "intro text")
    local ask = wow.FindButton("Ask me")
    assert(ask, "Ask me choice")
    ask.scripts.OnClick(ask)
    eq(ns.db.qpOnFlights, "OFFER", "clicking Ask me applies it")
    W:Hide()
    -- The banner ships at 1024 x 256.
    local file = assert(io.open("Textures/welcome-banner.tga", "rb"))
    local header = file:read(18)
    file:close()
    eq(header:byte(13) + header:byte(14) * 256, 1024, "banner width")
    eq(header:byte(15) + header:byte(16) * 256, 256, "banner height")
end
do
    -- An update from 1.1.0 shows the two new rows with the update text.
    local ns = load({ saved = { hammerCore = { whatsNewSeen = "1.1.0" } } })
    local W = ns.HammerCore.Welcome
    eq(W.queued and W.queued.mode, "update", "updating players get the update text")
    eq(#W.queued.rows, 2, "both 1.3.0 rows")
end

io.write("test_daily: ok\n")
