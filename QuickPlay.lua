local _, ns = ...
local HC = ns.HammerCore

-- Quick play: a one-click solo quiz on a small card, for flights and idle
-- moments. Nothing goes to chat, History or the party Hall of Fame; it keeps
-- its own personal bests. QuickCard.lua draws it; this file is the game:
--
--   Quick play        endless; per-question timer unless Relaxed
--   Streak            until the first miss; per-question timer unless Relaxed
--   Lightning         as many as you can before the clock (qpLightning) ends
--   Flight challenge  as many as you can before you land (HC.Flights)
--
-- A mode change waits for the open question. Landing never cuts a question
-- off: it finishes, then the Touchdown! summary shows.

local Quick = { state = nil }
ns.Quick = Quick

local LOREMASTER_TITLE = 93 -- the title mask ID IsTitleKnown takes (125 is the record ID)
local REVEAL_FAST = 0.8      -- seconds a reveal shows in Lightning, where every second counts
local COUNTDOWN = 3
local TOUCHDOWN_CLOSE = 6
local LOREMASTER_SHARE = 3   -- one prompt in this many uses a Loremaster line

Quick.DEFAULTS = {
    qpMode = "quick", qpRelaxed = false, qpSeconds = 15, qpLightning = 60, qpAutoNext = true, qpNextDelay = 2,
    qpSize = "MEDIUM", qpArt = true, qpAnimations = true, qpOnFlights = "OFFER", qpShortest = 20,
    qpCloseOnLanding = true, qpLoremaster = true,
    qpFlightReveal = 3,   -- seconds an answer shows in Flight challenge
    qpLandingGrace = 10,  -- seconds to finish the open question after landing (0 ends straight away)
    soloMain = "QUICK",   -- the Play tab's main button when solo: QUICK or PRACTICE
}
Quick.LIMITS = { qpSeconds = { 5, 30 }, qpLightning = { 30, 180 }, qpNextDelay = { 1, 5 }, qpShortest = { 0, 60 },
    qpFlightReveal = { 1, 8 }, qpLandingGrace = { 0, 30 } }
Quick.SIZES = { SMALL = 0.85, MEDIUM = 1, LARGE = 1.2 }
Quick.ON_FLIGHTS = { "OFFER", "START", "NONE" }
Quick.ON_FLIGHTS_LABELS = { OFFER = "Ask me", START = "Auto-start", NONE = "Off" }
for key, value in pairs(Quick.DEFAULTS) do ns.DEFAULTS[key] = value end

Quick.MODES = {
    { key = "quick", label = "Quick play", line = "Endless questions",
        tip = "Questions keep coming until you close the card. The timer applies unless Relaxed mode is on." },
    { key = "streak", label = "Streak", line = "Until your first miss",
        tip = "Keep answering until you get one wrong. Relaxed mode removes the timer, but one miss still ends it." },
    { key = "lightning", label = "Lightning", line = "Beat the clock",
        tip = "Answer as many as you can before the time runs out. Wrong answers don't end it. Length is set on the settings page." },
    { key = "flight", label = "Flight challenge", line = "Until you land", ground = "Only on flights",
        tip = "Answer as many as you can before you land. The clock counts down to landing, and wrong answers don't end it.",
        groundTip = "Take a flight to play this." },
}
Quick.MODE = {}
for _, mode in ipairs(Quick.MODES) do Quick.MODE[mode.key] = mode end
-- The daily question (Daily.lua) plays on the card too, but isn't one of the
-- modes you switch between.
Quick.MODE.daily = { key = "daily", label = "Daily question", line = "One try, no timer",
    tip = "The same question for everyone today. One try, no timer. Answer it right to keep your streak going." }

