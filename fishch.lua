-- ============================================================
--  Fisch Script | Fluent UI
--  Game  : Fisch (Roblox) - 2026 Updates (Tidefall, Scoria Reach, Lost Jungle)
--  GUI   : https://github.com/dawid-scripts/Fluent
--  Fixed : AddSection takes plain string (not table)
-- ============================================================

local Fluent         = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager    = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

-- ============================================================
--  Services
-- ============================================================
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer  = Players.LocalPlayer

local function GetChar()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end
local function GetRoot()
    local c = GetChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end

-- ============================================================
--  Remote Helpers
-- ============================================================
local RS = game:GetService("ReplicatedStorage")

local function WaitForRemote(name, timeout)
    timeout = timeout or 3
    local t = 0
    while t < timeout do
        local r = RS:FindFirstChild(name, true)
        if r then return r end
        task.wait(0.1)
        t += 0.1
    end
    return nil
end

local function FireRemote(name, ...)
    local r = WaitForRemote(name, 1)
    if r and r:IsA("RemoteEvent") then
        pcall(function() r:FireServer(...) end)
    end
end

-- ============================================================
--  State
-- ============================================================
local State = {
    AutoCast          = false,
    AutoShake         = false,
    AutoReel          = false,
    InstantBobber     = false,
    CenterShake       = false,
    AlwaysProgressing = false,
    AntiProgressLoss  = false,
    SuperBoat         = false,
    BoatSpeed         = 60,
    SellOnCatch       = false,
    AutoSell          = false,
    AutoSellDelay     = 5,
    AutoCollectStar   = false,
    ShowRadar         = false,
    AntiOxygen        = false,
    AntiTemperature   = false,
    AntiPressure      = false,
    SelectedRod       = "Flimsy Rod",
    SelectedCrate     = "Common Crate",
    SelectedTotem     = "Luck Totem",
    BuyCrateAmount    = 1,
    BuyTotemAmount    = 1,
    SelectedTeleport  = "Spawn Island",
    lastSellTime      = os.clock(),
    progressCache     = 0,
}

-- ============================================================
--  Data Lists (Updated 2026)
-- ============================================================
local RodList = {
    "Flimsy Rod", "Old Rod", "Basic Rod", "Travelers Rod",
    "Trusty Rod", "Hardy Rod", "Lucky Rod", "Oceanic Rod",
    "Storm Rod", "Deep Rod", "Abyss Rod", "Lunar Rod",
    "Masterline Rod",  -- Feb 2026: fishes any liquid
    "Tidefall Rod",    -- Jan 2026 Tidefall update
    "Volcanic Rod",    -- Feb 15 2026 Scoria Reach
    "Jungle Rod",      -- Mar 7 2026 Lost Jungle
    "Toxic Rod",       -- Mar 7 2026 Toxic Grove (Lost Jungle Expansion)
    "Ancient Rod", "Celestial Rod", "Astraeus Rod",
}

local CrateList = {
    "Common Crate", "Uncommon Crate", "Rare Crate",
    "Epic Crate", "Legendary Crate", "Mythic Crate",
    "Tidefall Crate", "Volcanic Crate", "Jungle Crate",
}

local TotemList = {
    "Luck Totem", "Speed Totem", "Rare Totem", "Double Totem",
    "Epic Totem", "Legendary Totem", "Hunt Totem", "Mythic Totem",
}

-- 2026 locations
local TeleportLocations = {
    ["Spawn Island"]    = Vector3.new(0,    5,   0),
    ["Moosewood"]       = Vector3.new(478,  5,   134),
    ["Roslit Bay"]      = Vector3.new(-350, 5,   280),
    ["Forsaken Shores"] = Vector3.new(820,  5,  -400),
    ["Deep Sea"]        = Vector3.new(-620, 5,   580),
    ["Tidefall"]        = Vector3.new(1100, -40, 200),  -- Jan 2026 underwater
    ["Scoria Reach"]    = Vector3.new(-900, 5,  -700),  -- Feb 2026 lava island
    ["Lost Jungle"]     = Vector3.new(700,  5,   900),  -- Mar 2026
    ["Toxic Grove"]     = Vector3.new(720,  5,   980),  -- Mar 7 2026 expansion
    ["Trade Plaza"]     = Vector3.new(50,   5,   250),
    ["Star Crater"]     = Vector3.new(-100, 5,  -600),
}

