local addonName, ns = ...
local HC = ns.HammerCore
local T, UI = HC.Theme, HC.UI

-- The movable settings window every addon shares.  The rail carries the
-- addon's name and lists its own pages under SETTINGS, a divider, then
-- REFERENCE: What's new, any addon reference pages, then Commands,
-- Troubleshooting and About.  The header band shows the page's title,
-- description and tabs; the footer has Reload UI, the support links and
-- Close.  Blizzard's Options > AddOns entry is only a launcher.

local Settings = { queue = {}, pages = {}, buttons = {} }
HC.Settings = Settings

local RAIL_WIDTH = 214
local HEADER_HEIGHT = 112
local FOOTER_HEIGHT = 56
local MIN_WIDTH, MIN_HEIGHT = 1000, 720
-- The What's new rail badge: unread, then the turn-in as the page opens.
local BADGE_UNREAD = "Interface\\GossipFrame\\AvailableQuestIcon"
local BADGE_READ = "Interface\\GossipFrame\\ActiveQuestIcon"
local GROUPS = { { key = "main", heading = "SETTINGS" }, { key = "reference", heading = "REFERENCE" } }

-- Where players find help and support the work.  An addon may replace
-- these with spec.links = { { label, url, icon = "Name.tga", hint? } }.
Settings.LINKS = {
    { label = "Discord", url = "https://discord.gg/z3xKxRygDc", icon = "Discord.tga",
        hint = "Questions, bug reports and ideas." },
    { label = "Buy me a coffee", url = "https://buymeacoffee.com/consecratedhammer", icon = "Coffee.tga",
        hint = "If the addon helps you, a coffee keeps the forge lit." },
}
Settings.SCALE_MIN, Settings.SCALE_MAX = 0.7, 1.3

-- spec = { name = "Buffs", title = "Buffs"?, description = "..."?,
--          group = "main" | "reference", columns = 1 | 2?,
--          tabs = { { name, build, columns? }, ... }? }, build(panel, y) -> bottom y
-- A page with tabs builds each tab on its own scrolling body; without tabs,
-- the page is its one tab.
function Settings:NewPage(spec, build)
    if type(spec) == "string" then spec = { name = spec } end
    spec.group = spec.group or "main"
    spec.build = build or spec.build
    self.queue[#self.queue + 1] = spec
    return spec
end

-- Standard pages are appended once, in a fixed order, when the window is
-- built.  Visibility goes last in the main section unless the addon placed
-- it with Settings:AddVisibility().
function Settings:Ordered()
    local ordered, hasVisibility = {}, false
    for _, spec in ipairs(self.queue) do
        if HC.Pages and spec == HC.Pages.visibility then hasVisibility = true end
    end
    for _, group in ipairs(GROUPS) do
        for _, spec in ipairs(self.queue) do
            if spec.group == group.key then ordered[#ordered + 1] = spec end
        end
        if group.key == "main" and not hasVisibility and HC.Pages then
            ordered[#ordered + 1] = HC.Pages.visibility
        end
        if group.key == "reference" and HC.Pages then
            -- What's new leads REFERENCE for addons that supply highlights.
            if HC.Pages.whatsNew and HC.WhatsNew and HC.WhatsNew.Enabled() then
                ordered[#ordered + 1] = HC.Pages.whatsNew
            end
            for _, spec in ipairs(HC.Pages.reference) do ordered[#ordered + 1] = spec end
        end
    end
    return ordered
end

-- One scrolling body: a tab's content, with its own scroll bar.
local function createBody(page, build, columns, top)
    local body = CreateFrame("Frame", nil, page)
    body:SetAllPoints(page)
    body:Hide()
    local contentTop = top or -14

    local scroll = CreateFrame("ScrollFrame", nil, body)
    scroll:SetPoint("TOPLEFT", 0, contentTop)
    scroll:SetPoint("BOTTOMRIGHT", -16, 8)
    local bar = CreateFrame("Slider", nil, body)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(4)
    bar:SetPoint("TOPRIGHT", body, "TOPRIGHT", -8, contentTop)
    bar:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -8, 8)
    T.Fill(bar:CreateTexture(nil, "BACKGROUND"), "edge"):SetAllPoints()
    local thumb = T.Fill(bar:CreateTexture(nil, "ARTWORK"), "accent")
    thumb:SetSize(4, 36)
    if bar.SetThumbTexture then bar:SetThumbTexture(thumb) end

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(UI.CONTENT_WIDTH + UI.PAD * 2, 1)
    scroll:SetScrollChild(content)
    content.hcRefresh = page.hcRefresh
    content.hcHeaderOwner = body
    content.hcColumns = columns

    local syncing = false
    local function updateBar()
        local range = scroll:GetVerticalScrollRange() or 0
        bar:SetShown(range > 1)
        range = math.max(1, range)
        bar:SetMinMaxValues(0, range)
        syncing = true
        bar:SetValue(math.min(range, scroll:GetVerticalScroll() or 0))
        syncing = false
    end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 48)))
    end)
    scroll:SetScript("OnVerticalScroll", updateBar)
    bar:SetScript("OnValueChanged", function(_, value)
        if syncing then return end
        scroll:SetVerticalScroll(math.max(0, math.min(scroll:GetVerticalScrollRange() or 0, value)))
    end)

    content.hcRefreshAll = page.hcRefreshAll
    -- A fixed area above the scrolling content, for a live preview that must
    -- stay in view while the settings below it scroll.
    content.hcCreatePinned = function(height, width)
        height = math.max(1, height or 1)
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", 0, contentTop - height)
        scroll:SetPoint("BOTTOMRIGHT", -16, 8)
        bar:ClearAllPoints()
        bar:SetPoint("TOPRIGHT", body, "TOPRIGHT", -8, contentTop - height)
        bar:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -8, 8)
        local pinned = CreateFrame("Frame", nil, body)
        pinned:SetPoint("TOPLEFT", body, "TOPLEFT", 0, contentTop)
        pinned:SetSize(width or UI.CONTENT_WIDTH + UI.PAD * 2, height)
        pinned.hcRefresh = page.hcRefresh
        pinned.hcRefreshAll = page.hcRefreshAll
        pinned.hcHeaderOwner = body
        return pinned
    end
    -- Pages that relayout their own rows report their new bottom here.
    content.hcSetBottom = function(bottom)
        bottom = UI.Flush(content, bottom or -1)
        content:SetHeight(math.max(1, -bottom + 24))
        updateBar()
    end

    content.hcSetBottom(build(content, -4) or -600)
    body:SetScript("OnShow", updateBar)
    body.content = content
    return body