-- "Fancy a question?" lines (Kevin's wording).
Quick.LINES = {
    "You've got time to kill (instead of mobs). Fancy a question?",
    "Azeroth looks lovely from up here. How well do you know it?",
    "No steering required. Fancy putting your brain to work?",
    "Your destination is set. Ready to test your knowledge?",
    "A captive audience of one. Up for a quick quiz?",
    "You've paid for the flight. Fancy getting an education too?",
    "Explored Azeroth? How much do you remember?",
    "Can't fight, can't loot, can't dismount. Fancy a little trivia?",
    "Know Azeroth better than your flight master?",
    "Got a few minutes to spare? Fancy a test of your lore?",
}
-- For characters with the Loremaster title, on Retail.
Quick.LOREMASTER_LINES = {
    "Loremaster, eh? Fancy proving you've earned that title?",
    "Think you know everything, Loremaster? Fancy a question?",
    "How much of that lore do you actually remember, Loremaster?",
    "Loremaster on board! Shall we put that title to the test?",
    "One more question couldn't hurt, could it, Loremaster?",
}

local function now() return GetTime and GetTime() or 0 end
local function stamp() return (GetServerTime and GetServerTime()) or (time and time()) or 0 end
local function random(n) return math.random and math.random(n) or 1 end

local function flights() return HC.Flights and HC.Flights.enabled and HC.Flights or nil end

function Quick.Flying()
    local f = flights()
    return f and f:Flying() or false
end

-- ── Settings and saved data ────────────────────────────────────────────────

function Quick.Initialise()
    local db = ns.db
    for key, spec in pairs(Quick.LIMITS) do
        local value = tonumber(db[key])
        if not value or value ~= value then db[key] = Quick.DEFAULTS[key]
        else db[key] = math.max(spec[1], math.min(spec[2], math.floor(value))) end
    end
    if not Quick.SIZES[db.qpSize] then db.qpSize = Quick.DEFAULTS.qpSize end
    if not Quick.ON_FLIGHTS_LABELS[db.qpOnFlights] then db.qpOnFlights = Quick.DEFAULTS.qpOnFlights end
    if db.soloMain ~= "QUICK" and db.soloMain ~= "PRACTICE" then db.soloMain = Quick.DEFAULTS.soloMain end
    if db.soloLeftClick ~= "WINDOW" and db.soloLeftClick ~= "QUICK" then db.soloLeftClick = "WINDOW" end
    if not Quick.MODE[db.qpMode] or db.qpMode == "flight" then db.qpMode = "quick" end
    for _, key in ipairs({ "quickBests", "quickToday", "quickUsed" }) do
        if type(db[key]) ~= "table" then db[key] = {} end
        if type(db[key][ns.era]) ~= "table" then db[key][ns.era] = {} end
    end
    -- Registered before HC:Start switches flights on.
    local f = HC.Flights
    if f then
        f:OnTakeoff(function(info) Quick.Takeoff(info) end)
        f:OnLanding(function(info) Quick.Landed(info) end)
    end
end

function Quick.Bests() return ns.db.quickBests[ns.era] end

local function today()
    local day = date and date("%Y-%m-%d") or "today"
    local record = ns.db.quickToday[ns.era]
    if record.day ~= day then
        record.day, record.answered, record.correct = day, 0, 0
    end
    return record
end
Quick.Today = today

function Quick.HasLoremaster()
    if ns.era ~= "retail" or type(IsTitleKnown) ~= "function" then return false end
    local ok, known = pcall(IsTitleKnown, LOREMASTER_TITLE)
    return ok and known == true
end

function Quick.LoremasterReport()
    if type(IsTitleKnown) ~= "function" then return "Loremaster title (93): Not available" end
    local ok, known = pcall(IsTitleKnown, LOREMASTER_TITLE)
    if not ok then return "Loremaster title (93): Not available" end
    return "Loremaster title (93): " .. (known == true and "Known" or "Not known")
end

function Quick.Report()
    local f = flights()
    local bests = Quick.Bests()
    local lines = { "Quick play: " .. (Quick.state and (Quick.state.mode .. ", " .. Quick.state.phase) or "closed"),
        Quick.LoremasterReport(),
        "On flights: " .. tostring(ns.db.qpOnFlights) .. (f and "" or " (flights off)"),
        "Best streak: " .. tostring(bests.streak and bests.streak.value or 0)
            .. ", best flight: " .. tostring(bests.flight and bests.flight.value or 0) }
    if ns.Daily then
        local ok, report = pcall(ns.Daily.Report)
        lines[#lines + 1] = ok and report or ("Daily: " .. tostring(report))
    end
    return table.concat(lines, "\n")
end

-- A line for the takeoff prompt, never the same twice running.
function Quick.PromptLine()
    local pool = Quick.LINES
    if ns.db.qpLoremaster ~= false and Quick.HasLoremaster() and random(LOREMASTER_SHARE) == 1 then
        pool = Quick.LOREMASTER_LINES
    end
    local index = random(#pool)
    if pool[index] == Quick.lastLine and #pool > 1 then index = index % #pool + 1 end
    Quick.lastLine = pool[index]
    return pool[index]
end

-- ── Questions ──────────────────────────────────────────────────────────────

local function categoryOf(entry)
    for _, tag in ipairs(ns.Game.Categories(entry)) do
        if ns.db.categories[tag] then return tag end
    end
    return "mixed"
end

local function categoryLabel(key)
    for _, category in ipairs(ns.Game.CATEGORIES) do
        if category[1] == key then return category[2] end
    end
    return "A bit of everything"
end
Quick.CategoryLabel = categoryLabel

function Quick.Pool()
    return ns.Game.Pool(HC.QUIZ, { categories = ns.db.categories, difficulty = ns.db.difficulty }, ns.era)
end

-- The next question: no repeats until every question in the pool is used.
function Quick.Draw()
    local pool = Quick.Pool()
    if #pool == 0 then return nil end
    local used = ns.db.quickUsed[ns.era]
    local fresh = {}
    for _, entry in ipairs(pool) do
        if not used[entry.id or entry[1]] then fresh[#fresh + 1] = entry end
    end
    if #fresh == 0 then
        for key in pairs(used) do used[key] = nil end
        fresh = pool
    end
    local entry = fresh[random(#fresh)]
    used[entry.id or entry[1]] = true
    local choices = { entry[2], entry[3], entry[4], entry[5] }
    for i = 4, 2, -1 do
        local j = random(i)
        choices[i], choices[j] = choices[j], choices[i]
    end
    local correct
    for i, choice in ipairs(choices) do if choice == entry[2] then correct = i end end
    local category = categoryOf(entry)
    return { text = entry[1], choices = choices, correct = correct, category = category,
        categoryLabel = categoryLabel(category) }
end

-- ── The run ────────────────────────────────────────────────────────────────

-- Whether this mode has a per-question timer.
function Quick.Timed(mode)
    mode = mode or (Quick.state and Quick.state.mode) or ns.db.qpMode
    if mode == "daily" then return false end
    return (mode == "quick" or mode == "streak") and not ns.db.qpRelaxed
end

local function changed()
    if ns.QuickCard and ns.QuickCard.Render then ns.QuickCard.Render() end
end

local function ask(s)
    s.question = Quick.Draw()
    if not s.question then
        s.phase, s.summary = "over", { kind = "empty", title = "No questions",
            lines = { "No questions match your categories and difficulty." } }
        return
    end
    s.phase, s.choice, s.revealUntil = "question", nil, nil
    s.questionDeadline = Quick.Timed(s.mode) and (now() + ns.db.qpSeconds) or nil
end

-- The daily question: today's one question, or its summary once answered.
function Quick.StartDaily()
    local Daily = ns.Daily
    local today = Daily.Today()
    local s = { mode = "daily", correct = 0, answered = 0, streak = Daily.Streak(today), bestStreak = 0,
        started = now(), day = today.number }
    Quick.state = s
    local summary = Daily.Summary(today)
    if summary then
        s.phase, s.summary = "over", summary
        s.dailyId = Daily.Answered(today).id
    else
        s.question = Daily.Question(today)
        if s.question then
            s.dailyId = s.question.id
            s.phase, s.choice, s.revealUntil = "question", nil, nil
        else
            s.phase, s.summary = "over", { kind = "empty", title = "No questions",
                lines = { "There's no daily question today." } }
        end
    end
    changed()
    return s
end

-- mode: a Quick.MODE key. options.countdown opens with "starting in 3".
function Quick.Start(mode, options)
    options = options or {}
    if mode == "daily" then return Quick.StartDaily() end
    if mode == "flight" and not Quick.Flying() then mode = "quick" end
    if not Quick.MODE[mode] then mode = "quick" end
    if mode ~= "flight" then ns.db.qpMode = mode end
    local s = { mode = mode, correct = 0, answered = 0, streak = 0, bestStreak = 0, started = now() }
    if mode == "lightning" then s.length = ns.db.qpLightning end
    if mode == "flight" then
        local current = flights():Current()
        s.flight = { from = current and current.from, to = current and current.to }
    end
    Quick.state = s
    if options.countdown then
        s.phase, s.countdownUntil = "countdown", now() + COUNTDOWN
    else
        if mode == "lightning" then s.deadline = now() + s.length end
        ask(s)
    end
    changed()
    return s
end

-- Waits for the open question, then switches.
function Quick.SetMode(mode)
    if not Quick.MODE[mode] or (mode == "flight" and not Quick.Flying()) then return false end
    local s = Quick.state
    -- Leaving an unanswered daily is fine: it waits until it's answered.
    if s and s.phase == "question" and s.mode ~= "daily" and mode ~= "daily" then
        s.pendingMode = mode ~= s.mode and mode or nil
        if mode ~= "flight" then ns.db.qpMode = mode end
        changed()
        return true
    end
    Quick.Start(mode)
    return true
end

function Quick.Close()
    Quick.state = nil
    changed()
end

local function setBest(key, value, extra)
    local bests = Quick.Bests()
    local old = bests[key]
    if value <= 0 or (old and (tonumber(old.value) or 0) >= value) then return false end
    local best = { value = value, at = stamp() }
    for k, v in pairs(extra or {}) do best[k] = v end
    bests[key] = best
    return true
end

function Quick.LightningBest(length)
    local all = Quick.Bests().lightning
    return type(all) == "table" and all[tostring(length or ns.db.qpLightning)] or nil
end

local function setLightningBest(length, value)
    local bests = Quick.Bests()
    bests.lightning = type(bests.lightning) == "table" and bests.lightning or {}
    local key = tostring(length)
    local old = bests.lightning[key]
    if value <= 0 or (old and (tonumber(old.value) or 0) >= value) then return false end
    bests.lightning[key] = { value = value, at = stamp(), length = length }
    return true
end

local function finish(s, kind)
    local summary = { kind = kind }
    if kind == "streak" then
        summary.title = "Streak over"
        summary.lines = { s.correct .. " in a row" }
        -- The miss that ended it stays readable after the reveal.
        if s.missedAnswer then summary.note = s.missedAnswer end
        summary.newBest = setBest("streak", s.correct)
    elseif kind == "lightning" then
        summary.title = "Time!"
        summary.lines = { s.correct .. " right in " .. s.length .. "s" }
        summary.newBest = setLightningBest(s.length, s.correct)
    elseif kind == "daily" then
        summary = ns.Daily.Summary() or { kind = "daily", title = "Daily question", lines = {} }
        summary.newBest = s.lastRight and ns.Daily.Streak() > 1 and ns.Daily.Streak() >= ns.Daily.Best() or nil
    elseif kind == "touchdown" then
        summary.title = "Touchdown!"
        summary.lines = { s.correct .. " right this flight", "Best streak " .. s.bestStreak }
        summary.newBest = setBest("flight", s.correct, { answered = s.answered,
            from = s.flight and s.flight.from, to = s.flight and s.flight.to })
        if ns.db.qpCloseOnLanding then summary.closeAt = now() + TOUCHDOWN_CLOSE end
    end
    if summary.newBest then summary.lines[#summary.lines + 1] = "New best!" end
    s.phase, s.summary, s.question = "over", summary, nil
    ns.Sound("finish")
end

-- index 1-4, or nil when the question timed out.
function Quick.Answer(index)
    local s = Quick.state
    if not (s and s.phase == "question" and s.question) then return false end
    local right = index ~= nil and index == s.question.correct
    s.choice = index
    if s.mode == "daily" then
        local today = ns.Daily.Today()
        if s.day ~= today.number then
            Quick.StartDaily()
            return false
        end
        -- One try: it counts once, then the summary.
        if not ns.Daily.Record(s.question, index, right, today) then
            Quick.StartDaily()
            return false
        end
        s.answered, s.correct = 1, right and 1 or 0
        s.streak, s.lastRight = ns.Daily.Streak(), right
        ns.Sound(right and "correct" or "wrong")
        s.phase, s.revealUntil, s.endAfterReveal = "reveal", now() + 2, "daily"
        changed()
        return right
    end
    s.answered = s.answered + 1
    local record = today()
    record.answered = record.answered + 1
    if right then
        s.correct, s.streak = s.correct + 1, s.streak + 1
        s.bestStreak = math.max(s.bestStreak, s.streak)
        record.correct = record.correct + 1
        if s.mode == "quick" then setBest("streak", s.streak) end
    else
        s.streak = 0
    end
    s.lastRight = right
    ns.Sound(right and "correct" or "wrong")
    s.phase = "reveal"
    s.landedDeadline = nil
    if s.mode == "streak" and not right then
        local q = s.question
        s.missedAnswer = q and q.choices and q.choices[q.correct] and ("It was " .. q.choices[q.correct] .. ".") or nil
        s.revealUntil, s.endAfterReveal = now() + math.max(2.5, ns.db.qpNextDelay or 2), "streak"
    elseif s.landed then
        s.revealUntil, s.endAfterReveal = now() + math.max(1.5, ns.db.qpFlightReveal or 3), "touchdown"
    elseif s.mode == "flight" then
        s.revealUntil = now() + (ns.db.qpFlightReveal or 3)
    elseif s.mode == "lightning" then
        s.revealUntil = now() + REVEAL_FAST
    elseif ns.db.qpAutoNext then
        s.revealUntil = now() + ns.db.qpNextDelay
    else
        s.revealUntil = nil
    end
    changed()
    return right
end

function Quick.Next()
    local s = Quick.state
    if not s then return end
    if s.endAfterReveal then
        finish(s, s.endAfterReveal)
        changed()
        return
    end
    if s.pendingMode then
        local mode = s.pendingMode
        s.pendingMode = nil
        Quick.Start(mode)
        return
    end
    ask(s)
    changed()
end

-- The card hides in combat. Its clocks stop meanwhile, except a flight's.
function Quick.Pause()
    local s = Quick.state
    if s and not s.pausedAt then s.pausedAt = now() end
end

function Quick.Resume()
    local s = Quick.state
    if not (s and s.pausedAt) then return end
    local gap = now() - s.pausedAt
    s.pausedAt = nil
    for _, key in ipairs({ "questionDeadline", "deadline", "revealUntil", "countdownUntil", "landedDeadline" }) do
        if s[key] then s[key] = s[key] + gap end
    end
    if s.summary and s.summary.closeAt then s.summary.closeAt = s.summary.closeAt + gap end
end

-- Touchdown! or after-run: carry on in Quick play.
function Quick.KeepGoing()
    Quick.Start("quick")
end

-- Called every frame the card shows.
function Quick.Tick()
    local s = Quick.state
    if not s then return end
    local t = now()
    if s.phase == "countdown" then
        if t >= s.countdownUntil then
            s.countdownUntil = nil
            if s.mode == "lightning" then s.deadline = t + s.length end
            ask(s)
            changed()
        end
    elseif s.phase == "question" then
        if s.mode == "lightning" and s.deadline and t >= s.deadline then finish(s, "lightning"); changed()
        elseif s.landedDeadline and t >= s.landedDeadline then
            -- Out of landing grace: the open question isn't counted.
            s.landedDeadline = nil
            finish(s, "touchdown"); changed()
        elseif s.questionDeadline and t >= s.questionDeadline then Quick.Answer(nil) end
    elseif s.phase == "reveal" then
        if s.mode == "lightning" and s.deadline and t >= s.deadline and not s.endAfterReveal then
            finish(s, "lightning"); changed()
        elseif s.revealUntil and t >= s.revealUntil then Quick.Next() end
    elseif s.phase == "over" then
        if s.summary and s.summary.closeAt and t >= s.summary.closeAt then
            if ns.QuickCard then ns.QuickCard.Hide() else Quick.Close() end
        end
    end
end

-- The clock line: "12 s", "0:45 left", "1:12 to landing", "Until you land".
local function clock(seconds)
    seconds = math.max(0, math.ceil(seconds))
    return math.floor(seconds / 60) .. ":" .. string.format("%02d", seconds % 60)
end
Quick.ClockText = clock

function Quick.Clock()
    local s = Quick.state
    if not s then return "" end
    local t = now()
    if s.mode == "daily" then
        return ns.Daily.Label(s.day or ns.Daily.Today().number)
    elseif s.mode == "flight" then
        if s.landed then
            if s.landedDeadline and s.phase == "question" then
                return "Landed: " .. math.max(0, math.ceil(s.landedDeadline - t)) .. " s"
            end
            return "Landed"
        end
        local current = flights() and flights():Current()
        if current and current.remaining then return clock(current.remaining) .. " to landing" end
        return "Until you land"
    elseif s.mode == "lightning" then
        if not s.deadline then return clock(s.length) .. " left" end
        return clock(s.deadline - t) .. " left"
    elseif s.questionDeadline and s.phase == "question" then
        return math.max(0, math.ceil(s.questionDeadline - t)) .. " s"
    end
    return Quick.Timed(s.mode) and "" or "Relaxed"
end

-- Fraction of the per-question time left, or nil without a timer.
function Quick.TimerFraction()
    local s = Quick.state
    if not s then return nil end
    local t = now()
    if s.mode == "lightning" and s.deadline then return math.max(0, (s.deadline - t) / s.length), s.deadline - t end
    if s.mode == "flight" and s.landedDeadline and s.phase == "question" then
        local grace = math.max(1, s.landedGrace or 1)
        return math.max(0, (s.landedDeadline - t) / grace), s.landedDeadline - t
    end
    if s.mode == "flight" then
        local current = flights() and flights():Current()
        if current and current.seconds and current.remaining and current.seconds > 0 then
            return current.remaining / current.seconds, current.remaining
        end
        return nil
    end
    if s.questionDeadline and s.phase == "question" then
        return math.max(0, (s.questionDeadline - t) / ns.db.qpSeconds), s.questionDeadline - t
    end
end

-- ── Flights ────────────────────────────────────────────────────────────────

function Quick.Takeoff(info)
    if not info or info.resumed then return end
    if ns.QuickCard and ns.QuickCard.IsShown() then changed(); return end
    local choice = ns.db.qpOnFlights
    if choice == "OFFER" then
        if ns.QuickCard then ns.QuickCard.Prompt() end
    elseif choice == "START" then
        local shortest = ns.db.qpShortest or 0
        if info.seconds and info.seconds < shortest then return end
        if ns.QuickCard then ns.QuickCard.Show("flight", { countdown = true }) else Quick.Start("flight", { countdown = true }) end
    end
end

function Quick.Landed(info)
    if ns.QuickCard then
        ns.QuickCard.HidePrompt(true)
        ns.QuickCard.HideLauncher()
        if Quick.state and Quick.state.pausedAt and not ns.QuickCard.IsShown() and not ns.QuickCard.combatHidden then
            Quick.Close()
        end
    end
    local s = Quick.state
    if not (s and s.mode == "flight") then changed(); return end
    s.landed = info or {}
    if s.phase == "countdown" then
        Quick.Close()
        if ns.QuickCard then ns.QuickCard.Hide() end
        return
    end
    if s.phase == "question" then
        -- A short grace to finish the open question, then Touchdown.
        local grace = ns.db.qpLandingGrace or 10
        if grace <= 0 then finish(s, "touchdown")
        else s.landedGrace, s.landedDeadline = grace, now() + grace end
    elseif s.phase ~= "over" then
        -- Between questions: finish now.
        if s.phase == "reveal" then s.endAfterReveal = "touchdown"; s.revealUntil = s.revealUntil or now()
        else finish(s, "touchdown") end
    end
    changed()
end

-- ── Best lines and tooltips ────────────────────────────────────────────────

local function day(at)
    if not (date and at) then return nil end
    return (date("%d %b %Y", at):gsub("^0", ""))
end
Quick.Day = day

-- One best per mode: { text, detail lines } or nil.
function Quick.BestLine(mode)
    local bests = Quick.Bests()
    if mode == "daily" then
        local Daily = ns.Daily
        if not Daily then return nil end
        local state = Daily.State()
        if not state.lastNumber then return nil end
        local detail = {}
        if state.best > 0 and day(state.bestAt) then detail[1] = "Best " .. state.best .. " on " .. day(state.bestAt) end
        return { text = Daily.FooterText(), detail = detail }
    elseif mode == "quick" then
        local record = today()
        if record.answered == 0 then return nil end
        return { text = "Today: " .. record.correct .. " of " .. record.answered }
    elseif mode == "streak" then
        local best = bests.streak
        if not best then return nil end
        return { text = "Best streak: " .. best.value, detail = { day(best.at) } }
    elseif mode == "lightning" then
        local best = Quick.LightningBest()
        if not best then return nil end
        return { text = "Best Lightning: " .. best.value .. " in " .. best.length .. "s", detail = { day(best.at) } }
    elseif mode == "flight" then
        local best = bests.flight
        if not best then return nil end
        local route = best.from and best.to and (best.from .. " to " .. best.to) or nil
        local detail = {}
        if route then detail[#detail + 1] = route end
        if day(best.at) then detail[#detail + 1] = day(best.at) end
        if best.answered then detail[#detail + 1] = best.value .. " right of " .. best.answered end
        return { text = "Best flight: " .. best.value .. " right", detail = detail,
            short = route and (route .. (day(best.at) and (", " .. day(best.at)) or "")) or day(best.at) }
    end
end