local TeleportNames = {}
for k in pairs(TeleportLocations) do table.insert(TeleportNames, k) end
table.sort(TeleportNames)

-- ============================================================
--  Window
-- ============================================================
local Window = Fluent:CreateWindow({
    Title       = "Fisch Script",
    SubTitle    = "2026 Edition - Lost Jungle Ready",
    TabWidth    = 160,
    Size        = UDim2.fromOffset(620, 490),
    Acrylic     = true,
    Theme       = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
})

local Tabs = {
    Fishing   = Window:AddTab({ Title = "Fishing",   Icon = "fish" }),
    Utilities = Window:AddTab({ Title = "Utilities", Icon = "wrench" }),
    Teleports = Window:AddTab({ Title = "Teleports", Icon = "map-pin" }),
    Settings  = Window:AddTab({ Title = "Settings",  Icon = "settings" }),
}

local Options = Fluent.Options

-- ============================================================
--  FISHING TAB
-- ============================================================

-- FIX: AddSection harus menerima STRING bukan table {}
Tabs.Fishing:AddSection("Automation")

Tabs.Fishing:AddToggle("AutoCast", {
    Title       = "Auto Cast",
    Description = "Otomatis melempar kail ketika idle.",
    Default     = false,
    Callback    = function(v) State.AutoCast = v end,
})

Tabs.Fishing:AddToggle("AutoShake", {
    Title       = "Auto Shake",
    Description = "Otomatis handle minigame shake/bobber.",
    Default     = false,
    Callback    = function(v) State.AutoShake = v end,
})

Tabs.Fishing:AddToggle("AutoReel", {
    Title       = "Auto Reel",
    Description = "Otomatis menarik ikan setelah bobber bergetar.",
    Default     = false,
    Callback    = function(v) State.AutoReel = v end,
})

Tabs.Fishing:AddSection("Modification")

Tabs.Fishing:AddToggle("InstantBobber", {
    Title       = "Instant Bobber",
    Description = "Pelampung langsung menyentuh air setelah cast.",
    Default     = false,
    Callback    = function(v) State.InstantBobber = v end,
})

Tabs.Fishing:AddToggle("CenterShake", {
    Title       = "Center Shake",
    Description = "Indikator shake selalu berada di tengah.",
    Default     = false,
    Callback    = function(v) State.CenterShake = v end,
})

Tabs.Fishing:AddToggle("AlwaysProgressing", {
    Title       = "Always Progressing",
    Description = "Progress bar tangkapan terus maju.",
    Default     = false,
    Callback    = function(v) State.AlwaysProgressing = v end,
})

Tabs.Fishing:AddToggle("AntiProgressLoss", {
    Title       = "Anti Progress Loss",
    Description = "Progress tangkapan tidak akan berkurang.",
    Default     = false,
    Callback    = function(v)
        State.AntiProgressLoss = v
        if v then State.progressCache = 0 end
    end,
})

-- ============================================================
--  UTILITIES TAB
-- ============================================================

Tabs.Utilities:AddSection("Boat")

Tabs.Utilities:AddToggle("SuperBoat", {
    Title       = "Super Boat",
    Description = "Boost kecepatan kapalmu secara drastis.",
    Default     = false,
    Callback    = function(v)
        State.SuperBoat = v
        task.spawn(function()
            for _, seat in ipairs(workspace:GetDescendants()) do
                if seat:IsA("VehicleSeat") then
                    local owner = seat.Parent:FindFirstChild("Owner")
                    if owner and owner.Value == LocalPlayer.Name then
                        pcall(function()
                            seat.MaxSpeed  = v and State.BoatSpeed or 30
                            seat.Torque    = v and 10000 or 2000
                            seat.TurnSpeed = v and 4 or 1
                        end)
                    end
                end
            end
        end)
    end,
})