end

local function createPage(spec, host)
    local page = CreateFrame("Frame", nil, host)
    page:SetAllPoints(host)
    page:Hide()
    page.name = spec.name
    page.hcRefresh = {}
    page.hcRefreshAll = function()
        if page.hcRefreshing then return end
        page.hcRefreshing = true
        for _, fn in ipairs(page.hcRefresh) do fn() end
        page.hcRefreshing = false
    end
    page.tabs, page.bodies = {}, {}
    -- spec.pinned = { height, build(frame) }: an area above every tab's
    -- scrolling body, such as a live preview the tabs share.  It builds
    -- first, so tab builds can use what it creates.
    local top = -14
    if spec.pinned then
        local pinned = CreateFrame("Frame", nil, page)
        pinned:SetPoint("TOPLEFT", page, "TOPLEFT", 0, top)
        pinned:SetSize(UI.CONTENT_WIDTH + UI.PAD * 2, spec.pinned.height)
        pinned.hcRefresh = page.hcRefresh
        pinned.hcRefreshAll = page.hcRefreshAll
        pinned.hcHeaderOwner = page
        spec.pinned.build(pinned)
        page.pinned = pinned
        top = top - spec.pinned.height
    end
    -- Settings pages lay rows out in two columns unless they ask for one;
    -- reference pages are prose and lists, so they stay single.
    local columns = spec.columns or (spec.group == "reference" and 1 or 2)
    local tabs = spec.tabs or { { name = spec.title or spec.name, build = spec.build } }
    for index, tab in ipairs(tabs) do
        page.tabs[index] = tab.name
        page.bodies[tab.name] = createBody(page, tab.build, tab.columns or columns, top)
    end
    page.selectedTab = page.tabs[1]
    page:SetScript("OnShow", function(self) self.hcRefreshAll() end)
    return page
end

local function errorPage(spec, host, err)
    local page = CreateFrame("Frame", nil, host)
    page:SetAllPoints(host)
    page:Hide()
    page.tabs, page.bodies = { spec.title or spec.name }, {}
    local message = UI.FontString(page, "GameFontHighlightSmall")
    message:SetPoint("TOPLEFT", UI.PAD, -20)
    message:SetWidth(UI.CONTENT_WIDTH)
    message:SetJustifyH("LEFT")
    T.Text(message, "danger")
    message:SetText("This settings page did not build.\n\n" .. tostring(err)
        .. "\n\nPlease send this text to the developer.")
    return page
end

