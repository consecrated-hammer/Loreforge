local addonName, ns = ...
local HC = ns.HammerCore
local Updates = { PREFIX = "CHVer1", THROTTLE = 30, MAX_AGE = 3 * 24 * 60 * 60,
    pending = {}, lastSent = {}, generation = 0, status = "not started" }
HC.UpdateReminders = Updates

-- Strict release versions only. Never strip suffixes: that would let a dev
-- or prerelease copy advertise a stable release which does not exist yet.
function Updates.Parse(text)
    if type(text) ~= "string" or #text > 20 then return nil end
    local a, b, c = text:match("^(%d+)%.(%d+)%.(%d+)$")
    if not a then return nil end
    local out = {}
    for i, part in ipairs({ a, b, c }) do
        if #part > 4 or (#part > 1 and part:sub(1, 1) == "0") then return nil end
        out[i] = tonumber(part)
    end
    return out
end
function Updates.Compare(a, b)
    local left, right = Updates.Parse(a), Updates.Parse(b)
    if not left or not right then return nil end
    for i = 1, 3 do
        if left[i] ~= right[i] then return left[i] > right[i] and 1 or -1 end
    end
    return 0
end
local function stamp()
    local value = GetServerTime and GetServerTime() or time and time()
    return type(value) == "number" and value == value and value > 0 and value < math.huge and value or nil
end
local function elapsed() return GetTime and GetTime() or 0 end
local function channels()
    local out = {}
    if IsInGuild and IsInGuild() then out.GUILD = true end
    if IsInGroup then
        if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then out.INSTANCE_CHAT = true end
        if IsInRaid and IsInRaid(LE_PARTY_CATEGORY_HOME) then out.RAID = true
        elseif IsInGroup(LE_PARTY_CATEGORY_HOME) then out.PARTY = true end
    end
    return out
end
local function selfSender(sender)
    local name, realm
    if UnitFullName then name, realm = UnitFullName("player")
    elseif UnitName then name, realm = UnitName("player") end
    if type(name) ~= "string" then return false end
    if sender == name then return true end
    if type(realm) ~= "string" or realm == "" then
        realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName())
    end
    return type(realm) == "string" and sender == name .. "-" .. realm:gsub("%s", "")
end
function Updates:Active()
    local state = self.enabled and HC.State()
    return state and state.updateReminders ~= false or false
end
function Updates:Notify(version)
    if self.notified or not self.ready or not self:Active() or self.Compare(version, self.current) ~= 1 then return end
    self.notified = true
    HC.Print("Version " .. version .. " is available (you have " .. self.current .. "). Update on CurseForge.")
end
function Updates:Remembered(state)
    state = state or HC.State()
    local now = stamp()
    local record = state and state.updateRelease
    if record == nil then return nil end
    if type(record) ~= "table" or self.Compare(record.version, self.current) ~= 1
        or type(record.heardAt) ~= "number" or record.heardAt ~= record.heardAt
        or not now or record.heardAt > now or now - record.heardAt > self.MAX_AGE then
        state.updateRelease = nil
        return nil
    end
    return record.version
end
function Updates:Queue(channel, reason, delay, retry)
    if not self:Active() then return end
    if self.pending[channel] then
        if reason == "broadcast" then self.pending[channel].reason = "broadcast" end
        return
    end
    local generation, token = self.generation, {}
    self.pending[channel] = { token = token, reason = reason }
    local remaining = self.lastSent[channel] and (self.THROTTLE - (elapsed() - self.lastSent[channel])) or 0
    delay = math.max(delay or 0, remaining)
    local function send()
        local pending = self.pending[channel]
        if generation ~= self.generation or not pending or pending.token ~= token then return end
        self.pending[channel] = nil
        if not self:Active() or not channels()[channel] then return end
        local wait = self.lastSent[channel] and (self.THROTTLE - (elapsed() - self.lastSent[channel])) or 0
        if wait > 0 then
            if not retry and C_Timer and C_Timer.After then self:Queue(channel, pending.reason, wait + 0.05, true) end
            return
        end
        local ok, result = pcall(self.send, self.PREFIX, addonName .. "\t" .. self.current, channel)
        if ok and (result == nil or result == true or result == 0) then self.lastSent[channel] = elapsed()
        elseif not retry and C_Timer and C_Timer.After then self:Queue(channel, pending.reason, 5, true) end
    end
    if C_Timer and C_Timer.After then C_Timer.After(delay, send) else send() end
