package.path = './tests/hammercore/?.lua;' .. package.path
local wow = require('wow')
local function eq(a, b, why) assert(a == b, why .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)) end

-- The game windows under HammerCore's Classic theme: its framed edge is
-- 11px, so the header bar, body, timer and art all sit inside it.
wow.Install({ Loreforge = { Version = '0.1.1' } })
LoreforgeDB = { windowOpacity = 0.83 }
local now = 100
GetTime = function() return now end
InCombatLockdown = function() return false end
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

assert(loadfile('tests/transport-libs.lua'))()()
local ns = wow.LoadHammerCore('Libs/HammerCore', 'Loreforge')
local T = ns.HammerCore.Theme
T.Active = function() return T.registry.classic, 'classic' end
assert(T.IsClassic(), 'the Classic theme is active')
for _, file in ipairs({ 'Transport.lua', 'Codec.lua', 'PartyBus.lua', 'Game.lua', 'Core.lua', 'Flair.lua', 'Setup.lua', 'History.lua', 'Host.lua', 'Options.lua', 'Party.lua', 'Probe.lua', 'Player.lua' }) do
    assert(loadfile(file))('Loreforge', ns)
end
local loader
for _, f in ipairs(wow.frames) do if f.scripts.OnEvent then loader = f end end
loader.scripts.OnEvent(loader, 'ADDON_LOADED', 'Loreforge')
eq(ns.db.windowOpacity, 0.85, 'a saved opacity is normalised at load')

ns.OpenHost('play')
local host = ns.hostFrame
eq(host.inset, 11, 'the host uses the framed edge')
eq(host.header.points[1][2], 11, 'its header bar sits inside the edge')
eq(host.hcBody.colour[4], 0.85, 'its body uses the saved opacity')
eq(host.backdropColour[4], 0, 'its framed backdrop shows only the edge')
for _, name in ipairs({ 'history', 'records' }) do
    ns.OpenHost(name)
    assert(host[name]:IsShown(), name .. ' opens under the Classic theme')
end
ns.OpenHost('play')
assert(host.setup:IsShown(), 'setup opens under the Classic theme')
eq(host:GetWidth(), ns.HostLayout.width, 'the host window has its own size')
assert(ns.HostLayout.width >= 900 and ns.HostLayout.height <= 700, 'wide, and short enough for 1080p at scale 1')
eq(host.tabs.play.active, true, 'the Play tab is underlined under Classic too')
eq(host.tabs.play.line:IsShown(), true, 'with its accent line')
local setup = host.setup
wow.Click(setup.subtabs.categories)
assert(setup.pages.categories:IsShown(), 'Categories opens under the Classic theme')
local lore = setup.categoryRows.lore
eq(lore.count.points[1][2], lore, "Classic's count sits at the row edge")
eq(lore.hcCheckbox.Text.points[#lore.hcCheckbox.Text.points][2], lore.count, 'and the name stops short of it')
wow.Click(setup.subtabs.game)

local P = ns.Player
P.Initialise()
ns.Party = { RequestSync = function() end }
P.Render({ id = 'g', state = 'accepting', host = 'Host-Realm', joined = true, me = 'guest-realm', rows = {},
    config = { rounds = 1, perRound = 3, seconds = 20, difficulty = 'mixed', categories = 'Lore' },
    index = 1, round = 1, totalQuestions = 3, attempt = 1, question = 'Who?', choices = { 'A', 'B', 'C', 'D' },
    deadline = now + 20, answeredCount = 0, art = 'goblins' })
local f = P.frame
assert(f:IsShown(), 'the player window opens')
eq(f.inset, 11, 'the player window uses the framed edge')
eq(f.scroll.points[1][5], -(11 + 40 + 23), 'the body starts below the header bar and timer')
assert(f.timer.points[1][3] < -(11 + 40), 'the timer sits below the header bar')
eq(f.art:GetHeight(), f:GetHeight() - 11 - 40 - 11, 'the art fills the panel below the bar')
eq(f:GetWidth(), 460 + f.art:GetWidth() + 22, 'and the window widens by it')
ns.SetWindowOpacity(1)
eq(f.hcBody.colour[4], 1, 'opacity applies to the player window')
eq(host.hcBody.colour[4], 1, 'and the host window')
io.write('loreforge window theme tests passed\n')
