local addonName, ns = ...
local HC = ns.HammerCore

-- Flight paths: when the player takes off, where to, how long it should
-- take, and when they land. Opt-in: an addon passes `flights = true` (or
-- `flights = { estimates = false }`) to HC:Init and HC:Start switches it on. Addons that don't ask never hook
-- anything or register a taxi event.
--
-- No game API reports a flight's duration, so the time comes from:
--   1. a time learned on an earlier normal landing on the same route;
--   2. LibTaxiData's leg lengths (`LibTaxiData_API`), at the speed fitted
--      to real flights, with Frequent Flier where the game has it;
--   3. nothing ("unknown"): the flight still starts and lands.
-- HammerCore never requires LibTaxiData. An addon that turns flights on
-- declares it, required or optional, in its own TOC and .pkgmeta (check.py
-- enforces it).
--
-- ☠ LEARNED TIMES ARE SHARED BY EVERY FLIGHTS ADDON. WoW only saves an
--   addon's own saved variables, so each flights addon keeps a copy in its
--   HammerCore state. At start, each copy merges its saved routes into the
--   SHARED_KEY global and then points its saved field at that one table, so
--   every addon writes the same merged set at logout and removing one addon
--   loses nothing. Keep the entry shape stable ({ seconds, samples, at }):
--   older copies merge newer entries. Seconds are stored at normal flight
--   speed (Frequent Flier taken out), so one entry serves both speeds.
--
-- `flights = { estimates = false }` tracks takeoff and landing only: no
-- learned or LibTaxiData times, nothing saved, and check.py doesn't ask for
-- LibTaxiData. Estimates come back nil, "unknown"; OnTakeoff, OnLanding and
-- Current() work as usual.
--
-- A reload mid-flight loses the route: the game won't say where a flight in
-- progress is going. The flight still lands, as `resumed`, with no time.

local Flights = {
    SPEED = 30.4,              -- yards per second, fitted to measured flights
    FREQUENT_FLIER = 1.2,
    FREQUENT_FLIER_TREE = 1188,
    FREQUENT_FLIER_NODE = 110300,
    MIN_LEARN = 10,            -- seconds; shorter flights aren't learned
    IDLE_POLL = 2,             -- seconds between fallback taxi checks once the world has loaded
    BOARD_WAIT = 10,           -- seconds to confirm taxi state after a request or control loss
    POLL = 0.5,
    SHARED_KEY = "ConsecratedHammerFlights",
    LIBRARY_URL = "https://www.curseforge.com/wow/addons/libtaxidata",
    SCHEMA = 1,
}
HC.Flights = Flights

local listeners = { takeoff = {}, landing = {} }
local pending, flight, ticker, takeoffDeadline

local function now() return GetTime and GetTime() or 0 end
local function stamp() return (GetServerTime and GetServerTime()) or (time and time()) or 0 end

-- Every game call is guarded: taxi functions differ between clients and
-- some only answer while the flight map is open.
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

local function readable(value)
    return value ~= nil and not (issecretvalue and issecretvalue(value))
end

local function library()
    local api = rawget(_G, "LibTaxiData_API")
    return type(api) == "table" and api or nil
end

function Flights.LibraryInstalled() return library() ~= nil end

-- False when the spec asks for takeoff and landing only.
function Flights.Estimates()
    local spec = HC.spec and HC.spec.flights
    return not (type(spec) == "table" and spec.estimates == false)
end

function Flights:LearnedCount()
    local count = 0
    for _ in pairs(self:Store().routes) do count = count + 1 end
    return count
end

-- ── Learned times ──────────────────────────────────────────────────────────

local function valid(entry)
    return type(entry) == "table" and type(entry.seconds) == "number" and entry.seconds > 0
end

-- Whether entry a should replace b: the most recent wins, then the one
-- with more flights behind it.
local function better(a, b)
    if not valid(b) then return true end
    local at, bt = tonumber(a.at) or 0, tonumber(b.at) or 0
    if at ~= bt then return at > bt end
    return (tonumber(a.samples) or 0) > (tonumber(b.samples) or 0)
end

