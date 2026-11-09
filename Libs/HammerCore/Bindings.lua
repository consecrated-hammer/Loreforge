local addonName, ns = ...
local HC = ns.HammerCore
local T, UI = HC.Theme, HC.UI

-- Key bindings, the same in every addon.  The page has two panes: Active
-- bindings on the left (what's bound, to which key, with a remove button)
-- and the pool on the right (everything that can be bound, as tiles grouped
-- under headings).  Clicking a tile or an active row opens the capture
-- prompt; the next key, mouse button or wheel turn binds it.

local Bindings = {}
HC.Bindings = Bindings

-- ── Key names ──────────────────────────────────────────────────────────────

local MOUSE = { LeftButton = "BUTTON1", RightButton = "BUTTON2", MiddleButton = "BUTTON3" }
local MOUSE_NAMES = { BUTTON1 = "Left click", BUTTON2 = "Right click", BUTTON3 = "Middle click" }
local IGNORED = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true, UNKNOWN = true }

-- ALT-CTRL-SHIFT- in the order WoW's own bindings use.
function Bindings.Modifiers()
    local prefix = ""
    if IsAltKeyDown and IsAltKeyDown() then prefix = prefix .. "ALT-" end
    if IsControlKeyDown and IsControlKeyDown() then prefix = prefix .. "CTRL-" end
    if IsShiftKeyDown and IsShiftKeyDown() then prefix = prefix .. "SHIFT-" end
    return prefix
end

-- A mouse button name from OnMouseDown ("LeftButton", "Button4") as a key.
function Bindings.MouseKey(button)
    local key = MOUSE[button]
    if not key then
        local number = tostring(button or ""):match("^Button(%d+)$")
        key = number and ("BUTTON" .. number) or nil
    end
    return key and (Bindings.Modifiers() .. key) or nil
end

