local addonName, ns = ...
local HC = ns.HammerCore
local T, UI = HC.Theme, HC.UI

-- The movable settings window every addon shares.  The rail lists the
-- addon's own pages under CORE, a divider, then REFERENCE: any addon
-- reference pages, followed by the standard Theme, Commands, Troubleshooting
-- and About pages.  Blizzard's Options > AddOns entry is only a launcher.

local Settings = { queue = {}, pages = {}, buttons = {} }
HC.Settings = Settings

local RAIL_WIDTH = 178
local GROUPS = { { key = "main", heading = "CORE" }, { key = "reference", heading = "REFERENCE" } }

-- spec = { name = "Buffs", title = "Buffs"?, description = "..."?,
--          group = "main" | "reference" }, build(panel, y) -> bottom y
function Settings:NewPage(spec, build)
    if type(spec) == "string" then spec = { name = spec } end
    spec.group = spec.group or "main"
    spec.build = build
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
            for _, spec in ipairs(HC.Pages.reference) do ordered[#ordered + 1] = spec end
        end
    end
    return ordered
end

local function createPage(spec, host)
    local panel = CreateFrame("Frame", nil, host)
    panel:SetAllPoints(host)
    panel:Hide()
    panel.name = spec.name
    panel.hcRefresh = {}

    local title = UI.FontString(panel, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", UI.PAD, -16)
    title:SetText(spec.title or spec.name)
    local contentTop = -48
    if spec.description then
        local description = UI.FontString(panel, "GameFontHighlightSmall", "muted")
        description:SetPoint("TOPLEFT", UI.PAD, -42)
        description:SetWidth(UI.CONTENT_WIDTH)
        description:SetJustifyH("LEFT")
        description:SetText(spec.description)
        contentTop = -68
    end

    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", 0, contentTop)
    scroll:SetPoint("BOTTOMRIGHT", -16, 10)
    local bar = CreateFrame("Slider", nil, panel)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(6)
    bar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -7, contentTop)
    bar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -7, 10)
    T.Fill(bar:CreateTexture(nil, "BACKGROUND"), "rail"):SetAllPoints()
    local thumb = T.Fill(bar:CreateTexture(nil, "ARTWORK"), "selected")
    thumb:SetSize(6, 28)
    if bar.SetThumbTexture then bar:SetThumbTexture(thumb) end

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(UI.CONTENT_WIDTH + 20, 1)
    scroll:SetScrollChild(content)
    content.hcRefresh = panel.hcRefresh
    content.hcHeaderOwner = panel

    local syncing = false
    local function updateBar()
        local range = math.max(1, scroll:GetVerticalScrollRange() or 0)
        bar:SetMinMaxValues(0, range)
        syncing = true
        bar:SetValue(math.min(range, scroll:GetVerticalScroll() or 0))
        syncing = false
    end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 40)))
    end)
    scroll:SetScript("OnVerticalScroll", updateBar)
    bar:SetScript("OnValueChanged", function(_, value)
        if syncing then return end
        scroll:SetVerticalScroll(math.max(0, math.min(scroll:GetVerticalScrollRange() or 0, value)))
    end)

    panel.hcRefreshAll = function()
        if panel.hcRefreshing then return end
        panel.hcRefreshing = true
        for _, fn in ipairs(panel.hcRefresh) do fn() end
        panel.hcRefreshing = false
    end
    content.hcRefreshAll = panel.hcRefreshAll
    -- A fixed area above the scrolling content, for a live preview that must
    -- stay in view while the settings below it scroll.
    content.hcCreatePinned = function(height, width)
        height = math.max(1, height or 1)
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", 0, contentTop - height)
        scroll:SetPoint("BOTTOMRIGHT", -16, 10)
        bar:ClearAllPoints()
        bar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -7, contentTop - height)
        bar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -7, 10)
        local pinned = CreateFrame("Frame", nil, panel)
        pinned:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, contentTop)
        pinned:SetSize(width or UI.CONTENT_WIDTH + 20, height)
        pinned.hcRefresh = panel.hcRefresh
        pinned.hcRefreshAll = panel.hcRefreshAll
        pinned.hcHeaderOwner = panel
        return pinned
    end
    -- Pages that relayout their own rows report their new bottom here.
    content.hcSetBottom = function(bottom)
        content:SetHeight(math.max(1, -(bottom or -1) + 16))
        updateBar()
    end

    content.hcSetBottom(spec.build(content, -8) or -600)
    panel:SetScript("OnShow", function(self)
        self.hcRefreshAll()
        updateBar()
    end)
    return panel
end

local function errorPage(spec, host, err)
    local page = CreateFrame("Frame", nil, host)
    page:SetAllPoints(host)
    page:Hide()
    local heading = UI.FontString(page, "GameFontNormalLarge", "danger")
    heading:SetPoint("TOPLEFT", UI.PAD, -16)
    heading:SetText(spec.title or spec.name)
    local message = UI.FontString(page, "GameFontHighlightSmall")
    message:SetPoint("TOPLEFT", UI.PAD, -52)
    message:SetWidth(500)
    message:SetJustifyH("LEFT")
    message:SetText("This settings page did not build.\n\n" .. tostring(err)
        .. "\n\nPlease send this text to the developer.")
    return page
end

