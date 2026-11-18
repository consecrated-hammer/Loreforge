local ns = { DEFAULTS = {} }
for _, file in ipairs({ "Game.lua", "Daily.lua", "Seasons.lua" }) do
    assert(loadfile(file))("Loreforge", ns)
end
local Game, Seasons = ns.Game, ns.Seasons

local function eq(actual, expected, label)
    assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

assert(Seasons.Active(2026, 12, 15).winterveil, "Winter Veil starts in December")
assert(Seasons.Active(2027, 1, 2).winterveil, "Winter Veil crosses New Year")
assert(not Seasons.Active(2027, 1, 3).winterveil, "Winter Veil ends in January")
assert(Seasons.Active(2026, 11, 2).darkmoon, "Darkmoon starts on the first Sunday")
assert(not Seasons.Active(2026, 11, 9).darkmoon, "Darkmoon lasts one week")
assert(not Seasons.Active(2026, 11, 2, "classic").darkmoon, "Forever skips Retail's Sunday window")
assert(Seasons.Active(2026, 11, 9, "classic").darkmoon, "Forever Faire opens the Monday after first Friday")
assert(Seasons.Active(2027, 2, 2, "classic").lunar, "Forever Lunar Festival uses its client date")
assert(Seasons.Active(2026, 11, 19).holidays, "2026 anniversary uses its announced dates")
assert(Seasons.Active(2026, 4, 6).noblegarden and not Seasons.Active(2026, 4, 5).noblegarden, "Noblegarden follows Easter")
assert(Seasons.Active(2027, 3, 29).noblegarden and not Seasons.Active(2027, 4, 6).noblegarden, "Noblegarden moves with Easter")
assert(Seasons.Active(2026, 5, 27).holidays and not Seasons.Active(2026, 5, 28).holidays, "Glowcap is a single day")
for key in pairs(Game.SEASONAL) do
    assert((Seasons.RULES[key] or key == "holidays") and Seasons.WHEN[key], key .. " has a calendar and tooltip")
end
for key in pairs(Seasons.RULES) do assert(Game.SEASONAL[key], key .. " is a game category") end

local config = {
    categories = { lore = true, winterveil = true, brewfest = true },
    difficulty = "mixed",
    perRound = 1,
}
local winter = { "Winter", "A", "B", "C", "D", categories = { "winterveil", "lore" } }
local ordinary = { "Ordinary", "A", "B", "C", "D", categories = { "lore" } }
local brew = { "Brew", "A", "B", "C", "D", categories = { "brewfest" }, era = "retail" }
local pirate = { "Pirate", "A", "B", "C", "D", id = "holidays-pirates-test", categories = { "holidays" } }
local anniversary = { "Anniversary", "A", "B", "C", "D", id = "holidays-anniv-test", categories = { "holidays" } }
local bank = { ordinary, winter, brew }
local today = { year = 2026, month = 12, day = 20 }

config.seasonal = Seasons.Config({}, today)
local pool, counts = Game.Pool(bank, config, "retail", true)
eq(#pool, 2, "out-of-season Brewfest is hidden")
eq(counts.lore, 2, "both lore questions count")
eq(counts.winterveil, 1, "multi-tag question counts once per category")
eq(counts.brewfest, nil, "unavailable category count is absent")
eq(Game.Weight(winter, config), 3, "Winter Veil receives the default weight")
eq(Game.Weight(ordinary, config), 1, "everyday question keeps its weight")
eq(Game.TakeWeighted(pool, config, function(total) eq(total, 4, "weighted roll"); return 2 end),
    winter, "weighted roll selects the in-season question")
eq(Game.TakeWeighted(pool, config, function() return 1 end), ordinary, "draw removes questions without replacement")
eq(Game.TakeWeighted(pool, config, function() error("empty draw must not roll") end), nil, "empty pool")

eq(Game.PickTheme({ ordinary, winter }, config, {}, function(total)
    eq(total, 4, "theme weight")
    return total
end).key, "winterveil", "themed rounds favour Winter Veil")
config.categories.winterveil = false
eq(Game.Weight(winter, config), 1, "an unticked holiday adds no weight through a different tag")
eq(#Game.Pool(bank, config, "retail"), 2, "active winter question can still match lore")

config.seasonal = Seasons.Config({ seasonHide = false, seasonBoost = 1 }, today)
eq(#Game.Pool(bank, config, "retail"), 3, "showing out of season restores Brewfest")
eq(#Game.Pool(bank, config, "classic"), 2, "showing out of season preserves client filtering")
eq(Game.Weight(winter, config), 1, "boost off uses equal weights")
eq(Seasons.Boost(1000000), 3, "unexpected saved multiplier uses the default")
config.categories.holidays = true
config.seasonal = Seasons.Config({}, { year = 2026, month = 11, day = 19 })
pool = Game.Pool({ pirate, anniversary }, config, "retail")
eq(#pool, 1, "only the running smaller event enters the pool")
eq(pool[1], anniversary, "November holiday does not bring in Pirates' Day")
eq(Game.Weight(anniversary, config), 3, "running smaller event is weighted")
print("loreforge seasons and weighted draws passed")
