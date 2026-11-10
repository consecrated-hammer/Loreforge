local _, ns = ...
local HC = ns.HammerCore

-- The daily question: one question a day, one try, no timer, and a streak of
-- days answered right. It plays on the Quick play card (QuickCard.lua) in a
-- one-question "daily" mode.
--
-- Picking the day's question, the same on every copy of a client:
--   * every question's score is Hash(id .. "YYYY-MM-DD"), the server's
--     calendar date; the highest score wins (ties go to the smaller ID);
--   * a question that was a daily on either client in the previous
--     LOOKBACK days is skipped;
--   * each day Retail picks first (retail and both-era questions), then
--     WoW Forever (classic and both-era questions), never Retail's pick.
-- Both TOCs load the whole bank, every era, so each client can work out both
-- schedules and keep them apart. Splitting the bank per client breaks that.
--
-- The lookback makes each day depend on the days before it, so the schedule
-- is worked out from day 1 (DAILY_EPOCH) and kept in LoreforgeDB.dailySchedule
-- under a signature of the bank; a new bank recomputes it.
--
-- Saved state is account-wide: LoreforgeDB is the addon's only saved
-- variable, so answering on one character counts for all of them. It's kept
-- per client era (LoreforgeDB.daily[era]) as Retail and Forever are separate
-- installs with separate banks.

local Daily = {}
ns.Daily = Daily

Daily.EPOCH = { 2026, 11, 10 }   -- Daily #1
Daily.LOOKBACK = 60               -- days a daily stays out of the running
Daily.OFFER_DELAY = 6             -- seconds after loading in before the login offer
Daily.RETRY = 5                   -- seconds between tries while something else is open
Daily.DEFAULTS = { dailyOn = true, dailyOffer = true }
for key, value in pairs(Daily.DEFAULTS) do ns.DEFAULTS[key] = value end

-- ── Hashing ────────────────────────────────────────────────────────────────
-- Pure Lua 5.1 on doubles: every intermediate stays below 2^53, so the
-- result is exact and the same on every client. No bit library needed.

local P = 4294967291      -- the largest prime below 2^32
local M32 = 4294967296
local floor = math.floor

-- (a * b) mod 2^32 for a, b < 2^32, split so nothing passes 2^49.
local function mul32(a, b)
    local hi, lo = floor(a / 65536), a % 65536
    return ((hi * b) % 65536 * 65536 + lo * b) % M32
end

-- (a * b) mod P for a, b < 2^32.
local function mulP(a, b)
    local hi, lo = floor(a / 65536), a % 65536
    return ((hi * b) % P * 65536 % P + lo * b) % P
end

-- Polynomial string hash mod P, continuing from h.
local function poly(text, h)
    h = h or 0
    for i = 1, #text do h = (h * 31 + text:byte(i)) % P end
    return h
end

-- A murmur-style finaliser with adds in place of xors, to spread the bits.
local function mix(h)
    h = (h + floor(h / 65536)) % M32
    h = mul32(h, 2246822507)   -- 0x85EBCA6B
    h = (h + floor(h / 8192)) % M32
    h = mul32(h, 3266489909)   -- 0xC2B2AE35
    return (h + floor(h / 65536)) % M32
end

function Daily.Hash(text) return mix(poly(text, 0)) end

-- 31^10 mod P: the shift for a ten-character date after the ID.
local SHIFT = 1
for _ = 1, 10 do SHIFT = (SHIFT * 31) % P end

-- Per-ID hashes, worked out once: the ID's polynomial shifted past the date.
local bases = {}
local function base(id)
    local value = bases[id]
    if not value then
        value = mulP(poly(id, 0), SHIFT)
        bases[id] = value
    end
    return value
end

-- Hash(id .. dateKey), from the cached ID part. dateKey is "YYYY-MM-DD".
function Daily.Score(id, dateKey, datePart)
    return mix((base(id) + (datePart or poly(dateKey, 0))) % P)
end

-- ── Dates ──────────────────────────────────────────────────────────────────

-- Days since 1970-01-01 for a calendar date (proleptic Gregorian).
function Daily.DayIndex(year, month, day)
    local y = month <= 2 and year - 1 or year
    local era = floor(y / 400)
    local yoe = y - era * 400
    local m = month > 2 and month - 3 or month + 9
    local doy = floor((153 * m + 2) / 5) + day - 1
    local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

