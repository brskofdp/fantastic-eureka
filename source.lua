--[[===========================================================================

  MemeSenseUI - A Dear ImGui-styled UI library for Roblox script executors
  ============================================================================

  Visual style ported from the "MemeSense" DX11/C++ ImGui framework:
    - Dark theme:  sidebar (19,20,22) / active tab (24,25,28) / page (17,18,20)
    - Red accent (232,34,67), animated RGB "flow strip" on top of the menu
    - Sidebar tabs with icons + 2px accent bar, 140px sidebar, 700x620 menu
    - Section titles, 28px rows, 16px checkboxes, 4px slider bars, etc.

  HOW TO USE (in your script executor):
      local ImGui = loadstring(game:HttpGet("https://raw.githubusercontent.com/..../source.lua"))()
      local Window = ImGui:CreateWindow("My Script")
      local Tab = Window:AddTab("Main")
      Tab:AddToggle("Enable Fly", false, function(state) print("fly:", state) end)

  No HttpService needed. Runs on CoreGui (falls back to PlayerGui).
  Icons are optional image labels - if an icon fails to load the UI never
  breaks, it simply shows the tab without an icon.

============================================================================]]

local ImGui = {}

ImGui.Version = "1.0.0"

-- Icon asset IDs (free, optional). Replace with your own rbxassetid:// if
-- any of these fail to load - a broken icon is silently ignored.
ImGui.Icons = {
    Gear        = "rbxassetid://7071817",
    Settings    = "rbxassetid://7071817",
    User        = "rbxassetid://130340212",
    Keyboard    = "rbxassetid://298708055",
    Eye         = "rbxassetid://298708092",
    Wand        = "rbxassetid://298708095",
    Home        = "rbxassetid://298708098",
    Star        = "rbxassetid://298708101",
    Bolt        = "rbxassetid://298708104",
    Bag         = "rbxassetid://298708107",
}

--[[====================== 1. ENVIRONMENT SETUP ===============================
   Grab the services we need and pick a parent for the ScreenGui.
   CoreGui keeps the menu on top of everything; if the executor blocks
   CoreGui we quietly fall back to PlayerGui.                                           ]]

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local LocalPlayer      = Players.LocalPlayer

local Holder = nil
do
    local ok, gui = pcall(function() return game:GetService("CoreGui") end)
    if ok and gui then
        Holder = gui
    else
        Holder = LocalPlayer:WaitForChild("PlayerGui")
    end
end

-- task.spawn may not exist on very old clients, so provide a fallback.
local spawn = task and task.spawn or function(f) coroutine.wrap(f)() end

--[[====================== 2. THEME (MemeSense colors) =========================
   Every color used by the UI lives here. Tweak these to reskin the whole
   library, or call ImGui:SetAccent(color) at runtime.                                   ]]

ImGui.Theme = {
    Accent        = Color3.fromRGB(232, 34, 67),   -- red highlight (checkbox fill, active bar)
    WindowBg      = Color3.fromRGB(19, 20, 22),    -- main window background
    SidebarBg     = Color3.fromRGB(19, 20, 22),    -- sidebar background
    ActiveBg      = Color3.fromRGB(24, 25, 28),    -- selected sidebar tab
    HoverBg       = Color3.fromRGB(34, 35, 38),    -- hovered sidebar tab
    PageBg        = Color3.fromRGB(17, 18, 20),    -- page content background
    Line          = Color3.fromRGB(29, 30, 32),    -- separators / slider empty track
    ButtonBg      = Color3.fromRGB(39, 40, 44),    -- buttons & dropdown bodies
    ButtonHover   = Color3.fromRGB(98, 101, 110),  -- hovered button
    ButtonActive  = Color3.fromRGB(24, 25, 28),    -- pressed button
    CheckboxEmpty = Color3.fromRGB(29, 30, 34),    -- unchecked checkbox box
    SliderFill    = Color3.fromRGB(105, 112, 122), -- filled part of a slider
    PopupBg       = Color3.fromRGB(39, 40, 44),    -- dropdown list background
    PopupWinBg    = Color3.fromRGB(18, 20, 24),    -- floating popup (color picker) background
    Text          = Color3.fromRGB(255, 255, 255), -- normal text
    TextDim       = Color3.fromRGB(115, 116, 121), -- dropdown item text
    TextHover     = Color3.fromRGB(196, 198, 202), -- dropdown item hover
    TextDisabled  = Color3.fromRGB(128, 128, 128), -- unchecked toggle label / section titles
    Border        = Color3.fromRGB(43, 43, 43),    -- thin outlines
    BrandRed      = Color3.fromRGB(255, 40, 54),   -- the red "Meme" part of branding
}