-- A square icon button with a tinted HammerCore texture.
local function iconButton(parent, size, texture, hintTitle, hint)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    button.icon = T.Icon(button:CreateTexture(nil, "ARTWORK"), texture, "muted")
    button.icon:SetAllPoints()
    button:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(T.Unpack("accent"))
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(hintTitle, T.Unpack("accent"))
        if hint then GameTooltip:AddLine(hint, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(T.Unpack("muted"))
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    return button
end

-- The square close button: a bordered box with an X.  Shared as
-- UI.CloseButton(parent, onClick, size) for an addon's own windows.
function UI.CloseButton(parent, onClick, size)
    local close = CreateFrame("Button", nil, parent, "BackdropTemplate")
    close:SetSize(size or 30, size or 30)
    T.Surface(close, "raised", "edge")
    local strokes = {}
    for _, angle in ipairs({ 0.785, -0.785 }) do
        local stroke = T.Fill(close:CreateTexture(nil, "ARTWORK"), "muted")
        stroke:SetSize(14, 2)
        stroke:SetPoint("CENTER")
        if stroke.SetRotation then stroke:SetRotation(angle) end
        strokes[#strokes + 1] = stroke
    end
    close:SetScript("OnEnter", function(self)
        T.Border(self, "accent")
        for _, stroke in ipairs(strokes) do T.Fill(stroke, "text") end
    end)
    close:SetScript("OnLeave", function(self)
        T.Border(self, "edge")
        for _, stroke in ipairs(strokes) do T.Fill(stroke, "muted") end
    end)
    close:SetScript("OnClick", onClick)
    return close
end

local function closeButton(parent, frame)
    return UI.CloseButton(parent, function() frame:Hide() end)
end

-- Opens a link the only way WoW allows: selected in a box, ready to copy.
function Settings:OpenLink(link)
    HC.Dialog:Link({ title = link.label, url = link.url, icon = link.icon })
end

-- The addon's own CurseForge page (## X-CurseForge in its TOC) leads, so
-- players can rate it or check for updates; then the shared links.
function Settings:Links()
    local links = HC.spec.links
    if links == false then return {} end
    if type(links) == "table" then return links end
    local list = {}
    local page = HC.GetMetadata("X-CurseForge")
    if type(page) == "string" and page:find("^https://") then
        list[1] = { label = "CurseForge", url = page, icon = "CurseForge.tga",
            hint = HC.name .. "'s page: updates, comments and other addons." }
    end
    for _, link in ipairs(self.LINKS) do list[#list + 1] = link end
    return list
end

function Settings:ApplyScale()
    if not self.window then return end
    local scale = tonumber(HC.State().settingsScale) or 1
    scale = math.max(self.SCALE_MIN, math.min(self.SCALE_MAX, scale))
    self.window:SetScale(scale)
    if self.scaleValue then self.scaleValue:SetText(math.floor(scale * 100 + 0.5) .. "%") end
end

function Settings:Create()
    if self.window then return self.window end
    local size = HC.spec.window or {}
    local state = HC.State()
    local width = math.max(size.width or 0, MIN_WIDTH)
    local height = math.max(size.height or 0, MIN_HEIGHT)
    -- Settings fill the space between the rail and the scroll bar.
    UI.CONTENT_WIDTH = width - RAIL_WIDTH - UI.PAD * 2 - 22

    local frame = CreateFrame("Frame", HC.FrameName("SettingsFrame"), UIParent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    T.Surface(frame, "outer", "edge")
    local saved = state and state.settingsPoint or { "CENTER", "CENTER", 0, 0 }
    frame:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
    local function dragFrom(region)
        region:EnableMouse(true)
        region:RegisterForDrag("LeftButton")
        region:SetScript("OnDragStart", function() frame:StartMoving() end)
        region:SetScript("OnDragStop", function()
            frame:StopMovingOrSizing()
            local point, _, relativePoint, x, y = frame:GetPoint()
            HC.State().settingsPoint = { point, relativePoint, x, y }
        end)
    end

    -- ── Rail: brand, page list, version ──
    local rail = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    rail:SetPoint("TOPLEFT", 1, -1)
    rail:SetPoint("BOTTOMLEFT", 1, 1)
    rail:SetWidth(RAIL_WIDTH)
    T.Surface(rail, "rail")
    local railEdge = T.Fill(frame:CreateTexture(nil, "ARTWORK"), "edge")
    railEdge:SetPoint("TOPLEFT", RAIL_WIDTH + 1, -1)
    railEdge:SetPoint("BOTTOMLEFT", RAIL_WIDTH + 1, 1)
    railEdge:SetWidth(1)

    local brand = CreateFrame("Button", nil, rail)
    brand:SetPoint("TOPLEFT", 0, 0)
    brand:SetPoint("TOPRIGHT", 0, 0)
    brand:SetHeight(HEADER_HEIGHT - 20)
    dragFrom(brand)
    local icon = brand:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40)
    icon:SetPoint("LEFT", 20, 0)
    icon:SetTexture(HC.spec.icon)
    local title = T.Font(UI.FontString(brand, "GameFontNormalLarge", "text"), 20)
    title:SetPoint("LEFT", icon, "RIGHT", 12, 0)
    title:SetPoint("RIGHT", -12, 0)
    title:SetJustifyH("LEFT")
    title:SetText(HC.name)
    local brandRule = T.Fill(rail:CreateTexture(nil, "ARTWORK"), "edge")
    brandRule:SetPoint("TOPLEFT", 16, -(HEADER_HEIGHT - 20))
    brandRule:SetPoint("TOPRIGHT", -16, -(HEADER_HEIGHT - 20))
    brandRule:SetHeight(1)

    local version = UI.FontString(rail, "GameFontDisableSmall", "muted")
    version:SetPoint("BOTTOMLEFT", 20, 18)
    version:SetText(tostring(HC.VERSION_TEXT))
    self.versionText = version

    -- ── Header band: title, description, scale, close, tabs ──
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", RAIL_WIDTH + 2, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_HEIGHT)
    T.Fill(header:CreateTexture(nil, "BACKGROUND"), "header"):SetAllPoints()
    local shade = T.Icon(header:CreateTexture(nil, "BORDER"), "Fade.tga", "outer")
    shade:SetPoint("BOTTOMLEFT")
    shade:SetPoint("BOTTOMRIGHT")
    shade:SetHeight(HEADER_HEIGHT / 2)
    if shade.SetTexCoord then shade:SetTexCoord(0, 1, 1, 0) end
    shade:SetAlpha(0.35)
    local headerRule = T.Fill(header:CreateTexture(nil, "ARTWORK"), "edge")
    headerRule:SetPoint("BOTTOMLEFT")
    headerRule:SetPoint("BOTTOMRIGHT")
    headerRule:SetHeight(1)
    dragFrom(header)

    local pageTitle = T.Font(UI.FontString(header, "GameFontNormalLarge", "text"), 26)
    pageTitle:SetPoint("TOPLEFT", UI.PAD + 4, -20)
    local pageDescription = UI.FontString(header, "GameFontHighlightSmall", "muted")
    pageDescription:SetPoint("TOPLEFT", pageTitle, "BOTTOMLEFT", 1, -8)
    pageDescription:SetPoint("RIGHT", header, "RIGHT", -260, 0)
    pageDescription:SetJustifyH("LEFT")
    if pageDescription.SetWordWrap then pageDescription:SetWordWrap(false) end
    self.pageTitle, self.pageDescription = pageTitle, pageDescription

    -- Beside the title: the active profile, and whether this page's settings
    -- are saved to it or shared by every profile.  Click for Profiles.
    local tag = CreateFrame("Button", nil, header, "BackdropTemplate")
    tag:SetHeight(22)
    tag:SetPoint("LEFT", pageTitle, "RIGHT", 14, -1)
    T.Surface(tag, "raised", "edge")
    tag.Text = UI.FontString(tag, "GameFontHighlightSmall", "text")
    tag.Text:SetPoint("LEFT", 10, 0)
    tag:SetScript("OnClick", function()
        local name = Settings.profilesPageName
        if name then Settings:Select(name) end
    end)
    UI.AttachHint(tag, "Profile", "")
    tag:Hide()
    self.profileTag = tag

    local close = closeButton(header, frame)
    close:SetPoint("TOPRIGHT", -14, -14)

    -- Window scale: a small slider, saved with the window position.
    local scaleValue = UI.FontString(header, "GameFontHighlightSmall", "text")
    scaleValue:SetPoint("RIGHT", close, "LEFT", -14, 0)
    scaleValue:SetWidth(38)
    scaleValue:SetJustifyH("RIGHT")
    self.scaleValue = scaleValue
    local scale = CreateFrame("Slider", nil, header)
    scale:SetOrientation("HORIZONTAL")
    scale:SetSize(100, 16)
    scale:SetPoint("RIGHT", scaleValue, "LEFT", -8, 0)
    scale:SetMinMaxValues(self.SCALE_MIN * 100, self.SCALE_MAX * 100)
    scale:SetValueStep(5)
    scale:SetObeyStepOnDrag(true)
    local scaleTrack = T.Fill(scale:CreateTexture(nil, "BACKGROUND"), "edge")
    scaleTrack:SetPoint("LEFT", 5, 0)
    scaleTrack:SetPoint("RIGHT", -5, 0)
    scaleTrack:SetHeight(3)
    local scaleThumb = T.Icon(scale:CreateTexture(nil, "OVERLAY"), "Circle.tga", "accent")
    scaleThumb:SetSize(12, 12)
    if scale.SetThumbTexture then scale:SetThumbTexture(scaleThumb) end
    local scaleLabel = UI.FontString(header, "GameFontHighlightSmall", "muted")
    scaleLabel:SetPoint("RIGHT", scale, "LEFT", -10, 0)
    scaleLabel:SetText("Window scale")

    -- A page's own action (spec.headerAction), such as opening a live
    -- preview, on the right of the header under the window controls.
    local action = UI.Button(header, 170, 26)
    action:SetPoint("TOPRIGHT", close, "BOTTOMRIGHT", 0, -14)
    action:Hide()
    action:SetScript("OnClick", function(self)
        local spec = self.hcSpec
        if spec and spec.onClick then spec.onClick() end
        Settings:RefreshHeaderAction()
    end)
    self.headerAction = action
    scale:SetValue((tonumber(state and state.settingsScale) or 1) * 100)
    -- Scaling while dragging would move the slider under the cursor; the
    -- new scale applies when the mouse is released.
    scale:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value / 5 + 0.5) * 5
        HC.State().settingsScale = value / 100
        scaleValue:SetText(value .. "%")
    end)
    scale:SetScript("OnMouseUp", function() Settings:ApplyScale() end)
    self.scaleSlider = scale

    self.tabButtons = {}
    local tabBar = CreateFrame("Frame", nil, header)
    tabBar:SetPoint("BOTTOMLEFT", UI.PAD, 0)
    tabBar:SetPoint("BOTTOMRIGHT", -UI.PAD, 0)
    tabBar:SetHeight(32)
    self.tabBar = tabBar

    -- ── Footer: reload, support links, close ──
    local footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT", RAIL_WIDTH + 2, 1)
    footer:SetPoint("BOTTOMRIGHT", -1, 1)
    footer:SetHeight(FOOTER_HEIGHT)
    T.Fill(footer:CreateTexture(nil, "BACKGROUND"), "rail"):SetAllPoints()
    local footerRule = T.Fill(footer:CreateTexture(nil, "ARTWORK"), "edge")
    footerRule:SetPoint("TOPLEFT")
    footerRule:SetPoint("TOPRIGHT")
    footerRule:SetHeight(1)
    local reload = UI.Button(footer, 150, 30)
    reload:SetPoint("LEFT", UI.PAD, 0)
    reload:SetText("Reload UI")
    UI.AttachHint(reload, "Reload UI", "Reload the interface, as /reload does.")
    reload:SetScript("OnClick", function() if ReloadUI then ReloadUI() end end)
    local done = UI.Button(footer, 150, 30)
    done:SetPoint("RIGHT", -UI.PAD, 0)
    done:SetText("Close")
    done:SetScript("OnClick", function() frame:Hide() end)
    self.linkButtons = {}
    local anchor = done
    local links = self:Links()
    for index = #links, 1, -1 do
        local link = links[index]
        local button = iconButton(footer, 26, link.icon or "Discord.tga", link.label, link.hint)
        button:SetPoint("RIGHT", anchor, "LEFT", anchor == done and -24 or -16, 0)
        button:SetScript("OnClick", function() Settings:OpenLink(link) end)
        button.link = link
        self.linkButtons[#self.linkButtons + 1] = button
        anchor = button
    end
    self.footer, self.reloadButton, self.closeButton = footer, reload, done

    -- ── Pages ──
    local host = CreateFrame("Frame", nil, frame)
    host:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    host:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 0)
    T.Fill(host:CreateTexture(nil, "BACKGROUND"), "content"):SetAllPoints()
    -- A faint watermark of the addon's logo gives the page some depth.
    local watermark = host:CreateTexture(nil, "BORDER")
    watermark:SetTexture(HC.spec.icon)
    watermark:SetSize(320, 320)
    watermark:SetPoint("CENTER", 0, 0)
    if watermark.SetDesaturated then watermark:SetDesaturated(true) end
    watermark:SetAlpha(0.035)

    self.window, self.host, self.rail, self.header = frame, host, rail, header
    self.order = self:Ordered()

    -- Finish the rail before building any page: a page that fails must not
    -- leave the window without navigation.
    local railY, previous = -(HEADER_HEIGHT - 4), nil
    self.dividers = {}
    for _, spec in ipairs(self.order) do
        if spec.group ~= previous then
            if previous then
                local divider = T.Fill(rail:CreateTexture(nil, "ARTWORK"), "edge")
                divider:SetPoint("TOPLEFT", 20, railY - 6)
                divider:SetPoint("TOPRIGHT", -20, railY - 6)
                divider:SetHeight(1)
                self.dividers[#self.dividers + 1] = divider
                railY = railY - 18
            end
            for _, group in ipairs(GROUPS) do
                if group.key == spec.group then
                    local heading = UI.FontString(rail, "GameFontNormalSmall", "accent")
                    heading:SetPoint("TOPLEFT", 20, railY - 6)
                    heading:SetText(group.heading)
                end
            end
            railY = railY - 28
            previous = spec.group
        end
        local button = CreateFrame("Button", nil, rail)
        button:SetSize(RAIL_WIDTH, 32)
        button:SetPoint("TOPLEFT", 0, railY)
        button.Text = UI.FontString(button)
        button.Text:SetPoint("LEFT", 26, 0)
        button.Text:SetText(spec.title or spec.name)
        button.hover = T.Fill(button:CreateTexture(nil, "BACKGROUND"), "stripe")
        button.hover:SetAllPoints()
        button.hover:Hide()
        button.activeBg = T.Fill(button:CreateTexture(nil, "BACKGROUND"), "raised")
        button.activeBg:SetAllPoints()
        button.activeBar = T.Fill(button:CreateTexture(nil, "ARTWORK"), "accent")
        button.activeBar:SetPoint("TOPLEFT")
        button.activeBar:SetPoint("BOTTOMLEFT")
        button.activeBar:SetWidth(3)
        button:SetScript("OnEnter", function(self) self.hover:Show() end)
        button:SetScript("OnLeave", function(self) self.hover:Hide() end)
        local name = spec.name
        button:SetScript("OnClick", function() Settings:Show(name) end)
        if HC.Pages and spec == HC.Pages.whatsNew then
            -- The unread badge: the quest-giver "!" (the same icon as the What's
            -- new window), right-aligned in the row so the label never moves.
            local badge = button:CreateTexture(nil, "OVERLAY")
            badge:SetTexture(BADGE_UNREAD)
            badge:SetSize(20, 20)
            badge:SetPoint("RIGHT", -16, 0)
            badge:Hide()
            -- Opening the page turns the "!" into the turn-in "?", which
            -- holds a moment and fades, like handing in a quest.
            local complete = badge:CreateAnimationGroup()
            local fade = complete:CreateAnimation("Alpha")
            fade:SetFromAlpha(1)
            fade:SetToAlpha(0)
            fade:SetStartDelay(0.7)
            fade:SetDuration(0.5)
            complete:SetScript("OnFinished", function()
                badge:Hide()
                badge:SetAlpha(1)
                badge:SetTexture(BADGE_UNREAD)
            end)
            badge.complete = complete
            button.Text:SetPoint("RIGHT", badge, "LEFT", -4, 0)
            button.Text:SetJustifyH("LEFT")
            button.unreadBadge = badge
        end
        self.buttons[name] = button
        railY = railY - 32
    end

    -- An addon may pin one action to the foot of the rail, such as a live
    -- preview the player wants while changing settings on any page.
    -- spec.railButton = { label = string|fn, run = fn, active = fn? }
    local railButton = HC.spec.railButton
    if railButton then
        local button = UI.Button(rail, RAIL_WIDTH - 40, 28)
        button:SetPoint("BOTTOMLEFT", 20, 42)
        button:SetScript("OnClick", function()
            railButton.run()
            Settings:RefreshRail()
        end)
        self.railButton = button
    end

    self.errors = {}
    for _, spec in ipairs(self.order) do
        local ok, page = xpcall(function() return createPage(spec, host) end,
            function(err) return tostring(err) end)
        if not ok then
            self.errors[spec.name] = page
            page = errorPage(spec, host, page)
        end
        page.spec = spec
        self.pages[spec.name] = page
    end

    frame:SetScript("OnShow", function()
        Settings:Select(Settings.selected)
        if HC.spec.onSettingsShown then HC.spec.onSettingsShown() end
        Settings:RefreshHeaderAction()
    end)
    frame:SetScript("OnHide", function()
        if HC.spec.onSettingsHidden then HC.spec.onSettingsHidden() end
    end)
    self:ApplyScale()
    self:RefreshFooter()
    frame:Hide()
    -- Escape closes the window like any Blizzard panel.
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = frame:GetName() end
    return frame
end

-- Support links follow the Visibility setting.
function Settings:RefreshFooter()
    local shown = HC.State().supportLinks ~= false
    for _, button in ipairs(self.linkButtons or {}) do button:SetShown(shown) end
end

-- The header's tabs for the selected page.  A page without tabs shows its
-- own title as its one tab, so every page has the same shape.
function Settings:RefreshTabs(page)
    for _, button in ipairs(self.tabButtons) do button:Hide() end
    if not page then return end
    local x = 0
    for index, name in ipairs(page.tabs or {}) do
        local button = self.tabButtons[index]
        if not button then
            button = CreateFrame("Button", nil, self.tabBar)
            button:SetHeight(32)
            button.Text = T.Font(UI.FontString(button, "GameFontHighlight"), 14)
            button.Text:SetPoint("CENTER", 0, 2)
            button.line = T.Fill(button:CreateTexture(nil, "OVERLAY"), "accent")
            button.line:SetPoint("BOTTOMLEFT", 4, 0)
            button.line:SetPoint("BOTTOMRIGHT", -4, 0)
            button.line:SetHeight(2)
            button:SetScript("OnEnter", function(self)
                if not self.active then T.Text(self.Text, "text") end
            end)
            button:SetScript("OnLeave", function(self)
                if not self.active then T.Text(self.Text, "muted") end
            end)
            self.tabButtons[index] = button
        end
        button.Text:SetText(name)
        local width = (button.Text.GetStringWidth and button.Text:GetStringWidth() or 0) or 0
        width = math.max(60, width + 28)
        button:SetWidth(width)
        button:ClearAllPoints()
        button:SetPoint("BOTTOMLEFT", x, 0)
        x = x + width + 6
        button.active = name == page.selectedTab
        button.line:SetShown(button.active)
        T.Text(button.Text, button.active and "text" or "muted")
        local pageName, tabName = page.name, name
        button:SetScript("OnClick", function() Settings:Show(pageName, tabName) end)
        button:Show()
    end
end

-- Shows or hides the What's new unread badge.  `opened` is true when the
-- player has just opened the page with the badge showing: it plays the
-- turn-in instead of vanishing.
function Settings:RefreshBadges(opened)
    local page = HC.Pages and HC.Pages.whatsNew
    local button = page and self.buttons[page.name]
    local badge = button and button.unreadBadge
    if not badge then return end
    if HC.WhatsNew:Unread() then
        if badge.complete then badge.complete:Stop() end
        badge:SetTexture(BADGE_UNREAD)
        badge:SetAlpha(1)
        badge:Show()
    elseif opened and badge:IsShown() and badge.complete then
        badge:SetTexture(BADGE_READ)
        badge.complete:Play()
        if HC.State().whatsNewSound ~= false then HC.WhatsNew:PlayTurnIn() end
    elseif not (badge.complete and badge.complete:IsPlaying()) then
        badge:Hide()
    end
end

function Settings:RefreshRail()
    local spec = HC.spec.railButton
    local button = self.railButton
    if not (spec and button) then return end
    local label = spec.label
    if type(label) == "function" then label = label() end
    button:SetText(label)
    local active = spec.active and spec.active() or false
    T.Border(button, active and "selected" or "edge")
end

function Settings:Select(name, tab)
    if not self.window then return end
    self:RefreshRail()
    if not (name and self.pages[name]) then name = self.order[1] and self.order[1].name end
    self.selected = name
    local opened = HC.Pages and HC.Pages.whatsNew and name == HC.Pages.whatsNew.name
    if opened then HC.WhatsNew:MarkPageSeen() end
    self:RefreshBadges(opened)
    for pageName, page in pairs(self.pages) do
        local active = pageName == name
        page:SetShown(active)
        local button = self.buttons[pageName]
        if button then
            button:SetEnabled(not active)
            button.activeBar:SetShown(active)
            button.activeBg:SetShown(active)
            T.Text(button.Text, active and "text" or "muted")
        end
    end
    local page = self.pages[name]
    if page then
        if tab and page.bodies[tab] then page.selectedTab = tab end
        for tabName, body in pairs(page.bodies) do body:SetShown(tabName == page.selectedTab) end
        local spec = page.spec or {}
        self.pageTitle:SetText(spec.title or spec.name or name)
        self.pageDescription:SetText(spec.description or "")
        self:RefreshTabs(page)
        self:RefreshHeaderAction()
        self:RefreshProfileTag()
        -- A reopened page re-reads values that changed while it was hidden.
        if page.hcRefreshAll then page.hcRefreshAll() end
    end
end

-- spec.profileGroups = { "grid", ... }: the profile groups whose settings
-- live on this page.  Every main page of an addon with profiles shows the
-- tag; reference pages and the Profiles page itself don't.
function Settings:RefreshProfileTag()
    local tag = self.profileTag
    if not tag then return end
    local page = self.selected and self.pages[self.selected]
    local spec = page and page.spec or {}
    for _, other in pairs(self.pages) do
        if other.spec and other.spec.profilesPage then self.profilesPageName = other.spec.name end
    end
    local profiles = HC.Profiles
    local active, saved
    if profiles and profiles.PageStatus and spec.group == "main" and not spec.profilesPage then
        active, saved = profiles:PageStatus(spec.profileGroups)
    end
    if not active then tag:Hide(); return end
    local hint
    if #saved > 0 then
        tag.Text:SetText("Saved to profile: " .. active)
        T.Text(tag.Text, "accent")
        T.Border(tag, "accent")
        hint = "These settings on this page are saved to the " .. active .. " profile: "
            .. table.concat(saved, ", ") .. "."
        if #saved < #(spec.profileGroups or {}) or spec.profilePartial then
            hint = hint .. " Everything else here is shared by all profiles."
        end
    else
        tag.Text:SetText("Shared by all profiles (active: " .. active .. ")")
        T.Text(tag.Text, "muted")
        T.Border(tag, "edge")
        hint = "Changes on this page apply to every profile."
        if spec.profileGroups and #spec.profileGroups > 0 then
            hint = hint .. " Tick it under Included in profiles to save it per profile."
        end
    end
    tag.hcHintTitle, tag.hcHint = "Profile", hint .. " Click to manage profiles."
    tag:SetWidth((tag.Text.GetStringWidth and tag.Text:GetStringWidth() or 160) + 20)
    tag:SetEnabled(self.profilesPageName ~= nil)
    tag:Show()
end

-- spec.headerAction = { text = "..." or fn, onClick = fn, hint = "..."? }
function Settings:RefreshHeaderAction()
    local button = self.headerAction
    if not button then return end
    local page = self.selected and self.pages[self.selected]
    local spec = page and page.spec and page.spec.headerAction
    button.hcSpec = spec
    if not spec then button:Hide(); return end
    local text = spec.text
    if type(text) == "function" then text = text() end
    button:SetText(tostring(text or ""))
    if spec.hint then
        if not button.hcHinted then UI.AttachHint(button, "", "") end
        button.hcHinted = true
        button.hcHintTitle, button.hcHint = tostring(text or ""), spec.hint
    else
        button.hcHint = nil
    end
    button:Show()
end

function Settings:IsShown()
    return self.window and self.window:IsShown() or false
end

-- Open settings, optionally on a named page and tab.
function Settings:Show(name, tab)
    if HC.spec.hideInCombat and InCombatLockdown and InCombatLockdown() then
        HC.Print("settings open after combat")
        return false
    end
    if HC.spec.canOpen then
        local ok, reason = HC.spec.canOpen()
        if not ok then
            if reason then HC.Print(reason) end
            return false
        end
    end
    local built, err = pcall(self.Create, self)
    if not built or not self.window then
        HC.Print("settings could not be built: " .. tostring(err))
        return false
    end
    if SettingsPanel and SettingsPanel.IsShown and SettingsPanel:IsShown() then
        if HideUIPanel then HideUIPanel(SettingsPanel) else SettingsPanel:Hide() end
    end
    self.selected = name or self.selected
    self.window:Show()
    self.window:Raise()
    self:Select(self.selected, tab)
    return true
end

function Settings:Hide()
    if self.window then self.window:Hide() end
end

function Settings:Toggle(name)
    if self:IsShown() and not name then self:Hide() else self:Show(name) end
end

-- Blizzard's Options > AddOns tree gets a small launcher for the real window.
function Settings:CreateLauncher()
    if self.launcher then return end
    local panel = CreateFrame("Frame", HC.FrameName("OptionsLauncher"))
    panel.name = HC.name
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(HC.name)
    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(210, 28)
    open:SetPoint("TOPLEFT", 16, -54)
    open:SetText("Open " .. HC.name .. " settings")
    open:SetScript("OnClick", function() Settings:Show() end)
    local build = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    build:SetPoint("TOPLEFT", 16, -98)
    build:SetText("Version " .. tostring(HC.VERSION_TEXT))
    if _G.Settings and _G.Settings.RegisterCanvasLayoutCategory then
        local category = _G.Settings.RegisterCanvasLayoutCategory(panel, HC.name, HC.name)
        _G.Settings.RegisterAddOnCategory(category)
        self.category = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
        self.category = panel
    end
    self.launcher = panel
end
