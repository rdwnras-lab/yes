-- ============================================================
--  Fisch Script | Fluent UI
--  GUI Library : https://github.com/dawid-scripts/Fluent
-- ============================================================

local Fluent        = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager   = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

-- ============================================================
--  Services
-- ============================================================
local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local TweenService   = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService    = game:GetService("HttpService")

local LocalPlayer   = Players.LocalPlayer
local Character     = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local RootPart      = Character:WaitForChild("HumanoidRootPart")

-- ============================================================
--  Helpers / Remotes
-- ============================================================
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)

local function GetRemote(name)
    if Remotes then
        return Remotes:FindFirstChild(name)
    end
    return nil
end

local function SafeFireServer(remoteName, ...)
    local remote = GetRemote(remoteName)
    if remote and remote:IsA("RemoteEvent") then
        remote:FireServer(...)
    end
end

local function SafeInvokeServer(remoteName, ...)
    local remote = GetRemote(remoteName)
    if remote and remote:IsA("RemoteFunction") then
        return remote:InvokeServer(...)
    end
end

-- ============================================================
--  State Table
-- ============================================================
local State = {
    -- Automation
    AutoCast            = false,
    AutoShake           = false,
    AutoReel            = false,
    -- Modification
    InstantBobber       = false,
    CenterShake         = false,
    AlwaysProgressing   = false,
    AntiProgressLoss    = false,
    -- Boat
    SuperBoat           = false,
    BoatSpeed           = 50,
    -- Selling
    SellOnCatch         = false,
    AutoSell            = false,
    AutoSellDelay       = 5,
    -- Starfall
    AutoCollectStar     = false,
    -- Miscellaneous
    ShowRadar           = false,
    AntiOxygen          = false,
    AntiTemperature     = false,
    AntiPressure        = false,
    -- Selected Items
    SelectedRod         = "None",
    SelectedCrate       = "None",
    SelectedTotem       = "None",
    BuyCrateAmount      = 1,
    BuyTotemAmount      = 1,
    SelectedTeleport    = "Spawn",
}

-- ============================================================
--  Game Constants / Lists
-- ============================================================
local RodList = {
    "Starter Rod",
    "Basic Rod",
    "Advanced Rod",
    "Pro Rod",
    "Expert Rod",
    "Master Rod",
    "Legendary Rod",
    "Ancient Rod",
    "Mythic Rod",
    "Celestial Rod",
}

local CrateList = {
    "Common Crate",
    "Uncommon Crate",
    "Rare Crate",
    "Epic Crate",
    "Legendary Crate",
    "Mythic Crate",
}

local TotemList = {
    "Luck Totem",
    "Speed Totem",
    "Rare Totem",
    "Double Totem",
    "Epic Totem",
    "Legendary Totem",
}

local TeleportLocations = {
    ["Spawn"]           = CFrame.new(0,   5,   0),
    ["Fishing Dock"]    = CFrame.new(120, 5,  50),
    ["Deep Ocean"]      = CFrame.new(500, 5, 200),
    ["Coral Reef"]      = CFrame.new(300, 5, -150),
    ["Sunken Ship"]     = CFrame.new(-400, 5, 300),
    ["Volcano Island"]  = CFrame.new(-200, 5, -400),
    ["Arctic Zone"]     = CFrame.new(700, 5, -300),
    ["Treasure Cave"]   = CFrame.new(-600, 5, 600),
    ["Mystic Lake"]     = CFrame.new(250, 5, 700),
    ["Star Crater"]     = CFrame.new(-100, 5, -600),
}