-- Layout constants (mirror the C++ framework's MenuSettings).
local MENU_W, MENU_H     = 700, 620
local SIDEBAR_W          = 140
local FLOW_H             = 3            -- animated strip height
local HEAD_H             = 55           -- page "menu bar" height
local HEAD_LINE          = 2            -- separator under the head
local BODY_X             = 28           -- page content left margin
local BODY_RIGHT_MARGIN  = 24
local COL_W              = 240          -- widget column width
local COL_STEP           = COL_W + 28   -- gap between columns
local ROW_H              = 28           -- standard row height
local SLIDER_ROW_H       = 32
local COMBO_W            = 100
local BRAND_X, BRAND_Y   = 20, 20
local SIDEBAR_BTN_Y      = 60           -- first sidebar button Y
local FONT_SIZE          = 14
local TITLE_SIZE         = 24

--[[====================== 3. SMALL HELPERS ====================================
   Instance factory, font helper (Gotham = closest free match to Rubik,
   with SourceSans fallback), math + color utilities.                                 ]]

local function New(className, props, parent)
    local obj = Instance.new(className)
    if props then
        for k, v in pairs(props) do obj[k] = v end
    end
    obj.Parent = parent or Holder
    return obj
end

local function applyFont(obj, size, bold)
    -- FontFace is the modern way; fall back to the legacy Font property if
    -- the executor's client is too old to support it.
    local ok = pcall(function()
        obj.FontFace = Font.new(Enum.Font[bold and "GothamBold" or "GothamSemibold"])
    end)
    if not ok then
        pcall(function() obj.Font = Enum.Font[bold and "GothamBold" or "GothamSemibold"] end)
    end
    obj.TextSize = size or FONT_SIZE
end

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end
local function round(v) return math.floor(v + 0.5) end

local function rgbToHsv(r, g, b)
    local maxC, minC = math.max(r, g, b), math.min(r, g, b)
    local d = maxC - minC
    local h
    if d == 0 then h = 0
    elseif maxC == r then h = ((g - b) / d) % 6
    elseif maxC == g then h = ((b - r) / d) + 2
    else h = ((r - g) / d) + 4 end
    h = h / 6
    local s = maxC == 0 and 0 or (d / maxC)
    return h, s, maxC
end

local function hsvToRgb(h, s, v)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then return v, t, p
    elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v
    else return v, p, q end
end

local function tween(obj, props, dur, cb)
    -- Animate with TweenService, or just snap if tweens are unavailable.
    if TweenService then
        local tw = TweenService:Create(obj, TweenInfo.new(dur or 0.2), props)
        tw:Play()
        if cb then tw.Completed:Connect(cb) end
        return tw
    else
        for k, v in pairs(props) do obj[k] = v end
        if cb then task.delay(dur or 0.2, cb) end
    end
end

local function makeImage(assetId, size, color)
    local img = New("ImageLabel", {
        Size          = UDim2.fromOffset(size, size),
        BackgroundTransparency = 1,
        ImageColor3   = color or Color3.new(1, 1, 1),
    })
    -- A bad / missing asset must never crash the UI.
    pcall(function() img.Image = assetId end)
    return img
end

--[[====================== 4. SHAPE PRIMITIVES =================================
   Checkmarks and triangles drawn with plain Frames + rotations so the UI
   never depends on fonts or images having special glyphs available.                  ]]

-- White checkmark made of two rotated bars inside a 16px box.
local function addCheckMark(parent, boxSize)
    boxSize = boxSize or 16
    local A = Vector2.new(0.22 * boxSize, 0.54 * boxSize)
    local B = Vector2.new(0.42 * boxSize, 0.74 * boxSize)
    local C = Vector2.new(0.78 * boxSize, 0.30 * boxSize)
    local function seg(p1, p2)
        local mid = (p1 + p2) / 2
        local len = (p2 - p1).Magnitude
        local rot = math.deg(math.atan2(p2.Y - p1.Y, p2.X - p1.X))
        return New("Frame", {
            Size = UDim2.fromOffset(len, 2.6),
            Position = UDim2.fromOffset(mid.X, mid.Y),
            AnchorPoint = Vector2.new(0.5, 0.5),
            Rotation = rot,
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
            ZIndex = 4,
        }, parent)
    end
    return { seg(A, B), seg(B, C) }
end

-- Solid triangle: a 45 degree rotated square with its top/left half masked
-- by a rectangle painted in the background color of the host widget.
local function makeTriangle(parent, cx, cy, size, color, direction, maskColor)
    size = size or 7
    local diamond = New("Frame", {
        Size = UDim2.fromOffset(size, size),
        Position = UDim2.fromOffset(cx, cy),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Rotation = 45,
        BackgroundColor3 = color,
        BorderSizePixel = 0,
    }, parent)
    local mask
    if direction == "up" or direction == "down" then
        mask = New("Frame", {
            Size = UDim2.fromOffset(size, size / 2),
            Position = UDim2.fromOffset(cx, cy + (direction == "down" and -size / 4 or size / 4)),
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = maskColor,
            BorderSizePixel = 0,
            ZIndex = diamond.ZIndex + 1,
        }, parent)
    else
        mask = New("Frame", {
            Size = UDim2.fromOffset(size / 2, size),
            Position = UDim2.fromOffset(cx + (direction == "right" and -size / 4 or size / 4), cy),
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = maskColor,
            BorderSizePixel = 0,
            ZIndex = diamond.ZIndex + 1,
        }, parent)
    end
    return diamond
end

--[[====================== 5. TOOLTIPS =========================================
   A small dark label that follows the mouse while hovering a widget that
   was given a tooltip string (the last optional argument of any Add* call,
   or widget:SetTooltip("...")).                                                        ]]

local Tooltip = {}
do
    local frame, label, currentBtn

    local function hide()
        if frame then frame.Visible = false end
        currentBtn = nil
    end

    function Tooltip.Show(text, btn)
        if currentBtn and currentBtn ~= btn then hide() end
        if currentBtn == btn then return end
        if not frame then
            frame = New("Frame", {
                BackgroundColor3 = ImGui.Theme.PopupWinBg,
                BorderColor3 = ImGui.Theme.Border,
                BorderSizePixel = 1,
                Visible = false,
                ZIndex = 30,
            })
            label = New("TextLabel", {
                BackgroundTransparency = 1,
                TextColor3 = Color3.new(1, 1, 1),
                TextWrapped = false,
                Size = UDim2.new(1, -12, 1, -8),
                Position = UDim2.fromOffset(6, 4),
                ZIndex = 31,
            }, frame)
            applyFont(label, 13)
        end
        currentBtn = btn
        label.Text = text
        local tb = label.TextBounds
        frame.Size = UDim2.fromOffset(clamp(tb.X + 16, 30, 320), tb.Y + 10)
        frame.Visible = true
        -- position it next to the mouse (flip if it would leave the screen)
        local mouse = UserInputService:GetMouseLocation()
        local fx = mouse.X + 16
        local fy = mouse.Y + 18
        local gs = frame.AbsoluteSize
        if fx + gs.X > game:GetService("GuiService"):GetScreenResolution().X - 4 then fx = mouse.X - gs.X - 12 end
        if fy + gs.Y > game:GetService("GuiService"):GetScreenResolution().Y - 4 then fy = mouse.Y - gs.Y - 6 end
        frame.Position = UDim2.fromOffset(fx, fy)
    end

    function Tooltip.Hide() hide() end

    UserInputService.InputChanged:Connect(function(input)
        if frame and frame.Visible and input.UserInputType == Enum.UserInputType.MouseMovement then
            local mouse = UserInputService:GetMouseLocation()
            local gs = frame.AbsoluteSize
            local fx = mouse.X + 16
            local fy = mouse.Y + 18
            local res = game:GetService("GuiService"):GetScreenResolution()
            if fx + gs.X > res.X - 4 then fx = mouse.X - gs.X - 12 end
            if fy + gs.Y > res.Y - 4 then fy = mouse.Y - gs.Y - 6 end
            frame.Position = UDim2.fromOffset(fx, fy)
        end
    end)
end

-- attach a tooltip to an interactive button if a tooltip string was given
local function setTooltip(btn, text)
    if not text then return end
    btn.MouseEnter:Connect(function() Tooltip.Show(text, btn) end)
    btn.MouseLeave:Connect(function() Tooltip.Hide() end)
end

--[[====================== 6. POPUP MANAGER ====================================
   Dropdowns and the color picker open "popup" frames. Only one popup can be
   open at a time; clicking anywhere outside it (or pressing Esc) closes it.          ]]

local Popup = { current = nil }
do
    local function close()
        if Popup.current then
            local p = Popup.current
            Popup.current = nil
            p:Close()
        end
    end

    function Popup.Open(p)
        close()
        Popup.current = p
        p.frame.Visible = true
        p.frame.ZIndex = 20
    end

    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if Popup.current then
            local t = input.InputType == Enum.UserInputType.Keyboard
                and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.LeftAlt)
            if t then close() return end
        end
        if Popup.current and (input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.MouseButton2) then
            local target = input.Target
            local p = Popup.current
            -- don't close if the click landed on the trigger button or inside the popup
            if target == p.trigger or (target and p.frame:IsAncestorOf(target)) then return end
            close()
        end
    end)
end

--[[====================== 7. LAYOUT BOX =======================================
   Every column/section owns a LayoutBox: it stacks rows from top to bottom
   and can re-flow them when a collapsible section expands or collapses.            ]]

local LayoutBox = {}
LayoutBox.__index = LayoutBox

function LayoutBox.new(frame, width, onHeight)
    return setmetatable({
        frame = frame, width = width, rows = {}, onHeight = onHeight,
    }, LayoutBox)
end

function LayoutBox:AddRow(h)
    local f = New("Frame", {
        Size = UDim2.fromOffset(self.width, h),
        BackgroundTransparency = 1,
    }, self.frame)
    local row = { f = f, h = h, on = function() return true end }
    self.rows[#self.rows + 1] = row
    self:Relayout()
    return row
end

function LayoutBox:Relayout()
    local y = 0
    for _, r in ipairs(self.rows) do
        local visible = r.on()
        r.f.Visible = visible
        if visible then
            r.f.Position = UDim2.fromOffset(0, y)
            y = y + r.h
        end
    end
    self.frame.Size = UDim2.fromOffset(self.width, y)
    if self.onHeight then self.onHeight(y) end
end

--[[====================== 8. WIDGET HOST ======================================
   Tabs, Columns and Sections all share the same Add* API. A "host" simply
   owns a LayoutBox plus a reference to the window (for popups/notifications).       ]]

local WidgetHost = {}
WidgetHost.__index = WidgetHost

-- Returns the LayoutBox a widget should be placed in.
local function boxOf(self) return self.box end

-- Buttons -------------------------------------------------------------------
function WidgetHost:AddButton(text, callback, tooltip)
    local box = boxOf(self)
    local row = box:AddRow(ROW_H)
    local btn = New("TextButton", {
        Size = UDim2.new(1, 0, 0, ROW_H - 4),
        Position = UDim2.fromOffset(0, 2),
        BackgroundColor3 = ImGui.Theme.ButtonBg,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
    }, row.f)
    local corner = New("UICorner", { CornerRadius = UDim.new(0, 3) }, btn)
    local lbl = New("TextLabel", {
        BackgroundTransparency = 1,
        TextColor3 = Color3.new(1, 1, 1),
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(1, -16, 1, 0),
        Position = UDim2.fromOffset(8, 0),
        Text = text,
    }, btn)
    applyFont(lbl, FONT_SIZE)
    -- hover / press colors, just like the C++ framework
    btn.MouseEnter:Connect(function() btn.BackgroundColor3 = ImGui.Theme.ButtonHover end)
    btn.MouseLeave:Connect(function() btn.BackgroundColor3 = ImGui.Theme.ButtonBg end)
    btn.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then btn.BackgroundColor3 = ImGui.Theme.ButtonActive end
    end)
    btn.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then btn.BackgroundColor3 = ImGui.Theme.ButtonHover end
    end)
    btn.MouseButton1Click:Connect(function()
        if callback then callback() end
    end)
    setTooltip(btn, tooltip)
    return { SetTooltip = function(_, t) setTooltip(btn, t) end }
