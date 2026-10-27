-- A small headless stand-in for the WoW client API: enough for HammerCore
-- (and addon tests built on it) to create frames, run scripts and inspect
-- results under plain Lua 5.1.  Unknown widget methods are harmless no-ops.

local wow = { printed = {}, frames = {}, regions = {}, reloads = 0, popups = {}, sentMessages = {} }

local Widget = {}
local methods = {}

function methods:SetShown(shown) self.shown = shown and true or false end
function methods:Show() self.shown = true end
function methods:Hide()
    local was = self.shown
    self.shown = false
    if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown end
function methods:SetScript(name, fn) self.scripts[name] = fn end
function methods:GetScript(name) return self.scripts[name] end
function methods:HookScript(name, fn)
    local previous = self.scripts[name]
    self.scripts[name] = function(...)
        if previous then previous(...) end
        fn(...)
    end
end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:GetWidth() return self.width or 0 end
function methods:GetHeight() return self.height or 0 end
function methods:SetPoint(...) self.points[#self.points + 1] = { ... } end
function methods:ClearAllPoints() self.points = {} end
function methods:GetPoint() local p = self.points[1] or {}; return p[1], p[2], p[3], p[4], p[5] end
function methods:GetName() return self.name end
function methods:GetParent() return self.parent end
function methods:SetText(text) self.text = text end
function methods:GetText() return self.text end
function methods:GetStringHeight() return 12 end
function methods:GetEffectiveScale() return 1 end
function methods:GetCenter() return 0, 0 end
function methods:GetVerticalScrollRange() return 0 end
function methods:GetVerticalScroll() return 0 end
function methods:IsMouseOver() return false end
function methods:IsOwned() return false end
function methods:SetEnabled(enabled) self.enabled = enabled end
function methods:SetBackdropColor(...) self.backdropColour = { ... } end
function methods:SetBackdropBorderColor(...) self.borderColour = { ... } end
function methods:SetTextColor(...) self.textColour = { ... } end
function methods:SetColorTexture(...) self.colour = { ... } end
function methods:SetTexture(texture) self.texture = texture end
function methods:SetValue(value)
    self.value = value
    if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
end
function methods:GetValue() return self.value end
function methods:SetHighlightTexture(texture)
    self.highlight = wow.CreateTexture(self)
    self.highlight.texture = texture
end
function methods:GetHighlightTexture() return self.highlight end
function methods:CreateFontString() return wow.CreateRegion(self, "FontString") end
function methods:CreateTexture() return wow.CreateRegion(self, "Texture") end
function methods:Raise() self.raised = true end
function methods:EnableMouse(enabled) self.mouseEnabled = enabled end
function methods:SetBackdrop(backdrop) self.backdrop = backdrop end
function methods:SetNormalTexture(texture) self.normalTexture = texture end
function methods:IsMouseEnabled() return self.mouseEnabled ~= false end
function methods:SetFrameLevel(level) self.frameLevel = level end
function methods:GetFrameLevel() return self.frameLevel or 1 end
function methods:SetFrameStrata(strata) self.strata = strata end
function methods:GetFrameStrata() return self.strata or "MEDIUM" end
function methods:SetAttribute(key, value) self.attributes = self.attributes or {}; self.attributes[key] = value end
function methods:GetAttribute(key) return self.attributes and self.attributes[key] end
function methods:SetID(id) self.id = id end
function methods:GetID() return self.id or 0 end
function methods:GetScale() return 1 end
function methods:GetAlpha() return self.alpha or 1 end
function methods:SetAlpha(alpha) self.alpha = alpha end
function methods:GetNumPoints() return #self.points end
function methods:GetLeft() return 0 end
function methods:GetRight() return 0 end
function methods:GetTop() return 0 end
function methods:GetBottom() return 0 end
function methods:GetChildren() return end
function methods:GetRegions() return end
function methods:CreateAnimationGroup() return wow.CreateRegion(self, "AnimationGroup") end
function methods:CreateAnimation() return wow.CreateRegion(self, "Animation") end

-- Widget methods are capitalised; fields an addon stores are not.  Only an
-- unknown method becomes a no-op, so a missing field still reads as nil.
Widget.__index = function(object, key)
    if methods[key] then return methods[key] end
    if type(key) == "string" and key:match("^%u") then return function() end end
    return nil
end

function wow.CreateRegion(parent, kind)
    local region = setmetatable({ kind = kind, parent = parent, shown = true, scripts = {}, points = {} }, Widget)
    wow.regions[#wow.regions + 1] = region
    return region
end
wow.CreateTexture = function(parent) return wow.CreateRegion(parent, "Texture") end

function wow.CreateFrame(kind, name, parent, template)
    local frame = setmetatable({ kind = kind, name = name, parent = parent, template = template,
        shown = true, scripts = {}, points = {} }, Widget)
    wow.frames[#wow.frames + 1] = frame
    if name then _G[name] = frame end
    return frame
end

function wow.Click(frame, button)
    local handler = frame.scripts.OnClick
    assert(handler, "frame has no OnClick")
    handler(frame, button or "LeftButton")
end

function wow.Install(metadata)
    metadata = metadata or {}
    wow.printed = {}
    wow.sentMessages = {}
    wow.frames = {}
    wow.regions = {}
    CreateFrame = wow.CreateFrame
    UIParent = wow.CreateFrame("Frame", "UIParent")
    Minimap = wow.CreateFrame("Frame", "Minimap")
    Minimap:SetSize(140, 140)
    GameTooltip = wow.CreateFrame("GameTooltip", "GameTooltip")
    ChatFontNormal = {}
    SlashCmdList = {}
    UISpecialFrames = {}
    StaticPopupDialogs = {}
    StaticPopup_Show = function(key) wow.popups[#wow.popups + 1] = key end
    ReloadUI = function() wow.reloads = wow.reloads + 1 end
    GetCursorPosition = function() return 0, 0 end
    InCombatLockdown = function() return false end
    Settings, SettingsPanel, InterfaceOptions_AddCategory = nil, nil, nil
    C_AddOns = { GetAddOnMetadata = function(addon, key)
        local values = metadata[addon]
        return values and values[key] or nil
    end }
    -- WoW's global aliases for the string and table libraries.
    strmatch, strfind, strsub, strlen = string.match, string.find, string.sub, string.len
    strlower, strupper, strrep, format = string.lower, string.upper, string.rep, string.format
    gsub, strbyte, strchar = string.gsub, string.byte, string.char
    tinsert, tremove, tconcat = table.insert, table.remove, table.concat
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
        wow.printed[#wow.printed + 1] = table.concat(parts, " ")
    end
    IsInGroup = function() return false end
    C_ChatInfo = { SendChatMessage = function(message, channel)
        wow.sentMessages[#wow.sentMessages + 1] = { message = message, channel = channel }
    end }
    SendChatMessage = function() error("legacy SendChatMessage must not be used when C_ChatInfo is available") end
end

-- Loads a copy of HammerCore into a fresh addon namespace, in XML order.
function wow.LoadHammerCore(root, addonName, ns)
    ns = ns or {}
    local xml = assert(io.open(root .. "/HammerCore.xml")):read("*a")
    for file in xml:gmatch('<Script file="([^"]+)"') do
        assert(loadfile(root .. "/" .. file))(addonName, ns)
    end
    return ns
end

-- The first font string or frame showing exactly this text.
function wow.FindText(text)
    for _, region in ipairs(wow.regions) do
        if region.text == text then return region end
    end
    for _, frame in ipairs(wow.frames) do
        if frame.text == text then return frame end
    end
end

-- The first button whose label (its Text font string) reads exactly this.
function wow.FindButton(label)
    for _, frame in ipairs(wow.frames) do
        local text = rawget(frame, "Text")
        if type(text) == "table" and text.text == label then return frame end
    end
end

-- True when a region and every parent up the chain are shown.
function wow.Visible(region)
    while region do
        if region.shown == false then return false end
        region = region.parent
    end
    return true
end

-- Strips colour codes so assertions read like the chat line the player sees.
function wow.Plain(text)
    return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

function wow.LastPrint()
    return wow.Plain(wow.printed[#wow.printed] or "")
end

return wow