Tabs.Utilities:AddSlider("BoatSpeed", {
    Title       = "Boat Speed",
    Description = "Kecepatan Super Boat.",
    Default     = 60,
    Min         = 30,
    Max         = 400,
    Rounding    = 0,
    Callback    = function(v) State.BoatSpeed = v end,
})

Tabs.Utilities:AddSection("Selling")

Tabs.Utilities:AddToggle("SellOnCatch", {
    Title       = "Sell All On Fish Caught",
    Description = "Langsung jual semua ikan setiap kali dapat tangkapan.",
    Default     = false,
    Callback    = function(v) State.SellOnCatch = v end,
})

Tabs.Utilities:AddSlider("AutoSellDelay", {
    Title       = "Auto Sell Delay (Minutes)",
    Description = "Interval otomatis jual semua inventory (menit).",
    Default     = 5,
    Min         = 1,
    Max         = 60,
    Rounding    = 0,
    Callback    = function(v) State.AutoSellDelay = v end,
})

Tabs.Utilities:AddToggle("AutoSell", {
    Title       = "Auto Sell All",
    Description = "Otomatis jual semua inventory sesuai delay.",
    Default     = false,
    Callback    = function(v) State.AutoSell = v end,
})

Tabs.Utilities:AddSection("Starfall")

Tabs.Utilities:AddParagraph({
    Title   = "Star Crater Status",
    Content = "Aktifkan toggle di bawah untuk auto ambil Star Crater saat muncul di map.",
})

Tabs.Utilities:AddToggle("AutoCollectStar", {
    Title       = "Auto Collect Star Crater",
    Description = "Otomatis teleport & kumpulkan Star Crater saat muncul.",
    Default     = false,
    Callback    = function(v) State.AutoCollectStar = v end,
})

Tabs.Utilities:AddSection("Rods")

Tabs.Utilities:AddDropdown("SelectRod", {
    Title       = "Select Rod",
    Description = "Pilih rod yang ingin dibeli.",
    Values      = RodList,
    Multi       = false,
    Default     = 1,
    Callback    = function(v) State.SelectedRod = v end,
})

Tabs.Utilities:AddButton({
    Title       = "Purchase Selected Rod",
    Description = "Beli rod yang dipilih.",
    Callback    = function()
        FireRemote("BuyRod", State.SelectedRod)
        FireRemote("PurchaseRod", State.SelectedRod)
        Fluent:Notify({ Title = "Rod", Content = "Mencoba beli: " .. State.SelectedRod, Duration = 3 })
    end,
})

Tabs.Utilities:AddSection("Crates")

Tabs.Utilities:AddDropdown("SelectCrate", {
    Title       = "Select Crate",
    Description = "Pilih crate yang ingin dibeli.",
    Values      = CrateList,
    Multi       = false,
    Default     = 1,
    Callback    = function(v) State.SelectedCrate = v end,
})

Tabs.Utilities:AddSlider("BuyCrateAmount", {
    Title       = "Buy Crate Amount",
    Description = "Jumlah crate yang dibeli sekali tekan.",
    Default     = 1,
    Min         = 1,
    Max         = 100,
    Rounding    = 0,
    Callback    = function(v) State.BuyCrateAmount = v end,
})

Tabs.Utilities:AddButton({
    Title       = "Purchase Selected Crate",
    Description = "Beli crate sejumlah yang sudah diset.",
    Callback    = function()
        for i = 1, State.BuyCrateAmount do
            FireRemote("BuyCrate", State.SelectedCrate)
            task.wait(0.08)
        end
        Fluent:Notify({
            Title    = "Crate",
            Content  = string.format("Beli %dx %s", State.BuyCrateAmount, State.SelectedCrate),
            Duration = 3,
        })
    end,
})

Tabs.Utilities:AddSection("Totems")

Tabs.Utilities:AddDropdown("SelectTotem", {
    Title       = "Select Totem",
    Description = "Pilih totem yang ingin dibeli.",
    Values      = TotemList,
    Multi       = false,
    Default     = 1,
    Callback    = function(v) State.SelectedTotem = v end,
})