end

-- Toggles / checkboxes ------------------------------------------------------
function WidgetHost:AddToggle(text, default, callback, tooltip)
    local box = boxOf(self)
    local row = box:AddRow(ROW_H)
    local btn = New("TextButton", {
        Size = UDim2.new(1, 0, 0, ROW_H),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
    }, row.f)
    local state = default and true or false

    local boxFrame = New("Frame", {
        Size = UDim2.fromOffset(16, 16),
        Position = UDim2.fromOffset(0, (ROW_H - 16) / 2),
        BackgroundColor3 = state and ImGui.Theme.Accent or ImGui.Theme.CheckboxEmpty,
        BorderSizePixel = 0,
        ZIndex = 2,
    }, btn)
    New("UICorner", { CornerRadius = UDim.new(0, 3) }, boxFrame)

    local marks = {}
    local lbl
    local function refresh()
        boxFrame.BackgroundColor3 = state and ImGui.Theme.Accent or ImGui.Theme.CheckboxEmpty
        lbl.TextColor3 = state and ImGui.Theme.Text or ImGui.Theme.TextDisabled
        for _, m in ipairs(marks) do m.Visible = state end
    end
    marks = state and addCheckMark(boxFrame, 16) or { nil, nil }
    for _, m in ipairs(marks) do if m then m.Visible = state end end

    lbl = New("TextLabel", {
        BackgroundTransparency = 1,
        TextColor3 = state and ImGui.Theme.Text or ImGui.Theme.TextDisabled,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = text,
        Size = UDim2.fromOffset(box.width - 25, ROW_H),
        Position = UDim2.fromOffset(25, 0),
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, btn)
    applyFont(lbl, FONT_SIZE)

    btn.MouseButton1Click:Connect(function()
        state = not state
        refresh()
        if callback then callback(state) end
    end)
    setTooltip(btn, tooltip)

    return {
        SetTooltip = function(_, t) setTooltip(btn, t) end,
        GetValue = function() return state end,
        SetValue = function(_, v, silent)
            state = v and true or false
            refresh()
            if callback and not silent then callback(state) end
        end,
    }
end

-- Sliders -------------------------------------------------------------------
function WidgetHost:AddSlider(text, min, max, default, callback, opts)
    local box = boxOf(self)
    opts = opts or {}
    if max <= min then max = min + 1 end
    local precision = opts.Precision
    if precision == nil then precision = (round(min) == min and round(max) == max) and 0 or 2 end
    local suffix = opts.Suffix or ""
    local value = clamp(default or min, min, max)

    local row = box:AddRow(SLIDER_ROW_H)
    local lbl = New("TextLabel", {
        BackgroundTransparency = 1,
        TextColor3 = ImGui.Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = text,
        Size = UDim2.fromOffset(box.width - 110, 17),
    }, row.f)
    applyFont(lbl, FONT_SIZE)

    local valueLbl = New("TextLabel", {
        BackgroundTransparency = 1,
        TextColor3 = ImGui.Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Right,
        Size = UDim2.fromOffset(110, 17),
        Position = UDim2.fromOffset(box.width - 110, 0),
    }, row.f)
    applyFont(valueLbl, FONT_SIZE)

    local function fmt(v)
        if precision == 0 then return tostring(round(v)) .. suffix end
        return string.format("%." .. precision .. "f", v) .. suffix
    end

    -- the bar track (4px tall, rounded) and its filled part
    local barY = 21
    local bar = New("Frame", {
        Size = UDim2.fromOffset(box.width, 4),
        Position = UDim2.fromOffset(0, barY),
        BackgroundColor3 = ImGui.Theme.CheckboxEmpty,
        BorderSizePixel = 0,
    }, row.f)
    New("UICorner", { CornerRadius = UDim.new(0, 3) }, bar)
    local fill = New("Frame", {
        Size = UDim2.fromOffset(0, 4),
        BackgroundColor3 = ImGui.Theme.SliderFill,
        BorderSizePixel = 0,
        ZIndex = 2,
    }, bar)
    New("UICorner", { CornerRadius = UDim.new(0, 3) }, fill)

    local hit = New("TextButton", {
        Size = UDim2.fromOffset(box.width, 14),
        Position = UDim2.fromOffset(0, barY - 3),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 3,
    }, row.f)

    local dragging = false
    local function updateFromMouse()
        local mx = UserInputService:GetMouseLocation().X
        local left = bar.AbsolutePosition.X
        local ratio = clamp((mx - left) / box.width, 0, 1)
        local newVal = min + (max - min) * ratio
        if precision == 0 then newVal = round(newVal) end
        if newVal ~= value then
            value = newVal
            fill.Size = UDim2.fromOffset(round(ratio * box.width), 4)
            valueLbl.Text = fmt(value)
            if callback then callback(value) end
        end
    end

    hit.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            updateFromMouse()
        end
    end)
    -- track the mouse globally while dragging, so a fast drag never loses
    -- the slider even if the cursor leaves the 14px hit area
    local moveConn = UserInputService.InputChanged:Connect(function(i)
        if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then updateFromMouse() end
    end)
    local dragEndConn = UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
    setTooltip(hit, tooltip)

    -- initial paint
    local ratio = (value - min) / (max - min)
    fill.Size = UDim2.fromOffset(round(ratio * box.width), 4)
    valueLbl.Text = fmt(value)

    return {
        SetTooltip = function(_, t) setTooltip(hit, t) end,
        GetValue = function() return value end,
        SetValue = function(_, v, silent)
            value = clamp(v, min, max)
            local r = (value - min) / (max - min)
            fill.Size = UDim2.fromOffset(round(r * box.width), 4)
            valueLbl.Text = fmt(value)
            if callback and not silent then callback(value) end
        end,
        moveConn = moveConn, dragEndConn = dragEndConn,
    }
end

