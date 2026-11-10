local addonName, ns = ...
local HC = ns.HammerCore
local T, UI = HC.Theme, HC.UI

-- After an update, a small window lists the highlights of every release the
-- player hasn't seen yet.  The addon supplies them, newest or oldest first:
--   spec.whatsNew = {
--       { version = "1.8.0", items = {
--           { text = "Cooldown icons and a cooldown bar.", page = "Cooldowns" },
--       } },
--   }
-- An item is a line of text, or a table:
--   { text, title?, page?, kind? = "new" | "improved" | "fix",
--     client? = "retail" | "forever" }
-- `title` gives a bold first line with `text` under it; `page` makes the
-- item a link to that settings page; `kind` files it under New features
-- (the default), Improvements or Bug fixes; `client` adds a coloured
-- Retail or WoW Forever tag for changes that only apply there.  A release may
-- also carry `date = "2026-11-08"` (shown on the What's new page) and
-- `history = true` for highlights written after the fact: they appear under
-- Earlier releases, and tools/whatsnew_check.py doesn't require an entry
-- for every patch around them.
--
-- The rules every addon shares:
--   * never on a fresh install: the first run records the version silently;
--   * only releases with highlights, so routine patches stay quiet;
--   * never in combat: it waits for combat to end;
--   * -devN builds count as their base version;
--   * a highlight added to a release already seen shows on its own, so dev
--     builds pick up each new highlight for the release they're heading to;
--   * "Show what's new after updates" on Visibility turns it off, and the
--     `whatsnew` command and the About page show it any time.
--
-- ☠ ONE WINDOW FOR EVERY CONSECRATED HAMMER ADDON. Each addon carries its own
--   HammerCore and shares nothing else, so the after-update window is the one
--   deliberate exception: a small global, SHARED_KEY, where each copy leaves
--   its unseen highlights at login.  Whichever copy's timer fires first shows
--   them all in one window, using the newest renderer any copy brought, and
--   each addon still records what it has seen in its own saved variables.
--   Keep the entry shape stable: older copies may render newer entries.
--   The `whatsnew` command and About button show only their own addon.

local WhatsNew = {}
HC.WhatsNew = WhatsNew

local SHARED_KEY = "ConsecratedHammerWhatsNew"
-- Bump when the renderer improves, so the newest copy loaded draws the window.
local RENDERER = 2
local WIDTH, HEIGHT = 560, 460
-- The shared window's title icon: the quest giver's "!".
local SHARED_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"

-- "v1.8.0-dev2" -> { 1, 8, 0 }.  Anything without a leading number is nil.
function WhatsNew.Parse(version)
    if type(version) ~= "string" then return nil end
    local base = version:gsub("^v", ""):match("^(%d[%d%.]*)")
    if not base then return nil end
    local parts = {}
    for number in base:gmatch("%d+") do parts[#parts + 1] = tonumber(number) end
    return parts
end

function WhatsNew.Base(version)
    local parts = WhatsNew.Parse(version)
    if not parts then return nil end
    for index = 1, #parts do parts[index] = tostring(parts[index]) end
    return table.concat(parts, ".")
end

-- -1, 0 or 1.  An unreadable version sorts below every real one.
function WhatsNew.Compare(a, b)
    local left, right = WhatsNew.Parse(a), WhatsNew.Parse(b)
    if not left or not right then
        if left then return 1 end
        if right then return -1 end
        return 0
    end
    for index = 1, math.max(#left, #right) do
        local x, y = left[index] or 0, right[index] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end

local function later(a, b)
    if a == nil then return b end
    if b == nil then return a end
    return WhatsNew.Compare(a, b) >= 0 and a or b
end

function WhatsNew.Enabled()
    return type(HC.spec and HC.spec.whatsNew) == "table" and #HC.spec.whatsNew > 0
end

-- Releases that have highlights, newest first.
function WhatsNew:Releases()
    local releases = {}
    for _, release in ipairs(HC.spec and HC.spec.whatsNew or {}) do
        if type(release) == "table" and WhatsNew.Parse(release.version)
            and type(release.items) == "table" and #release.items > 0 then
            releases[#releases + 1] = release
        end
    end
    table.sort(releases, function(a, b) return WhatsNew.Compare(a.version, b.version) > 0 end)
    return releases
end

-- Releases newer than `seen`, plus any highlights the `seen` release has
-- gained since `seenItems` of them were shown.  With no record on an existing
-- profile (an update from before What's new existed), only this release's
-- own highlights: older ones were probably seen in the addon already.
function WhatsNew:Unseen(seen, current, seenItems)
    local unseen = {}
    for _, release in ipairs(self:Releases()) do
        -- History was written after the fact: the page lists it, the popup doesn't.
        if release.history then
            -- skip
        elseif seen then
            local order = WhatsNew.Compare(release.version, seen)
            if order > 0 then
                unseen[#unseen + 1] = release
            elseif order == 0 and #release.items > (seenItems or 0) then
                local items = {}
                for index = (seenItems or 0) + 1, #release.items do items[#items + 1] = release.items[index] end
                unseen[#unseen + 1] = { version = release.version, items = items }
            end
        elseif current ~= nil and WhatsNew.Compare(release.version, current) >= 0 then
            unseen[#unseen + 1] = release
        end
    end
    return unseen
end

-- How many highlights `version` has, or 0 without a release for it.
-- What the What's new page's unread badge compares against: the newest
-- release and its highlight count, so a highlight added to it counts too.
function WhatsNew:LatestKey()
    local newest = self:Releases()[1]
    if not newest then return nil end
    return tostring(WhatsNew.Base(newest.version)) .. ":" .. #newest.items
end

function WhatsNew:Unread()
    local state = HC.State()
    if not (state and WhatsNew.Enabled()) or state.whatsNewDot == false then return false end
    local key = self:LatestKey()
    return key ~= nil and state.whatsNewPageSeen ~= key
end

-- The quest turn-in sound, for opening the page with the "!" showing.
-- Retail and Forever don't share a sound library, so this tries the sound
-- kit, then the classic file path, and remembers which one played (or
-- why none did) for `whatsnew sound` and the diagnostic report.
local TURN_IN_KIT = 878   -- SOUNDKIT.IG_QUEST_LIST_COMPLETE
local TURN_IN_FILE = "Sound\\Interface\\iQuestComplete.ogg"

function WhatsNew:PlayTurnIn()
    local kit = type(SOUNDKIT) == "table" and SOUNDKIT.IG_QUEST_LIST_COMPLETE or TURN_IN_KIT
    if type(PlaySound) == "function" then
        local ok, willPlay = pcall(PlaySound, kit, "SFX")
        if ok and willPlay then
            self.lastSound = "sound kit " .. tostring(kit)
            return true
        end
    end
    if type(PlaySoundFile) == "function" then
        local ok, willPlay = pcall(PlaySoundFile, TURN_IN_FILE, "SFX")
        if ok and willPlay then
            self.lastSound = "sound file " .. TURN_IN_FILE
            return true
        end
    end
    self.lastSound = "nothing played (kit " .. tostring(kit) .. " and the sound file were refused; is Sound Effects on?)"
    return false
end

-- For testing the popup, badge and turn-in again: steps the record back to
-- the release before the newest, so the next /reload shows the newest
-- release's highlights and the "!" returns straight away.
function WhatsNew:ResetSeen()
    local state = HC.State()
    if not state then return false end
    local releases = self:Releases()
    local newest, previous = releases[1], releases[2]
    if not newest then return false end
    if previous then
        state.whatsNewSeen = tostring(WhatsNew.Base(previous.version))
        state.whatsNewSeenItems = #previous.items
    else
        state.whatsNewSeen = tostring(WhatsNew.Base(newest.version))
        state.whatsNewSeenItems = 0
    end
    state.whatsNewPageSeen = nil
    if HC.Settings and HC.Settings.RefreshBadges then HC.Settings:RefreshBadges() end
    return true
end

function WhatsNew:MarkPageSeen()
    local state = HC.State()
    if state then state.whatsNewPageSeen = self:LatestKey() end
end

function WhatsNew:ItemCount(version)
    for _, release in ipairs(self:Releases()) do
        if WhatsNew.Compare(release.version, version) == 0 then return #release.items end
    end
    return 0
end

-- Moves the record on to `mark`, never back, with how many of its highlights
-- have now been seen.
function WhatsNew:MarkSeen(state, mark)
    if mark == nil then return end
    local seen = state.whatsNewSeen
    local order = seen and WhatsNew.Compare(mark, seen) or 1
    if order > 0 then
        state.whatsNewSeen = mark
        state.whatsNewSeenItems = self:ItemCount(mark)
    elseif order == 0 then
        state.whatsNewSeenItems = math.max(state.whatsNewSeenItems or 0, self:ItemCount(seen))
    end
end

function WhatsNew.PageTitle(name)
    for _, spec in ipairs(HC.Settings.queue or {}) do
        if spec.name == name then return spec.title or spec.name end
    end
    return nil
end

-- This addon's section of a window.  Plain data and closures only: another
-- addon's HammerCore copy may be the one drawing it.
-- `icon` is the minimap button's, which reads better small beside a heading;
-- `logo` is the addon's own, for a window that's only this addon.
function WhatsNew:Section(releases, onShown)
    local minimap = type(HC.spec.minimap) == "table" and HC.spec.minimap.icon or nil
    return {
        name = HC.name,
        icon = minimap or HC.spec.icon,
        logo = HC.spec.icon,
        releases = releases,
        pageTitle = WhatsNew.PageTitle,
        openPage = function(page) HC.Settings:Show(page) end,
        isEnabled = function() return HC.State().whatsNew ~= false end,
        setEnabled = function(value) HC.State().whatsNew = value and true or false end,
        onShown = onShown,
    }
end

local function shared()
    local registry = _G[SHARED_KEY]
    if type(registry) ~= "table" then
        registry = { sections = {}, renderer = 0 }
        _G[SHARED_KEY] = registry
    end
    registry.sections = registry.sections or {}
    return registry
end

-- Called from HC:Start.  Decides once per session whether to show anything.
-- A welcome window opening at login (Welcome.lua) replaces the popup.
function WhatsNew:Check()
    self.checked = true
    local welcome = HC.Welcome and HC.Welcome:Check()
    if not WhatsNew.Enabled() then return end
    local state = HC.State()
    if not state then return end
    local current = WhatsNew.Base(HC.VERSION_TEXT)
    local releases = self:Releases()
    -- Where the record moves to once this session's highlights are handled.
    -- A dev build can carry highlights for the release it's heading towards,
    -- so the newest highlight counts too.
    local mark = later(current, releases[1] and releases[1].version)

    if state.whatsNewSeen == nil and HC.freshState then
        self:MarkSeen(state, mark)
        return
    end
    local unseen = self:Unseen(state.whatsNewSeen, current, state.whatsNewSeenItems)
    if #unseen == 0 or state.whatsNew == false then
        self:MarkSeen(state, mark)
        return
    end
    if welcome then
        -- Seen once the welcome has shown; the page still lists the release.
        HC.Welcome:OnLoginShown(function()
            local live = HC.State()
            if live then WhatsNew:MarkSeen(live, mark) end
        end)
        return
    end

    local registry = shared()
    registry.sections[#registry.sections + 1] = self:Section(unseen, function()
        local live = HC.State()
        if live then WhatsNew:MarkSeen(live, mark) end
    end)
    if (registry.renderer or 0) < RENDERER then
        registry.renderer = RENDERER
        registry.render = function(sections) return WhatsNew:ShowSections(sections) end
    end
    self.registered = true
    self:Schedule()
end

local function inCombat()
    return InCombatLockdown and InCombatLockdown() or false
end

-- Any copy may get here first; the registry makes sure the window opens once
-- with every addon's section.
function WhatsNew:TryShow()
    if not self.registered then return end
    self:Flush()
end

-- Shows whatever any copy left in the registry.  A welcome window that's
-- waiting or open holds it back, and calls this when it closes.
function WhatsNew:Flush()
    if inCombat() then return end   -- PLAYER_REGEN_ENABLED tries again
    if HC.Welcome and HC.Welcome.Busy() then return end
    local registry = shared()
    local sections = registry.sections
    if #sections == 0 or not registry.render then return end
    registry.sections = {}
    if registry.render(sections) then
        for _, section in ipairs(sections) do
            if section.onShown then pcall(section.onShown) end
        end
    else
        registry.sections = sections
    end
end

-- Waits for the world to finish loading, then a moment more so the window
-- doesn't land under the loading screen or the addon's own login chatter.
function WhatsNew:Schedule()
    if self.eventFrame then return end
    local frame = CreateFrame("Frame")
    self.eventFrame = frame
    local function soon()
        if C_Timer and C_Timer.After then
            C_Timer.After(3, function() WhatsNew:TryShow() end)
        else
            WhatsNew:TryShow()
        end
    end
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
            soon()
        else
            WhatsNew:TryShow()
        end
    end)
    if IsLoggedIn and IsLoggedIn() then soon() end
end

-- ── Drawing releases ────────────────────────────────────────────────────────
-- One renderer for the settings page and the after-update window.

WhatsNew.KINDS = {
    { key = "new", label = "NEW FEATURES" },
    { key = "improved", label = "IMPROVEMENTS" },
    { key = "fix", label = "BUG FIXES" },
}
local CLIENTS = { retail = "Retail", forever = "WoW Forever" }

function WhatsNew.Item(item)
    if type(item) ~= "table" then return { text = tostring(item or ""), kind = "new" } end
    local kind = item.kind
    if kind ~= "improved" and kind ~= "fix" then kind = "new" end
    return { text = tostring(item.text or ""), title = item.title, page = item.page, kind = kind,
        client = CLIENTS[item.client] and item.client or nil }
end

-- "Minor release   New features: 3   Bug fixes: 2"
function WhatsNew.Summary(release)
    local parts = WhatsNew.Parse(release.version) or {}
    local kind = (parts[3] or 0) > 0 and "Patch" or (parts[2] or 0) > 0 and "Minor release" or "Major release"
    local counts = {}
    for _, item in ipairs(release.items or {}) do
        local key = WhatsNew.Item(item).kind
        counts[key] = (counts[key] or 0) + 1
    end
    local text = { kind }
    for _, entry in ipairs(WhatsNew.KINDS) do
        if counts[entry.key] then
            local label = entry.label:sub(1, 1) .. entry.label:sub(2):lower()
            text[#text + 1] = label .. ": " .. counts[entry.key]
        end
    end
    return table.concat(text, "     ")
end

local function tag(item)
    if not item.client then return "" end
    return T.Code(item.client) .. CLIENTS[item.client] .. "|r" .. T.Code("muted") .. "  -  |r"
end

-- Draws a release's items into `parent` from (x, y), `width` wide, grouped
-- by kind.  opts = { pageTitle(page) -> title?, openPage(page) }.
-- Returns the y below the last item.
function WhatsNew.DrawItems(parent, x, y, width, release, opts)
    local groups = {}
    for _, raw in ipairs(release.items or {}) do
        local item = WhatsNew.Item(raw)
        groups[item.kind] = groups[item.kind] or {}
        table.insert(groups[item.kind], item)
    end
    local first = true
    for _, kind in ipairs(WhatsNew.KINDS) do
        local items = groups[kind.key]
        if items then
            if not first then y = y - 8 end
            first = false
            local label = UI.FontString(parent, "GameFontNormalSmall", "section")
            label:SetPoint("TOPLEFT", x, y)
            label:SetText(kind.label)
            local rule = T.Fill(parent:CreateTexture(nil, "ARTWORK"), "edge")
            rule:SetHeight(1)
            rule:SetPoint("LEFT", label, "RIGHT", 10, 0)
            rule:SetPoint("RIGHT", parent, "LEFT", x + width, 0)
            y = y - 22
            for _, item in ipairs(items) do
                if kind.key == "fix" then
                    local dot = T.Icon(parent:CreateTexture(nil, "ARTWORK"), "Circle.tga", "accent")
                    dot:SetSize(5, 5)
                    dot:SetPoint("TOPLEFT", x + 6, y - 5)
                    local line = UI.FontString(parent, "GameFontHighlightSmall")
                    line:SetPoint("TOPLEFT", x + 18, y)
                    line:SetWidth(width - 22)
                    line:SetJustifyH("LEFT")
                    if line.SetWordWrap then line:SetWordWrap(true) end
                    line:SetText(tag(item) .. (item.title and (item.title .. ": ") or "") .. item.text)
                    y = y - math.max(14, line:GetStringHeight() or 0) - 7
                else
                    local pageTitle = item.page and opts.pageTitle and opts.pageTitle(item.page)
                    local row = CreateFrame("Button", nil, parent)
                    row:SetPoint("TOPLEFT", x, y)
                    local hover = T.Fill(row:CreateTexture(nil, "BACKGROUND"), "hover")
                    hover:SetAllPoints()
                    hover:Hide()
                    local textWidth = width - 20 - (pageTitle and 150 or 0)
                    local head = UI.FontString(row, "GameFontHighlight")
                    head:SetPoint("TOPLEFT", 10, -7)
                    head:SetWidth(textWidth)
                    head:SetJustifyH("LEFT")
                    if head.SetWordWrap then head:SetWordWrap(true) end
                    head:SetText(tag(item) .. (item.title or item.text))
                    local height = 7 + math.max(14, head:GetStringHeight() or 0)
                    if item.title then
                        local body = UI.FontString(row, "GameFontHighlightSmall", "muted")
                        body:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -3)
                        body:SetWidth(textWidth)
                        body:SetJustifyH("LEFT")
                        if body.SetWordWrap then body:SetWordWrap(true) end
                        body:SetText(item.text)
                        height = height + 3 + math.max(12, body:GetStringHeight() or 0)
                    end
                    height = height + 8
                    row:SetSize(width, height)
                    if pageTitle then
                        local page = item.page
                        local link = UI.Link(row, "Open " .. pageTitle, function() opts.openPage(page) end)
                        link:SetPoint("TOPRIGHT", -10, -8)
                        row.link = link
                        row:SetScript("OnEnter", function() hover:Show(); link:GetScript("OnEnter")() end)
                        row:SetScript("OnLeave", function() hover:Hide(); link:GetScript("OnLeave")() end)
                        row:SetScript("OnClick", function() opts.openPage(page) end)
                    end
                    y = y - height - 2
                end
            end
        end
    end
    return y
end

-- ── The window ─────────────────────────────────────────────────────────────

function WhatsNew:Create()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", HC.FrameName("WhatsNew"), UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
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

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(26, 26)
    frame.icon:SetPoint("TOPLEFT", 16, -12)
    frame.title = UI.FontString(frame, "GameFontNormalLarge")
    frame.title:SetPoint("LEFT", frame.icon, "RIGHT", 8, 0)

    local well = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    well:SetPoint("TOPLEFT", 16, -48)
    well:SetPoint("BOTTOMRIGHT", -16, 46)
    T.Surface(well, "rail", "edge")
    local scroll = CreateFrame("ScrollFrame", nil, well, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    frame.scroll = scroll

    local again = UI.CheckButton(frame)
    again:SetPoint("BOTTOMLEFT", 18, 16)
    again.Text:SetText("Show after updates")
    again:SetScript("OnClick", function(self)
        self:SetChecked(not self:GetChecked())
        for _, section in ipairs(frame.sections or {}) do
            pcall(section.setEnabled, self:GetChecked())
        end
    end)
    frame.again = again

    local close = UI.Button(frame, 90, 22, "primary")
    close:SetPoint("BOTTOMRIGHT", -16, 14)
    close:SetText("Close")
    close:SetScript("OnClick", function() frame:Hide() end)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = frame:GetName() end
    self.frame = frame
    return frame
end

-- A fresh content frame per showing: it's rare, and the list differs.
local function fill(frame, sections)
    if frame.content then frame.content:Hide() end
    local width = WIDTH - 72
    local content = CreateFrame("Frame", nil, frame.scroll)
    content:SetWidth(width)
    frame.scroll:SetScrollChild(content)
    frame.content = content
    local several = #sections > 1

    local y = -2
    for sectionIndex, section in ipairs(sections) do
        if several then
            if sectionIndex > 1 then y = y - 14 end
            local icon = content:CreateTexture(nil, "ARTWORK")
            icon:SetSize(18, 18)
            icon:SetPoint("TOPLEFT", 2, y)
            icon:SetTexture(section.icon)
            local name = UI.FontString(content, "GameFontNormalLarge")
            name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
            name:SetText(section.name)
            y = y - 26
        end
        for index, release in ipairs(section.releases) do
            if index > 1 then y = y - 14 end
            local heading = T.Font(UI.FontString(content, "GameFontHighlight", "text"), 15)
            heading:SetPoint("TOPLEFT", 4, y)
            heading:SetText(tostring(section.name) .. " " .. tostring(WhatsNew.Base(release.version)))
            local summary = UI.FontString(content, "GameFontHighlightSmall", "muted")
            summary:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -4)
            summary:SetText(WhatsNew.Summary(release))
            y = y - 44
            y = WhatsNew.DrawItems(content, 0, y, width, release, {
                pageTitle = section.pageTitle,
                openPage = function(page)
                    frame:Hide()
                    section.openPage(page)
                end,
            })
        end
    end
    content:SetHeight(math.max(1, -y))
end

-- Draws one or more addons' sections.  Returns whether anything was shown.
function WhatsNew:ShowSections(sections)
    if type(sections) ~= "table" or #sections == 0 then return false end
    local frame = self:Create()
    frame.sections = sections
    if #sections == 1 then
        frame.icon:SetTexture(sections[1].logo or sections[1].icon)
        frame.title:SetText("What's new in " .. tostring(sections[1].name))
    else
        frame.icon:SetTexture(SHARED_ICON)
        frame.title:SetText("What's new in Consecrated Hammer addons")
    end
    fill(frame, sections)
    local enabled = true
    for _, section in ipairs(sections) do
        local ok, on = pcall(section.isEnabled)
        if ok and on == false then enabled = false end
    end
    frame.again:SetChecked(enabled)
    frame:Show()
    frame:Raise()
    return true
end

-- This addon only: every release with highlights, or the given ones.
function WhatsNew:Show(releases)
    releases = releases or self:Releases()
    if #releases == 0 then return false end
    return self:ShowSections({ self:Section(releases) })
end

function WhatsNew:Hide()
    if self.frame then self.frame:Hide() end
end