-- The calendar date for a day index (the inverse of DayIndex).
function Daily.DateOf(index)
    local z = index + 719468
    local era = floor(z / 146097)
    local doe = z - era * 146097
    local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
    local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
    local mp = floor((5 * doy + 2) / 153)
    local day = doy - floor((153 * mp + 2) / 5) + 1
    local month = mp < 10 and mp + 3 or mp - 9
    return yoe + era * 400 + (month <= 2 and 1 or 0), month, day
end

local EPOCH_INDEX = Daily.DayIndex(Daily.EPOCH[1], Daily.EPOCH[2], Daily.EPOCH[3])

function Daily.DateKey(year, month, day) return string.format("%04d-%02d-%02d", year, month, day) end

-- The daily number for a day index: launch day is #1.
function Daily.Number(index) return index - EPOCH_INDEX + 1 end

function Daily.KeyFor(number)
    return Daily.DateKey(Daily.DateOf(EPOCH_INDEX + number - 1))
end

-- The server's calendar date and time: { year, month, day, hour, minute }.
-- C_DateAndTime is the realm's calendar; without it, UTC from the server
-- clock stands in.
function Daily.ServerTime()
    if C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime then
        local ok, t = pcall(C_DateAndTime.GetCurrentCalendarTime)
        if ok and type(t) == "table" and tonumber(t.year) and tonumber(t.month) and tonumber(t.monthDay) then
            return { year = t.year, month = t.month, day = t.monthDay, hour = tonumber(t.hour) or 0, minute = tonumber(t.minute) or 0 }
        end
    end
    local stamp = (GetServerTime and GetServerTime()) or (time and time()) or 0
    local t = date and date("!*t", stamp)
    if type(t) == "table" then
        return { year = t.year, month = t.month, day = t.day, hour = t.hour or 0, minute = t.min or 0 }
    end
    return { year = Daily.EPOCH[1], month = Daily.EPOCH[2], day = Daily.EPOCH[3], hour = 0, minute = 0 }
end

-- Today: { number, key, minutesLeft }. Before launch counts as #1.
function Daily.Today()
    local t = Daily.ServerTime()
    local number = math.max(1, Daily.Number(Daily.DayIndex(t.year, t.month, t.day)))
    local left = math.max(1, 1440 - (t.hour * 60 + t.minute))
    return { number = number, key = Daily.KeyFor(number), minutesLeft = left }
end

function Daily.NextText(today)
    local left = (today or Daily.Today()).minutesLeft
    local hours, minutes = floor(left / 60), left % 60
    return "Next question in " .. (hours > 0 and (hours .. "h " .. minutes .. "m") or (minutes .. "m"))
end

-- ── The schedule ───────────────────────────────────────────────────────────

local function eligible(entry, era)
    local client = entry.era or "both"
    return client == "both" or client == era
end