-- Dropdowns / combos --------------------------------------------------------
function WidgetHost:AddDropdown(text, options, defaultIndex, callback, tooltip)
    local box = boxOf(self)
    if type(options) ~= "table" then options = { options } end
    local index = clamp(defaultIndex or 1, 1, #options)
    local row = box:AddRow(ROW_H)

    local lbl
    if text and text ~= "" then
        lbl = New("TextLabel", {
            BackgroundTransparency = 1,
            TextColor3 = ImGui.Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = text,
            Size = UDim2.fromOffset(box.width - COMBO_W - 12, ROW_H),
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, row.f)
        applyFont(lbl, FONT_SIZE)
    end

    local btn = New("TextButton", {
        Size = UDim2.fromOffset(COMBO_W, ROW_H - 4),
        Position = UDim2.fromOffset(box.width - COMBO_W, 2),
        BackgroundColor3 = ImGui.Theme.ButtonBg,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
    }, row.f)
    New("UICorner", { CornerRadius = UDim.new(0, 3) }, btn)

    local preview = New("TextLabel", {
        BackgroundTransparency = 1,
        TextColor3 = ImGui.Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(1, -22, 1, 0),
        Position = UDim2.fromOffset(8, 0),
    }, btn)
    applyFont(preview, FONT_SIZE)

    local arrow = makeTriangle(btn, COMBO_W - 11, ROW_H / 2 - 2, 7, ImGui.Theme.TextDim, "down", ImGui.Theme.ButtonBg)

    -- the popup list (rendered above everything, parented to the window gui)
    local popupFrame = New("Frame", {
        BackgroundColor3 = ImGui.Theme.PopupBg,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 20,
    }, self.window.gui)
    New("UICorner", { CornerRadius = UDim.new(0, 3) }, popupFrame)
    local pad = New("UIPadding", { PaddingTop = UDim.new(0, 8) }, popupFrame)

    local items = {}
    for i, name in ipairs(options) do
        local item = New("TextButton", {
            Size = UDim2.new(1, 0, 0, 22),
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 21,
        }, popupFrame)
        local it = New("TextLabel", {
            BackgroundTransparency = 1,
            TextXAlignment = Enum.TextXAlignment.Left,
            Size = UDim2.new(1, -16, 1, 0),
            Position = UDim2.fromOffset(8, 0),
        }, item)
        applyFont(it, FONT_SIZE)
        local hovered = false
        local function paint()
            it.TextColor3 = (i == index) and ImGui.Theme.Text
                or (hovered and ImGui.Theme.TextHover or ImGui.Theme.TextDim)
        end
        item.MouseEnter:Connect(function() hovered = true paint() end)
        item.MouseLeave:Connect(function() hovered = false paint() end)
        item.MouseButton1Click:Connect(function()
            index = i
            preview.Text = options[index]
            paint()
            Popup.current = nil
            popupFrame.Visible = false
            if callback then callback(index, options[index]) end
        end)
        items[i] = item
    end

    popupFrame.Size = UDim2.fromOffset(COMBO_W, 8 + #options * 22)

    local open = false
    local function positionPopup()
        popupFrame.Position = UDim2.fromOffset(btn.AbsolutePosition.X - self.window.gui.AbsolutePosition.X,
            btn.AbsolutePosition.Y - self.window.gui.AbsolutePosition.Y + btn.AbsoluteSize.Y - 3)
    end
    btn.MouseButton1Click:Connect(function()
        open = not open
        if open then
            positionPopup()
            Popup.Open({ frame = popupFrame, trigger = btn, Close = function() popupFrame.Visible = false end })
        else
            Popup.current = nil
            popupFrame.Visible = false
        end
    end)
    setTooltip(btn, tooltip)

    preview.Text = options[index]
    local handle = {
        SetTooltip = function(_, t) setTooltip(btn, t) end,
        GetValue = function() return index end,
        SetValue = function(_, v, silent)
            index = clamp(v, 1, #options)
            preview.Text = options[index]
            for i, item in ipairs(items) do
                local it = item:FindFirstChildOfClass("TextLabel")
                if it then it.TextColor3 = (i == index) and ImGui.Theme.Text or ImGui.Theme.TextDim end
            end
            if callback and not silent then callback(index, options[index]) end
        end,
        GetOptions = function() return options end,
    }
    return handle
end

-- Textboxes ----------------------------------------------------------------
function WidgetHost:AddTextbox(text, default, callback, tooltip, placeholder)
    local box = boxOf(self)
    local row = box:AddRow(ROW_H)
    local lbl
    local boxW = box.width
    if text and text ~= "" then
        lbl = New("TextLabel", {
            BackgroundTransparency = 1,
            TextColor3 = ImGui.Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = text,
            Size = UDim2.fromOffset(math.min(boxW * 0.45, boxW - 160), ROW_H),
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, row.f)
        applyFont(lbl, FONT_SIZE)
    end
    local tb = New("TextBox", {
        Size = UDim2.fromOffset(150, ROW_H - 4),
        Position = UDim2.fromOffset(boxW - 150, 2),
        BackgroundColor3 = ImGui.Theme.ButtonBg,
        BorderSizePixel = 0,
        Text = default or "",
        TextColor3 = Color3.new(1, 1, 1),
        PlaceholderText = placeholder or "",
        PlaceholderColor3 = ImGui.Theme.TextDisabled,
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row.f)
    New("UICorner", { CornerRadius = UDim.new(0, 3) }, tb)
    New("UIPadding", { PaddingLeft = UDim.new(0, 8) }, tb)
    applyFont(tb, FONT_SIZE)
    tb.FocusLost:Connect(function(enter)
        if callback then callback(tb.Text, enter) end
    end)
    setTooltip(tb, tooltip)
    return {
        SetTooltip = function(_, t) setTooltip(tb, t) end,
        GetValue = function() return tb.Text end,
        SetValue = function(_, v, silent)
            tb.Text = tostring(v)
            if callback and not silent then callback(tb.Text, false) end
        end,
    }
end

-- Keybinds ------------------------------------------------------------------
function WidgetHost:AddKeybind(text, defaultKey, callback, tooltip)
    local box = boxOf(self)
    local row = box:AddRow(ROW_H)

    -- accept Enum.KeyCode, Enum.UserInputType or a string like "RightShift"
    local key = nil
    if defaultKey then
        if type(defaultKey) == "string" then
            key = Enum.KeyCode[defaultKey] or Enum.UserInputType[defaultKey]
        else
            key = defaultKey
        end
    end

    local lbl
    if text and text ~= "" then
        lbl = New("TextLabel", {
            BackgroundTransparency = 1,
            TextColor3 = ImGui.Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = text,
            Size = UDim2.fromOffset(box.width - COMBO_W - 12, ROW_H),
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, row.f)
        applyFont(lbl, FONT_SIZE)
    end

    local btn = New("TextButton", {
        Size = UDim2.fromOffset(COMBO_W, ROW_H - 4),
        Position = UDim2.fromOffset(box.width - COMBO_W, 2),
        BackgroundColor3 = ImGui.Theme.ButtonBg,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
    }, row.f)
    New("UICorner", { CornerRadius = UDim.new(0, 3) }, btn)
    local cap = New("TextLabel", {
        BackgroundTransparency = 1,
        TextColor3 = Color3.new(1, 1, 1),
        Size = UDim2.new(1, 0, 1, 0),
    }, btn)
    applyFont(cap, FONT_SIZE)

    local capturing = false
    local function keyName(k)
        if not k then return "Not bound" end
        local s = tostring(k)
        return s:match("^Enum%.%w+%.(.+)$") or s
    end
    local function paint()
        cap.Text = capturing and "..." or keyName(key)
        btn.BackgroundColor3 = capturing and ImGui.Theme.Accent or ImGui.Theme.ButtonBg
    end

    local captureConn = nil
    local function stopCapturing()
        if captureConn then captureConn:Disconnect() captureConn = nil end
        capturing = false
        paint()
    end

    btn.MouseButton1Click:Connect(function()
        if capturing then stopCapturing() return end
        capturing = true
        paint()
        captureConn = UserInputService.InputBegan:Connect(function(input, gpe)
            if gpe then return end
            -- clicking the keybind button itself should cancel, not rebind
            local t = input.Target
            if t and (t == btn or btn:IsAncestorOf(t)) then
                stopCapturing()
                return
            end
            local kc = input.KeyCode
            if kc ~= Enum.KeyCode.Unknown and kc ~= Enum.KeyCode.Escape then
                key = kc
                stopCapturing()
                if callback then callback(key) end
            elseif input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.MouseButton2 then
                key = input.UserInputType
                stopCapturing()
                if callback then callback(key) end
            elseif kc == Enum.KeyCode.Escape then
                stopCapturing()
            end
        end)
    end)
    -- right click clears the bind
    btn.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton2 and not capturing then
            key = nil
            paint()
            if callback then callback(nil) end
        end
    end)
    setTooltip(btn, tooltip)
    paint()

    return {
        SetTooltip = function(_, t) setTooltip(btn, t) end,
        GetValue = function() return key end,
        SetValue = function(_, k, silent)
            key = k
            paint()
            if callback and not silent then callback(key) end
        end,
        stopCapturing = stopCapturing,
    }
end

-- Color pickers -------------------------------------------------------------
function WidgetHost:AddColorPicker(text, defaultColor, callback, tooltip)
    local box = boxOf(self)
    local row = box:AddRow(ROW_H)
    local enabled = true
    local color = defaultColor or Color3.new(1, 0, 0)

    local lbl
    if text and text ~= "" then
        lbl = New("TextLabel", {
            BackgroundTransparency = 1,
            TextColor3 = ImGui.Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = text,
            Size = UDim2.fromOffset(box.width - 40, ROW_H),
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, row.f)
        applyFont(lbl, FONT_SIZE)
    end

    local swatch = New("TextButton", {
        Size = UDim2.fromOffset(16, 16),
        Position = UDim2.fromOffset(box.width - 18, (ROW_H - 16) / 2),
        BackgroundColor3 = color,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 2,
    }, row.f)
    New("UICorner", { CornerRadius = UDim.new(0, 3) }, swatch)

    local function paint()
        swatch.BackgroundColor3 = enabled and color or ImGui.Theme.CheckboxEmpty
    end
    paint()

    -- ---- the popup picker window --------------------------------------
    local popupFrame = New("Frame", {
        BackgroundColor3 = ImGui.Theme.PopupWinBg,
        BorderColor3 = ImGui.Theme.Border,
        BorderSizePixel = 1,
        Visible = false,
        ZIndex = 20,
    }, self.window.gui)
    New("UICorner", { CornerRadius = UDim.new(0, 3) }, popupFrame)
    New("UIPadding", {
        PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12),
        PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
    }, popupFrame)

    local h, s, v = rgbToHsv(color.R, color.G, color.B)

    -- saturation/value square: base = hue color, white gradient = S, black = V
    local sv = New("Frame", {
        Size = UDim2.fromOffset(120, 120),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderColor3 = ImGui.Theme.Border,
        BorderSizePixel = 1,
    }, popupFrame)
    local svBase = New("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = color, BorderSizePixel = 0 }, sv)
    local svS = New("ImageLabel", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Image = "",
    }, sv)
    local g1 = Instance.new("UIGradient")
    g1.Rotation = 90
    g1.Color = ColorSequence.new(Color3.new(1, 1, 1))
    g1.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
    g1.Parent = svS
    local svV = New("ImageLabel", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Image = "",
    }, sv)
    local g2 = Instance.new("UIGradient")
    g2.Color = ColorSequence.new(Color3.new(0, 0, 0))
    g2.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
    g2.Parent = svV

    local svMarker = New("Frame", {
        Size = UDim2.fromOffset(10, 10),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        BorderColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 2,
        ZIndex = 5,
    }, sv)

    -- hue bar: 7 stacked color segments (red -> yellow -> ... -> red)
    local hueBar = New("Frame", {
        Size = UDim2.fromOffset(14, 120),
        Position = UDim2.fromOffset(132, 0),
        BackgroundTransparency = 1,
    }, popupFrame)
    local hues = {
        Color3.fromRGB(255, 0, 0), Color3.fromRGB(255, 255, 0), Color3.fromRGB(0, 255, 0),
        Color3.fromRGB(0, 255, 255), Color3.fromRGB(0, 0, 255), Color3.fromRGB(255, 0, 255),
        Color3.fromRGB(255, 0, 0),
    }
    local hueSegs = {}
    for i, c in ipairs(hues) do
        local seg = New("Frame", {
            Size = UDim2.new(1, 0, 0, 120 / (#hues - 1)),
            Position = UDim2.fromOffset(0, (i - 1) * 20),
            BackgroundColor3 = c,
            BorderSizePixel = 0,
        }, hueBar)
        hueSegs[i] = seg
    end
    local hueMarker = New("Frame", {
        Size = UDim2.fromOffset(18, 3),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromOffset(7, 0),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        ZIndex = 5,
    }, hueBar)

    local rgbLabel = New("TextLabel", {
        BackgroundTransparency = 1,
        TextColor3 = ImGui.Theme.TextDim,
        Size = UDim2.new(0, 120, 0, 16),
        Position = UDim2.fromOffset(0, 128),
        Text = "",
    }, popupFrame)
    applyFont(rgbLabel, 12)

    popupFrame.Size = UDim2.fromOffset(120 + 14 + 24, 128 + 16 + 24)

    local dragging = nil -- "sv" or "hue"
    local function refresh()
        color = Color3.fromHSV(h, s, v)
        svBase.BackgroundColor3 = color
        svMarker.Position = UDim2.fromScale(s, 1 - v)
        hueMarker.Position = UDim2.fromOffset(7, h * 120)
        rgbLabel.Text = string.format("R %d  G %d  B %d", round(color.R * 255), round(color.G * 255), round(color.B * 255))
        paint()
    end

    local function updateFromMouse()
        local mouse = UserInputService:GetMouseLocation()
        if dragging == "sv" then
            local ap = sv.AbsolutePosition
            s = clamp((mouse.X - ap.X) / 120, 0, 1)
            v = clamp(1 - (mouse.Y - ap.Y) / 120, 0, 1)
        elseif dragging == "hue" then
            local ap = hueBar.AbsolutePosition
            h = clamp((mouse.Y - ap.Y) / 120, 0, 1)
        end
        refresh()
        if callback then callback(color, enabled) end
    end

    sv.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = "sv"
            updateFromMouse()
        end
    end)
    hueBar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = "hue"
            updateFromMouse()
        end
    end)
    local moveConn = UserInputService.InputChanged:Connect(function(i)
        if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then updateFromMouse() end
    end)
    local upConn = UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = nil end
    end)

    local popup = {
        frame = popupFrame,
        Close = function() popupFrame.Visible = false end,
    }

    -- left click toggles the feature, right click opens the picker
    swatch.MouseButton1Click:Connect(function()
        enabled = not enabled
        paint()
        if callback then callback(color, enabled) end
    end)
    swatch.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton2 then
            local sw = swatch.AbsolutePosition
            popupFrame.Position = UDim2.fromOffset(
                sw.X - self.window.gui.AbsolutePosition.X + 22,
                sw.Y - self.window.gui.AbsolutePosition.Y - 10)
            Popup.Open(popup)
        end
    end)
    setTooltip(swatch, tooltip)

    refresh()
    return {
        SetTooltip = function(_, t) setTooltip(swatch, t) end,
        GetValue = function() return { Color = color, Enabled = enabled } end,
        SetValue = function(_, v, silent)
            if type(v) == "table" and v.Color then
                color = v.Color
                enabled = v.Enabled == nil and enabled or v.Enabled
            else
                color = v
                enabled = true
            end
            h, s, v = rgbToHsv(color.R, color.G, color.B)
            refresh()
            if callback and not silent then callback(color, enabled) end
        end,
        moveConn = moveConn, upConn = upConn,
    }
end

-- Plain labels / separators / spacing --------------------------------------
function WidgetHost:AddLabel(text, dim)
    local box = boxOf(self)
    local row = box:AddRow(20)
    local lbl = New("TextLabel", {
        BackgroundTransparency = 1,
        TextColor3 = dim and ImGui.Theme.TextDisabled or ImGui.Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = text,
        Size = UDim2.new(1, 0, 1, 0),
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, row.f)
    applyFont(lbl, FONT_SIZE)
    return { SetTooltip = function(_, t) setTooltip(lbl, t) end }
end

function WidgetHost:AddSeparator()
    local box = boxOf(self)
    local row = box:AddRow(9)
    New("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        Position = UDim2.fromOffset(0, 4),
        BackgroundColor3 = ImGui.Theme.Line,
        BorderSizePixel = 0,
    }, row.f)
end

function WidgetHost:AddSpace(height)
    local box = boxOf(self)
    box:AddRow(height or 8)
end

-- Collapsible sections ------------------------------------------------------
function WidgetHost:AddSection(title, startCollapsed, tooltip)
    local box = boxOf(self)
    local expanded = not (startCollapsed and true or false)
    local section = {}

    -- header row (28px, acts like an ImGui collapsing header)
    local row = box:AddRow(ROW_H)
    local header = New("TextButton", {
        Size = UDim2.new(1, 0, 0, ROW_H),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
    }, row.f)
    local headerText = New("TextLabel", {
        BackgroundTransparency = 1,
        TextColor3 = ImGui.Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = title,
        Size = UDim2.fromOffset(box.width - 30, ROW_H),
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, header)
    applyFont(headerText, FONT_SIZE)
    local arrow = makeTriangle(header, box.width - 12, ROW_H / 2, 7, ImGui.Theme.TextDisabled,
        expanded and "down" or "right", ImGui.Theme.PageBg)

    -- content box (the section's own LayoutBox)
    local contentFrame = New("Frame", {
        Size = UDim2.fromOffset(box.width, 0),
        BackgroundTransparency = 1,
        Visible = expanded,
    }, row.f)
    local contentBox = LayoutBox.new(contentFrame, box.width, function(h)
        -- when the section's content height changes, update this row's height
        -- and re-flow the parent column
        row.h = ROW_H + (expanded and h or 0)
        box:Relayout()
    end)
    row.on = function() return true end

    header.MouseButton1Click:Connect(function()
        expanded = not expanded
        contentFrame.Visible = expanded
        arrow:Destroy()
        arrow = makeTriangle(header, box.width - 12, ROW_H / 2, 7, ImGui.Theme.TextDisabled,
            expanded and "down" or "right", ImGui.Theme.PageBg)
        contentBox:Relayout()
        box:Relayout()
    end)
    setTooltip(header, tooltip)

    -- sections inherit the full widget API, minus nesting
    local mt = { __index = function(_, k) return WidgetHost[k] end }
    local s = setmetatable({ box = contentBox, window = self.window }, mt)
    s.AddSection = function() warn("MemeSenseUI: nested sections are not supported") end
    return s
end

-- Columns -------------------------------------------------------------------
function WidgetHost:AddColumn(title)
    -- explicit second (or third) column, like the MemeSense page layout
    local tab = self.tab or self
    local idx = tab.columnCount + 1
    tab.columnCount = idx
    local frame = New("Frame", {
        Size = UDim2.fromOffset(COL_W, 0),
        Position = UDim2.fromOffset(BODY_X + (idx - 1) * COL_STEP, 0),
        BackgroundTransparency = 1,
    }, tab.bodyCanvas)
    local box = LayoutBox.new(frame, COL_W, function(h) tab:LayoutCanvas() end)
    box.parentColumn = nil

    if title and title ~= "" then
        -- centered gray section title, just like ksd::DrawSectionTitle
        local row = box:AddRow(14)
        local lbl = New("TextLabel", {
            BackgroundTransparency = 1,
            TextColor3 = ImGui.Theme.TextDisabled,
            Text = title,
            Size = UDim2.new(1, 0, 0, 14),
        }, row.f)
        applyFont(lbl, FONT_SIZE)
    end

    local col = setmetatable({ box = box, window = self.window, tab = tab, isColumn = true }, WidgetHost)
    tab.columns[#tab.columns + 1] = col
    tab:LayoutCanvas()
    return col
end

--[[====================== 9. TABS ============================================
   A tab is a page: a head ("menu bar") plus a scrollable body. Tabs also act
   as widget hosts - widgets added directly to the tab land in column 1.           ]]

local Tab = {}
Tab.__index = Tab

function Tab.new(window, name, iconAsset)
    local self = setmetatable({}, Tab)
    self.window = window
    self.name = name
    self.iconAsset = iconAsset
    self.columnCount = 1
    self.columns = {}

    -- page frame (head + body), hidden until this tab is selected
    self.page = New("Frame", {
        Size = UDim2.fromOffset(MENU_W - SIDEBAR_W, MENU_H - FLOW_H),
        Position = UDim2.fromOffset(SIDEBAR_W, FLOW_H),
        BackgroundColor3 = ImGui.Theme.PageBg,
        BorderSizePixel = 0,
        Visible = false,
    }, window.menu)

    -- head: 55px tall, widgets laid out left-to-right with a shared cursor
    self.head = New("Frame", {
        Size = UDim2.new(1, 0, 0, HEAD_H),
        BackgroundTransparency = 1,
    }, self.page)
    self.headX = BODY_X
    self.headWidgets = {}

    -- 2px separator line under the head
    New("Frame", {
        Size = UDim2.new(1, 0, 0, HEAD_LINE),
        Position = UDim2.fromOffset(0, HEAD_H),
        BackgroundColor3 = ImGui.Theme.Line,
        BorderSizePixel = 0,
    }, self.page)

    -- scrollable body canvas holding the widget columns
    self.body = New("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, -(HEAD_H + HEAD_LINE)),
        Position = UDim2.fromOffset(0, HEAD_H + HEAD_LINE),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.fromOffset(0, 0),
        ScrollBarImageColor3 = ImGui.Theme.Line,
        ScrollBarThickness = 3,
        AutomaticCanvasSize = Enum.AutomaticSize.None,
    }, self.page)
    self.bodyCanvas = New("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundTransparency = 1,
    }, self.body)

    -- the default (first) column
    local colFrame = New("Frame", {
        Size = UDim2.fromOffset(COL_W, 0),
        Position = UDim2.fromOffset(BODY_X, 0),
        BackgroundTransparency = 1,
    }, self.bodyCanvas)
    local box = LayoutBox.new(colFrame, COL_W, function(h) self:LayoutCanvas() end)
    self.box = box
    self.columns[#self.columns + 1] = setmetatable({
        box = box, window = window, tab = self, isColumn = true,
    }, WidgetHost)

    self:LayoutCanvas()
    return self
end

function Tab:LayoutCanvas()
    local h = 0
    for _, c in ipairs(self.columns) do
        h = math.max(h, c.box.frame.AbsoluteSize.Y)
    end
    self.body.CanvasSize = UDim2.fromOffset(0, h + 12)
end

function Tab:SetVisible(visible)
    self.page.Visible = visible
    if visible and Popup.current then
        Popup.current.frame.Visible = false
        Popup.current = nil
    end
end

-- head widgets --------------------------------------------------------------
function Tab:AddHeadToggle(text, default, callback, tooltip)
    local x = self.headX
    local btn = New("TextButton", {
        Size = UDim2.fromOffset(16, 16),
        Position = UDim2.fromOffset(x, (HEAD_H - 16) / 2),
        BackgroundColor3 = default and ImGui.Theme.Accent or ImGui.Theme.CheckboxEmpty,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 2,
    }, self.head)
    New("UICorner", { CornerRadius = UDim.new(0, 3) }, btn)
    local state = default and true or false
    local marks = state and addCheckMark(btn, 16) or {}
    for _, m in ipairs(marks) do m.Visible = state end
    local lbl = New("TextLabel", {
        BackgroundTransparency = 1,
        TextColor3 = ImGui.Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = text,
        Size = UDim2.fromOffset(200, HEAD_H),
        Position = UDim2.fromOffset(x + 22, 0),
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, self.head)
    applyFont(lbl, FONT_SIZE)
    local function refresh()
        btn.BackgroundColor3 = state and ImGui.Theme.Accent or ImGui.Theme.CheckboxEmpty
        lbl.TextColor3 = state and ImGui.Theme.Text or ImGui.Theme.TextDisabled
        for _, m in ipairs(marks) do m.Visible = state end
    end
    btn.MouseButton1Click:Connect(function()
        state = not state
        refresh()
        if callback then callback(state) end
    end)
    setTooltip(btn, tooltip)
    self.headX = x + 22 + math.min(#text * 8 + 20, 200) + 12
    self.headWidgets[#self.headWidgets + 1] = btn
    self.headWidgets[#self.headWidgets + 1] = lbl
    return {
        SetTooltip = function(_, t) setTooltip(btn, t) end,
        GetValue = function() return state end,
        SetValue = function(_, v, silent)
            state = v and true or false
            refresh()
            if callback and not silent then callback(state) end
        end,
    }
end

function Tab:AddHeadDropdown(options, defaultIndex, callback, tooltip)
    local x = self.headX
    local btn = New("TextButton", {
        Size = UDim2.fromOffset(124, ROW_H - 4),
        Position = UDim2.fromOffset(x, (HEAD_H - ROW_H + 4) / 2),
        BackgroundColor3 = ImGui.Theme.ButtonBg,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 2,
    }, self.head)
    New("UICorner", { CornerRadius = UDim.new(0, 3) }, btn)
    local preview = New("TextLabel", {
        BackgroundTransparency = 1,
        TextColor3 = ImGui.Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(1, -22, 1, 0),
        Position = UDim2.fromOffset(8, 0),
    }, btn)
    applyFont(preview, FONT_SIZE)
    makeTriangle(btn, 124 - 11, ROW_H / 2 - 2, 7, ImGui.Theme.TextDim, "down", ImGui.Theme.ButtonBg)

    local index = clamp(defaultIndex or 1, 1, #options)
    local popupFrame = New("Frame", {
        BackgroundColor3 = ImGui.Theme.PopupBg,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 20,
    }, self.window.gui)
    New("UICorner", { CornerRadius = UDim.new(0, 3) }, popupFrame)
    New("UIPadding", { PaddingTop = UDim.new(0, 8) }, popupFrame)
    popupFrame.Size = UDim2.fromOffset(124, 8 + #options * 22)
    local items = {}
    for i, name in ipairs(options) do
        local item = New("TextButton", {
            Size = UDim2.new(1, 0, 0, 22),
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 21,
        }, popupFrame)
        local it = New("TextLabel", {
            BackgroundTransparency = 1,
            TextXAlignment = Enum.TextXAlignment.Left,
            Size = UDim2.new(1, -16, 1, 0),
            Position = UDim2.fromOffset(8, 0),
        }, item)
        applyFont(it, FONT_SIZE)
        local hovered = false
        local function paint()
            it.TextColor3 = (i == index) and ImGui.Theme.Text
                or (hovered and ImGui.Theme.TextHover or ImGui.Theme.TextDim)
        end
        item.MouseEnter:Connect(function() hovered = true paint() end)
        item.MouseLeave:Connect(function() hovered = false paint() end)
        item.MouseButton1Click:Connect(function()
            index = i
            preview.Text = options[index]
            paint()
            Popup.current = nil
            popupFrame.Visible = false
            if callback then callback(index, options[index]) end
        end)
        items[i] = item
    end
    local open = false
    btn.MouseButton1Click:Connect(function()
        open = not open
        if open then
            popupFrame.Position = UDim2.fromOffset(
                btn.AbsolutePosition.X - self.window.gui.AbsolutePosition.X,
                btn.AbsolutePosition.Y - self.window.gui.AbsolutePosition.Y + btn.AbsoluteSize.Y - 3)
            Popup.Open({ frame = popupFrame, trigger = btn, Close = function() popupFrame.Visible = false end })
        else
            Popup.current = nil
            popupFrame.Visible = false
        end
    end)
    setTooltip(btn, tooltip)
    preview.Text = options[index]
    self.headX = x + 124 + 10
    self.headWidgets[#self.headWidgets + 1] = btn
    return {
        SetTooltip = function(_, t) setTooltip(btn, t) end,
        GetValue = function() return index end,
        SetValue = function(_, v, silent)
            index = clamp(v, 1, #options)
            preview.Text = options[index]
            if callback and not silent then callback(index, options[index]) end
        end,
    }
end

function Tab:AddHeadButton(text, callback, tooltip)
    local x = self.headX
    local btn = New("TextButton", {
        Size = UDim2.fromOffset(80, ROW_H - 4),
        Position = UDim2.fromOffset(x, (HEAD_H - ROW_H + 4) / 2),
        BackgroundColor3 = ImGui.Theme.ButtonBg,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 2,
    }, self.head)
    New("UICorner", { CornerRadius = UDim.new(0, 3) }, btn)
    local lbl = New("TextLabel", {
        BackgroundTransparency = 1,
        TextColor3 = Color3.new(1, 1, 1),
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(1, -16, 1, 0),
        Position = UDim2.fromOffset(8, 0),
        Text = text,
    }, btn)
    applyFont(lbl, FONT_SIZE)
    btn.MouseEnter:Connect(function() btn.BackgroundColor3 = ImGui.Theme.ButtonHover end)
    btn.MouseLeave:Connect(function() btn.BackgroundColor3 = ImGui.Theme.ButtonBg end)
    btn.MouseButton1Click:Connect(function() if callback then callback() end end)
    setTooltip(btn, tooltip)
    self.headX = x + 80 + 10
    self.headWidgets[#self.headWidgets + 1] = btn
    return { SetTooltip = function(_, t) setTooltip(btn, t) end }
end

-- Tab gets the widget API from WidgetHost (widgets land in column 1)
Tab.__index = setmetatable({}, { __index = function(t, k) return Tab[k] or WidgetHost[k] end })

--[[====================== 10. NOTIFICATIONS ==================================
   Small toast popups in the top-right corner that slide in and fade out.          ]]

local Notification = {}
function Notification.Show(gui, title, text, duration)
    local index = #Notification.active + 1
    local toast = New("Frame", {
        Size = UDim2.fromOffset(280, 56),
        Position = UDim2.fromOffset(0, 0),
        BackgroundColor3 = ImGui.Theme.PopupWinBg,
        BorderColor3 = ImGui.Theme.Border,
        BorderSizePixel = 1,
        ZIndex = 25,
        Visible = false,
    }, gui)
    New("UICorner", { CornerRadius = UDim.new(0, 4) }, toast)

    local titleLbl = New("TextLabel", {
        BackgroundTransparency = 1,
        TextColor3 = Color3.new(1, 1, 1),
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = title,
        Size = UDim2.new(1, -20, 0, 18),
        Position = UDim2.fromOffset(10, 6),
    }, toast)
    applyFont(titleLbl, 14, true)
    local textLbl = New("TextLabel", {
        BackgroundTransparency = 1,
        TextColor3 = ImGui.Theme.TextDim,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top,
        Text = text,
        Size = UDim2.new(1, -20, 1, -24),
        Position = UDim2.fromOffset(10, 24),
    }, toast)
    applyFont(textLbl, 13)
    local tb = textLbl.TextBounds
    toast.Size = UDim2.fromOffset(280, math.max(56, tb.Y + 34))

    local entry = { frame = toast }
    Notification.active[index] = entry
    local function relayout()
        local y = 8
        for _, e in ipairs(Notification.active) do
            if e and e.frame then
                e.frame.Position = UDim2.fromOffset(0, y)
                e.frame.Visible = true
                y = y + e.frame.AbsoluteSize.Y + 8
            end
        end
    end
    toast.Visible = true
    local tx = gui.AbsoluteSize.X
    toast.Position = UDim2.fromOffset(tx - 280 - 8, 8 + (index - 1) * 64)
    tween(toast, { Position = UDim2.fromOffset(tx - 280 - 8, 8 + (index - 1) * 64) }, 0.15)
    tween(toast, { Position = UDim2.fromOffset(tx - 280 + 60, 8 + (index - 1) * 64) }, 0.001)
    tween(toast, { Position = UDim2.fromOffset(tx - 280 - 8, 8 + (index - 1) * 64) }, 0.25)

    task.delay(duration or 4, function()
        tween(toast, { BackgroundTransparency = 1 }, 0.35, function()
            toast:Destroy()
            for i, e in ipairs(Notification.active) do
                if e == entry then Notification.active[i] = nil end
            end
            relayout()
        end)
    end)
end
Notification.active = {}

--[[====================== 11. THE WINDOW =====================================
   CreateWindow returns a Window: the full MemeSense-style menu (flow strip,
   branding, sidebar with tabs, page head + two-column body, drag + toggle).       ]]

-- Registry of live windows (used by ImGui:Notify / SetAccent / SetToggleKey).
local Windows = {}

-- flow strip color function, ported 1:1 from the C++ framework
local function flowColor(point, t)
    local red = Color3.fromRGB(255, 15, 41)
    local green = Color3.fromRGB(15, 230, 56)
    local blue = Color3.fromRGB(20, 102, 255)
    local moveTime = t * 0.85
    local blendTime = t * 0.02
    local sp = point * 0.12
    sp = sp + 0.015 * math.sin(sp * math.pi * 2 * 0.45 + blendTime * 0.15)
    local phase = (moveTime + sp) % 1
    local function smooth(v) return v * v * (3 - 2 * v) end
    if phase < 1 / 3 then return red:Lerp(green, smooth(phase / (1 / 3)))
    elseif phase < 2 / 3 then return green:Lerp(blue, smooth((phase - 1 / 3) / (1 / 3)))
    else return blue:Lerp(red, smooth((phase - 2 / 3) / (1 / 3))) end
end

local Window = {}
Window.__index = Window

function ImGui:CreateWindow(title, opts)
    opts = opts or {}
    local win = setmetatable({}, Window)

    win.gui = New("ScreenGui", {
        IgnoreGuiInset = true,
        DisplayOrder = 5,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })
    Windows[#Windows + 1] = win
    win.notifyTitle = title or "Notification"
    win.ToggleKey = opts.ToggleKey or Enum.KeyCode.RightShift
    win.accentOverride = opts.Accent
    win.tabs = {}
    win.currentTab = nil
    win.destroyed = false

    win.menu = New("Frame", {
        Size = UDim2.fromOffset(MENU_W, MENU_H),
        Position = UDim2.fromOffset(
            math.floor((game:GetService("GuiService"):GetScreenResolution().X - MENU_W) / 2),
            40),
        BackgroundColor3 = ImGui.Theme.WindowBg,
        BorderSizePixel = 0,
        ClipsDescendants = true,
    }, win.gui)

    -- animated RGB flow strip on top of the menu
    win.flow = New("Frame", {
        Size = UDim2.new(1, 0, 0, FLOW_H),
        BackgroundTransparency = 1,
        ZIndex = 6,
    }, win.menu)
    win.flowSegs = {}
    local SEGMENTS = 48
    for i = 1, SEGMENTS do
        win.flowSegs[i] = New("Frame", {
            Size = UDim2.fromOffset(MENU_W / SEGMENTS + 1, FLOW_H),
            Position = UDim2.fromOffset((i - 1) * (MENU_W / SEGMENTS), 0),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
        }, win.flow)
    end

    -- sidebar
    win.sidebar = New("Frame", {
        Size = UDim2.fromOffset(SIDEBAR_W, MENU_H),
        Position = UDim2.fromOffset(0, FLOW_H),
        BackgroundColor3 = ImGui.Theme.SidebarBg,
        BorderSizePixel = 0,
    }, win.menu)

    -- branding (draggable): "Meme" in red + "Sense" in white, like MemeSense
    win.brandRow = New("Frame", {
        Size = UDim2.fromOffset(SIDEBAR_W, SIDEBAR_BTN_Y - 4),
        BackgroundTransparency = 1,
        ZIndex = 2,
    }, win.sidebar)
    win.brandLabels = {}
    local function paintBrand()
        for _, lbl in ipairs(win.brandLabels) do lbl:Destroy() end
        win.brandLabels = {}
        local x = BRAND_X
        local parts = opts.Branding
        if not parts or #parts == 0 then parts = { { win.notifyTitle, Color3.new(1, 1, 1) } } end
        for _, p in ipairs(parts) do
            local lbl = New("TextLabel", {
                BackgroundTransparency = 1,
                TextColor3 = p[2],
                Text = p[1],
                Size = UDim2.fromOffset(200, TITLE_SIZE),
                Position = UDim2.fromOffset(x, BRAND_Y),
                TextXAlignment = Enum.TextXAlignment.Left,
            }, win.brandRow)
            applyFont(lbl, TITLE_SIZE, true)
            x = x + lbl.TextBounds.X + 2
            win.brandLabels[#win.brandLabels + 1] = lbl
        end
    end
    paintBrand()

    -- sidebar tabs scroll frame
    win.tabList = New("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, -SIDEBAR_BTN_Y + 4),
        Position = UDim2.fromOffset(0, SIDEBAR_BTN_Y - 4),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.fromOffset(0, 0),
        ScrollBarImageColor3 = ImGui.Theme.Line,
        ScrollBarThickness = 3,
    }, win.sidebar)
    win.tabButtons = {}

    -- page head separator is drawn per-tab; body drag comes from the head area
    win.tabListY = 0

    -- window dragging (branding row only, so widgets never fight the drag)
    local dragOffset
    local function startDrag(input)
        dragOffset = Vector2.new(
            win.menu.AbsolutePosition.X - input.Position.X,
            win.menu.AbsolutePosition.Y - input.Position.Y)
    end
    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe or win.destroyed or not win.menu.Visible then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            local t = input.Target
            if t == win.brandRow or t == win.sidebar then
                -- only when clicking the branding area itself
                if t == win.brandRow then startDrag(input) end
            end
        end
    end)
    UserInputService.InputChanged:Connect(function(input, gpe)
        if gpe or not dragOffset then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            win.menu.Position = UDim2.fromOffset(
                input.Position.X + dragOffset.X,
                input.Position.Y + dragOffset.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragOffset = nil end
    end)

    -- window toggle hotkey
    win.toggleConn = UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe or win.destroyed then return end
        if input.KeyCode == win.ToggleKey then win:Toggle() end
    end)

    -- flow strip animation
    win.flowConn = (RunService.RenderStepped or RunService.Heartbeat):Connect(function()
        local t = time()
        for i, seg in ipairs(win.flowSegs) do
            seg.BackgroundColor3 = flowColor((i - 1) / SEGMENTS, t)
        end
    end)

    return win
end

function Window:AddTab(name, iconAsset)
    local tab = Tab.new(self, name, iconAsset)

    -- sidebar button for this tab
    local btn = New("TextButton", {
        Size = UDim2.fromOffset(SIDEBAR_W, 26),
        Position = UDim2.fromOffset(0, self.tabListY),
        BackgroundColor3 = ImGui.Theme.SidebarBg,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 2,
    }, self.tabList)
    self.tabListY = self.tabListY + 29

    local icon
    if iconAsset then
        icon = makeImage(iconAsset, 16, Color3.new(1, 1, 1))
        icon.Position = UDim2.fromOffset(11, 5)
        icon.Parent = btn
    end
    local lbl = New("TextLabel", {
        BackgroundTransparency = 1,
        TextColor3 = Color3.new(1, 1, 1),
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = name,
        Size = UDim2.fromOffset(SIDEBAR_W - 40, 26),
        Position = UDim2.fromOffset(37, 0),
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, btn)
    applyFont(lbl, FONT_SIZE)

    -- 2px accent bar on the left edge when active/hovered
    local accentBar = New("Frame", {
        Size = UDim2.fromOffset(2, 26),
        BackgroundColor3 = self.accentOverride or ImGui.Theme.Accent,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 3,
    }, btn)

    local function paint(active, hovered)
        btn.BackgroundColor3 = active and ImGui.Theme.ActiveBg
            or (hovered and ImGui.Theme.HoverBg or ImGui.Theme.SidebarBg)
        accentBar.Visible = active or hovered
        if icon then
            icon.ImageColor3 = (active or hovered) and (self.accentOverride or ImGui.Theme.Accent) or Color3.new(1, 1, 1)
        end
    end
    local hovered = false
    btn.MouseEnter:Connect(function() hovered = true paint(self.currentTab == tab, true) end)
    btn.MouseLeave:Connect(function() hovered = false paint(self.currentTab == tab, false) end)
    btn.MouseButton1Click:Connect(function()
        self:SelectTab(tab)
    end)

    tab.btn = btn
    tab.paint = paint
    tab.accentBar = accentBar

    self.tabs[#self.tabs + 1] = tab
    self.tabList.CanvasSize = UDim2.fromOffset(0, self.tabListY + 8)

    if not self.currentTab then self:SelectTab(tab) end
    return tab
end

function Window:SelectTab(tab)
    if self.currentTab then
        self.currentTab.page.Visible = false
        self.currentTab.paint(false, false)
    end
    self.currentTab = tab
    tab.page.Visible = true
    tab.paint(true, false)
    -- close any open popup when switching tabs
    if Popup.current then
        Popup.current.frame.Visible = false
        Popup.current = nil
    end
end

function Window:Toggle()
    self:SetVisible(not self.menu.Visible)
end

function Window:SetVisible(visible)
    self.menu.Visible = visible
    self.gui.Enabled = visible
    if not visible and Popup.current then
        Popup.current.frame.Visible = false
        Popup.current = nil
    end
end

function Window:Destroy()
    self.destroyed = true
    if self.toggleConn then self.toggleConn:Disconnect() end
    if self.flowConn then self.flowConn:Disconnect() end
    for i, w in ipairs(Windows) do
        if w == self then table.remove(Windows, i) break end
    end
    self.gui:Destroy()
end

function Window:SetToggleKey(key)
    self.ToggleKey = key
end

function Window:SetAccent(color)
    self.accentOverride = color
    -- refresh sidebar bars + tabs
    for _, tab in ipairs(self.tabs) do
        if tab.accentBar then tab.accentBar.BackgroundColor3 = color end
        tab.paint(self.currentTab == tab, false)
    end
end

function Window:SetTitle(branding)
    -- rebuild the branding labels ("Meme" red + "Sense" white, etc.)
    for _, lbl in ipairs(self.brandLabels) do lbl:Destroy() end
    self.brandLabels = {}
    local x = BRAND_X
    for _, p in ipairs(branding or {}) do
        local lbl = New("TextLabel", {
            BackgroundTransparency = 1,
            TextColor3 = p[2],
            Text = p[1],
            Size = UDim2.fromOffset(200, TITLE_SIZE),
            Position = UDim2.fromOffset(x, BRAND_Y),
            TextXAlignment = Enum.TextXAlignment.Left,
        }, self.brandRow)
        applyFont(lbl, TITLE_SIZE, true)
        x = x + lbl.TextBounds.X + 2
        self.brandLabels[#self.brandLabels + 1] = lbl
    end
end

--[[====================== 12. PUBLIC API =====================================
   Functions you call from your script:                                         ]]

-- Window notifications (window title is used as the toast header)
function Window:Notify(text, duration)
    Notification.Show(self.gui, self.notifyTitle or "Notification", text, duration)
end

function ImGui:Notify(title, text, duration)
    local gui = nil
    -- notify from any active window; fall back to a temporary gui
    for _, w in ipairs(Windows) do
        if w.gui and w.gui.Parent then gui = w.gui break end
    end
    if not gui then
        gui = New("ScreenGui", { IgnoreGuiInset = true, DisplayOrder = 7 })
    end
    Notification.Show(gui, title, text, duration)
end

function ImGui:SetToggleKey(key)
    for _, w in ipairs(Windows) do w:SetToggleKey(key) end
end

function ImGui:SetAccent(color)
    ImGui.Theme.Accent = color
    for _, w in ipairs(Windows) do w:SetAccent(color) end
end

return ImGui