Tabs.Utilities:AddSlider("BuyTotemAmount", {
    Title       = "Buy Totem Amount",
    Description = "Jumlah totem yang dibeli sekali tekan.",
    Default     = 1,
    Min         = 1,
    Max         = 50,
    Rounding    = 0,
    Callback    = function(v) State.BuyTotemAmount = v end,
})

Tabs.Utilities:AddButton({
    Title       = "Purchase Selected Totem",
    Description = "Beli totem sejumlah yang sudah diset.",
    Callback    = function()
        for i = 1, State.BuyTotemAmount do
            FireRemote("BuyTotem", State.SelectedTotem)
            task.wait(0.08)
        end
        Fluent:Notify({
            Title    = "Totem",
            Content  = string.format("Beli %dx %s", State.BuyTotemAmount, State.SelectedTotem),
            Duration = 3,
        })
    end,
})

Tabs.Utilities:AddSection("Miscellaneous")

Tabs.Utilities:AddToggle("ShowRadar", {
    Title       = "Show Radar",
    Description = "Tampilkan fish radar (persist antar join sejak Feb 2026 update).",
    Default     = false,
    Callback    = function(v)
        State.ShowRadar = v
        FireRemote("SetRadar", v)
        FireRemote("ToggleRadar", v)
        for _, gui in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
            if gui.Name:lower():find("radar") then
                pcall(function() gui.Enabled = v end)
            end
        end
    end,
})

Tabs.Utilities:AddToggle("AntiOxygen", {
    Title       = "Anti Oxygen",
    Description = "Cegah oksigen habis (penting di Tidefall underwater).",
    Default     = false,
    Callback    = function(v) State.AntiOxygen = v end,
})

Tabs.Utilities:AddToggle("AntiTemperature", {
    Title       = "Anti Temperature",
    Description = "Cegah damage suhu (berguna di Scoria Reach lava zone).",
    Default     = false,
    Callback    = function(v) State.AntiTemperature = v end,
})

Tabs.Utilities:AddToggle("AntiPressure", {
    Title       = "Anti Pressure",
    Description = "Cegah damage tekanan di perairan dalam Tidefall.",
    Default     = false,
    Callback    = function(v) State.AntiPressure = v end,
})

-- ============================================================
--  TELEPORTS TAB
-- ============================================================

Tabs.Teleports:AddSection("Teleport")

Tabs.Teleports:AddParagraph({
    Title   = "Lokasi Tersedia (2026)",
    Content = "Tidefall (Jan) · Scoria Reach (Feb 15) · Lost Jungle + Toxic Grove (Mar 7)\nTekan RightCtrl untuk minimize GUI.",
})

Tabs.Teleports:AddDropdown("TeleportLocation", {
    Title       = "Select Teleport Location",
    Description = "Pilih tujuan teleport.",
    Values      = TeleportNames,
    Multi       = false,
    Default     = 1,
    Callback    = function(v) State.SelectedTeleport = v end,
})

Tabs.Teleports:AddButton({
    Title       = "Teleport To Selected Location",
    Description = "Teleport karakter ke lokasi yang dipilih.",
    Callback    = function()
        local destVec = TeleportLocations[State.SelectedTeleport]
        if not destVec then return end
        local root = GetRoot()
        if root then
            root.CFrame = CFrame.new(destVec)
            Fluent:Notify({ Title = "Teleport", Content = "Tiba di: " .. State.SelectedTeleport, Duration = 3 })
        else
            Fluent:Notify({ Title = "Gagal", Content = "Karakter tidak ditemukan, coba lagi.", Duration = 3 })
        end
    end,
})

-- ============================================================
--  SETTINGS TAB
-- ============================================================
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
InterfaceManager:SetFolder("FischScript2026")
SaveManager:SetFolder("FischScript2026/configs")
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

-- ============================================================
--  CORE LOGIC
-- ============================================================

-- Minigame GUI detection
local function GetFischGui()
    local pg = LocalPlayer.PlayerGui
    for _, name in ipairs({"FishingGui","MiniGame","FishingMiniGame","GameGui","Fishing"}) do
        local g = pg:FindFirstChild(name)
        if g then return g end
    end
    for _, gui in ipairs(pg:GetChildren()) do
        if gui:IsA("ScreenGui") then
            if gui:FindFirstChild("ShakeFrame") or gui:FindFirstChild("ReelFrame")
            or gui:FindFirstChild("FishingFrame") or gui:FindFirstChild("MiniGameFrame") then
                return gui
            end
        end
    end
    return nil
