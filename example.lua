--[[
    MemeSense UI - Example / Demo Script
    ====================================
    A complete example that shows every widget in the library, laid out
    exactly like the original C++ MemeSense cheat: sidebar tabs, animated
    RGB flow strip, page head with a master switch, two columns, toasts.

    HOW TO USE
    ----------
    1. Paste the whole source.lua into this file ABOVE this script, OR
       load the library from a paste/raw URL:

           local ImGui = loadstring(game:HttpGet("PASTE_RAW_URL_HERE"))()

    2. Run the script. Press RightShift to show/hide the menu.

    If you keep source.lua separate, just replace the "Load the library"
    line below with your loadstring call and run both chunks in the same
    executor session.
--]]

-- ----------------------------------------------------------------------
-- 0. LOAD THE LIBRARY
-- ----------------------------------------------------------------------
-- Choose ONE of these options:
--
--   A) Single file:  paste source.lua ABOVE this script. The library's
--      `return ImGui` works when loaded with loadstring(), so the normal
--      setup is:   loadstring(sourceCode)()  ->  ImGui
--
--   B) Two files:   keep source.lua separate and load it from a paste
--      site by setting PASTE_URL below:
--         local libSource = game:HttpGet("PASTE_URL_HERE")
--         ImGui = loadstring(libSource)()
--
--   C) Same session: once loaded, the library is cached in
--      (getgenv or _G).MemeSense, so later scripts can reuse it.
--
local ImGui
local env = (getgenv or function() return _G end)()
if env.MemeSense then
    ImGui = env.MemeSense                        -- option C: already loaded
else
    local libSource = game:HttpGet("PASTE_URL_HERE")   -- option B: <-- EDIT THIS
    ImGui = loadstring(libSource)()
    env.MemeSense = ImGui                        -- cache for later scripts
end

-- ----------------------------------------------------------------------
-- 1. SETTINGS (tweak the cheat options here)
-- ----------------------------------------------------------------------
local Settings = {
    Fly            = false,
    Noclip         = false,
    WalkSpeed      = 16,
    JumpPower      = 50,
    FlySpeed       = 50,
    InfiniteJump   = Enum.KeyCode.Space,
    ESP            = true,
    ESPMode        = 1,                  -- 1 = Box, 2 = Tracer, 3 = Name
    ESPColor       = Color3.fromRGB(255, 60, 90),
    TeamColor      = Color3.fromRGB(60, 255, 140),
    FOV            = 70,
    Glow           = false,
    GlowColor      = Color3.fromRGB(255, 160, 0),
    MenuKey        = Enum.KeyCode.RightShift,
    Notifications  = true,
}

-- ----------------------------------------------------------------------
-- 2. CREATE THE WINDOW (700x620, dark theme, brand row on top)
-- ----------------------------------------------------------------------
local Window = ImGui:CreateWindow("MemeSense", {
    Branding = {
        { "Meme", Color3.fromRGB(255, 40, 54) },   -- red part, like the C++ logo
        { "Sense", Color3.new(1, 1, 1) },
    },
    ToggleKey = Settings.MenuKey,                -- RightShift toggles the menu
    Resizable = true,                            -- drag the bottom-right corner
})

-- ----------------------------------------------------------------------
-- 3. TABS
-- ----------------------------------------------------------------------

-- ========== TAB: MAIN ==========
local MainTab = Window:AddTab("Main", ImGui.Icons.Home)

-- -- Movement section ------------------------------------------------
local Movement = MainTab:AddSection("Movement", false)

Movement:AddToggle("Fly", Settings.Fly, function(v)
    Settings.Fly = v
    if v and Window then Window:Notify("Fly", "Fly enabled - use your movement keys") end
end, "Lets you fly around the map")

Movement:AddSlider("Fly Speed", 10, 200, Settings.FlySpeed, function(v)
    Settings.FlySpeed = v
end, { Suffix = " studs/s", Precision = 0 })

Movement:AddSlider("Walk Speed", 1, 250, Settings.WalkSpeed, function(v)
    Settings.WalkSpeed = v
    local hum = game:GetService("Players").LocalPlayer.Character
        and game:GetService("Players").LocalPlayer.Character:FindFirstChild("Humanoid")
    if hum and hum.WalkSpeed ~= v then hum.WalkSpeed = v end
end, { Suffix = " studs", Precision = 0 })

Movement:AddSlider("Jump Power", 0, 200, Settings.JumpPower, function(v)
    Settings.JumpPower = v
end, { Suffix = "", Precision = 0 })

-- -- Combat section ---------------------------------------------------
local Combat = MainTab:AddSection("Combat", false)

Combat:AddToggle("Infinite Jump", Settings.InfiniteJump ~= nil, function(v)
    Settings.InfiniteJump = v and Enum.KeyCode.Space or nil
end, "Hold Space to jump repeatedly")

Combat:AddKeybind("Menu Key", Settings.MenuKey, function(k)
    Settings.MenuKey = k
end, "Right-click to clear this bind")

Combat:AddDropdown("Aim Mode", { "Off", "Silent", "Normal" }, 1, function(i)
    print("[MemeSense] Aim mode set to:", i)
end)

-- -- Info label --------------------------------------------------------
MainTab:AddLabel("Rebind the menu key or clear it to keep it on RightShift", true)
MainTab:AddSeparator()

-- ========== TAB: VISUALS ==========
local VisualsTab = Window:AddTab("Visuals", ImGui.Icons.Eye)