function Settings:Create()
    if self.window then return self.window end
    local size = HC.spec.window or {}
    local state = HC.State()

    local frame = CreateFrame("Frame", HC.FrameName("SettingsFrame"), UIParent, "BackdropTemplate")
    frame:SetSize(size.width or 780, size.height or 640)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    T.Surface(frame, "outer", "edge")
    local saved = state and state.settingsPoint or { "CENTER", "CENTER", 0, 0 }
    frame:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])

    local titleBar = CreateFrame("Button", nil, frame)
    titleBar:SetPoint("TOPLEFT", 8, -6)
    titleBar:SetPoint("TOPRIGHT", -38, -6)
    titleBar:SetHeight(36)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local point, _, relativePoint, x, y = frame:GetPoint()
        HC.State().settingsPoint = { point, relativePoint, x, y }
    end)
    local icon = titleBar:CreateTexture(nil, "ARTWORK")
    icon:SetSize(26, 26)
    icon:SetPoint("LEFT", 8, 0)
    icon:SetTexture(HC.spec.icon)
    local title = UI.FontString(titleBar, "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetText(HC.name)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() frame:Hide() end)
    local version = UI.FontString(titleBar, "GameFontDisableSmall", "muted")
    version:SetPoint("RIGHT", close, "LEFT", -8, 0)
    version:SetText(tostring(HC.VERSION_TEXT))

    local rail = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    rail:SetPoint("TOPLEFT", 1, -42)
    rail:SetPoint("BOTTOMLEFT", 1, 1)
    rail:SetWidth(RAIL_WIDTH)
    T.Surface(rail, "rail")
    local railEdge = T.Fill(frame:CreateTexture(nil, "ARTWORK"), "edge")
    railEdge:SetPoint("TOPLEFT", RAIL_WIDTH + 1, -42)
    railEdge:SetPoint("BOTTOMLEFT", RAIL_WIDTH + 1, 1)
    railEdge:SetWidth(1)

    local host = CreateFrame("Frame", nil, frame)
    host:SetPoint("TOPLEFT", RAIL_WIDTH + 2, -42)
    host:SetPoint("BOTTOMRIGHT", -10, 10)
    T.Fill(host:CreateTexture(nil, "BACKGROUND"), "content"):SetAllPoints()

    self.window, self.host, self.rail = frame, host, rail
    self.order = self:Ordered()

    -- Finish the rail before building any page: a page that fails must not
    -- leave the window without navigation.
    -- The first rail heading lines up with the page title (both 16px down).
    local railY, previous = -16, nil
    self.dividers = {}
    for _, spec in ipairs(self.order) do
        if spec.group ~= previous then
            if previous then
                local divider = T.Fill(rail:CreateTexture(nil, "ARTWORK"), "edge")
                divider:SetPoint("TOPLEFT", 16, railY - 8)
                divider:SetPoint("TOPRIGHT", -16, railY - 8)
                divider:SetHeight(1)
                self.dividers[#self.dividers + 1] = divider
                railY = railY - 24
            end
            for _, group in ipairs(GROUPS) do
                if group.key == spec.group then
                    local heading = UI.FontString(rail, "GameFontDisableSmall", "muted")
                    heading:SetPoint("TOPLEFT", 16, railY)
                    heading:SetText(group.heading)
                end
            end
            railY = railY - 24
            previous = spec.group
        end
        local button = CreateFrame("Button", nil, rail)
        button:SetSize(RAIL_WIDTH, 30)
        button:SetPoint("TOPLEFT", 0, railY)
        button.Text = UI.FontString(button)
        button.Text:SetPoint("LEFT", 18, 0)
        button.Text:SetText(spec.title or spec.name)
        button.activeBg = T.Fill(button:CreateTexture(nil, "BACKGROUND"), "raised")
        button.activeBg:SetAllPoints()
        button.activeBar = T.Fill(button:CreateTexture(nil, "ARTWORK"), "accent")
        button.activeBar:SetPoint("TOPLEFT")
        button.activeBar:SetPoint("BOTTOMLEFT")
        button.activeBar:SetWidth(3)
        local name = spec.name
        button:SetScript("OnClick", function() Settings:Show(name) end)
        self.buttons[name] = button
        railY = railY - 30
    end

    -- An addon may pin one action to the foot of the rail, such as a live
    -- preview the player wants while changing settings on any page.
    -- spec.railButton = { label = string|fn, run = fn, active = fn? }
    local railButton = HC.spec.railButton
    if railButton then
        local button = UI.Button(rail, RAIL_WIDTH - 24, 24)
        button:SetPoint("BOTTOMLEFT", 12, 14)
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
        self.pages[spec.name] = page
    end

    frame:SetScript("OnShow", function() Settings:Select(Settings.selected) end)
    frame:SetScript("OnHide", function()
        if HC.spec.onSettingsHidden then HC.spec.onSettingsHidden() end
    end)
    frame:Hide()
    -- Escape closes the window like any Blizzard panel.
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = frame:GetName() end
    return frame
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

function Settings:Select(name)
    if not self.window then return end
    self:RefreshRail()
    if not (name and self.pages[name]) then name = self.order[1] and self.order[1].name end
    self.selected = name
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
    -- A reopened page re-reads values that changed while it was hidden.
    local page = self.pages[name]
    if page and page.hcRefreshAll then page.hcRefreshAll() end
end

function Settings:IsShown()
    return self.window and self.window:IsShown() or false
end

-- Open settings, optionally on a named page.
function Settings:Show(name)
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
    self:Select(self.selected)
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