-- The bank as the daily sees it: every question with an ID, retired ones out.
function Daily.Bank(bank)
    bank = bank or HC.QUIZ or {}
    local list, sum = {}, 0
    for _, entry in ipairs(bank) do
        if type(entry) == "table" and entry.id and not entry.retired then
            list[#list + 1] = entry
            sum = (sum + Daily.Hash(entry.id .. ":" .. (entry.era or "both"))) % M32
        end
    end
    return list, "daily-v1:" .. #list .. ":" .. sum
end

-- Higher score wins; the smaller ID breaks a tie.
local function better(score, id, bestScore, bestId)
    if not bestId then return true end
    if score ~= bestScore then return score > bestScore end
    return id < bestId
end

-- One day's picks from the scores, skipping recent dailies.
local function pickDay(list, number, last)
    local datePart = poly(Daily.KeyFor(number), 0)
    local rScore, rId
    local c1Score, c1Id, c2Score, c2Id
    for i = 1, #list do
        local entry = list[i]
        local id = entry.id
        local seen = last[id]
        if not (seen and number - seen <= Daily.LOOKBACK) then
            local score = mix((base(id) + datePart) % P)
            local client = entry.era or "both"
            if (client == "both" or client == "retail") and better(score, id, rScore, rId) then
                rScore, rId = score, id
            end
            if client == "both" or client == "classic" then
                if better(score, id, c1Score, c1Id) then
                    c2Score, c2Id = c1Score, c1Id
                    c1Score, c1Id = score, id
                elseif better(score, id, c2Score, c2Id) then
                    c2Score, c2Id = score, id
                end
            end
        end
    end
    local classic = c1Id
    if classic ~= nil and classic == rId then classic = c2Id end
    return rId, classic
end

-- Both clients' picks for every day up to `number`, cached in memory and in
-- the saved schedule. Returns { retail = { ids }, classic = { ids } }.
function Daily.Schedule(number, bank)
    local list, signature = Daily.Bank(bank)
    local store = ns.db and ns.db.dailySchedule
    local cache = Daily.cache
    if not (cache and cache.signature == signature) then
        if type(store) == "table" and store.signature == signature and type(store.retail) == "table"
            and type(store.classic) == "table" and #store.retail == #store.classic then
            cache = { signature = signature, retail = store.retail, classic = store.classic }
        else
            cache = { signature = signature, retail = {}, classic = {} }
        end
        cache.list = list
        Daily.cache = cache
    end
    local retail, classic = cache.retail, cache.classic
    if #retail < number then
        -- When each recent question was last a daily, from the lookback window.
        local last = {}
        for n = math.max(1, #retail - Daily.LOOKBACK + 1), #retail do
            if retail[n] then last[retail[n]] = n end
            if classic[n] then last[classic[n]] = n end
        end
        for n = #retail + 1, number do
            local r, c = pickDay(cache.list or list, n, last)
            -- false keeps the arrays dense when a client has nothing left.
            retail[n], classic[n] = r or false, c or false
            if r then last[r] = n end
            if c then last[c] = n end
        end
        if ns.db then ns.db.dailySchedule = { signature = signature, retail = retail, classic = classic } end
    end
    return cache
end

-- The question ID for a client on a day ("retail" or "classic").
function Daily.PickId(era, number, bank)
    local schedule = Daily.Schedule(number, bank)
    local list = era == "classic" and schedule.classic or schedule.retail
    return list[number] or nil
end

local function find(id)
    for _, entry in ipairs(HC.QUIZ or {}) do
        if entry.id == id then return entry end
    end
end
Daily.Find = find

-- Today's question for this client, ready for the card: the four answers in
-- the same order for everyone, so "it was the second one" works too.
function Daily.Question(today)
    today = today or Daily.Today()
    local id = Daily.PickId(ns.era, today.number)
    local entry = id and find(id)
    if not entry then return nil end
    local choices = { entry[2], entry[3], entry[4], entry[5] }
    local seed = Daily.Hash(id .. "|" .. today.key)
    for i = 4, 2, -1 do
        seed = mix((seed + 2654435769) % M32)
        local j = seed % i + 1
        choices[i], choices[j] = choices[j], choices[i]
    end
    local correct
    for i, choice in ipairs(choices) do if choice == entry[2] then correct = i end end
    local category = ns.Game.Categories(entry)[1] or "mixed"
    return { text = entry[1], choices = choices, correct = correct, category = category,
        categoryLabel = ns.Quick.CategoryLabel(category), id = id, number = today.number,
        daily = true }
end

function Daily.Label(number)
    return "Daily #" .. number
end

-- ── Saved state and the streak ─────────────────────────────────────────────

function Daily.State()
    local db = ns.db
    if type(db.daily) ~= "table" then db.daily = {} end
    local state = db.daily[ns.era]
    if type(state) ~= "table" then
        state = {}
        db.daily[ns.era] = state
    end
    state.streak = tonumber(state.streak) or 0
    state.best = tonumber(state.best) or 0
    return state
end

function Daily.Enabled() return ns.db.dailyOn ~= false end

-- Today's answer, or nil before it's answered.
function Daily.Answered(today)
    local state = Daily.State()
    local number = (today or Daily.Today()).number
    local answer = state.answer
    return type(answer) == "table" and answer.number == number and answer or nil
end

function Daily.Done(today) return Daily.Answered(today) ~= nil end

-- The streak as it stands today: a missed day or a wrong answer is 0.
function Daily.Streak(today)
    local state = Daily.State()
    local number = (today or Daily.Today()).number
    local last = tonumber(state.lastNumber)
    if not (last and state.lastRight and (last == number or last == number - 1)) then return 0 end
    return state.streak
end

function Daily.Best() return Daily.State().best end

-- Records today's one answer. Returns false if today already has one.
function Daily.Record(question, choice, right, today)
    today = today or Daily.Today()
    local state = Daily.State()
    if Daily.Done(today) then return false end
    if type(question) ~= "table" or (question.number and question.number ~= today.number) then return false, "expired" end
    local number = today.number
    if right then
        local last = tonumber(state.lastNumber)
        state.streak = (state.lastRight and last == number - 1) and (state.streak + 1) or 1
    else
        state.streak = 0
    end
    state.lastNumber, state.lastRight = number, right and true or false
    state.answer = { number = number, id = question.id, right = right and true or false,
        choice = choice and question.choices[choice] or nil }
    if state.streak > state.best then
        state.best = state.streak
        state.bestAt = (GetServerTime and GetServerTime()) or (time and time()) or 0
    end
    -- The Play tab's tick and the Hall of Fame's streak.
    if ns.RefreshHost then pcall(ns.RefreshHost) end
    return true
end

function Daily.FooterText(today)
    return "Daily streak: " .. Daily.Streak(today) .. " (best " .. Daily.Best() .. ")"
end

-- The card's summary after answering, or on opening it again that day.
function Daily.Summary(today)
    today = today or Daily.Today()
    local answer = Daily.Answered(today)
    if not answer then return nil end
    local entry = find(answer.id)
    local lines = { Daily.Label(today.number) }
    if not answer.right and entry then lines[#lines + 1] = "It was " .. entry[2] .. "." end
    lines[#lines + 1] = "Daily streak: " .. Daily.Streak(today)
    return { kind = "daily", title = answer.right and "Correct!" or "Not this time",
        lines = lines, note = Daily.NextText(today), right = answer.right }
end

function Daily.Report()
    local today = Daily.Today()
    return "Daily: " .. Daily.Label(today.number) .. " (" .. today.key .. "), "
        .. (Daily.Done(today) and "done" or "not yet") .. ", " .. Daily.FooterText(today)
        .. (Daily.Enabled() and "" or ", off")
end

-- ── The login offer ────────────────────────────────────────────────────────

local function later(seconds, fn)
    if C_Timer and C_Timer.After then C_Timer.After(seconds, fn) end
end

local function inCombat() return InCombatLockdown and InCombatLockdown() or false end

local function inInstance()
    if not IsInInstance then return false end
    local ok, inside = pcall(IsInInstance)
    return ok and inside and true or false
end

-- Another login window or the card is in the way.
local function busy()
    local welcome = HC.Welcome
    if welcome and ((welcome.Busy and welcome.Busy()) or (welcome.IsShown and welcome:IsShown())) then return true end
    local whatsNew = HC.WhatsNew and HC.WhatsNew.frame
    if whatsNew and whatsNew:IsShown() then return true end
    local card = ns.QuickCard
    if card and (card.IsShown() or (card.prompt and card.prompt:IsShown())) then return true end
    return false
end

-- Whether the offer can open now: true, or false and why ("off", "done",
-- "offered", "combat", "instance", "busy").
function Daily.CanOffer(today, resume)
    today = today or Daily.Today()
    if not (Daily.Enabled() and ns.db.dailyOffer ~= false) then return false, "off" end
    if Daily.Done(today) then return false, "done" end
    if not resume and Daily.State().offered == today.number then return false, "offered" end
    if inCombat() then return false, "combat" end
    if inInstance() then return false, "instance" end
    if busy() then return false, "busy" end
    return true
end

function Daily.TryOffer()
    local today = Daily.Today()
    local ok, why = Daily.CanOffer(today)
    Daily.waitingCombat = why == "combat" or nil
    if why == "busy" and not Daily.retrying then
        Daily.retrying = true
        later(Daily.RETRY, function() Daily.retrying = nil; Daily.TryOffer() end)
    end
    if not ok then return false, why end
    Daily.State().offered = today.number
    if ns.QuickCard and ns.QuickCard.DailyPrompt then ns.QuickCard.DailyPrompt(today) end
    return true
end

-- Each loading screen tries again, so leaving an instance can still offer.
function Daily.OnEvent(event)
    if event == "PLAYER_ENTERING_WORLD" then
        if inInstance() and ns.QuickCard then ns.QuickCard.HideDailyPrompt() end
        if C_Timer and C_Timer.After then later(Daily.OFFER_DELAY, Daily.TryOffer) else Daily.TryOffer() end
    elseif event == "PLAYER_REGEN_ENABLED" and Daily.waitingCombat then
        Daily.waitingCombat = nil
        later(2, Daily.TryOffer)
    end
end

function Daily.Initialise()
    Daily.State()
    if Daily.events then return end
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:SetScript("OnEvent", function(_, event) Daily.OnEvent(event) end)
    Daily.events = events
end