-- ============================================================
--  Window
-- ============================================================
local Window = Fluent:CreateWindow({
    Title    = "Fisch Script",
    SubTitle = "by Script Hub",
    TabWidth = 160,
    Size     = UDim2.fromOffset(600, 480),
    Acrylic  = true,
    Theme    = "Dark",
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

-- ── Automation Section ────────────────────────────────────────
Tabs.Fishing:AddSection({ Title = "Automation" })

-- Auto Cast
local AutoCastToggle = Tabs.Fishing:AddToggle("AutoCast", {
    Title       = "Auto Cast",
    Description = "Automatically casts your rod when idle.",
    Default     = false,
    Callback    = function(val)
        State.AutoCast = val
    end,
})

-- Auto Shake
local AutoShakeToggle = Tabs.Fishing:AddToggle("AutoShake", {
    Title       = "Auto Shake",
    Description = "Automatically handles the shake minigame.",
    Default     = false,
    Callback    = function(val)
        State.AutoShake = val
    end,
})

-- Auto Reel
local AutoReelToggle = Tabs.Fishing:AddToggle("AutoReel", {
    Title       = "Auto Reel",
    Description = "Automatically reels in the fish.",
    Default     = false,
    Callback    = function(val)
        State.AutoReel = val
    end,
})

-- ── Modification Section ──────────────────────────────────────
Tabs.Fishing:AddSection({ Title = "Modification" })

-- Instant Bobber
local InstantBobberToggle = Tabs.Fishing:AddToggle("InstantBobber", {
    Title       = "Instant Bobber",
    Description = "Makes the bobber land instantly after casting.",
    Default     = false,
    Callback    = function(val)
        State.InstantBobber = val
    end,
})

-- Center Shake
local CenterShakeToggle = Tabs.Fishing:AddToggle("CenterShake", {
    Title       = "Center Shake",
    Description = "Keeps the shake indicator centered at all times.",
    Default     = false,
    Callback    = function(val)
        State.CenterShake = val
    end,
})

-- Always Progressing
local AlwaysProgressingToggle = Tabs.Fishing:AddToggle("AlwaysProgressing", {
    Title       = "Always Progressing",
    Description = "Forces the catch progress bar to always move forward.",
    Default     = false,
    Callback    = function(val)
        State.AlwaysProgressing = val
    end,
})

-- Anti Progress Loss
local AntiProgressLossToggle = Tabs.Fishing:AddToggle("AntiProgressLoss", {
    Title       = "Anti Progress Loss",
    Description = "Prevents the catch progress from decreasing.",
    Default     = false,
    Callback    = function(val)
        State.AntiProgressLoss = val
    end,
})

-- ============================================================
--  UTILITIES TAB
-- ============================================================

-- ── Boat Section ──────────────────────────────────────────────
Tabs.Utilities:AddSection({ Title = "Boat" })

local SuperBoatToggle = Tabs.Utilities:AddToggle("SuperBoat", {
    Title       = "Super Boat",
    Description = "Massively boosts your boat's movement speed.",
    Default     = false,
    Callback    = function(val)
        State.SuperBoat = val
        -- Apply/remove boat speed
        local boat = workspace:FindFirstChild("Boat_" .. LocalPlayer.Name)
            or workspace:FindFirstChildWhichIsA("Model", true)
        if boat then
            local seat = boat:FindFirstChildOfClass("VehicleSeat")
                or boat:FindFirstChild("VehicleSeat")
            if seat then
                seat.MaxSpeed = val and State.BoatSpeed or 20
                seat.Torque   = val and 5000 or 1000
                seat.TurnSpeed = val and 3 or 1
            end
        end
    end,
})

Tabs.Utilities:AddSlider("BoatSpeed", {
    Title       = "Boat Speed",
    Description = "Set the super-boat speed multiplier.",
    Default     = 50,
    Min         = 20,
    Max         = 300,
    Rounding    = 0,
    Callback    = function(val)
        State.BoatSpeed = val
        if State.SuperBoat then
            local boat = workspace:FindFirstChild("Boat_" .. LocalPlayer.Name)
            if boat then
                local seat = boat:FindFirstChildOfClass("VehicleSeat")
                if seat then
                    seat.MaxSpeed = val
                end
            end
        end
    end,
})

-- ── Selling Section ───────────────────────────────────────────
Tabs.Utilities:AddSection({ Title = "Selling" })

local SellOnCatchToggle = Tabs.Utilities:AddToggle("SellOnCatch", {
    Title       = "Sell All On Fish Caught",
    Description = "Automatically sells all fish as soon as one is caught.",
    Default     = false,
    Callback    = function(val)
        State.SellOnCatch = val
    end,
})

Tabs.Utilities:AddSlider("AutoSellDelay", {
    Title       = "Auto Sell All Delay (Minutes)",
    Description = "How often (in minutes) to auto sell all inventory.",
    Default     = 5,
    Min         = 1,
    Max         = 30,
    Rounding    = 0,
    Callback    = function(val)
        State.AutoSellDelay = val
    end,
})

local AutoSellToggle = Tabs.Utilities:AddToggle("AutoSell", {
    Title       = "Auto Sell All",
    Description = "Sells all inventory on the configured delay.",
    Default     = false,
    Callback    = function(val)
        State.AutoSell = val
    end,
})

-- ── Starfall Section ──────────────────────────────────────────
Tabs.Utilities:AddSection({ Title = "Starfall" })

-- Star Crater status paragraph (updated dynamically)
local StarStatusParagraph = Tabs.Utilities:AddParagraph({
    Title   = "Star Crater Status",
    Content = "Checking...",
})

Tabs.Utilities:AddToggle("AutoCollectStar", {
    Title       = "Auto Collect Star Crater",
    Description = "Automatically collects star craters when they appear.",
    Default     = false,
    Callback    = function(val)
        State.AutoCollectStar = val
    end,
})

-- ── Rods Section ──────────────────────────────────────────────
Tabs.Utilities:AddSection({ Title = "Rods" })

local RodDropdown = Tabs.Utilities:AddDropdown("SelectRod", {
    Title       = "Select Rod",
    Description = "Choose which rod to purchase.",
    Values      = RodList,
    Multi       = false,
    Default     = 1,
    Callback    = function(val)
        State.SelectedRod = val
    end,
})

Tabs.Utilities:AddButton({
    Title       = "Purchase Selected Rod",
    Description = "Buy the rod chosen above.",
    Callback    = function()
        if State.SelectedRod ~= "None" then
            SafeFireServer("BuyRod", State.SelectedRod)
            Fluent:Notify({
                Title   = "Rod Purchased",
                Content = "Attempted to purchase: " .. State.SelectedRod,
                Duration = 3,
            })
        else
            Fluent:Notify({
                Title   = "No Rod Selected",
                Content = "Please select a rod first.",
                Duration = 3,
            })
        end
    end,
})

-- ── Crates Section ────────────────────────────────────────────
Tabs.Utilities:AddSection({ Title = "Crates" })

local CrateDropdown = Tabs.Utilities:AddDropdown("SelectCrate", {
    Title       = "Select Crate",
    Description = "Choose a crate to buy.",
    Values      = CrateList,
    Multi       = false,
    Default     = 1,
    Callback    = function(val)
        State.SelectedCrate = val
    end,
})

Tabs.Utilities:AddSlider("BuyCrateAmount", {
    Title       = "Buy Crate Amount",
    Description = "How many crates to purchase at once.",
    Default     = 1,
    Min         = 1,
    Max         = 100,
    Rounding    = 0,
    Callback    = function(val)
        State.BuyCrateAmount = val
    end,
})

Tabs.Utilities:AddButton({
    Title       = "Purchase Selected Crate",
    Description = "Buy the selected crate the set amount of times.",
    Callback    = function()
        if State.SelectedCrate ~= "None" then
            for i = 1, State.BuyCrateAmount do
                SafeFireServer("BuyCrate", State.SelectedCrate)
                task.wait(0.1)
            end
            Fluent:Notify({
                Title   = "Crate Purchased",
                Content = string.format("Bought %dx %s", State.BuyCrateAmount, State.SelectedCrate),
                Duration = 3,
            })
        end
    end,
})

-- ── Totems Section ────────────────────────────────────────────
Tabs.Utilities:AddSection({ Title = "Totems" })

local TotemDropdown = Tabs.Utilities:AddDropdown("SelectTotem", {
    Title       = "Select Totem",
    Description = "Choose a totem to purchase.",
    Values      = TotemList,
    Multi       = false,
    Default     = 1,
    Callback    = function(val)
        State.SelectedTotem = val
    end,
})

Tabs.Utilities:AddSlider("BuyTotemAmount", {
    Title       = "Buy Totem Amount",
    Description = "How many totems to purchase at once.",
    Default     = 1,
    Min         = 1,
    Max         = 50,
    Rounding    = 0,
    Callback    = function(val)
        State.BuyTotemAmount = val
    end,
})

Tabs.Utilities:AddButton({
    Title       = "Purchase Selected Totem",
    Description = "Buy the selected totem the set amount of times.",
    Callback    = function()
        if State.SelectedTotem ~= "None" then
            for i = 1, State.BuyTotemAmount do
                SafeFireServer("BuyTotem", State.SelectedTotem)
                task.wait(0.1)
            end
            Fluent:Notify({
                Title   = "Totem Purchased",
                Content = string.format("Bought %dx %s", State.BuyTotemAmount, State.SelectedTotem),
                Duration = 3,
            })
        end
    end,
})

-- ── Miscellaneous Section ─────────────────────────────────────
Tabs.Utilities:AddSection({ Title = "Miscellaneous" })

Tabs.Utilities:AddToggle("ShowRadar", {
    Title       = "Show Radar",
    Description = "Displays the fish radar on screen.",
    Default     = false,
    Callback    = function(val)
        State.ShowRadar = val
        local radarGui = LocalPlayer.PlayerGui:FindFirstChild("RadarGui")
        if radarGui then
            radarGui.Enabled = val
        end
        -- Try to enable via remote if GUI isn't client-side
        SafeFireServer("SetRadar", val)
    end,
})

Tabs.Utilities:AddToggle("AntiOxygen", {
    Title       = "Anti Oxygen",
    Description = "Prevents oxygen from depleting underwater.",
    Default     = false,
    Callback    = function(val)
        State.AntiOxygen = val
    end,
})

Tabs.Utilities:AddToggle("AntiTemperature", {
    Title       = "Anti Temperature",
    Description = "Prevents temperature damage in extreme zones.",
    Default     = false,
    Callback    = function(val)
        State.AntiTemperature = val
    end,
})

Tabs.Utilities:AddToggle("AntiPressure", {
    Title       = "Anti Pressure",
    Description = "Prevents pressure damage in deep water.",
    Default     = false,
    Callback    = function(val)
        State.AntiPressure = val
    end,
})

-- ============================================================
--  TELEPORTS TAB
-- ============================================================

local TeleportLocationNames = {}
for k in pairs(TeleportLocations) do
    table.insert(TeleportLocationNames, k)
end
table.sort(TeleportLocationNames)

Tabs.Teleports:AddSection({ Title = "Teleport" })

Tabs.Teleports:AddParagraph({
    Title   = "How to use",
    Content = "Select a destination from the dropdown below, then press the Teleport button. Make sure you are not in a fishing minigame.",
})

local TeleportDropdown = Tabs.Teleports:AddDropdown("TeleportLocation", {
    Title       = "Select Teleport Location",
    Description = "Pick a location to teleport to.",
    Values      = TeleportLocationNames,
    Multi       = false,
    Default     = 1,
    Callback    = function(val)
        State.SelectedTeleport = val
    end,
})

Tabs.Teleports:AddButton({
    Title       = "Teleport To Selected Location",
    Description = "Teleports your character to the chosen destination.",
    Callback    = function()
        local dest = TeleportLocations[State.SelectedTeleport]
        if dest then
            -- Refresh character reference
            Character = LocalPlayer.Character
            RootPart  = Character and Character:FindFirstChild("HumanoidRootPart")
            if RootPart then
                RootPart.CFrame = dest
                Fluent:Notify({
                    Title   = "Teleported",
                    Content = "Arrived at: " .. State.SelectedTeleport,
                    Duration = 3,
                })
            else
                Fluent:Notify({
                    Title   = "Teleport Failed",
                    Content = "Could not find character. Try again.",
                    Duration = 3,
                })
            end
        end
    end,
})

-- ============================================================
--  SETTINGS TAB
-- ============================================================
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
InterfaceManager:SetFolder("FischScript")
SaveManager:SetFolder("FischScript/configs")

InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

-- ============================================================
--  CORE LOGIC LOOPS
-- ============================================================

-- ── Fishing Logic ─────────────────────────────────────────────
local isCasting     = false
local lastSellTime  = os.clock()

-- Hook into fishing GUI events to detect game state
local function GetFishingGui()
    return LocalPlayer.PlayerGui:FindFirstChild("FishingGui")
        or LocalPlayer.PlayerGui:FindFirstChild("Fishing")
        or LocalPlayer.PlayerGui:FindFirstChildWhichIsA("ScreenGui")
end

local function GetFishingFrame(gui)
    if not gui then return nil end
    return gui:FindFirstChild("FishingFrame")
        or gui:FindFirstChild("MainFrame")
        or gui:FindFirstChild("GameFrame")
end

-- Main heartbeat loop
local mainConnection = RunService.Heartbeat:Connect(function(dt)
    -- Refresh character
    Character = LocalPlayer.Character
    if not Character then return end
    RootPart = Character:FindFirstChild("HumanoidRootPart")

    local fishGui   = GetFishingGui()
    local fishFrame = fishGui and GetFishingFrame(fishGui)

    -- ── Auto Cast ──────────────────────────────────────────────
    if State.AutoCast and not isCasting then
        local castRemote = GetRemote("Cast") or GetRemote("CastRod") or GetRemote("StartFishing")
        if castRemote and castRemote:IsA("RemoteEvent") then
            isCasting = true
            castRemote:FireServer()
            task.delay(2, function() isCasting = false end)
        end
    end

    -- ── Auto Shake ─────────────────────────────────────────────
    if State.AutoShake then
        local shakeRemote = GetRemote("Shake") or GetRemote("ShakeInput") or GetRemote("PressBobber")
        if shakeRemote and shakeRemote:IsA("RemoteEvent") then
            shakeRemote:FireServer()
        end
        -- Also try to click via UI
        if fishFrame then
            local shakeBtn = fishFrame:FindFirstChild("ShakeButton")
                or fishFrame:FindFirstChild("BobberButton")
                or fishFrame:FindFirstChildWhichIsA("TextButton")
            if shakeBtn and shakeBtn:IsA("TextButton") then
                local conn = shakeBtn.Activated
                if conn then
                    shakeBtn:Activate()
                end
            end
        end
    end

    -- ── Auto Reel ──────────────────────────────────────────────
    if State.AutoReel then
        local reelRemote = GetRemote("Reel") or GetRemote("ReelFish") or GetRemote("PullFish")
        if reelRemote and reelRemote:IsA("RemoteEvent") then
            reelRemote:FireServer()
        end
        if fishFrame then
            local reelBtn = fishFrame:FindFirstChild("ReelButton")
                or fishFrame:FindFirstChild("PullButton")
            if reelBtn then reelBtn:Activate() end
        end
    end

    -- ── Instant Bobber ─────────────────────────────────────────
    if State.InstantBobber then
        local bobber = workspace:FindFirstChild("Bobber_" .. LocalPlayer.Name)
            or workspace:FindFirstChildWhichIsA("Model")
        if bobber then
            local part = bobber:FindFirstChildOfClass("Part")
                or bobber:FindFirstChildOfClass("BasePart")
            if part then
                -- Snap to water surface
                part.Velocity = Vector3.new(0, -9999, 0)
            end
        end
    end

    -- ── Center Shake ───────────────────────────────────────────
    if State.CenterShake and fishFrame then
        local shakeBar  = fishFrame:FindFirstChild("ShakeBar")
            or fishFrame:FindFirstChild("ProgressBar")
        local indicator = shakeBar and (
            shakeBar:FindFirstChild("Indicator")
            or shakeBar:FindFirstChild("Pointer")
            or shakeBar:FindFirstChildOfClass("Frame")
        )
        if indicator and indicator:IsA("GuiObject") then
            indicator.Position = UDim2.new(0.5, 0, indicator.Position.Y.Scale, indicator.Position.Y.Offset)
        end
    end

    -- ── Always Progressing / Anti Progress Loss ─────────────────
    if (State.AlwaysProgressing or State.AntiProgressLoss) and fishFrame then
        local progressBar = fishFrame:FindFirstChild("Progress")
            or fishFrame:FindFirstChild("CatchProgress")
            or fishFrame:FindFirstChild("ProgressBar")
        if progressBar then
            local fill = progressBar:FindFirstChild("Fill")
                or progressBar:FindFirstChild("Bar")
            if fill and fill:IsA("Frame") then
                if State.AlwaysProgressing then
                    fill.Size = UDim2.new(
                        math.min(fill.Size.X.Scale + 0.005, 1),
                        0,
                        fill.Size.Y.Scale,
                        fill.Size.Y.Offset
                    )
                end
                if State.AntiProgressLoss then
                    -- Cache max and never go below it
                    if not fill._maxProgress or fill.Size.X.Scale > fill._maxProgress then
                        fill._maxProgress = fill.Size.X.Scale
                    else
                        fill.Size = UDim2.new(fill._maxProgress, 0, fill.Size.Y.Scale, fill.Size.Y.Offset)
                    end
                end
            end
        end
    end

    -- ── Anti Oxygen ────────────────────────────────────────────
    if State.AntiOxygen then
        local oxygenBar = LocalPlayer.PlayerGui:FindFirstChild("OxygenGui")
            or LocalPlayer.PlayerGui:FindFirstChildWhichIsA("ScreenGui")
        if oxygenBar then
            local fill = oxygenBar:FindFirstChild("Fill") or oxygenBar:FindFirstChildWhichIsA("Frame")
            if fill then fill.Size = UDim2.new(1, 0, fill.Size.Y.Scale, 0) end
        end
        -- Also fire keep-alive remote if it exists
        local oxyRemote = GetRemote("RefillOxygen") or GetRemote("OxygenRegen")
        if oxyRemote then oxyRemote:FireServer() end
    end

    -- ── Anti Temperature ───────────────────────────────────────
    if State.AntiTemperature then
        local tempRemote = GetRemote("SetTemperature") or GetRemote("Temperature")
        if tempRemote and tempRemote:IsA("RemoteEvent") then
            tempRemote:FireServer(37) -- normal body temp
        end
    end

    -- ── Anti Pressure ──────────────────────────────────────────
    if State.AntiPressure then
        local presRemote = GetRemote("SetPressure") or GetRemote("Pressure")
        if presRemote and presRemote:IsA("RemoteEvent") then
            presRemote:FireServer(0)
        end
    end

    -- ── Auto Sell (timer) ──────────────────────────────────────
    if State.AutoSell then
        local now = os.clock()
        if now - lastSellTime >= (State.AutoSellDelay * 60) then
            lastSellTime = now
            SafeFireServer("SellAll")
            SafeFireServer("SellFish")
            Fluent:Notify({
                Title   = "Auto Sell",
                Content = "Sold all fish inventory.",
                Duration = 2,
            })
        end
    end
end)

-- ── Fish Caught hook for Sell On Catch ────────────────────────
local catchConnection
do
    local catchRemote = GetRemote("FishCaught") or GetRemote("CaughtFish") or GetRemote("OnFishCaught")
    if catchRemote and catchRemote:IsA("RemoteEvent") then
        catchConnection = catchRemote.OnClientEvent:Connect(function()
            isCasting = false -- allow re-cast
            if State.SellOnCatch then
                task.wait(0.5)
                SafeFireServer("SellAll")
                SafeFireServer("SellFish")
            end
        end)
    end
end

-- ── Star Crater Detector ──────────────────────────────────────
local starConnection = RunService.Heartbeat:Connect(function()
    local crater = workspace:FindFirstChild("StarCrater")
        or workspace:FindFirstChildWhichIsA("Model", true)

    local exists = crater ~= nil
    if StarStatusParagraph then
        -- Update status (Fluent paragraph doesn't have a live setter, use notifications or re-create)
    end

    if State.AutoCollectStar and exists then
        -- Teleport to crater and collect
        local craterPart = crater:FindFirstChildOfClass("Part")
            or crater:FindFirstChildOfClass("BasePart")
        if craterPart and RootPart then
            RootPart.CFrame = craterPart.CFrame + Vector3.new(0, 3, 0)
        end
        SafeFireServer("CollectStarCrater")
        SafeFireServer("CollectCrater")
    end
end)

-- Periodic star crater status notification
task.spawn(function()
    while task.wait(10) do
        local crater = workspace:FindFirstChild("StarCrater")
        local status  = crater and "⭐ Star Crater: EXISTS" or "❌ Star Crater: Not Found"
        if State.AutoCollectStar or not crater then
            -- Silent background check — notification only if found
            if crater then
                Fluent:Notify({
                    Title   = "Star Crater Detected!",
                    Content = "Auto-collecting star crater...",
                    Duration = 4,
                })
            end
        end
    end
end)

-- ── Super Boat continuous update ──────────────────────────────
RunService.Heartbeat:Connect(function()
    if State.SuperBoat then
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("VehicleSeat") then
                local ownerVal = obj.Parent:FindFirstChild("Owner")
                if ownerVal and ownerVal.Value == LocalPlayer.Name then
                    obj.MaxSpeed  = State.BoatSpeed
                    obj.Torque    = 5000
                    obj.TurnSpeed = 3
                end
            end
        end
    end
end)

-- ============================================================
--  Notify on load
-- ============================================================
Fluent:Notify({
    Title   = "Fisch Script Loaded",
    Content = "Press RightCtrl to toggle the GUI.",
    Duration = 5,
})

-- ============================================================
--  Save / Load config on init
-- ============================================================
SaveManager:LoadAutoloadConfig()
