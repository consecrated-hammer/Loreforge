package.path = "./tests/hammercore/?.lua;" .. package.path
local wow = require("wow")
local function eq(a, b, why) assert(a == b, why .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local function has(text, needle, why) assert(tostring(text):find(needle, 1, true), why .. ": " .. tostring(text)) end

local clock, combat, taxi, hooks, titles, era
local function load(options)
    options = options or {}
    era = options.era or "retail"
    local toc = era == "classic" and "Loreforge_Camelot.toc" or "Loreforge.toc"
    wow.Install({ Loreforge = { Version = "1.2.0" } })
    LoreforgeDB = options.saved
    clock, combat, taxi, hooks, titles = 100, false, false, {}, options.titles or {}
    GetTime = function() return clock end
    GetServerTime = function() return 1762740000 + clock end
    date = os.date
    InCombatLockdown = function() return combat end
    GetBuildInfo = function() return "version", "build", "date", era == "classic" and 16001 or 120105 end
    WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
    GetNormalizedRealmName = function() return "Realm" end
    UnitFullName = function(unit) return unit == "player" and "Host" or nil, "Realm" end
    GetUnitName = function(unit) return (UnitFullName(unit)) end
    UnitGUID = function(unit) return unit == "player" and "hostGUID" or nil end
    IsInRaid = function() return false end
    GetNumSubgroupMembers = function() return 0 end
    RegisterStateDriver = function() end
    UnregisterStateDriver = function() end
    IsTitleKnown = function(id) return titles[id] == true end
    if options.noTitles then IsTitleKnown = nil end
    -- Flight paths: Booty Bay (slot 1, node 19) straight to Orgrimmar (slot 2, node 23).
    UnitOnTaxi = function() return taxi end
    hooksecurefunc = function(name, fn) hooks[name] = fn end
    TakeTaxiNode = function() end
    TaxiRequestEarlyLanding = function() end
    C_Timer = nil
    GetTaxiMapID = function() return 1 end
    C_TaxiMap = { GetAllTaxiNodes = function() return { { slotIndex = 1, nodeID = 19 }, { slotIndex = 2, nodeID = 23 } } end }
    NumTaxiNodes = function() return 2 end
    TaxiNodeName = function(slot) return slot == 1 and "Booty Bay" or "Orgrimmar" end
    TaxiNodeGetType = function(slot) return slot == 1 and "CURRENT" or "REACHABLE" end
    GetNumRoutes = function() return 1 end
    TaxiGetNodeSlot = function(slot, _, source) return source and 1 or slot end
    LibTaxiData_API = { GetOutgoingPaths = function(node)
        return node == 19 and { { toNodeID = 23, distanceYards = options.yards or 3040 } } or {}
    end }
    assert(loadfile('tests/transport-libs.lua'))()()
    -- The transport stubs replace hooksecurefunc; keep ours for the taxi hooks.
    hooksecurefunc = function(name, fn) hooks[name] = fn end
    local ns = wow.LoadHammerCore("Libs/HammerCore", "Loreforge")
    for file in assert(io.open(toc)):read("*a"):gmatch("([^\r\n]+)") do
        if file:match("^[%w]+%.lua$") then assert(loadfile(file))("Loreforge", ns) end
    end
    local loader
    for _, f in ipairs(wow.frames) do if f.scripts.OnEvent then loader = f end end
    loader.scripts.OnEvent(loader, "ADDON_LOADED", "Loreforge")
    return ns
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

local function flightEvent(ns, event) ns.HammerCore.Flights.frame.scripts.OnEvent(ns.HammerCore.Flights.frame, event) end

local function takeOff(ns)
    hooks.TakeTaxiNode(2)
    taxi = true
    flightEvent(ns, "PLAYER_CONTROL_LOST")
end

local function land(ns, after)
    clock = clock + after
    taxi = false
    flightEvent(ns, "PLAYER_CONTROL_GAINED")
end

-- Defaults and the dependency.
do
    local ns = load()
    eq(ns.db.qpRelaxed, false, "timer on by default")
    eq(ns.db.qpOnFlights, "OFFER", "offer on flights by default")
    eq(ns.db.qpCloseOnLanding, true, "close on landing by default")
    eq(ns.HammerCore.Flights.enabled, true, "Loreforge turns HammerCore flights on")
    for _, toc in ipairs({ "Loreforge.toc", "Loreforge_Camelot.toc" }) do
        has(assert(io.open(toc)):read("*a"), "## OptionalDeps: LibTaxiData", toc .. " loads LibTaxiData first when installed")
    end
    has(assert(io.open(".pkgmeta")):read("*a"), "optional-dependencies:\n  - libtaxidata", ".pkgmeta lists libtaxidata as optional")
end

-- Quick play: one click, a timed question, scoring and today's count.
do
    local ns = load()
    SlashCmdList.LOREFORGE("quick")
    local card, s = ns.QuickCard.frame, ns.Quick.state
    eq(card:IsShown(), true, "/lf quick opens the card")
    eq(s.mode, "quick", "Quick play by default")
    eq(s.phase, "question", "a question straight away")
    eq(card.title.text, "Loreforge · Quick play", "card title names the mode")
    eq(card.clock.text, "15 s", "per-question timer")
    has(card.art.texture, "theme-", "category painting")
    eq(card.caption.text, s.question.categoryLabel, "caption names the category")
    answer(ns, true)
    eq(s.phase, "reveal", "answer revealed")
    eq(card.feedback.text:sub(1, 8), "Correct!", "feedback")
    tick(ns, 2.1)
    eq(s.phase, "question", "next question after the wait")
    eq(s.answered, 1, "one answered")
    tick(ns, 15.1)
    eq(s.phase, "reveal", "the timer runs out")
    eq(s.choice, nil, "timed out without a choice")
    has(card.feedback.text, "Time's up", "time's up feedback")
    eq(ns.Quick.Today().answered, 2, "today counts every answer")
    eq(ns.Quick.Today().correct, 1, "today counts right answers")
    has(card.footer.text, "Today 1 / 2", "footer shows today")
    -- The answer keys answer on the card.
    tick(ns, 2.1)
    LoreforgeAnswer(s.question.correct)
    eq(s.lastRight, true, "Answer key answers Quick play")
    -- Relaxed: no timer.
    tick(ns, 2.1)
    ns.db.qpRelaxed = true
    ns.Quick.Start("quick")
    eq(ns.Quick.state.questionDeadline, nil, "relaxed has no timer")
    eq(card.clock.text, "Relaxed", "relaxed clock text")
    -- Next by click when automatic is off.
    ns.db.qpAutoNext = false
    answer(ns, true)
    tick(ns, 10)
    eq(ns.Quick.state.phase, "reveal", "waits for Next")
    eq(card.next:IsShown(), true, "Next button")
    card.next.scripts.OnClick(card.next)
    eq(ns.Quick.state.phase, "question", "Next moves on")
    -- Closing ends the run.
    card.closeButton.scripts.OnClick(card.closeButton)
    eq(card:IsShown(), false, "close hides the card")
    eq(ns.Quick.state, nil, "close ends the run")
end

-- Without LibTaxiData: no countdown on a new route, then the learned time.
do
    local ns = load()
    LibTaxiData_API = nil
    takeOff(ns)
    ns.QuickCard.prompt.flight.scripts.OnClick(ns.QuickCard.prompt.flight)
    eq(ns.QuickCard.frame.clock.text, "Until you land", "no countdown without LibTaxiData")
    land(ns, 80)
    takeOff(ns)
    ns.QuickCard.Show("flight")
    eq(ns.QuickCard.frame.clock.text, "1:20 to landing", "the learned time next flight")
    land(ns, 80)
end

-- Right-click on the minimap button: HammerCore's settings, then Hall of
-- Fame, the daily question, a line and the modes.
do
    local ns = load()
    local menu = ns.HammerCore.Minimap:MenuItems()
    eq(menu[1].text, "Loreforge settings", "HammerCore's settings first")
    eq(menu[2].separator, true, "then HammerCore's line")
    eq(menu[3].text, "Hall of Fame", "Hall of Fame")
    local items = ns.QuickCard.MenuItems()
    eq(items[1].text, "Hall of Fame", "Hall of Fame leads Loreforge's items")
    eq(items[2].text, "Daily question", "the daily question")
    eq(items[3].separator, true, "then a line")
    eq(items[4].text, "Quick play", "then the modes")
    eq(items[7].disabled, true, "Flight challenge greyed on the ground")
    eq(items[7].text, "Flight challenge (on flights)", "and says why")
    for _, item in ipairs(items) do assert(item.text ~= "Loreforge settings", "HammerCore adds settings, not Loreforge") end
    items[6].func()
    eq(ns.Quick.state.mode, "lightning", "a mode opens the card in it")
    eq(ns.QuickCard.MenuItems()[6].checked, true, "the current mode is ticked")
    wow.Click(ns.HammerCore.Minimap.button, "RightButton")
    eq(ns.HammerCore.Menu.frame:IsShown(), true, "right-click opens the menu")
    takeOff(ns)
    eq(ns.QuickCard.MenuItems()[7].disabled, nil, "Flight challenge on a flight")
    land(ns, 100)
    -- The daily item opens it, and says when it's done.
    ns.QuickCard.MenuItems()[2].func()
    eq(ns.Quick.state.mode, "daily", "the daily item opens the daily question")
    answer(ns, true)
    eq(ns.QuickCard.MenuItems()[2].text, "Daily question (done)", "done once answered")
    ns.db.dailyOn = false
    eq(ns.QuickCard.MenuItems()[2].separator, true, "no daily item with the daily off")
end

-- No repeats until the pool is used up.
do
    local ns = load()
    local pool = #ns.Quick.Pool()
    local seen = {}
    for _ = 1, pool do
        local q = ns.Quick.Draw()
        assert(not seen[q.text], "a repeat before the pool ran out: " .. q.text)
        seen[q.text] = true
    end
    assert(ns.Quick.Draw(), "the pool starts again")
end

-- Streak: a miss ends it, and the best is saved with its date.
do
    local ns = load()
    ns.QuickCard.Show("streak")
    local card = ns.QuickCard.frame
    answer(ns, true); tick(ns, 2.1)
    answer(ns, true); tick(ns, 2.1)
    answer(ns, false); tick(ns, 1.6)
    eq(ns.Quick.state.phase, "reveal", "the miss stays readable for a moment")
    tick(ns, 1)
    local s = ns.Quick.state
    eq(s.phase, "over", "a miss ends the streak")
    has(card.overNote.text, "It was ", "the summary keeps the right answer")
    eq(card.overTitle.text, "Streak over", "summary title")
    has(card.overLines.text, "2 in a row", "summary score")
    has(card.overLines.text, "New best!", "a new best")
    eq(ns.Quick.BestLine("streak").text, "Best streak: 2", "best streak line")
    assert(ns.Quick.BestLine("streak").detail[1], "best streak has a date")
    card.primary.scripts.OnClick(card.primary)
    eq(ns.Quick.state.mode, "streak", "Play again")
end

-- Lightning: the clock ends it; wrong answers don't.
do
    local ns = load()
    ns.QuickCard.Show("lightning")
    local s = ns.Quick.state
    eq(s.questionDeadline, nil, "no per-question timer in Lightning")
    eq(ns.QuickCard.frame.clock.text, "1:00 left", "Lightning clock")
    answer(ns, false); tick(ns, 0.9)
    eq(s.phase, "question", "a wrong answer carries on")
    answer(ns, true); tick(ns, 0.9)
    tick(ns, 60)
    eq(s.phase, "over", "time's up")
    has(ns.QuickCard.frame.overLines.text, "1 right in 60s", "Lightning score")
    eq(ns.Quick.BestLine("lightning").text, "Best Lightning: 1 in 60s", "Lightning best per length")
end

-- Mode changes wait for the open question.
do
    local ns = load()
    ns.QuickCard.Show("quick")
    ns.Quick.SetMode("streak")
    eq(ns.Quick.state.mode, "quick", "still Quick play during the question")
    eq(ns.Quick.state.pendingMode, "streak", "streak is next")
    answer(ns, true); tick(ns, 2.1)
    eq(ns.Quick.state.mode, "streak", "switched after the question")
    eq(ns.Quick.SetMode("flight"), false, "Flight challenge only on flights")
end

-- Options tab: modes with their lines, the timer switch, look settings.
do
    local ns = load()
    ns.QuickCard.Show("quick")
    ns.QuickCard.ToggleOptions()
    local o = ns.QuickCard.options
    eq(o:IsShown(), true, "Options tab opens")
    local flightRow = o.controls[4]
    eq(flightRow.line.text, "Only on flights", "Flight challenge greyed on the ground")
    eq(o.controls[1].line.text, "Endless questions", "mode subtext")
    o.timer.relaxed.scripts.OnClick(o.timer.relaxed)
    eq(ns.db.qpRelaxed, true, "Relaxed from the Options tab")
    ns.Quick.SetMode("lightning")
    answer(ns, true); tick(ns, 2.1)
    eq(ns.Quick.state.mode, "lightning", "now Lightning")
    eq(o.timer.clock.enabled, false, "the timer switch is greyed for Lightning")
    -- Artwork off: no painting, the category becomes a header line.
    local art = o.controls[6]
    art.scripts.OnClick(art)
    eq(ns.db.qpArt, false, "Artwork off")
    eq(ns.QuickCard.frame.art.shown, false, "no painting")
    has(ns.QuickCard.frame.heading.text, ns.Quick.state.question.categoryLabel, "category header line")
    -- Mode tooltips.
    ns.QuickCard.ModeTooltip(flightRow, "flight")
end

-- Takeoff prompt, Loremaster lines and diagnostics.
do
    local ns = load({ titles = { [93] = true } })
    has(ns.HammerCore.DiagnosticReport(), "Loremaster title (93): Known", "diagnostics show the title")
    has(ns.HammerCore.DiagnosticReport(), "LibTaxiData: loaded", "diagnostics show LibTaxiData")
    local random = math.random
    math.random = function(n) return 1 end
    local line = ns.Quick.PromptLine()
    eq(line, ns.Quick.LOREMASTER_LINES[1], "a Loremaster line for the title holder")
    math.random = function(n) return n == 3 and 2 or 1 end
    eq(ns.Quick.PromptLine(), ns.Quick.LINES[1], "the general lines too")
    ns.db.qpLoremaster = false
    math.random = function() return 1 end
    eq(ns.Quick.PromptLine(), ns.Quick.LINES[2], "never the same line twice running; Loremaster lines off")
    math.random = random
    ns.db.qpLoremaster = true
    takeOff(ns)
    local prompt = ns.QuickCard.prompt
    eq(prompt:IsShown(), true, "Fancy a question? on takeoff")
    eq(prompt.flight.line.text, "Until you land", "prompt button subtext")
    prompt.always.scripts.OnClick(prompt.always)
    eq(ns.db.qpOnFlights, "START", "Always start Flight challenge from the prompt")
    prompt.always.scripts.OnClick(prompt.always)
    prompt.dontOffer.scripts.OnClick(prompt.dontOffer)
    eq(ns.db.qpOnFlights, "NONE", "Don't offer on flights from the prompt")
    prompt.dontOffer.scripts.OnClick(prompt.dontOffer)
    prompt.flight.scripts.OnClick(prompt.flight)
    eq(prompt:IsShown(), false, "the prompt closes")
    eq(ns.Quick.state.mode, "flight", "Flight challenge from the prompt")
    eq(ns.QuickCard.frame.clock.text, "1:40 to landing", "countdown to landing from LibTaxiData")
    land(ns, 101)
end
do
    local ns = load({ era = "classic", titles = { [93] = true } })
    eq(ns.Quick.HasLoremaster(), false, "Loremaster lines are Retail only")
    local ns2 = load({ noTitles = true })
    has(ns2.HammerCore.DiagnosticReport(), "Loremaster title (93): Not available", "no title API")
end

-- Flight challenge: auto-start, landing mid-question, Touchdown! and the best flight.
do
    local ns = load()
    ns.db.qpOnFlights = "START"
    takeOff(ns)
    local card, s = ns.QuickCard.frame, ns.Quick.state
    eq(card:IsShown(), true, "auto-start opens the card")
    eq(s.phase, "countdown", "with a countdown")
    has(card.overLines.text, "Starting in 3", "starting in 3")
    eq(card.primary.text, "Not now", "Not now")
    tick(ns, 3.1)
    eq(s.phase, "question", "the challenge starts")
    answer(ns, true); tick(ns, 3.1)
    answer(ns, true); tick(ns, 3.1)
    land(ns, 20)
    eq(card.feedback.text, "Last question!", "landing waits for the question")
    eq(s.phase, "question", "never cut off mid-question")
    answer(ns, false); tick(ns, 3.1)
    eq(s.phase, "over", "Touchdown!")
    eq(card.overTitle.text, "Touchdown!", "Touchdown title")
    has(card.overLines.text, "2 right this flight", "flight score")
    has(card.overLines.text, "Best streak 2", "best streak this flight")
    eq(card.primary.text, "Keep going", "Keep going")
    has(card.overNote.text, "Closing in", "closes on landing")
    local best = ns.Quick.BestLine("flight")
    eq(best.text, "Best flight: 2 right", "best flight")
    eq(best.detail[1], "Booty Bay to Orgrimmar", "best flight route")
    eq(best.detail[3], "2 right of 3", "best flight count")
    tick(ns, 6.1)
    eq(card:IsShown(), false, "closed after Touchdown!")
    -- Keep going stays open.
    takeOff(ns)
    tick(ns, 3.1)
    land(ns, 30)
    answer(ns, true); tick(ns, 3.1)
    card.primary.scripts.OnClick(card.primary)
    eq(ns.Quick.state.mode, "quick", "Keep going carries on in Quick play")
    tick(ns, 10)
    eq(card:IsShown(), true, "Keep going keeps the card")
    -- Short flights don't auto-start.
    ns.QuickCard.Hide()
    ns.db.qpShortest = 60
    takeOff(ns)
    eq(ns.QuickCard.IsShown(), false, "a flight under Shortest flight doesn't start")
    land(ns, 100)
    -- Not now.
    ns.db.qpShortest = 20
    takeOff(ns)
    card.primary.scripts.OnClick(card.primary)
    eq(card:IsShown(), false, "Not now closes the card")
    land(ns, 100)
end

-- Combat hides the card and stops its clock; it comes back after.
do
    local ns = load()
    ns.QuickCard.Show("quick")
    local card, s = ns.QuickCard.frame, ns.Quick.state
    tick(ns, 5)
    combat = true
    ns.QuickCard.OnCombat("PLAYER_REGEN_DISABLED")
    eq(card:IsShown(), false, "hidden in combat")
    clock = clock + 60
    combat = false
    ns.QuickCard.OnCombat("PLAYER_REGEN_ENABLED")
    eq(card:IsShown(), true, "back after combat")
    eq(s.phase, "question", "the question waited")
    eq(card.clock.text, "10 s", "the timer picked up where it was")
end

-- Hall of Fame: personal bests with their tooltips.
do
    local ns = load()
    ns.QuickCard.Show("streak")
    answer(ns, true); tick(ns, 2.1)
    answer(ns, false); tick(ns, 2.6)
    SlashCmdList.LOREFORGE("records")
    local records = ns.hostFrame.records
    eq(records.bests[1].text.text, "Best streak: 1", "Hall of Fame streak best")
    eq(records.bests[3].text.text, "Best flight: none yet", "no flight best yet")
    records.bests[1].scripts.OnEnter(records.bests[1])
end

-- A dialogue flight (no flight-map click) still offers and auto-starts.
local function dialogueTakeOff(ns)
    taxi = true
    flightEvent(ns, "PLAYER_CONTROL_LOST")
end
do
    local ns = load()
    dialogueTakeOff(ns)
    eq(ns.QuickCard.prompt and ns.QuickCard.prompt:IsShown(), true, "a dialogue flight offers a question")
    ns.QuickCard.HidePrompt()
    land(ns, 60)
    ns.db.qpOnFlights = "START"
    dialogueTakeOff(ns)
    local card, s = ns.QuickCard.frame, ns.Quick.state
    eq(card:IsShown(), true, "a dialogue flight auto-starts, with no estimate to compare")
    tick(ns, 3.1)
    eq(card.clock.text, "Until you land", "no invented time to landing")
    answer(ns, true)
    eq(s.phase, "reveal", "the answer shows")
    tick(ns, 2.9)
    eq(s.phase, "reveal", "for the Flight answer pause")
    has(card.feedback.text, "Correct!", "with its feedback")
    tick(ns, 0.2)
    eq(s.phase, "question", "then the next question")
    -- Landing mid-question: a short grace, then Touchdown.
    land(ns, 30)
    eq(s.phase, "question", "landing leaves the open question")
    eq(card.clock.text, "Landed: 10 s", "with a grace countdown")
    tick(ns, 9)
    eq(s.phase, "question", "inside the grace")
    tick(ns, 1.1)
    eq(s.phase, "over", "the grace ends it")
    eq(card.overTitle.text, "Touchdown!", "with Touchdown")
    has(card.overLines.text, "1 right this flight", "the open question isn't counted")
    ns.QuickCard.Hide()
    -- Grace 0 ends it on landing.
    ns.db.qpLandingGrace = 0
    dialogueTakeOff(ns)
    tick(ns, 3.1)
    land(ns, 30)
    eq(ns.Quick.state.phase, "over", "no grace: Touchdown straight away")
    ns.QuickCard.Hide()
    -- The answer pause follows its setting; Lightning stays quick.
    ns.db.qpLandingGrace, ns.db.qpFlightReveal = 10, 6
    dialogueTakeOff(ns)
    tick(ns, 3.1)
    answer(ns, false); tick(ns, 5.9)
    eq(ns.Quick.state.phase, "reveal", "a longer answer pause")
    tick(ns, 0.2)
    eq(ns.Quick.state.phase, "question", "then on")
    land(ns, 30)
    ns.QuickCard.Hide()
    ns.QuickCard.Show("lightning")
    answer(ns, true); tick(ns, 0.9)
    eq(ns.Quick.state.phase, "question", "Lightning keeps its quick reveal")
    ns.QuickCard.Hide()
    -- The feedback gets the full width unless Next shares its row.
    ns.db.qpAutoNext = false
    ns.QuickCard.Show("quick")
    answer(ns, true)
    eq(ns.QuickCard.frame.next:IsShown(), true, "manual Next")
    eq(ns.QuickCard.frame.feedback:GetWidth() < 348, true, "feedback makes room for Next")
    ns.QuickCard.Hide()
    ns.db.qpAutoNext = true
    ns.QuickCard.Show("quick")
    answer(ns, true)
    eq(ns.QuickCard.frame.feedback:GetWidth(), 348, "feedback spans the card")
end

-- Dismissed flight quizzes retain their exact state on both clients.
for _, client in ipairs({ "retail", "classic" }) do
    local ns = load({ era = client })
    takeOff(ns)
    ns.QuickCard.Show("flight")
    answer(ns, true)
    local saved = ns.Quick.state
    ns.QuickCard.Hide()
    eq(ns.Quick.state, saved, "dismiss keeps progress")
    eq(ns.QuickCard.launcher:IsShown(), true, "flight launcher appears")
    clock = clock + 30
    ns.QuickCard.ResumeQuiz()
    eq(ns.Quick.state, saved, "resume keeps question and score")
    eq(saved.correct, 1, "score retained")
    eq(saved.phase, "reveal", "resume retains feedback")
    eq(saved.pausedAt, nil, "resume restarts quiz clock")
    eq(ns.QuickCard.launcher:IsShown(), false, "launcher hides on resume")
    ns.QuickCard.frame:Hide() -- Escape uses OnHide too.
    eq(ns.QuickCard.launcher:IsShown(), true, "Escape leaves launcher")
    ns.QuickCard.Show("flight")
    assert(ns.Quick.state ~= saved, "new quiz replaces saved progress")
    eq(ns.Quick.state.correct, 0, "new quiz resets score")
    ns.QuickCard.Hide()
    combat = true
    ns.QuickCard.OnCombat("PLAYER_REGEN_DISABLED")
    eq(ns.QuickCard.launcher:IsShown(), false, "launcher hides in combat")
    combat = false
    ns.QuickCard.OnCombat("PLAYER_REGEN_ENABLED")
    eq(ns.QuickCard.launcher:IsShown(), true, "launcher returns after combat")
    land(ns, 1)
    eq(ns.QuickCard.launcher:IsShown(), false, "landing removes launcher")
    eq(ns.Quick.state, nil, "landing clears dismissed quiz")
end

-- The settings page builds.
do
    local ns = load()
    ns.HammerCore.Settings:Show()
    if ns.HammerCore.Settings.Focus then ns.HammerCore.Settings:Focus("Quick play") end
    eq(ns.HammerCore.Settings.errors and ns.HammerCore.Settings.errors["Quick play"], nil, "Quick play page builds")
    assert(wow.FindText("Seconds per question"), "Quick play page rows exist")
    assert(wow.FindText("Loremaster lines"), "Loremaster lines on Retail")
    assert(wow.FindText("Flight answer pause"), "Flight answer pause setting")
    assert(wow.FindText("Landing grace"), "Landing grace setting")
end

io.write("test_quick_play: ok\n")