-- -- ESP section ------------------------------------------------------
local ESP = VisualsTab:AddSection("ESP", false)

ESP:AddToggle("Enable ESP", Settings.ESP, function(v)
    Settings.ESP = v
end, "Draw boxes/tracers around players")

ESP:AddDropdown("ESP Mode", { "Boxes", "Tracers", "Names" }, Settings.ESPMode, function(i)
    Settings.ESPMode = i
end)

ESP:AddColorPicker("Enemy Color", Settings.ESPColor, function(c, enabled)
    Settings.ESPColor = c
    Settings.ESP = enabled or Settings.ESP
end, "Right-click the swatch to open the picker")

ESP:AddColorPicker("Team Color", Settings.TeamColor, function(c, enabled)
    Settings.TeamColor = c
end)

ESP:AddSlider("ESP Distance", 100, 10000, 3000, function(v) end, { Suffix = " studs" })

-- -- World section -----------------------------------------------------
local World = VisualsTab:AddColumn("World")

World:AddSlider("Field of View", 40, 120, Settings.FOV, function(v)
    Settings.FOV = v
    local cam = workspace.CurrentCamera
    if cam and cam.FieldOfView then cam.FieldOfView = v end
end, { Suffix = " deg" })

World:AddToggle("Glow", Settings.Glow, function(v)
    Settings.Glow = v
end)

World:AddColorPicker("Glow Color", Settings.GlowColor, function(c)
    Settings.GlowColor = c
end)

-- -- Streaming ---------------------------------------------------------
local Streaming = VisualsTab:AddSection("Streaming", true)   -- collapsed by default

Streaming:AddToggle("Streamproof", false, function(v) end, "Hide the menu in recordings")
Streaming:AddToggle("Watermark", true, function(v) end)

-- ========== TAB: SETTINGS ==========
local SettingsTab = Window:AddTab("Settings", ImGui.Icons.Gear)

-- -- Config section ----------------------------------------------------
local Config = SettingsTab:AddSection("Config", false)

local ConfigName = Config:AddDropdown("Config", { "Config 1", "Config 2", "Config 3" }, 1)

Config:AddButton("Save Config", function()
    print("[MemeSense] Saved config", ConfigName:GetValue())
    Window:Notify("Config", "Saved slot " .. ConfigName:GetValue())
end)

Config:AddButton("Load Config", function()
    print("[MemeSense] Loaded config", ConfigName:GetValue())
    Window:Notify("Config", "Loaded slot " .. ConfigName:GetValue())
end)

-- -- Notifications section ---------------------------------------------
local Alerts = SettingsTab:AddSection("Notifications", false)

Alerts:AddToggle("Enable Toasts", Settings.Notifications, function(v)
    Settings.Notifications = v
end)

Alerts:AddButton("Test Toast", function()
    Window:Notify("MemeSense", "This is a test notification")
end, "Slide-in toast in the top-right corner")

Alerts:AddButton("Global Toast", function()
    ImGui:Notify("Global", "Notifications work outside the menu too")
end)

-- -- Text input ---------------------------------------------------------
local General = SettingsTab:AddColumn("General")

General:AddTextbox("Player Name", "no one", function(text)
    print("[MemeSense] Name:", text)
end, "The player to target", "Type a name...")

General:AddKeybind("Noclip Key", Enum.KeyCode.N, function(k)
    print("[MemeSense] Noclip key:", tostring(k))
end)

-- ----------------------------------------------------------------------
-- 4. HEAD WIDGETS (top bar of the page)
-- ----------------------------------------------------------------------
local Master = MainTab:AddHeadToggle("Master Switch", true, function(v)
    print("[MemeSense] Master switch:", v)
end, "Turns the whole cheat on/off")

MainTab:AddHeadDropdown({ "Config 1", "Config 2", "Config 3" }, 1, function(i)
    print("[MemeSense] Head config:", i)
end)

MainTab:AddHeadButton("Save", function()
    Window:Notify("MemeSense", "Config saved!")
end)

-- ----------------------------------------------------------------------
-- 5. USE THE HANDLES (a small example: read + write values later)
-- ----------------------------------------------------------------------
local WalkSpeedHandle = Movement:AddSlider("Walk Speed Backup", 1, 250, 16, function() end)
WalkSpeedHandle:SetValue(80, true)   -- silent set (no callback), like restoring a config
print("[MemeSense] WalkSpeed handle now:", WalkSpeedHandle:GetValue())

local FlyToggle = Movement:AddToggle("Noclip", Settings.Noclip, function(v)
    Settings.Noclip = v
end)

-- Turn the noclip toggle on from code (loud set -> callback runs):
FlyToggle:SetValue(true)
print("[MemeSense] Noclip is now:", FlyToggle:GetValue(), "->", Settings.Noclip)

-- ----------------------------------------------------------------------
-- 6. LIVE BEHAVIOR (optional, guarded so it can never crash the UI)
-- ----------------------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

RunService.RenderStepped:Connect(function()
    local lp = Players.LocalPlayer
    if not lp or not lp.Character then return end
    local hum = lp.Character:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    -- keep walk speed synced with the slider
    local target = Settings.WalkSpeed
    if math.abs(hum.WalkSpeed - target) > 0.5 then
        pcall(function() hum.WalkSpeed = target end)
    end
end)

-- ----------------------------------------------------------------------
-- 7. DONE
-- ----------------------------------------------------------------------
Window:Notify("Welcome", "MemeSense UI loaded - press RightShift to toggle")
print("[MemeSense] Demo loaded. Toggle the menu with RightShift.")