end

-- VirtualInputManager helper
local VIM = game:GetService("VirtualInputManager")

local function PressKey(key)
    pcall(function()
        VIM:SendKeyEvent(true,  key, false, game)
        task.wait(0.05)
        VIM:SendKeyEvent(false, key, false, game)
    end)
end

-- Cast
local castCooldown = false
local function TryCast()
    if castCooldown then return end
    castCooldown = true
    FireRemote("Cast")
    FireRemote("CastRod")
    FireRemote("StartFishing")
    PressKey(Enum.KeyCode.E)
    task.delay(2.5, function() castCooldown = false end)
end

-- Shake (click / spacebar during minigame)
local function TryShake()
    FireRemote("Shake")
    FireRemote("ShakeInput")
    PressKey(Enum.KeyCode.Space)
    -- click GUI button
    local gui = GetFischGui()
    if gui then
        for _, btn in ipairs(gui:GetDescendants()) do
            if (btn:IsA("TextButton") or btn:IsA("ImageButton")) then
                pcall(function() btn.Activated:Fire() end)
                break
            end
        end
    end
end

-- Reel
local function TryReel()
    FireRemote("Reel")
    FireRemote("ReelFish")
    FireRemote("PullFish")
    PressKey(Enum.KeyCode.Space)
end

-- Sell All
local function SellAll()
    FireRemote("SellAll")
    FireRemote("SellFish")
    FireRemote("SellInventory")
    local r = WaitForRemote("Sell", 1)
    if r and r:IsA("RemoteFunction") then
        pcall(function() r:InvokeServer("all") end)
    end
end

-- Stat killer (Oxygen / Temperature / Pressure)
local function KillStat(name, maxVal)
    FireRemote("SetStat", name, maxVal)
    for _, obj in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
        if obj.Name:lower():find(name:lower()) then
            if obj:IsA("Frame") then
                pcall(function() obj.Size = UDim2.new(1,0, obj.Size.Y.Scale,0) end)
            elseif obj:IsA("TextLabel") then
                pcall(function() obj.Text = tostring(maxVal) end)
            end
        end
    end
    local char = LocalPlayer.Character
    if char then
        for _, v in ipairs(char:GetDescendants()) do
            if v.Name:lower():find(name:lower())
            and (v:IsA("NumberValue") or v:IsA("IntValue")) then
                pcall(function() v.Value = maxVal end)
            end
        end
    end
end

-- ── Heartbeat step counter
local hbAccum = 0