-- A readable name: "Shift+Left click", "Ctrl+Num Pad -", "Wheel up".
function Bindings.Label(key)
    if not key or key == "" then return "Not bound" end
    local mods, base = tostring(key):match("^(.-)([^%-]+)$")
    if base == "" then mods, base = "", key end
    local name = MOUSE_NAMES[base]
    if not name then
        local number = base:match("^BUTTON(%d+)$")
        if number then
            name = "Mouse " .. number
        elseif base == "MOUSEWHEELUP" then
            name = "Wheel up"
        elseif base == "MOUSEWHEELDOWN" then
            name = "Wheel down"
        else
            name = GetBindingText and GetBindingText(base, "KEY_") or base
        end
    end
    local parts = {}
    for mod in mods:gmatch("(%u+)%-") do
        parts[#parts + 1] = mod == "CTRL" and "Ctrl" or mod:sub(1, 1) .. mod:sub(2):lower()
    end
    parts[#parts + 1] = name
    return table.concat(parts, "+")
end

-- ── The capture prompt ─────────────────────────────────────────────────────
-- A full-screen catcher takes the next input; the prompt sits above it with
-- Unbind and Cancel.  Escape cancels.

local Capture = {}
Bindings.Capture = Capture

local function buildCapture()
    if Capture.frame then return Capture.frame end
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(390)
    catcher:EnableMouse(true)
    if catcher.EnableMouseWheel then catcher:EnableMouseWheel(true) end
    if catcher.RegisterForClicks then catcher:RegisterForClicks("AnyDown") end
    local shade = catcher:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0, 0, 0, 0.35)

    local f = CreateFrame("Frame", HC.FrameName("KeyCapture"), catcher, "BackdropTemplate")
    f:SetSize(380, 150)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    f:SetFrameLevel(400)
    f:EnableMouse(true)
    T.Surface(f, "outer", "accent")
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(36, 36)
    f.icon:SetPoint("TOPLEFT", 18, -18)
    f.title = T.Font(UI.FontString(f, "GameFontHighlight", "text"), 15)
    f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 12, -2)
    f.title:SetPoint("RIGHT", -18, 0)
    f.title:SetJustifyH("LEFT")
    f.current = UI.FontString(f, "GameFontHighlightSmall", "muted")
    f.current:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -5)
    f.body = UI.FontString(f, "GameFontHighlight", "accent")
    f.body:SetPoint("TOP", 0, -72)
    f.body:SetWidth(344)
    f.error = UI.FontString(f, "GameFontHighlightSmall", "danger")
    f.error:SetPoint("TOP", f.body, "BOTTOM", 0, -6)
    f.error:SetWidth(344)
    f.unbind = UI.Button(f, 100, 24, "danger")
    f.unbind:SetPoint("BOTTOMLEFT", 18, 14)
    f.unbind:SetText("Unbind")
    f.cancel = UI.Button(f, 100, 24)
    f.cancel:SetPoint("BOTTOMRIGHT", -18, 14)
    f.cancel:SetText("Cancel")
    -- Shown when onKey refuses a key but offers to take it anyway (say, it's
    -- already bound to something else).
    f.replace = UI.Button(f, 100, 24, "primary")
    f.replace:SetPoint("BOTTOM", 0, 14)
    f.replace:SetText("Replace")
    f.replace:Hide()

    local function settle(problem, replace)
        if type(problem) == "string" then
            f.error:SetText(problem)
            f.replace.action = type(replace) == "function" and replace or nil
            f.replace:SetShown(f.replace.action ~= nil)
            return
        end
        Capture:Stop()
    end
    local function take(key)
        local spec = Capture.spec
        if not (spec and key) then return end
        settle(spec.onKey(key))
    end
    f.replace:SetScript("OnClick", function()
        local action = f.replace.action
        if action then settle(action()) end
    end)
    local function mouseDown(_, button)
        local spec = Capture.spec
        if spec and spec.inputs.mouse then take(Bindings.MouseKey(button)) end
    end
    local function mouseWheel(_, delta)
        local spec = Capture.spec
        if spec and spec.inputs.wheel then
            take(Bindings.Modifiers() .. (delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"))
        end
    end
    -- ☠ The prompt box takes the mouse too, so a click on it never reaches
    --   the catcher behind. Without these, clicking the box itself (where
    --   anyone would click) did nothing. Its buttons still handle their own.
    catcher:SetScript("OnMouseDown", mouseDown)
    catcher:SetScript("OnMouseWheel", mouseWheel)
    f:SetScript("OnMouseDown", mouseDown)
    if f.EnableMouseWheel then f:EnableMouseWheel(true) end
    f:SetScript("OnMouseWheel", mouseWheel)
    catcher:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then Capture:Stop(); return end
        local spec = Capture.spec
        if not (spec and spec.inputs.keys) or IGNORED[key] then return end
        if IsKeyPressIgnoredForBinding and IsKeyPressIgnoredForBinding(key) then return end
        take(Bindings.Modifiers() .. key)
    end)
    f.unbind:SetScript("OnClick", function()
        local spec = Capture.spec
        if spec and spec.onClear then spec.onClear() end
        Capture:Stop()
    end)
    f.cancel:SetScript("OnClick", function() Capture:Stop() end)
    catcher:Hide()
    catcher.prompt = f
    Capture.frame = catcher
    return catcher
end

-- spec = { title, icon?, current? (label), inputs = { keys, mouse, wheel },
--          onKey(key) -> error?, replace?, onClear()? }
-- onKey returns nothing to accept the key, or an error to keep the prompt
-- open.  With the error it may return a replace function, which shows a
-- Replace button that tries again (and returns nothing or another error).
function Capture:Start(spec)
    local catcher = buildCapture()
    local f = catcher.prompt
    spec.inputs = spec.inputs or { keys = true, mouse = true, wheel = true }
    self.spec = spec
    f.icon:SetTexture(spec.icon or HC.spec.icon)
    f.title:SetText("Bind " .. tostring(spec.title or ""))
    f.current:SetText(spec.current and ("Now: " .. spec.current) or "Not bound yet")
    local inputs = spec.inputs
    local what = inputs.keys and (inputs.mouse and "Press a key or click a mouse button" or "Press a key")
        or "Click a mouse button"
    f.body:SetText(what .. "\nHold Shift, Ctrl or Alt to add them. Esc cancels.")
    f.error:SetText("")
    f.replace.action = nil
    f.replace:Hide()
    f.unbind:SetShown(spec.current ~= nil and spec.onClear ~= nil)
    catcher:EnableKeyboard(true)
    if catcher.SetPropagateKeyboardInput then catcher:SetPropagateKeyboardInput(false) end
    catcher:Show()
    if catcher.Raise then catcher:Raise() end
end

function Capture:Stop()
    self.spec = nil
    local catcher = self.frame
    if not catcher then return end
    catcher:EnableKeyboard(false)
    catcher:Hide()
    if Bindings.onCaptureStopped then Bindings.onCaptureStopped() end
end

function Capture:IsActive()
    return self.spec ~= nil
end

-- ── The page ───────────────────────────────────────────────────────────────

local ROW_H, TILE_W, TILE_H, GAP = 46, 96, 84, 8

-- spec = {
--   inputs = { keys, mouse, wheel },
--   pool = function() -> { { title, items = { { id, name, icon, detail? } } } },
--   bound = function() -> { { id, name, icon, key } } in display order,
--   bind = function(item, key) -> true | false, error, replace? (a function that
--          takes the key anyway; the prompt shows Replace),
--   unbind = function(id),  clearAll = function()?,
--   label = function(key) -> text?   (defaults to Bindings.Label),
--   tooltip = function(owner, item)?,
--   empty = "Nothing bound yet. Pick something on the right.",
-- }
-- Returns the bottom y, and keeps the page's height current as it changes.
function Bindings.Page(panel, y, spec)
    local label = spec.label or Bindings.Label
    local width = UI.CONTENT_WIDTH
    local leftWidth = math.floor(width * 0.42)
    local rightWidth = width - leftWidth - 24
    local top = y - 6

    local left = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    left:SetPoint("TOPLEFT", UI.PAD, top)
    left:SetWidth(leftWidth)
    T.Surface(left, "raised", "edge")
    local right = CreateFrame("Frame", nil, panel)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 24, 0)
    right:SetWidth(rightWidth)

    local heading = T.Font(UI.FontString(left, "GameFontHighlight", "accent"), 14)
    heading:SetPoint("TOPLEFT", 14, -14)
    local hint = UI.FontString(left, "GameFontHighlightSmall", "muted")
    hint:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -4)
    hint:SetText("Click a binding to change it.")
    local clearAll
    if spec.clearAll then
        clearAll = UI.Link(left, "Clear all", function()
            HC.Dialog:Confirm({ title = "Clear all bindings", text = "Remove every binding on this page?",
                accept = "Clear all", cancel = "Keep", onAccept = function()
                    spec.clearAll()
                    panel.hcRefreshAll()
                end })
        end)
        T.Text(clearAll.Text, "danger")
        clearAll:SetScript("OnLeave", function() T.Text(clearAll.Text, "danger") end)
        clearAll:SetPoint("TOPRIGHT", -14, -16)
    end
    local empty = UI.FontString(left, "GameFontHighlightSmall", "muted")
    empty:SetPoint("TOPLEFT", 14, -58)
    empty:SetWidth(leftWidth - 28)
    empty:SetJustifyH("LEFT")
    empty:SetText(spec.empty or "Nothing bound yet. Pick something on the right.")

    local rightHeading = T.Font(UI.FontString(right, "GameFontHighlight", "accent"), 14)
    rightHeading:SetPoint("TOPLEFT", 2, -14)
    rightHeading:SetText(spec.poolTitle or "Available")
    local rightHint = UI.FontString(right, "GameFontHighlightSmall", "muted")
    rightHint:SetPoint("TOPLEFT", rightHeading, "BOTTOMLEFT", 0, -4)
    rightHint:SetText(spec.poolHint or "Click one to bind it.")

    local function capture(item, current)
        Capture:Start({
            title = item.name, icon = item.icon, inputs = spec.inputs,
            current = current and label(current) or nil,
            -- bind(item, key) -> false, problem, replace? refuses the key;
            -- replace() (same returns) takes it anyway, from the Replace button.
            onKey = function(key)
                local ok, problem, replace = spec.bind(item, key)
                if ok == false then
                    return problem or "That didn't bind.", replace and function()
                        local forced, why = replace()
                        if forced == false then return why or "That didn't bind." end
                        panel.hcRefreshAll()
                    end or nil
                end
                panel.hcRefreshAll()
            end,
            onClear = current and function()
                spec.unbind(item.id)
                panel.hcRefreshAll()
            end or nil,
        })
    end
    local function tooltip(owner, item)
        if spec.tooltip then return spec.tooltip(owner, item) end
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText(item.name, T.Unpack("accent"))
        if item.detail then GameTooltip:AddLine(item.detail, 1, 1, 1, true) end
        GameTooltip:Show()
    end

    -- Active rows, pooled.
    local rows = {}
    local function row(index)
        if rows[index] then return rows[index] end
        local r = CreateFrame("Button", nil, left, "BackdropTemplate")
        r:SetSize(leftWidth - 20, ROW_H - 4)
        T.Surface(r, "field", "edge")
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(30, 30)
        r.icon:SetPoint("LEFT", 6, 0)
        r.name = UI.FontString(r, "GameFontHighlight")
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 10, 0)
        r.name:SetJustifyH("LEFT")
        if r.name.SetWordWrap then r.name:SetWordWrap(false) end
        r.remove = CreateFrame("Button", nil, r)
        r.remove:SetSize(22, 22)
        r.remove:SetPoint("RIGHT", -8, 0)
        r.remove.Text = UI.FontString(r.remove, "GameFontHighlight", "muted")
        r.remove.Text:SetPoint("CENTER")
        r.remove.Text:SetText("x")
        r.remove:SetScript("OnEnter", function(self) T.Text(self.Text, "danger") end)
        r.remove:SetScript("OnLeave", function(self) T.Text(self.Text, "muted") end)
        r.key = UI.FontString(r, "GameFontHighlightSmall", "accent")
        r.key:SetPoint("RIGHT", r.remove, "LEFT", -8, 0)
        r.name:SetPoint("RIGHT", r.key, "LEFT", -8, 0)
        r:SetScript("OnEnter", function(self)
            self:SetBackdropColor(T.Unpack("hover"))
            if self.item then tooltip(self, self.item) end
        end)
        r:SetScript("OnLeave", function(self)
            self:SetBackdropColor(T.Unpack("field"))
            if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        end)
        rows[index] = r
        return r
    end

    -- Pool tiles and section labels, pooled.
    local tiles, labels = {}, {}
    local function tile(index)
        if tiles[index] then return tiles[index] end
        local t = CreateFrame("Button", nil, right, "BackdropTemplate")
        t:SetSize(TILE_W, TILE_H)
        T.Surface(t, "raised", "edge")
        t.icon = t:CreateTexture(nil, "ARTWORK")
        t.icon:SetSize(36, 36)
        t.icon:SetPoint("TOP", 0, -10)
        t.name = UI.FontString(t, "GameFontHighlightSmall")
        t.name:SetPoint("TOP", t.icon, "BOTTOM", 0, -5)
        t.name:SetWidth(TILE_W - 10)
        t.name:SetJustifyH("CENTER")
        if t.name.SetWordWrap then t.name:SetWordWrap(true) end
        if t.name.SetMaxLines then t.name:SetMaxLines(2) end
        t.badge = CreateFrame("Frame", nil, t, "BackdropTemplate")
        t.badge:SetPoint("TOPRIGHT", -3, -3)
        t.badge:SetHeight(14)
        T.Surface(t.badge, "field", "accent")
        t.badge.Text = UI.FontString(t.badge, "GameFontHighlightSmall", "accent")
        T.Font(t.badge.Text, 9)
        t.badge.Text:SetPoint("CENTER")
        t:SetScript("OnEnter", function(self)
            self:SetBackdropColor(T.Unpack("hover"))
            if self.item then tooltip(self, self.item) end
        end)
        t:SetScript("OnLeave", function(self)
            self:SetBackdropColor(T.Unpack("raised"))
            if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        end)
        tiles[index] = t
        return t
    end
    local function sectionLabel(index)
        if labels[index] then return labels[index] end
        local fs = UI.FontString(right, "GameFontNormalSmall", "section")
        labels[index] = fs
        return fs
    end

    local bottom
    local function layout()
        local bound = spec.bound()
        local keys = {}
        for _, entry in ipairs(bound) do keys[entry.id] = entry.key end
        heading:SetText("Active bindings (" .. #bound .. ")")
        if clearAll then clearAll:SetShown(#bound > 0) end
        empty:SetShown(#bound == 0)
        local ly = -54
        for index, entry in ipairs(bound) do
            local r = row(index)
            r.item = entry
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 10, ly)
            r.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            r.name:SetText(entry.name)
            r.key:SetText(label(entry.key))
            r:SetScript("OnClick", function() capture(entry, entry.key) end)
            r.remove:SetScript("OnClick", function()
                spec.unbind(entry.id)
                panel.hcRefreshAll()
            end)
            r:Show()
            ly = ly - ROW_H
        end
        for index = #bound + 1, #rows do rows[index]:Hide() end
        if #bound == 0 then ly = ly - 30 end
        local leftHeight = -ly + 10
        left:SetHeight(leftHeight)

        local ry, tileIndex, labelIndex = -54, 0, 0
        local perRow = math.max(1, math.floor((rightWidth + GAP) / (TILE_W + GAP)))
        for _, section in ipairs(spec.pool()) do
            labelIndex = labelIndex + 1
            local fs = sectionLabel(labelIndex)
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", 2, ry)
            fs:SetText(tostring(section.title or ""):upper())
            fs:Show()
            ry = ry - 20
            local items = section.items or {}
            if #items == 0 then
                labelIndex = labelIndex + 1
                local none = sectionLabel(labelIndex)
                none:ClearAllPoints()
                none:SetPoint("TOPLEFT", 2, ry)
                none:SetText(section.empty or "Nothing here for this character.")
                T.Text(none, "muted")
                none:Show()
                ry = ry - 26
            end
            for index, item in ipairs(items) do
                tileIndex = tileIndex + 1
                local t = tile(tileIndex)
                t.item = item
                local column = (index - 1) % perRow
                if column == 0 and index > 1 then ry = ry - TILE_H - GAP end
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", column * (TILE_W + GAP), ry)
                t.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                t.name:SetText(item.name)
                local key = keys[item.id]
                t.badge:SetShown(key ~= nil)
                if key then
                    t.badge.Text:SetText(label(key))
                    local textWidth = t.badge.Text.GetStringWidth and t.badge.Text:GetStringWidth() or 30
                    t.badge:SetWidth(math.min(TILE_W - 8, (textWidth or 30) + 8))
                end
                T.Border(t, key and "accent" or "edge")
                t:SetScript("OnClick", function() capture(item, key) end)
                t:Show()
            end
            if #items > 0 then ry = ry - TILE_H - GAP - 8 end
        end
        for index = tileIndex + 1, #tiles do tiles[index]:Hide() end
        for index = labelIndex + 1, #labels do labels[index]:Hide() end
        right:SetHeight(-ry)
        bottom = top - math.max(leftHeight, -ry) - 16
        if panel.hcSetBottom then panel.hcSetBottom(bottom) end
        return bottom
    end
    UI.OnRefresh(panel, layout)
    panel.hcBindingsLayout = layout
    return layout()
end
