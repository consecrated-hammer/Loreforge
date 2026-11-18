local _, ns = ...

-- Seasonal categories: when each holiday runs, and how in-season questions are
-- favoured. Windows are worked out from the server date with fixed rules, so
-- every copy agrees without the calendar API. These are day-level estimates
-- for the recurring schedule. Blizzard can move holiday dates by client or year.
local Seasons = {}
ns.Seasons = Seasons

local function dayIndex(year, month, day)
    return ns.Daily.DayIndex(year, month, day)
end

-- Day of week for a day index: 0 = Sunday. 1970-01-01 was a Thursday.
local function weekday(index) return (index + 4) % 7 end

-- The nth (1-based) given weekday of a month; n = -1 for the last one.
local function nthWeekday(year, month, wday, n)
    if n > 0 then
        local first = dayIndex(year, month, 1)
        return first + (wday - weekday(first)) % 7 + (n - 1) * 7
    end
    local nextMonth = month == 12 and dayIndex(year + 1, 1, 1) or dayIndex(year, month + 1, 1)
    local last = nextMonth - 1
    return last - (weekday(last) - wday) % 7
end

-- Lunar New Year, which the Lunar Festival follows. Outside the table the
-- festival falls back to a wide late-January to mid-February window.
local LUNAR_NEW_YEAR = {
    [2025] = { 1, 29 }, [2026] = { 2, 17 }, [2027] = { 2, 6 }, [2028] = { 1, 26 },
    [2029] = { 2, 13 }, [2030] = { 2, 3 }, [2031] = { 1, 23 }, [2032] = { 2, 11 },
    [2033] = { 1, 31 }, [2034] = { 2, 19 }, [2035] = { 2, 8 }, [2036] = { 1, 28 },
}

-- Fixed { month, day } to { month, day } window; the end can wrap the year.
local function window(year, m1, d1, m2, d2)
    return { dayIndex(year, m1, d1), dayIndex(m2 < m1 and year + 1 or year, m2, d2) }
end

local function fixed(m1, d1, m2, d2)
    return function(year) return { window(year, m1, d1, m2, d2) } end
end

-- Gregorian Easter (Meeus/Jones/Butcher). Noblegarden starts the day after.
local function easter(year)
    local floor = math.floor
    local a, b, c = year % 19, floor(year / 100), year % 100
    local d, e = floor(b / 4), b % 4
    local g = floor((b - floor((b + 8) / 25) + 1) / 3)
    local h = (19 * a + b - d - g + 15) % 30
    local l = (32 + 2 * e + 2 * floor(c / 4) - h - c % 4) % 7
    local date = h + l - 7 * floor((a + 11 * h + 22 * l) / 451) + 114
    return dayIndex(year, floor(date / 31), date % 31 + 1)
end

local HARVEST_START = {
    [2026] = { 9, 21 }, [2027] = { 9, 11 },
}