RunService.Heartbeat:Connect(function(dt)
    -- Auto Cast
    if State.AutoCast and not castCooldown then TryCast() end
    -- Auto Shake / Reel
    if State.AutoShake then TryShake() end
    if State.AutoReel  then TryReel()  end

    -- Instant Bobber
    if State.InstantBobber then
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") and obj.Name:lower():find("bobber") then
                local ow = obj.Parent:FindFirstChild("Owner")
                if ow and ow.Value == LocalPlayer.Name then
                    pcall(function() obj.Velocity = Vector3.new(0,-9999,0) end)
                end
            end
        end
    end

    -- Center Shake
    if State.CenterShake then
        local gui = GetFischGui()
        if gui then
            for _, obj in ipairs(gui:GetDescendants()) do
                local n = obj.Name:lower()
                if (n:find("indicator") or n:find("pointer") or n:find("cursor") or n:find("knob"))
                and obj:IsA("GuiObject") then
                    pcall(function()
                        obj.Position = UDim2.new(0.5, 0, obj.Position.Y.Scale, obj.Position.Y.Offset)
                    end)
                end
            end
        end
    end

    -- Progress bar mods
    if State.AlwaysProgressing or State.AntiProgressLoss then
        local gui = GetFischGui()
        if gui then
            for _, obj in ipairs(gui:GetDescendants()) do
                local n = obj.Name:lower()
                if (n:find("progress") or n:find("fill") or n:find("catch")) and obj:IsA("Frame") then
                    pcall(function()
                        if State.AlwaysProgressing then
                            obj.Size = UDim2.new(math.min(obj.Size.X.Scale+0.004, 1), 0, obj.Size.Y.Scale, 0)
                        end
                        if State.AntiProgressLoss then
                            if obj.Size.X.Scale > State.progressCache then
                                State.progressCache = obj.Size.X.Scale
                            else
                                obj.Size = UDim2.new(State.progressCache, 0, obj.Size.Y.Scale, 0)
                            end
                        end
                    end)
                end
            end
        end
    end

    -- Throttled (every 0.1s)
    hbAccum += dt
    if hbAccum >= 0.1 then
        hbAccum = 0

        if State.AntiOxygen      then KillStat("Oxygen",      100) end
        if State.AntiTemperature then KillStat("Temperature", 37)  end
        if State.AntiPressure    then KillStat("Pressure",    0)   end

        -- Super Boat
        if State.SuperBoat then
            for _, seat in ipairs(workspace:GetDescendants()) do
                if seat:IsA("VehicleSeat") then
                    local ow = seat.Parent:FindFirstChild("Owner") or seat.Parent:FindFirstChild("PlayerName")
                    if ow and ow.Value == LocalPlayer.Name then
                        pcall(function()
                            seat.MaxSpeed  = State.BoatSpeed
                            seat.Torque    = 10000
                            seat.TurnSpeed = 4
                        end)
                    end
                end
            end
        end

        -- Auto Sell timer
        if State.AutoSell then
            if (os.clock() - State.lastSellTime) >= (State.AutoSellDelay * 60) then
                State.lastSellTime = os.clock()
                SellAll()
                Fluent:Notify({ Title = "Auto Sell", Content = "Inventory dijual otomatis.", Duration = 2 })
            end
        end
    end
end)

-- Star Crater watcher
local lastStarNotif = 0
task.spawn(function()
    while task.wait(5) do
        local crater = workspace:FindFirstChild("StarCrater")
        if not crater then
            for _, obj in ipairs(workspace:GetChildren()) do
                if obj.Name:lower():find("crater") or obj.Name:lower():find("starfall") then
                    crater = obj; break
                end
            end
        end
        if crater then
            if State.AutoCollectStar then
                local cf = crater:IsA("Model") and pcall(function() return crater:GetPivot() end)
                        or (crater:IsA("BasePart") and crater.CFrame)
                local root = GetRoot()
                if root and cf then
                    if type(cf) == "userdata" then
                        root.CFrame = cf + Vector3.new(0, 3, 0)
                    end
                end
                FireRemote("CollectStarCrater")
                FireRemote("CollectCrater")
                FireRemote("GrabCrater")
            end
            if os.clock() - lastStarNotif > 30 then
                lastStarNotif = os.clock()
                Fluent:Notify({
                    Title    = "⭐ Star Crater!",
                    Content  = "Ditemukan! Auto Collect: " .. (State.AutoCollectStar and "ON" or "OFF"),
                    Duration = 5,
                })
            end
        end
    end
end)

-- Fish caught hook (sell on catch)
task.spawn(function()
    local catchRemote
    for _, name in ipairs({"FishCaught","CaughtFish","OnCatch","FishLanded"}) do
        catchRemote = WaitForRemote(name, 10)
        if catchRemote then break end
    end
    if catchRemote and catchRemote:IsA("RemoteEvent") then
        catchRemote.OnClientEvent:Connect(function()
            castCooldown = false
            State.progressCache = 0
            if State.SellOnCatch then
                task.wait(0.3)
                SellAll()
            end
        end)
    end
end)

-- ============================================================
--  Init
-- ============================================================
Window:SelectTab(1)

Fluent:Notify({
    Title    = "Fisch Script 2026",
    Content  = "Loaded! Tekan RightCtrl untuk toggle GUI.\nSupport: Tidefall · Scoria Reach · Lost Jungle",
    Duration = 6,
})

SaveManager:LoadAutoloadConfig()