function Flights.Merge(into, from)
    if type(from) ~= "table" then return into end
    for key, entry in pairs(from) do
        if type(key) == "string" and valid(entry) and better(entry, into[key]) then into[key] = entry end
    end
    return into
end

-- The shared store, merged with this addon's saved copy on first use.
function Flights:Store()
    local shared = rawget(_G, Flights.SHARED_KEY)
    if type(shared) ~= "table" then
        shared = {}
        _G[Flights.SHARED_KEY] = shared
    end
    if type(shared.routes) ~= "table" then shared.routes = {} end
    shared.schema = math.max(tonumber(shared.schema) or 0, Flights.SCHEMA)
    local state = HC.State and HC.State()
    if state and state.flights ~= shared then
        local saved = state.flights
        if type(saved) == "table" then
            Flights.Merge(shared.routes, saved.routes)
            shared.schema = math.max(shared.schema, tonumber(saved.schema) or 0)
        end
        state.flights = shared
    end
    return shared
end

function Flights.Key(fromID, toID, from, to)
    if fromID and toID then return fromID .. ">" .. toID end
    if from and to then return "name:" .. from .. ">" .. to end
end

function Flights:Learned(key)
    local entry = key and self:Store().routes[key]
    return valid(entry) and entry or nil
end

-- elapsed: real seconds; multiplier: the speed the flight was flown at.
function Flights:Learn(key, elapsed, multiplier)
    if not key or type(elapsed) ~= "number" or elapsed < Flights.MIN_LEARN then return false end
    local routes = self:Store().routes
    local old = routes[key]
    routes[key] = { seconds = elapsed * (multiplier or 1), at = stamp(),
        samples = (valid(old) and tonumber(old.samples) or 0) + 1 }
    return true
end

-- ── Estimates ──────────────────────────────────────────────────────────────