end
local function signature(channel)
    if channel == "GUILD" then return "guild" end
    local category = channel == "INSTANCE_CHAT" and LE_PARTY_CATEGORY_INSTANCE or LE_PARTY_CATEGORY_HOME
    local count = GetNumGroupMembers and GetNumGroupMembers(category)
    return channel .. ":" .. tostring(count or "joined")
end
function Updates:Broadcast(changedOnly)
    if not self.ready then return end
    local active = channels()
    self.signatures = self.signatures or {}
    for channel in pairs(active) do
        local current = signature(channel)
        if not changedOnly or self.signatures[channel] ~= current then self:Queue(channel, "broadcast", 1 + math.random()) end
        self.signatures[channel] = current
    end
    for channel in pairs(self.signatures) do if not active[channel] then self.signatures[channel] = nil end end
end
function Updates:Receive(prefix, payload, channel, sender)
    if not self:Active() or prefix ~= self.PREFIX or type(payload) ~= "string" or #payload > 80
        or type(sender) ~= "string" or selfSender(sender) or not channels()[channel] then return end
    local name, version = payload:match("^([^\t]+)\t([^\t]+)$")
    if name ~= addonName then return end
    local order = self.Compare(version, self.current)
    if order == nil then return end
    -- One equal/newer copy is enough to answer an older sender. Cancel only
    -- pending replies, never the ordinary announcement of our own version.
    local pending = self.pending[channel]
    if order >= 0 and pending and pending.reason == "reply" then self.pending[channel] = nil end
    if order < 0 then
        if self.ready then self:Queue(channel, "reply", 0.5 + math.random() * 2) end
        return
    end
    if order == 0 then return end
    local state, now = HC.State(), stamp()
    if not state then return end
    local remembered = self:Remembered(state)
    if now and (not remembered or self.Compare(version, remembered) >= 0) then
        state.updateRelease = { version = version, heardAt = now }
    end
    self:Notify(remembered and self.Compare(remembered, version) > 0 and remembered or version)
end
function Updates:Login()
    if self.loginQueued or not self:Active() then return end
    self.loginQueued = true
    local generation = self.generation
    local function ready()
        if generation ~= self.generation or not self:Active() then return end
        self.ready = true
        local version = self:Remembered()
        if version then self:Notify(version) end
        self:Broadcast()
    end
    if C_Timer and C_Timer.After then C_Timer.After(8 + math.random() * 2, ready) else ready() end
end
function Updates:Apply()
    self.generation = self.generation + 1
    self.enabled, self.ready, self.loginQueued, self.pending, self.signatures = false, false, false, {}, {}
    if self.events then self.events:UnregisterAllEvents() end
    self.current = HC.VERSION_TEXT
    if not self.Parse(self.current) then self.status = "silent: non-stable build"; return end
    local state = HC.State()
    if not state or state.updateReminders == false then self.status = "off"; return end
    local register = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
    self.send = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
    if not (register and self.send) then self.status = "unavailable: addon-message API"; return end
    local ok, result = pcall(register, self.PREFIX)
    local accepted = result == nil or result == true or result == 0 or result == 1
    if result == false then
        local registered = C_ChatInfo and C_ChatInfo.IsAddonMessagePrefixRegistered or IsAddonMessagePrefixRegistered
        if registered then local checked, present = pcall(registered, self.PREFIX); accepted = checked and present == true end
    end
    if not ok or not accepted then self.status = "unavailable: prefix registration"; return end
    self.enabled, self.status = true, "on: stable releases only"
    if not self.events then
        self.events = CreateFrame("Frame")
        self.events:SetScript("OnEvent", function(_, event, ...)
            if event == "CHAT_MSG_ADDON" then self:Receive(...)
            elseif event == "PLAYER_LOGIN" then self:Login()
            else self:Broadcast(true) end
        end)
    end
    for _, event in ipairs({ "CHAT_MSG_ADDON", "PLAYER_LOGIN", "GROUP_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE" }) do
        pcall(self.events.RegisterEvent, self.events, event)
    end
    if IsLoggedIn and IsLoggedIn() then self:Login() end
end
function Updates:Start()
    if self.started then return end
    self.started = true
    self:Apply()
end
function Updates:SetEnabled(value)
    local state = HC.State()
    if state then state.updateReminders = value == true end
    if self.started then self:Apply() end
end
