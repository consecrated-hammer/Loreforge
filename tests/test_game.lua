local ns = {}
assert(loadfile("Game.lua"))("Loreforge", ns)
local Game = ns.Game
local function eq(a, b, why) assert(a == b, why .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local time = 100
local bank = {}
for i = 1, 20 do bank[i] = { "Question " .. i, "Correct " .. i, "Wrong A", "Wrong B", "Wrong C", id = "test" .. i, categories = { "lore", "items" } } end
bank[21] = { "Forever mechanics", "a", "b", "c", "d", era = "classic", class = "MAGE", difficulty = "hard", categories = { "class" } }
bank[22] = { "Retail race", "a", "b", "c", "d", era = "retail", race = "Draenei", difficulty = "hard", categories = { "race" } }
local config = { rounds = 2, perRound = 2, seconds = 10, channel = "PARTY", readyCheck = false, difficulty = "mixed", categories = { lore = true, items = true, class = true, race = true } }
local roster = { { key = "a-r", name = "A-R", guid = "guidA" }, { key = "b-r", name = "B-R", guid = "guidB" } }
local records = {}
local function new() return Game.New(bank, function() return time end, function(n) return n end, records) end
local function flush(g)
    while g:NextMessage() do
        local line = g:NextMessage()
        assert(#line <= 240, "chat byte budget")
        g:Sent()
        eq(g:NextMessage(), nil, "one line in flight")
        eq(g:Echo("other message"), false, "unrelated echo ignored")
        eq(g:Echo(line), true, "exact echo advances")
    end
end
-- Multi-tag entries are included once; host class/race never narrows group topics.
eq(#Game.Pool(bank, config, "classic"), 21, "Forever pool")
eq(#Game.Pool(bank, config, "retail"), 21, "Retail pool")
local c = { rounds = 1, perRound = 1, seconds = 10, channel = "GUILD", readyCheck = false, difficulty = "hard", categories = { class = true, race = true } }
eq(#Game.Pool(bank, c, "classic"), 1, "hard class filter")
eq(Game.Pool(bank, c, "classic")[1][1], "Forever mechanics", "no Retail contamination")
local separate = new()
local separateConfig = {}
for k, v in pairs(config) do separateConfig[k] = v end
separateConfig.compactChoices = nil
assert(separate:Start(separateConfig, "retail", roster, 1))
for i = 1, 4 do
    assert(separate.queue[separate.questionCursor + i]:find('] ' .. i .. ') ', 1, true), 'one numbered option per chat message')
end
config.compactChoices = true
local g = new()
assert(g:Start(config, "retail", roster, 1))
eq(#g.queue - g.questionCursor, 1, "compact games post the question and one choices line")
local compact = g.queue[g.questionCursor + 1]
for i = 1, 4 do assert(compact:find(i .. ') ', 1, true), 'compact line carries choice ' .. i) end
assert(compact:find('[Loreforge #1] ', 1, true) == 1, 'readable game tag')
eq(g:Answer("a-r", "1", "guidA"), false, "answers closed during announcement")
flush(g)
eq(g.phase, "accepting", "echo opens answers")
eq(g.deadline, 110, "deadline begins at completed announcement")
eq(g:Answer("stranger", "1"), false, "not enrolled")
eq(g:Answer("a-r", "1", "imposter"), false, "GUID mismatch")
eq(g:Answer("a-r", "1 please", "guidA"), false, "strict number")
local right = tostring(g.run[g.index].correct)
assert(g:Answer("a-r", " " .. right .. " ", "guidA"))
eq(g:Answer("a-r", "2", "guidA"), false, "first answer locks")
assert(g:Answer("b-r", right, "guidB"))
time = 110
assert(not g:Answer("b-r", right, "guidB"))
eq(g.phase, "revealing", "timestamp closes even before tick")
eq(g.players["a-r"].total, 1, "correct shuffled answer scored")
eq(g.players["a-r"].streak, 1, "streak begins")
flush(g)
eq(g.phase, "between", "manual gap")
time = 1000; g:Tick(); eq(g.phase, "between", "timer cannot advance")
assert(g:Next()); flush(g)
assert(g:Answer("a-r", tostring(g.run[g.index].correct), "guidA"))
g:Pause("combat")
eq(g.phase, "paused", "combat pauses")
eq(next(g.answers), nil, "interrupted answers voided")
eq(g.players["a-r"].streak, 1, "void does not break streak")
assert(g:Resume()); eq(g.phase, "announcing", "resume re-announces")
flush(g)
for _ = 2, 4 do
    local answer = tostring(g.run[g.index].correct)
    assert(g:Answer("a-r", answer, "guidA")); assert(g:Answer("b-r", answer, "guidB"))
    time = time + 10; g:Tick(); flush(g)
    if g.phase ~= "finished" then assert(g:Next()); flush(g) end
end
eq(g.phase, "finished", "all rounds complete")
eq(g.players["a-r"].total, 4, "overall total")
eq(g.players["a-r"].round, 2, "round total resets")
eq(records["a-r"].bestStreak, 4, "persistent best streak")
eq(records["a-r"].wins, 1, "joint winner A")
eq(records["b-r"].wins, 1, "joint winner B")
g:RecordResults(); eq(records["a-r"].games, 1, "records recorded once")
-- Wrong and missed questions break streaks; no-answer game awards no wins.
local g2 = new(); assert(g2:Start(config, "retail", roster, 2)); flush(g2)
assert(g2:Answer("a-r", tostring(g2.run[1].correct), "guidA"))
g2:Close(); flush(g2); g2:Next(); flush(g2); g2:Close()
eq(g2.players["a-r"].streak, 0, "miss breaks streak")
g2:Stop(); eq(records["a-r"].games, 1, "stopped games leave records")
-- Missing echoes never open answers. Retry has a deliberate delay.
local g3 = new(); assert(g3:Start(config, "retail", roster, 3)); local first = g3:NextMessage(); g3:Sent()
eq(g3:ConfirmVisible(), false, "visible-line confirmation cannot bypass the initial echo wait")
eq(g3:Retry(), false, "no immediate retry"); time = time + 8; assert(g3:Retry()); eq(g3:NextMessage(), first, "same line retried")
-- UTF-8-safe byte splitting preserves content and keeps the macro under 255 bytes.
local original = string.rep("é", 400)
local parts = Game.Messages(original, "[LF] ")
local joined = {}
for _, line in ipairs(parts) do
    assert(#line <= 240); eq(line:byte(6), 195, "split starts at UTF8 lead byte")
    joined[#joined + 1] = line:sub(6)
end
eq(table.concat(joined), original, "no Unicode data loss")
local tooMany = { rounds = 20, perRound = 50, seconds = 10, channel = "PARTY", readyCheck = false, difficulty = "mixed", categories = { lore = true } }
assert(not new():Start(tooMany, "retail", roster, 4), "pool exhaustion refused")
local invalid = { rounds = 0, perRound = 5, seconds = 10, channel = "PARTY", readyCheck = false, difficulty = "mixed", categories = {} }
assert(not new():Start(invalid, "retail", roster, 5), "bad config refused")
-- A completed answer window is not a completed game until final output echoes.
local before = records["a-r"].games
local last = new()
assert(last:Start(c, "retail", roster, 6)); flush(last)
assert(last:Answer("a-r", tostring(last.run[1].correct), "guidA"))
last:Close()
eq(records["a-r"].games, before, "final scores are pending until the announcements finish")
last:RecordResults(); eq(records["a-r"].games, before, "cannot commit early")
last:Stop(); eq(records["a-r"].games, before, "stop during final output discards pending records")
-- No correct answers means there is no arbitrary zero-score winner.
local zero = new()
assert(zero:Start(c, "retail", roster, 7)); flush(zero)
assert(zero:Answer("a-r", tostring(zero.run[1].correct % 4 + 1), "guidA"))
zero:Close(); flush(zero)
eq(records["a-r"].wins, 1, "zero scores do not earn wins")
eq(records["a-r"].games, before + 1, "zero-score completed game is still recorded")
eq(records["b-r"].games, before, "bystanders do not get records")
-- Automatic gaps start after result echoes, and inactivity pauses are resumable.
local autoConfig = { rounds = 1, perRound = 4, seconds = 5, channel = "INSTANCE_CHAT", readyCheck = false,
    difficulty = "mixed", categories = { lore = true }, autoMode = true, questionGap = 3, idleLimit = 2 }
local auto = new()
assert(auto:Start(autoConfig, "retail", roster, 8)); flush(auto)
auto:Close(); flush(auto)
eq(auto.phase, "between", "first silent question leaves a gap")
time = time + 2; auto:Tick(); eq(auto.index, 1, "gap has not elapsed")
time = time + 1; auto:Tick(); eq(auto.index, 2, "automatic next question after gap")
eq(auto.phase, "announcing", "automatic next still requires delivered announcements")
flush(auto); auto:Close(); flush(auto)
eq(auto.phase, "paused", "consecutive silence pauses automatic play")
time = time + 100; auto:Tick(); eq(auto.index, 2, "paused game cannot advance")
assert(auto:Resume()); eq(auto.phase, "between", "resume follows completed results")
time = time + 3; auto:Tick(); flush(auto)
assert(auto:Answer("a-r", tostring(auto.run[auto.index].correct % 4 + 1), "guidA"))
auto:Close(); eq(auto.emptyQuestions, 0, "wrong replies still prove players are present")
local recap = table.concat(auto.queue, "\n")
assert(not recap:find("Correct: A%-R"), "wrong answers do not get correct-player recaps")
flush(auto); time = time + 3; auto:Tick(); flush(auto)
auto.config.idleLimit = 1
auto:Close(); flush(auto)
eq(auto.phase, "finished", "a final silent question finishes instead of pausing")
local badChannel = { rounds = 1, perRound = 1, seconds = 5, channel = "SAY", difficulty = "mixed", categories = { lore = true } }
assert(not new():Start(badChannel, "retail", roster, 9), "automatic public output is not supported")
local milestones = Game.New(bank, function() return time end, function(n) return n end, {})
local milestoneConfig = { rounds = 1, perRound = 5, seconds = 5, channel = "PARTY", readyCheck = false, difficulty = "mixed", categories = { lore = true } }
assert(milestones:Start(milestoneConfig, "retail", roster, 10)); flush(milestones)
local callouts = 0
for i = 1, 5 do
    local answer = milestones.run[i].correct
    if i == 3 then answer = answer % 4 + 1 end
    milestones:Answer("a-r", tostring(answer), "guidA")
    milestones:Close()
    for _, line in ipairs(milestones.queue) do
        if line:find("new personal best!", 1, true) then callouts = callouts + 1 end
    end
    flush(milestones)
    if i < 5 then milestones:Next(); flush(milestones) end
end
eq(callouts, 1, "rebuilding a streak does not repeat a personal-best callout")
local readyConfig = { rounds = 1, perRound = 1, seconds = 5, channel = "RAID", difficulty = "mixed",
    categories = { lore = true }, readyCheck = true, readySeconds = 5 }
local ready = Game.New(bank, function() return time end, function(n) return n end, {})
assert(ready:Start(readyConfig, "retail", roster, 11))
eq(ready.phase, "ready_announcing", "ready check is announced first")
assert(ready:Answer("a-r", "ready", "guidA"), "early ready is accepted before the final announcement echo")
eq(ready.readyDeadline, nil, "early check-in cannot start the countdown")
time = time + 100; ready:Tick(); eq(ready.phase, "ready_announcing", "countdown waits for delivered notice")
flush(ready); eq(ready.phase, "ready", "ready countdown opens after echoes")
eq(ready:Answer("a-r", " READY ", "guidA"), false, "duplicate ready remains a single check-in")
eq(ready:Answer("stranger", "ready"), false, "ready respects frozen roster")
eq(ready:Answer("b-r", "1", "guidB"), false, "numbers do not count as readiness")
eq(ready.players["a-r"].entered, nil, "ready check does not create a scored entry")
eq(#ready:ReadyPlayers(), 1, "ready player listed once")
ready:Pause("combat"); time = time + 100; ready:Tick()
assert(ready:Resume()); flush(ready)
eq(ready.readyDeadline, time + 5, "resume gives a fresh ready countdown")
time = time + 5; ready:Tick()
eq(ready.phase, "announcing", "countdown prepares first question")
flush(ready)
eq(ready.deadline, time + 5, "question has its own complete answer window")
ready:Stop()
assert(ready:Start(readyConfig, "retail", roster, 12)); flush(ready)
assert(ready:Next()); eq(ready.phase, "announcing", "host can start before ready countdown ends")
io.write("loreforge game tests passed\n")
