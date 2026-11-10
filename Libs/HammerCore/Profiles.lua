local addonName, ns = ...
local HC = ns.HammerCore

-- Named profiles for groups of an addon's settings.
--
-- The addon keeps reading and writing its own flat saved-variable keys; the
-- values sitting there always belong to the loaded profile.  Switching first
-- captures those keys back into the loaded profile, then copies the target's
-- values over them and asks the addon to refresh.  Nothing else in the addon
-- has to know profiles exist.
--
-- The addon declares groups of keys ("Position", "Grid and size") and every
-- group is saved per profile.  Players don't choose: a profile is the whole
-- layout (Kevin, 2026-11-10).  Keys outside the groups are the same in
-- every profile.
--
-- Everything lives in db.hcProfiles:
--   list        { [name] = { [key] = value } }
--   active      account-wide active profile
--   characters  { ["Name-Realm"] = profile } when perCharacter is on
--   loaded      the profile whose values are in the flat keys right now
--   groups      { [groupKey] = true } groups already seeded into profiles
--   newFrom     "ACTIVE" | "DEFAULTS"
--   auto, autoState   see AutoSwitch.lua
--
-- spec (HC.Profiles:Setup) = {
--   groups   = { { key, label, keys = { ... }, default = bool, hint? } },
--   defaults = function() -> the addon's defaults table,
--   seed     = { { name = "Party", values = { key = value } } }?, active = "Party"?,
--   rules    = { default auto-switch rules }?,
--   apply    = function(name, reason) refresh the addon after a switch,
--   unsafe   = function() -> true while a switch must wait (combat),
-- }

local Profiles = { MAX = 20, NAME_LENGTH = 24 }
HC.Profiles = Profiles

local function deepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = deepCopy(v) end
    return copy
end
Profiles.DeepCopy = deepCopy