-- 1.2 with Frequent Flier (Forever's Adventure tree), otherwise 1.
function Flights.SpeedMultiplier()
    local traits = C_Traits
    if not (traits and traits.GetConfigIDByTreeID and traits.GetNodeInfo) then return 1 end
    local config = call(traits.GetConfigIDByTreeID, Flights.FREQUENT_FLIER_TREE)
    local node = config and call(traits.GetNodeInfo, config, Flights.FREQUENT_FLIER_NODE)
    return type(node) == "table" and (tonumber(node.activeRank) or 0) > 0 and Flights.FREQUENT_FLIER or 1
end

-- slot -> nodeID for the open flight map.
local function nodeIDs()
    local ids = {}
    local mapID = call(GetTaxiMapID)
    local nodes = mapID and C_TaxiMap and call(C_TaxiMap.GetAllTaxiNodes, mapID)
    for _, node in ipairs(type(nodes) == "table" and nodes or {}) do
        if type(node) == "table" and node.slotIndex and node.nodeID then ids[node.slotIndex] = node.nodeID end
    end
    return ids
end

local function nodeName(slot)
    local name = slot and call(TaxiNodeName, slot)
    return readable(name) and type(name) == "string" and name ~= "" and name or nil
end

-- The route to a flight map slot: { from, to, fromID, toID, key, hops }.
function Flights:Route(slot)
    local ids, start = nodeIDs(), nil
    for index = 1, tonumber(call(NumTaxiNodes)) or 0 do
        if call(TaxiNodeGetType, index) == "CURRENT" then start = index; break end
    end
    local route = { from = nodeName(start), to = nodeName(slot), fromID = start and ids[start],
        toID = ids[slot], hops = {} }
    for hop = 1, tonumber(call(GetNumRoutes, slot)) or 0 do
        local a, b = call(TaxiGetNodeSlot, slot, hop, true), call(TaxiGetNodeSlot, slot, hop, false)
        route.hops[hop] = { from = a and ids[a], to = b and ids[b] }
    end
    route.key = Flights.Key(route.fromID, route.toID, route.from, route.to)
    return route
end

local function leg(api, from, to)
    local paths = call(api.GetOutgoingPaths, from)
    for _, path in pairs(type(paths) == "table" and paths or {}) do
        if type(path) == "table" and path.toNodeID == to then
            local yards = tonumber(path.distanceYards)
            if yards and yards > 0 then return yards, tonumber(path.delaySeconds) or 0 end
        end
    end
end

-- Seconds at normal speed from LibTaxiData, or nil if any leg is unknown.
function Flights.LibraryBase(route)
    local api = library()
    if not (api and api.GetOutgoingPaths and route and #route.hops > 0) then return nil end
    local total = 0
    for _, hop in ipairs(route.hops) do
        if not (hop.from and hop.to) then return nil end
        local yards, delay = leg(api, hop.from, hop.to)
        if not yards then return nil end
        total = total + yards / Flights.SPEED + delay
    end
    return total
end

-- seconds (or nil), source: "learned", "libtaxidata" or "unknown".
function Flights:EstimateRoute(route, multiplier)
    if not Flights.Estimates() then return nil, "unknown" end
    multiplier = multiplier or Flights.SpeedMultiplier()
    local learned = route and self:Learned(route.key)
    if learned then return learned.seconds / multiplier, "learned" end
    local base = Flights.LibraryBase(route)
    if base then return base / multiplier, "libtaxidata" end
    return nil, "unknown"
end

-- For a destination on the open flight map: seconds, source, route.
function Flights:Estimate(slot)
    local route = self:Route(slot)
    local seconds, source = self:EstimateRoute(route)
    return seconds, source, route
end

-- ── Takeoff and landing ────────────────────────────────────────────────────

local function emit(kind, info)
    for _, fn in ipairs(listeners[kind]) do
        local ok, err = pcall(fn, info)
        if not ok and geterrorhandler then geterrorhandler()(err) end
    end
end

function Flights:OnTakeoff(fn) listeners.takeoff[#listeners.takeoff + 1] = fn end
function Flights:OnLanding(fn) listeners.landing[#listeners.landing + 1] = fn end

local function onTaxi() return UnitOnTaxi and UnitOnTaxi("player") and true or false end

local function stopPoll()
    if ticker and ticker.Cancel then ticker:Cancel() end
    ticker = nil
end

local function startPoll()
    if ticker or not (C_Timer and C_Timer.NewTicker) then return end
    ticker = C_Timer.NewTicker(Flights.POLL, function() Flights:Tick() end)
end

-- The flight in progress, or nil: { from, to, key, elapsed, seconds,
-- remaining, source, early, resumed }. seconds and remaining are nil when
-- the time is unknown.
function Flights:Current()
    if not flight then return nil end
    local elapsed = now() - flight.start
    return { from = flight.from, to = flight.to, key = flight.key, start = flight.start, elapsed = elapsed,
        seconds = flight.seconds, remaining = flight.seconds and math.max(0, flight.seconds - elapsed),
        source = flight.source, early = flight.early, resumed = flight.resumed }
end

function Flights:Flying() return flight ~= nil end

local function board(resumed)
    local p = pending
    pending, takeoffDeadline = nil, nil
    local route = p and p.route or {}
    flight = { from = route.from, to = route.to, key = route.key, start = now(),
        seconds = p and p.seconds, source = p and p.source or "unknown",
        multiplier = Flights.SpeedMultiplier(), resumed = resumed or nil }
    emit("takeoff", Flights:Current())
end

local function land()
    local info = Flights:Current()
    local landed = flight
    flight = nil
    stopPoll()
    info.learned = Flights.Estimates() and not landed.early and not landed.resumed and Flights:Learn(landed.key, info.elapsed, landed.multiplier)
        or false
    emit("landing", info)
end

function Flights:Tick()
    if flight then
        if not onTaxi() then land() end
    else
        local t = now()
        if pending and t - pending.at > Flights.BOARD_WAIT then pending = nil end
        if takeoffDeadline and t > takeoffDeadline then takeoffDeadline = nil end
        if (pending or takeoffDeadline) and onTaxi() then board(false)
        elseif not pending and not takeoffDeadline then stopPoll() end
    end
end

-- TakeTaxiNode runs while the flight map is still open, the one moment the
-- route can be read.
function Flights:TakeTaxi(slot)
    if not self.enabled then return end
    local route = self:Route(slot)
    local seconds, source = self:EstimateRoute(route)
    pending = { route = route, seconds = seconds, source = source, at = now() }
    startPoll()
end

-- The fallback for any takeoff the hooks and events missed: once the world
-- has loaded, a cheap taxi check every IDLE_POLL seconds. It only starts
-- after PLAYER_ENTERING_WORLD has dealt with a flight already under way, so
-- a reload mid-flight is still resumed rather than offered again.
function Flights:Idle(elapsed)
    self.idleWait = (self.idleWait or 0) + (elapsed or 0)
    if self.idleWait < Flights.IDLE_POLL then return end
    self.idleWait = 0
    if flight or pending or takeoffDeadline then return end
    if onTaxi() then
        board(false)
        startPoll()
    end
end

-- An early landing ends at the next stop; its time isn't learned.
function Flights:EarlyLanding()
    if flight then flight.early = true end
end

function Flights:Enable()
    if self.enabled then return end
    self.enabled = true
    if Flights.Estimates() then self:Store() end
    if hooksecurefunc then
        if TakeTaxiNode then hooksecurefunc("TakeTaxiNode", function(slot) Flights:TakeTaxi(slot) end) end
        if TaxiRequestEarlyLanding then hooksecurefunc("TaxiRequestEarlyLanding", function() Flights:EarlyLanding() end) end
    end
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_CONTROL_LOST")
    frame:RegisterEvent("PLAYER_CONTROL_GAINED")
    frame:SetScript("OnEvent", function(_, event) Flights:OnEvent(event) end)
    self.frame = frame
end

function Flights:OnEvent(event)
    if event == "PLAYER_ENTERING_WORLD" then
        -- A reload mid-flight is resumed, unless a recent request or
        -- control-loss event already identifies a fresh takeoff.
        if not flight then
            self:Tick()
            if not flight and onTaxi() then board(true) end
            if pending or flight or takeoffDeadline then startPoll() end
        end
        if self.frame and not self.idleOn then
            self.idleOn, self.idleWait = true, 0
            self.frame:SetScript("OnUpdate", function(_, elapsed) Flights:Idle(elapsed) end)
        end
    elseif event == "PLAYER_CONTROL_LOST" then
        -- Dialogue and scripted taxis bypass TakeTaxiNode. Taxi state can
        -- lag this event, so watch briefly and require positive confirmation.
        if not flight then
            takeoffDeadline = now() + Flights.BOARD_WAIT
            self:Tick()
        end
        if pending or flight or takeoffDeadline then startPoll() end
    elseif event == "PLAYER_CONTROL_GAINED" then
        self:Tick()
    end
end

-- Diagnostics lines.
function Flights:Report()
    local taxi = "Taxi state: " .. (onTaxi() and "flying" or "not flying")
    if not Flights.Estimates() then
        local current = self:Current()
        return "Flights: on (no estimates)\n" .. taxi .. (current and ("\nFlying: " .. tostring(current.from or "?")
            .. " to " .. tostring(current.to or "?")) or "")
    end
    local api = library()
    local client = api and call(api.GetClientInfo)
    local count = self:LearnedCount()
    local lines = {
        "Flights: on",
        taxi,
        "LibTaxiData: " .. (api and ("loaded" .. (type(client) == "table" and client.dataSet
            and (" (" .. tostring(client.dataSet) .. ")") or "")) or "not installed"),
        "Learned routes: " .. count,
        "Frequent Flier: " .. (Flights.SpeedMultiplier() > 1 and "yes" or "no"),
    }
    local current = self:Current()
    if current then
        lines[#lines + 1] = "Flying: " .. tostring(current.from or "?") .. " to " .. tostring(current.to or "?")
            .. ", " .. (current.remaining and (math.floor(current.remaining + 0.5) .. " s left") or "time unknown")
            .. " (" .. tostring(current.source) .. ")"
    end
    return table.concat(lines, "\n")
end

-- Tests only: forget the flight in progress.
function Flights:Reset()
    pending, flight, takeoffDeadline = nil, nil, nil
    stopPoll()
end