local function darkmoon(year, classic)
    local list = {}
    for month = 1, 12 do
        local start = classic and nthWeekday(year, month, 5, 1) + 3 or nthWeekday(year, month, 0, 1)
        list[#list + 1] = { start, start + 6 }
    end
    return list
end

-- Each rule returns the year's windows as { firstDay, lastDay } day indexes,
-- for the windows that START in that year.
Seasons.RULES = {
    winterveil = fixed(12, 15, 1, 2),
    lunar = function(year)
        local lny = LUNAR_NEW_YEAR[year]
        if not lny then return { { dayIndex(year, 1, 25), dayIndex(year, 2, 20) } } end
        local index = dayIndex(year, lny[1], lny[2])
        return { { index - 2, index + 13 } }
    end,
    loveair = function(year)
        if year == 2026 then return { window(year, 2, 9, 2, 23) } end
        return { window(year, 2, 7, 2, 22) }
    end,
    noblegarden = function(year)
        local start = easter(year) + 1
        return { { start, start + 7 } }
    end,
    -- The last Monday of April, for a week and a day.
    childrensweek = function(year)
        local start = nthWeekday(year, 4, 1, -1)
        return { { start, start + 7 } }
    end,
    midsummer = fixed(6, 21, 7, 5),
    brewfest = fixed(9, 20, 10, 6),
    hallowsend = function(year)
        if year == 2026 then return { window(year, 10, 19, 11, 2) } end
        return { window(year, 10, 18, 11, 1) }
    end,
    -- The Monday of US Thanksgiving week, for a week and a day.
    pilgrims = function(year)
        local start = nthWeekday(year, 11, 4, 4) - 3
        return { { start, start + 7 } }
    end,
    darkmoon = darkmoon,
}

-- Forever differs from Retail. The early dates and weekly Faire were
-- checked against the 1.60.1.70862 Holidays and HolidayNames client tables.
local FOREVER_RULES = {
    darkmoon = function(year) return darkmoon(year, true) end,
    loveair = fixed(2, 11, 2, 16),
    hallowsend = fixed(10, 18, 11, 2),
    lunar = function(year)
        if year == 2026 then return { window(year, 2, 16, 3, 2) } end
        if year == 2027 then return { window(year, 2, 2, 2, 16) } end
        return Seasons.RULES.lunar(year)
    end,
}

-- Each Smaller Holidays question starts with holidays-<event>-. Keep the
-- individual events separate so an anniversary does not boost pirate trivia.
-- Blizzard's micro-holiday schedule: worldofwarcraft.blizzard.com/en-gb/news/23823433.
Seasons.SMALL = {
    scarab = fixed(1, 21, 1, 23),
    hippogryph = fixed(2, 23, 2, 23),
    ungoro = fixed(3, 17, 3, 19),
    trial = function(year)
        return { window(year, 3, 20, 3, 27), window(year, 8, 31, 9, 7) }
    end,
    tadpoles = fixed(4, 5, 4, 5),
    guard = fixed(4, 28, 4, 28),
    balloon = fixed(5, 10, 5, 12),
    glowcap = fixed(5, 27, 5, 27),
    boat = fixed(6, 6, 6, 8),
    pirates = fixed(9, 19, 9, 19),
    harvest = function(year)
        local harvest = HARVEST_START[year] or { 9, 20 }
        local start = dayIndex(year, harvest[1], harvest[2])
        return { { start, start + 7 } }
    end,
    gnome = function(year)
        local start = nthWeekday(year, 10, 6, 2)
        return { { start, start } }
    end,
    dotd = fixed(11, 1, 11, 2),
    moonkin = fixed(11, 12, 11, 12),
    anniv = function(year)
        local start = dayIndex(year, 11, year == 2026 and 17 or 16)
        return { { start, start + 21 } }
    end,
}

-- The short window shown in setup hints.
Seasons.WHEN = {
    winterveil = "15 Dec to 2 Jan", lunar = "around Lunar New Year",
    loveair = "early to late February", noblegarden = "the week after Easter",
    childrensweek = "the last week of April", midsummer = "21 Jun to 5 Jul",
    brewfest = "20 Sep to 6 Oct", hallowsend = "mid-October to early November",
    pilgrims = "Thanksgiving week", darkmoon = "for a week each month",
    holidays = "during smaller events throughout the year",
}

local function activeRules(rules, year, today, overrides)
    local active = {}
    for key, rule in pairs(rules) do
        rule = overrides and overrides[key] or rule
        -- A window that started last year can still be running (Winter Veil).
        for _, y in ipairs({ year - 1, year }) do
            for _, window in ipairs(rule(y)) do
                if today >= window[1] and today <= window[2] then active[key] = true end
            end
        end
    end
    return active
end

-- Active category keys and the active events within Smaller Holidays.
function Seasons.Active(year, month, day, era)
    local today = dayIndex(year, month, day)
    local active = activeRules(Seasons.RULES, year, today, era == "classic" and FOREVER_RULES)
    local small = activeRules(Seasons.SMALL, year, today)
    if next(small) then active.holidays = true end
    return active, small
end

Seasons.BOOSTS = { 1, 2, 3, 5 }

function Seasons.Boost(saved)
    for _, boost in ipairs(Seasons.BOOSTS) do
        if saved == boost then return boost end
    end
    return 3
end

-- The seasonal part of a game config, from saved settings and today's date.
-- `now` is { year, month, day }; it defaults to the server's calendar date.
function Seasons.Config(db, now)
    now = now or ns.Daily.ServerTime()
    local active, small = Seasons.Active(now.year, now.month, now.day, ns.era)
    return {
        active = active, small = small,
        boost = Seasons.Boost(db.seasonBoost),
        hide = db.seasonHide ~= false,
    }
end

-- Adds the seasonal part to a game, pool or count config and returns it.
function Seasons.Apply(config, db)
    config.seasonal = Seasons.Config(db or config)
    return config
end