local function trim(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function Profiles:Setup(spec)
    assert(type(spec) == "table" and type(spec.groups) == "table", "Profiles:Setup needs groups")
    self.spec = spec
    self.enabled = true
    if HC.Commands and HC.Commands.Add and not HC.Commands.byName.profile then
        HC.Commands:Add({ name = "profile", args = "[name]", section = HC.name,
            help = "List profiles, or switch to one",
            run = function(args) Profiles:Command(args) end })
    end
    if self.Auto and self.Auto.Setup then self.Auto:Setup() end
    return self
end

function Profiles:CharacterKey()
    local name = UnitName and UnitName("player")
    local realm = GetRealmName and GetRealmName()
    if type(name) ~= "string" or name == "" then return nil end
    return name .. "-" .. (type(realm) == "string" and realm or "")
end

-- The addon's flat saved variables.
local function db() return HC.spec and HC.spec.db() end

function Profiles:Data()
    local saved = db()
    if type(saved) ~= "table" then return nil end
    if type(saved.hcProfiles) ~= "table" then saved.hcProfiles = {} end
    return saved.hcProfiles
end

function Profiles:Group(key)
    for _, group in ipairs(self.spec and self.spec.groups or {}) do
        if group.key == key then return group end
    end
end

function Profiles:Included(key)
    return self:Data() ~= nil and self:Group(key) ~= nil
end

-- Every key currently stored per profile.
function Profiles:Keys()
    local keys = {}
    for _, group in ipairs(self.spec and self.spec.groups or {}) do
        if self:Included(group.key) then
            for _, key in ipairs(group.keys) do keys[#keys + 1] = key end
        end
    end
    return keys
end

local function defaults()
    local spec = Profiles.spec
    local value = spec and spec.defaults
    if type(value) == "function" then value = value() end
    return type(value) == "table" and value or {}
end

function Profiles:Snapshot()
    local saved, values = db(), {}
    for _, key in ipairs(self:Keys()) do values[key] = deepCopy(saved[key]) end
    return values
end

function Profiles:DefaultValues()
    local base, values = defaults(), {}
    for _, key in ipairs(self:Keys()) do values[key] = deepCopy(base[key]) end
    return values
end

-- ── Reading ────────────────────────────────────────────────────────────────

function Profiles:Names()
    local data, names = self:Data(), {}
    for name in pairs(data and data.list or {}) do names[#names + 1] = name end
    table.sort(names, function(a, b)
        local la, lb = a:lower(), b:lower()
        if la ~= lb then return la < lb end
        return a < b
    end)
    return names
end

function Profiles:Count() return #self:Names() end

function Profiles:Exists(name)
    local data = self:Data()
    return type(name) == "string" and data and type(data.list) == "table"
        and type(data.list[name]) == "table" or false
end

-- Case-insensitive lookup, for slash commands (HammerCore lowercases args).
function Profiles:Find(text)
    text = trim(text):lower()
    for _, name in ipairs(self:Names()) do
        if name:lower() == text then return name end
    end
end

function Profiles:Active()
    local data = self:Data()
    if not data then return nil end
    if data.perCharacter then
        local key = self:CharacterKey()
        local name = key and type(data.characters) == "table" and data.characters[key]
        if self:Exists(name) then return name end
    end
    return data.active
end

function Profiles:Loaded()
    local data = self:Data()
    return data and data.loaded
end

function Profiles:Setting(key)
    local data = self:Data()
    return data and data[key]
end

-- ── Normalising ────────────────────────────────────────────────────────────

-- Saved variables are player-controlled input.  Recover a sane shape and,
-- the first time, seed the addon's starter profiles from its current values.
function Profiles:Ready()
    if not self.enabled then return nil end
    local data = self:Data()
    if not data then return nil end
    local spec = self.spec
    if type(data.groups) ~= "table" then data.groups = {} end
    for key, value in pairs(data.groups) do
        if not self:Group(key) or type(value) ~= "boolean" then data.groups[key] = nil end
    end
    if type(data.characters) ~= "table" then data.characters = {} end
    data.perCharacter = data.perCharacter == true
    if data.newFrom ~= "ACTIVE" and data.newFrom ~= "DEFAULTS" then data.newFrom = "ACTIVE" end
    if type(data.list) ~= "table" then data.list = {} end
    for name, values in pairs(data.list) do
        if type(name) ~= "string" or trim(name) == "" or type(values) ~= "table" then data.list[name] = nil end
    end

    if next(data.list) == nil then
        local current = self:Snapshot()
        local seeds = spec.seed or { { name = "Default" } }
        for _, seed in ipairs(seeds) do
            local values = deepCopy(current)
            for key, value in pairs(seed.values or {}) do values[key] = deepCopy(value) end
            data.list[seed.name] = values
        end
        data.active = spec.active or seeds[1].name
        data.loaded = nil
    end
    -- Groups that used to be shared (before 0.3.2 players chose) join every
    -- profile with the value in use now, so nothing changes on screen.
    local current = db()
    for _, group in ipairs(spec.groups) do
        if data.groups[group.key] ~= true then
            for _, values in pairs(data.list) do
                for _, field in ipairs(group.keys) do
                    if values[field] == nil then values[field] = deepCopy(current[field]) end
                end
            end
            data.groups[group.key] = true
        end
    end
    if not self:Exists(data.active) then data.active = self:Names()[1] end
    for key, name in pairs(data.characters) do
        if type(key) ~= "string" or not self:Exists(name) then data.characters[key] = nil end
    end
    if self.Auto and self.Auto.Normalise then self.Auto:Normalise(data) end

    -- Put the right profile's values in the flat keys: the seed's overrides
    -- on first run, or this character's own profile when it differs.
    local want = self:Active()
    if data.loaded ~= want then
        if self:Exists(data.loaded) then self:Capture() end
        self:Load(want)
        data.loaded = want
    end
    return data
end

-- ── Moving values ──────────────────────────────────────────────────────────

-- Flat keys -> loaded profile.  Safe to call any time.
function Profiles:Capture()
    local data = self:Data()
    if not (data and self:Exists(data.loaded)) then return end
    local values = data.list[data.loaded]
    local saved = db()
    for _, key in ipairs(self:Keys()) do values[key] = deepCopy(saved[key]) end
end

-- Profile -> flat keys.  A key the profile lacks keeps its current value.
function Profiles:Load(name)
    local data = self:Data()
    if not (data and self:Exists(name)) then return end
    local values, saved = data.list[name], db()
    for _, key in ipairs(self:Keys()) do
        if values[key] ~= nil then saved[key] = deepCopy(values[key]) end
    end
end

function Profiles:SetActive(name)
    local data = self:Data()
    if data.perCharacter then
        local key = self:CharacterKey()
        if key then data.characters[key] = name end
    else
        data.active = name
    end
end

local function refreshSettings()
    local settings = HC.Settings
    for _, page in pairs(settings and settings.pages or {}) do
        if page.hcRefreshAll and page.IsShown and page:IsShown() then page.hcRefreshAll() end
    end
    if settings and settings.RefreshProfileTag then settings:RefreshProfileTag() end
end

-- The profile in use, for the tag beside each settings page's title.
function Profiles:PageStatus()
    if not self.spec then return nil end
    return self:Loaded() or self:Active()
end
Profiles.RefreshSettings = refreshSettings

local function applied(name, reason)
    local spec = Profiles.spec
    if spec.apply then spec.apply(name, reason) end
    refreshSettings()
end

-- reason: "manual" (the player picked it), "auto" (a switch rule), "load".
-- While unsafe() the switch waits; FlushPending runs it.
function Profiles:Switch(name, reason)
    reason = reason or "manual"
    local data = self:Data()
    if not (data and self:Exists(name)) then return false end
    local spec = self.spec
    if reason ~= "load" and spec.unsafe and spec.unsafe() then
        self.pending = { name = name, reason = reason }
        if reason == "manual" or self:Setting("auto") and data.auto.message then
            HC.Print("switching to the " .. name .. " profile after combat")
        end
        return true
    end
    self.pending = nil
    if reason == "manual" and self.Auto then self.Auto:NoteManual() end
    if data.loaded ~= name then
        self:Capture()
        self:Load(name)
        data.loaded = name
    end
    self:SetActive(name)
    applied(name, reason)
    if reason == "auto" and data.auto and data.auto.message then
        HC.Print("switched to the " .. name .. " profile")
    end
    return true
end

function Profiles:FlushPending()
    local pending = self.pending
    if not pending then return end
    local spec = self.spec
    if spec.unsafe and spec.unsafe() then return end
    self.pending = nil
    self:Switch(pending.name, pending.reason)
end

-- ── Managing ───────────────────────────────────────────────────────────────

-- Returns the trimmed name, or nil and a reason.
function Profiles:CheckName(name, except)
    name = trim(name)
    if name == "" then return nil, "Enter a name." end
    -- "|" starts a chat escape code; a name with one could recolour or hide text.
    if name:find("|", 1, true) then return nil, "Names can't contain |." end
    if #name > self.NAME_LENGTH then return nil, "Use " .. self.NAME_LENGTH .. " characters or fewer." end
    local existing = self:Find(name)
    if existing and existing ~= except then return nil, "That name is taken." end
    return name
end

-- source: "ACTIVE" copies the loaded profile, "DEFAULTS" starts fresh, nil
-- uses the player's New profiles start from setting.
function Profiles:Create(name, source)
    local data = self:Data()
    local checked, problem = self:CheckName(name)
    if not checked then return nil, problem end
    if self:Count() >= self.MAX then return nil, "Delete a profile first (" .. self.MAX .. " at most)." end
    source = source or data.newFrom
    self:Capture()
    data.list[checked] = source == "DEFAULTS" and self:DefaultValues() or self:Snapshot()
    self:Switch(checked, "manual")
    return checked
end

function Profiles:SaveAs(name) return self:Create(name, "ACTIVE") end

-- Copies another profile's values into the loaded one.
function Profiles:CopyFrom(name)
    local data = self:Data()
    if not (self:Exists(name) and self:Exists(data.loaded)) or name == data.loaded then return false end
    local target = data.list[data.loaded]
    for _, key in ipairs(self:Keys()) do
        if data.list[name][key] ~= nil then target[key] = deepCopy(data.list[name][key]) end
    end
    self:Load(data.loaded)
    applied(data.loaded, "copy")
    return true
end

local function renameReferences(data, old, new)
    if data.active == old then data.active = new end
    if data.loaded == old then data.loaded = new end
    for key, name in pairs(data.characters) do
        if name == old then data.characters[key] = new end
    end
    for _, rule in ipairs(data.auto and data.auto.rules or {}) do
        if rule.profile == old then rule.profile = new end
    end
end

function Profiles:Rename(old, new)
    local data = self:Data()
    if not self:Exists(old) then return nil, "No such profile." end
    local checked, problem = self:CheckName(new, old)
    if not checked then return nil, problem end
    if checked == old then return checked end
    data.list[checked], data.list[old] = data.list[old], nil
    renameReferences(data, old, checked)
    refreshSettings()
    return checked
end

function Profiles:Delete(name)
    local data = self:Data()
    if not self:Exists(name) then return false, "No such profile." end
    if self:Count() <= 1 then return false, "Keep at least one profile." end
    local replacement
    for _, other in ipairs(self:Names()) do
        if other ~= name then replacement = replacement or other end
    end
    if data.active == name then data.active = replacement end
    for key, assigned in pairs(data.characters) do
        if assigned == name then data.characters[key] = nil end
    end
    -- A rule pointing at a deleted profile becomes "No change".
    for _, rule in ipairs(data.auto and data.auto.rules or {}) do
        if rule.profile == name then rule.profile = "" end
    end
    local wasLoaded = data.loaded == name
    data.list[name] = nil
    if wasLoaded then
        data.loaded = nil
        local want = self:Active()
        self:Load(want)
        data.loaded = want
        applied(want, "delete")
    else
        refreshSettings()
    end
    return true
end

-- The loaded profile back to the addon's defaults.
function Profiles:Reset()
    local data = self:Data()
    if not self:Exists(data.loaded) then return false end
    data.list[data.loaded] = self:DefaultValues()
    self:Load(data.loaded)
    applied(data.loaded, "reset")
    return true
end

-- Ticking a group in gives every profile the current shared value, so they
-- start equal; ticking it out drops it from all of them.
function Profiles:SetPerCharacter(enabled)
    local data = self:Data()
    enabled = enabled and true or false
    if data.perCharacter == enabled then return end
    local current = data.loaded
    data.perCharacter = enabled
    if enabled then
        local key = self:CharacterKey()
        if key then data.characters[key] = current end
    else
        data.active = current
    end
end

function Profiles:SetNewFrom(value)
    local data = self:Data()
    if value == "ACTIVE" or value == "DEFAULTS" then data.newFrom = value end
end

-- ── Quick switching ────────────────────────────────────────────────────────

-- Menu entries for HC.Menu, one per profile with the active one ticked.
function Profiles:MenuItems()
    local items = { { text = "Profiles", title = true } }
    local loaded = self:Loaded()
    for _, name in ipairs(self:Names()) do
        items[#items + 1] = { text = name, checked = name == loaded,
            func = function() Profiles:Switch(name, "manual") end }
    end
    return items
end

function Profiles:Command(args)
    args = trim(args)
    if args == "" then
        local names, loaded = self:Names(), self:Loaded()
        for index, name in ipairs(names) do
            if name == loaded then names[index] = name .. " (active)" end
        end
        HC.Print("profiles: " .. table.concat(names, ", "))
        HC.Print("switch with " .. HC.Command() .. " profile <name>")
        return
    end
    local name = self:Find(args)
    if not name then
        HC.Print("no profile called " .. args)
        return
    end
    if name == self:Loaded() then
        HC.Print("already using the " .. name .. " profile")
        return
    end
    self:Switch(name, "manual")
    if not self.pending then HC.Print("switched to the " .. name .. " profile") end
end
