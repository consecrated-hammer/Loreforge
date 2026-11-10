local addonName, ns = ...
local HC = ns.HammerCore
local T, UI = HC.Theme, HC.UI

-- A small welcome window that walks a player through an addon's few big
-- choices.  The addon registers it once, before HC:Start:
--
--   HC.Welcome:Register({
--       banner = "Interface\\AddOns\\Loreforge\\Textures\\welcome-banner.tga",
--       bannerSize = { 1024, 256 },     -- the texture's pixels, for its shape
--       tagline = "You read the quest text, right?",
--       intro = "Host trivia for your party, raid or guild, or play on your own.",
--       update = "New in 1.3: Quick play and a daily question.",
--       rows = {
--           { key = "flights", label = "On a flight", since = "1.3.0",
--             subtext = "A few questions to pass the time on a taxi.",
--             choices = {
--                 { value = "ask", label = "Ask me", sub = "Offer at takeoff",
--                   tip = "Offer a few questions when a flight takes off." },
--                 { value = "auto", label = "Auto-start", sub = "Starts by itself" },
--                 { value = "off", label = "Off", sub = "No questions" },
--             },
--             get = function() return db.flights end,
--             set = function(value) db.flights = value end },
--       },
--       footer = "You can change these in settings.",
--   })
--
-- Spec fields (all optional apart from rows):
--   banner, bannerSize   texture across the top, shown WIDTH wide at the
--                        texture's own shape (4:1 when bannerSize is missing)
--   title                heading when there's no banner ("Welcome to <name>")
--   tagline              one line of gold game text under the banner
--   intro                text for a new install and for Show
--   update               text for an update that only shows new rows
--   rows                 { key, label, subtext?, since?, choices, get, set }
--                        choices = { { value, label, sub?, tip? }, ... }
--   footer               text beside Done
--   auto                 default for "Setup on new features" (true: Show)
--   delay                seconds after loading in before it opens (3)
--
-- The rules:
--   * every default is applied before it opens; only a click calls `set`,
--     so Done, Esc and the close button keep whatever is current;
--   * a new install shows every row with `intro`;
--   * an update shows only rows whose `since` is newer than the release the
--     player last had the welcome for, with `update`; nothing new, no window;
--     a row without `since` is only ever shown on a new install or by Show;
--   * a few seconds after loading in, never in combat: combat hides it and
--     it comes back afterwards;
--   * when it opens at login it replaces that login's What's new popup (the
--     release still shows on the What's new page);
--   * "Setup on new features" (HC.State().welcomeAuto) turns the automatic
--     window off; HC.Welcome:Show() and the "Run setup again" button in
--     AddSettings always open it.
--
-- ☠ SHARED WITH OTHER COPIES. Like What's new, the login windows coordinate
--   through one small global, SHARED_KEY, so two addons' welcomes open one
--   after the other and the shared What's new waits until they're done.
--   Keep its shape stable: { open = id?, queue = { fn }, busy = n }.

local Welcome = {}
HC.Welcome = Welcome

local SHARED_KEY = "ConsecratedHammerWelcome"
local WIDTH = 460
local PAD = 20
local DELAY = 3

local function shared()
    local registry = _G[SHARED_KEY]
    if type(registry) ~= "table" then
        registry = {}
        _G[SHARED_KEY] = registry
    end
    registry.queue = registry.queue or {}
    registry.busy = registry.busy or 0
    return registry
end

local function inCombat()
    return InCombatLockdown and InCombatLockdown() or false
end

local function compare(a, b) return HC.WhatsNew.Compare(a, b) end
local function base(version) return HC.WhatsNew.Base(version) end

local function later(a, b)
    if a == nil then return b end
    if b == nil then return a end
    return compare(a, b) >= 0 and a or b
end

-- True while any copy's login welcome is waiting or open, so What's new
-- holds its popup until they're done.
function Welcome.Busy()
    local registry = _G[SHARED_KEY]
    return type(registry) == "table" and ((registry.busy or 0) > 0 or registry.open ~= nil) or false
end

function Welcome:Register(spec)
    assert(type(spec) == "table" and type(spec.rows) == "table", "Welcome:Register needs rows")
    self.spec = spec
    if HC.Commands and not HC.Commands.byName["setup"] then
        HC.Commands:Add({ name = "setup", section = "Core", help = "Open the welcome window",
            run = function() Welcome:Show(true) end })
    end
    -- Registered after HC:Start: decide now, without replacing What's new.
    if HC.WhatsNew and HC.WhatsNew.checked then self:Check() end
end

function Welcome.Enabled()
    return Welcome.spec ~= nil
end

-- ── The setting ────────────────────────────────────────────────────────────

function Welcome:AutoShow()
    local state = HC.State()
    local value = state and state.welcomeAuto
    if value == nil then return not (self.spec and self.spec.auto == false) end
    return value and true or false
end

function Welcome:SetAutoShow(enabled)
    local state = HC.State()
    if state then state.welcomeAuto = enabled and true or false end
end

-- A "Setup on new features" select and a "Run setup again" button, for the
-- page that holds the addon's other login choices.  Returns the next y.
function Welcome:AddSettings(panel, y)
    if not self.spec then return y end
    local _
    _, y = UI.Dropdown(panel, "Setup on new features", "Open setup at login when an update adds new choices.", y,
        { "show", "hide" }, { "Show", "Don't show" },
        function() return Welcome:AutoShow() and "show" or "hide" end,
        function(value) Welcome:SetAutoShow(value == "show") end,
        nil, nil, 120)
    _, y = UI.ActionButton(panel, y, "Run setup again", function()
        if HC.Settings and HC.Settings.Hide then HC.Settings:Hide() end
        Welcome:Show(true)
    end, "Open the welcome window again.")
    return y
end

-- ── Which rows ─────────────────────────────────────────────────────────────

function Welcome:Rows()
    local rows = {}
    for _, row in ipairs(self.spec and self.spec.rows or {}) do
        if type(row) == "table" and type(row.choices) == "table" and #row.choices > 0 then rows[#rows + 1] = row end
    end
    return rows
end

-- The release the record moves to: this one, or a newer row's (dev builds
-- carry rows for the release they're heading to).
function Welcome:Mark()
    local mark = base(HC.VERSION_TEXT)
    for _, row in ipairs(self:Rows()) do
        if row.since and HC.WhatsNew.Parse(row.since) then mark = later(mark, base(row.since)) end
    end
    return mark
end

-- Rows new since the player last had the welcome.  Without a record (an
-- update from before the welcome existed), the last release What's new
-- recorded stands in, and failing that only this release's rows count.
function Welcome:NewRows(state)
    local seen, keys = state.welcomeSeen, {}
    for _, key in ipairs(type(state.welcomeKeys) == "table" and state.welcomeKeys or {}) do keys[key] = true end
    local current = base(HC.VERSION_TEXT)
    local rows = {}
    for _, row in ipairs(self:Rows()) do
        local since = row.since and HC.WhatsNew.Parse(row.since) and row.since
        local new = false
        if since then
            if seen then
                -- A row added to the release already seen (a later dev build) counts too.
                new = not keys[row.key] and compare(since, seen) >= 0
            elseif state.whatsNewSeen then
                new = compare(since, state.whatsNewSeen) > 0
            else
                new = current ~= nil and compare(since, current) >= 0
            end
        end
        if new then rows[#rows + 1] = row end
    end
    return rows
end

function Welcome:MarkSeen(state)
    state = state or HC.State()
    if not state then return end
    local mark = self:Mark()
    if mark then state.welcomeSeen = later(state.welcomeSeen, mark) end
    local keys = {}
    for _, row in ipairs(self:Rows()) do
        if row.key ~= nil then keys[#keys + 1] = row.key end
    end
    state.welcomeKeys = keys
    state.welcomePending = nil
end

local function release()
    if not Welcome.claimed then return end
    Welcome.claimed = false
    local registry = shared()
    registry.busy = math.max(0, (registry.busy or 0) - 1)
end

-- Called from WhatsNew:Check, which HC:Start runs.  Returns true when the
-- welcome will open at login, so What's new holds back its popup.
function Welcome:Check()
    if self.checked then return self.queued ~= nil end
    if not self.spec then return false end
    local state = HC.State()
    if not state then return false end
    self.checked = true
    -- A new install stays "new" until its welcome has actually shown.
    local fresh = state.welcomePending or (state.welcomeSeen == nil and HC.freshState)
    local rows = fresh and self:Rows() or self:NewRows(state)
    if #rows == 0 or not self:AutoShow() then
        self:MarkSeen(state)
        return false
    end
    if fresh then state.welcomePending = true end
    self.queued = { rows = rows, mode = fresh and "intro" or "update" }
    self.claimed = true
    local registry = shared()
    registry.busy = registry.busy + 1
    self:Schedule()
    return true
end

-- What's new hands over its popup's "seen" step, to run once this opens.
function Welcome:OnLoginShown(fn)
    self.onLoginShown = self.onLoginShown or {}
    self.onLoginShown[#self.onLoginShown + 1] = fn
end

-- ── Timing ─────────────────────────────────────────────────────────────────

function Welcome:Events()
    if self.eventFrame then return self.eventFrame end
    local frame = CreateFrame("Frame")
    self.eventFrame = frame
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
            Welcome:Soon()
        elseif event == "PLAYER_REGEN_DISABLED" then
            Welcome:CombatStarted()
        else
            Welcome:CombatEnded()
        end
    end)
    return frame
end

function Welcome:Soon()
    local function ready()
        Welcome.ready = true
        Welcome:TryShow()
    end
    local delay = tonumber(self.spec and self.spec.delay) or DELAY
    if C_Timer and C_Timer.After and delay > 0 then C_Timer.After(delay, ready) else ready() end
end

function Welcome:Schedule()
    local frame = self:Events()
    if self.scheduled then return end
    self.scheduled = true
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    if IsLoggedIn and IsLoggedIn() then
        frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
        self:Soon()
    end
end

function Welcome:CombatStarted()
    if self.frame and self.frame:IsShown() then
        self.combatHidden = true
        self.frame:Hide()
        self.combatHidden = false
        self.resume = true
    end
end

function Welcome:CombatEnded()
    if self.resume then
        self.resume = false
        if self.frame then self.frame:Show(); self.frame:Raise() end
    elseif self.waiting then
        local waiting = self.waiting
        self.waiting = nil
        self:Open(waiting.rows, waiting.mode, waiting.login)
    else
        self:TryShow()
    end
end

-- The login showing, once loaded in and out of combat.
function Welcome:TryShow()
    if not (self.queued and self.ready) then return end
    if inCombat() then return end   -- PLAYER_REGEN_ENABLED tries again
    local queued = self.queued
    self.queued = nil
    if not self:AutoShow() then
        -- Switched off since login: record it as handled and step aside.
        self:MarkSeen()
        release()
        Welcome.Next()
        return
    end
    self:Open(queued.rows, queued.mode, true)
end

-- Opens every row with the intro: the "/x setup" and "Run setup again" path.
-- `force` is accepted for callers that pass it; Show always opens.
function Welcome:Show(force)
    if not self.spec then return false end
    return self:Open(self:Rows(), "intro", false)
end

-- After a welcome closes: the next copy's waiting welcome, or once they're
-- all done, the shared What's new.
function Welcome.Next()
    local registry = shared()
    if registry.open then return end
    local nextOpen = table.remove(registry.queue, 1)
    if nextOpen then
        pcall(nextOpen)
    elseif registry.busy == 0 and HC.WhatsNew and HC.WhatsNew.Flush then
        HC.WhatsNew:Flush()
    end
end

function Welcome:Open(rows, mode, login)
    if #rows == 0 then return false end
    if inCombat() then
        self.waiting = { rows = rows, mode = mode, login = login }
        if not login then HC.Print("setup opens after combat.") end
        return false
    end
    local registry = shared()
    if registry.open and registry.open ~= addonName then
        registry.queue[#registry.queue + 1] = function() Welcome:Open(rows, mode, login) end
        return false
    end
    registry.open = addonName
    local frame = self:Create()
    self.mode = mode
    self:Fill(frame, rows, mode)
    frame:Show()
    frame:Raise()
    self:MarkSeen()
    if login then
        for _, fn in ipairs(self.onLoginShown or {}) do pcall(fn) end
        self.onLoginShown = nil
    end
    return true
end

function Welcome:Hide()
    if self.frame then self.frame:Hide() end
end

function Welcome:IsShown()
    return self.frame and self.frame:IsShown() or false
end

-- Done, Esc and the close button all end up here.  Combat's hide doesn't.
function Welcome:Closed()
    if self.combatHidden then return end
    local registry = shared()
    if registry.open == addonName then registry.open = nil end
    release()
    Welcome.Next()
end

-- ── The window ─────────────────────────────────────────────────────────────

function Welcome:Create()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", HC.FrameName("Welcome"), UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, 400)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    T.Surface(frame, "outer", "edge")
    frame:Hide()
    frame:SetScript("OnHide", function() Welcome:Closed() end)

    frame.close = UI.CloseButton(frame, function() frame:Hide() end, 24)
    frame.close:SetPoint("TOPRIGHT", -8, -8)
    if frame.close.SetFrameLevel and frame.GetFrameLevel then frame.close:SetFrameLevel(frame:GetFrameLevel() + 5) end

    frame.done = UI.Button(frame, 90, 24, "primary")
    frame.done:SetPoint("BOTTOMRIGHT", -16, 14)
    frame.done:SetText("Done")
    frame.done:SetScript("OnClick", function() frame:Hide() end)

    frame.footer = UI.FontString(frame, "GameFontHighlightSmall", "muted")
    frame.footer:SetPoint("BOTTOMLEFT", PAD, 20)
    frame.footer:SetPoint("RIGHT", frame.done, "LEFT", -12, 0)
    frame.footer:SetJustifyH("LEFT")
    if frame.footer.SetWordWrap then frame.footer:SetWordWrap(false) end

    if UISpecialFrames and frame:GetName() then UISpecialFrames[#UISpecialFrames + 1] = frame:GetName() end
    self.frame = frame
    return frame
end

local function paintChoice(button, active, hovered)
    button.active = active
    if button.SetBackdropColor then
        button:SetBackdropColor(T.Unpack(active and "menuActive" or hovered and "hover" or "raised"))
    end
    T.Border(button, active and "selected" or hovered and "menuEdge" or "edge")
    T.Text(button.Text, active and "selected" or "text")
end

-- Re-reads every row's value, since one choice may change another.
function Welcome:Refresh()
    for _, row in ipairs(self.rowFrames or {}) do
        local ok, current = pcall(row.spec.get)
        for _, button in ipairs(row.buttons) do
            paintChoice(button, ok and current == button.value, false)
        end
    end
end

local function wrapped(parent, template, role, width, text)
    local fs = UI.FontString(parent, template, role)
    fs:SetWidth(width)
    fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    fs:SetText(text)
    return fs, math.max(12, fs:GetStringHeight() or 0)
end

-- A fresh content frame per showing: it's rare, and the rows differ.
function Welcome:Fill(frame, rows, mode)
    if frame.content then frame.content:Hide() end
    local spec = self.spec
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT")
    content:SetPoint("TOPRIGHT")
    frame.content = content
    local inner = WIDTH - PAD * 2
    local y = -1

    if spec.banner then
        local size = type(spec.bannerSize) == "table" and spec.bannerSize or { 4, 1 }
        local w, h = tonumber(size[1]) or 4, tonumber(size[2]) or 1
        local height = math.floor((WIDTH - 2) * h / math.max(1, w) + 0.5)
        local banner = content:CreateTexture(nil, "ARTWORK")
        banner:SetTexture(spec.banner)
        banner:SetPoint("TOPLEFT", 1, y)
        banner:SetSize(WIDTH - 2, height)
        frame.banner = banner
        y = y - height - 8
    else
        local title = UI.FontString(content, "GameFontNormalLarge", "accent")
        title:SetPoint("TOPLEFT", PAD, -16)
        title:SetText(spec.title or ("Welcome to " .. tostring(HC.name)))
        frame.banner = nil
        y = -44
    end

    if spec.tagline then
        local tagline = T.Font(UI.FontString(content, "GameFontNormal", "accent"), 14)
        tagline:SetPoint("TOP", content, "TOP", 0, y)
        tagline:SetWidth(inner)
        tagline:SetJustifyH("CENTER")
        tagline:SetText(spec.tagline)
        frame.tagline = tagline
        y = y - 26
    end

    local text = mode == "update" and (spec.update or spec.intro) or spec.intro
    if text then
        local intro, height = wrapped(content, "GameFontHighlight", "text", inner, text)
        intro:SetPoint("TOPLEFT", PAD, y)
        frame.intro = intro
        y = y - height - 16
    else
        frame.intro = nil
    end

    self.rowFrames = {}
    for _, row in ipairs(rows) do
        local entry = { spec = row, buttons = {} }
        local label = UI.FontString(content, "GameFontNormal", "text")
        label:SetPoint("TOPLEFT", PAD, y)
        label:SetText(row.label or "")
        entry.label = label
        y = y - 18
        if row.subtext then
            local sub, height = wrapped(content, "GameFontHighlightSmall", "muted", inner, row.subtext)
            sub:SetPoint("TOPLEFT", PAD, y)
            y = y - height - 8
        else
            y = y - 4
        end
        local count = #row.choices
        local gap = 8
        local width = math.floor((inner - gap * (count - 1)) / count)
        local hasSub = false
        for index, choice in ipairs(row.choices) do
            local button = CreateFrame("Button", nil, content, "BackdropTemplate")
            button:SetSize(width, 26)
            button:SetPoint("TOPLEFT", PAD + (index - 1) * (width + gap), y)
            T.Surface(button, "raised", "edge")
            button.Text = UI.FontString(button, "GameFontHighlight")
            button.Text:SetAllPoints()
            button.Text:SetJustifyH("CENTER")
            button.Text:SetText(choice.label or tostring(choice.value))
            button.value = choice.value
            button:HookScript("OnEnter", function(self) paintChoice(self, self.active, true) end)
            button:HookScript("OnLeave", function(self) paintChoice(self, self.active, false) end)
            button:SetScript("OnClick", function()
                if row.set then pcall(row.set, choice.value) end
                Welcome:Refresh()
            end)
            if choice.tip then UI.AttachHint(button, choice.label, choice.tip) end
            if choice.sub then
                hasSub = true
                local sub = UI.FontString(content, "GameFontHighlightSmall", "muted")
                sub:SetPoint("TOP", button, "BOTTOM", 0, -4)
                sub:SetWidth(width)
                sub:SetJustifyH("CENTER")
                if sub.SetWordWrap then sub:SetWordWrap(false) end
                sub:SetText(choice.sub)
                button.sub = sub
            end
            entry.buttons[index] = button
        end
        y = y - 26 - (hasSub and 20 or 0) - 16
        self.rowFrames[#self.rowFrames + 1] = entry
    end

    frame.footer:SetText(spec.footer or "")
    local height = -y + 44
    content:SetHeight(-y)
    frame:SetHeight(height)
    self:Refresh()
end
