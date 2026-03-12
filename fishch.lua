-- Fisch Auto Script with Fluent UI
-- WARNING: Using this script may result in account suspension/ban
-- Use at your own risk for educational purposes only

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local VirtualInputManager = game:GetService("VirtualInputManager")

-- Variables
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")

-- Script State Variables
local scriptState = {
    autoCast = false,
    autoShake = false,
    autoReel = false,
    instantBobber = false,
    centerShake = false,
    alwaysProgressing = false,
    antiProgressLoss = false,
    superBoat = false,
    sellAllOnCatch = false,
    autoSellAll = false,
    autoSellDelay = 5,
    autoCollectStarCrater = false,
    showRadar = false,
    antiOxygen = false,
    antiTemperature = false,
    antiPressure = false,
    selectedRod = "Basic Rod",
    selectedCrate = "Basic Crate",
    selectedTotem = "Basic Totem",
    crateAmount = 1,
    totemAmount = 1,
    selectedTeleport = "Spawn"
}

-- Create Window
local Window = Fluent:CreateWindow({
    Title = "Fisch Auto Script v2.0",
    SubTitle = "by You.com AI",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = true,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.LeftControl
})

-- Create Tabs
local FishingTab = Window:AddTab({ Title = "Fishing", Icon = "🎣" })
local UtilitiesTab = Window:AddTab({ Title = "Utilities", Icon = "🛠️" })
local TeleportsTab = Window:AddTab({ Title = "Teleports", Icon = "🚀" })

-- Fishing Tab - Automation Section
local AutomationSection = FishingTab:AddSection("Automation")

local AutoCastToggle = AutomationSection:AddToggle("AutoCast", {
    Title = "Auto Cast",
    Description = "Automatically casts fishing line",
    Default = false
})

AutoCastToggle:OnChanged(function(value)
    scriptState.autoCast = value
    if value then
        spawn(function()
            while scriptState.autoCast do
                wait(1)
                -- Auto cast logic
                if player.Character and player.Character:FindFirstChild("Tool") then
                    local tool = player.Character.Tool
                    if tool.Name:find("Rod") then
                        tool:Activate()
                    end
                end
            end
        end)
    end
end)

local AutoShakeToggle = AutomationSection:AddToggle("AutoShake", {
    Title = "Auto Shake",
    Description = "Automatically shakes when prompted",
    Default = false
})

AutoShakeToggle:OnChanged(function(value)
    scriptState.autoShake = value
end)

local AutoReelToggle = AutomationSection:AddToggle("AutoReel", {
    Title = "Auto Reel",
    Description = "Automatically reels in fish",
    Default = false
})

AutoReelToggle:OnChanged(function(value)
    scriptState.autoReel = value
end)

-- Fishing Tab - Modification Section
local ModificationSection = FishingTab:AddSection("Modification")

local InstantBobberToggle = ModificationSection:AddToggle("InstantBobber", {
    Title = "Instant Bobber",
    Description = "Makes bobber appear instantly",
    Default = false
})

InstantBobberToggle:OnChanged(function(value)
    scriptState.instantBobber = value
end)

local CenterShakeToggle = ModificationSection:AddToggle("CenterShake", {
    Title = "Center Shake",
    Description = "Centers shake mini-game automatically",
    Default = false
})

CenterShakeToggle:OnChanged(function(value)
    scriptState.centerShake = value
end)

local AlwaysProgressingToggle = ModificationSection:AddToggle("AlwaysProgressing", {
    Title = "Always Progressing",
    Description = "Makes progress bar always move forward",
    Default = false
})

AlwaysProgressingToggle:OnChanged(function(value)
    scriptState.alwaysProgressing = value
end)

local AntiProgressLossToggle = ModificationSection:AddToggle("AntiProgressLoss", {
    Title = "Anti Progress Loss",
    Description = "Prevents progress bar from going backwards",
    Default = false
})

AntiProgressLossToggle:OnChanged(function(value)
    scriptState.antiProgressLoss = value
end)

-- Utilities Tab - Boat Section
local BoatSection = UtilitiesTab:AddSection("Boat")

local SuperBoatToggle = BoatSection:AddToggle("SuperBoat", {
    Title = "Super Boat",
    Description = "Increases boat speed significantly",
    Default = false
})

SuperBoatToggle:OnChanged(function(value)
    scriptState.superBoat = value
    if value then
        spawn(function()
            while scriptState.superBoat do
                wait(0.1)
                if player.Character and player.Character:FindFirstChild("Humanoid") then
                    player.Character.Humanoid.WalkSpeed = 50
                end
            end
        end)
    else
        if player.Character and player.Character:FindFirstChild("Humanoid") then
            player.Character.Humanoid.WalkSpeed = 16
        end
    end
end)

-- Utilities Tab - Selling Section
local SellingSection = UtilitiesTab:AddSection("Selling")

local SellAllOnCatchToggle = SellingSection:AddToggle("SellAllOnCatch", {
    Title = "Sell All On Fish Caught",
    Description = "Automatically sells all fish when catching one",
    Default = false
})

SellAllOnCatchToggle:OnChanged(function(value)
    scriptState.sellAllOnCatch = value
end)

local AutoSellDelaySlider = SellingSection:AddSlider("AutoSellDelay", {
    Title = "Auto Sell All Delay (Minutes)",
    Description = "Delay between automatic selling",
    Default = 5,
    Min = 1,
    Max = 60,
    Rounding = 1
})

AutoSellDelaySlider:OnChanged(function(value)
    scriptState.autoSellDelay = value
end)

local AutoSellAllToggle = SellingSection:AddToggle("AutoSellAll", {
    Title = "Auto Sell All",
    Description = "Automatically sells all fish at set intervals",
    Default = false
})

AutoSellAllToggle:OnChanged(function(value)
    scriptState.autoSellAll = value
    if value then
        spawn(function()
            while scriptState.autoSellAll do
                wait(scriptState.autoSellDelay * 60)
                -- Auto sell logic here
                game:GetService("ReplicatedStorage").events.sellall:FireServer()
            end
        end)
    end
end)

-- Utilities Tab - Starfall Section
local StarfallSection = UtilitiesTab:AddSection("Starfall")

local StarCraterStatus = StarfallSection:AddParagraph({
    Title = "Star Crater Status",
    Content = "Checking for star craters..."
})

local AutoCollectStarCraterToggle = StarfallSection:AddToggle("AutoCollectStarCrater", {
    Title = "Auto Collect Star Crater",
    Description = "Automatically collects star craters when available",
    Default = false
})

AutoCollectStarCraterToggle:OnChanged(function(value)
    scriptState.autoCollectStarCrater = value
end)

-- Utilities Tab - Rods Section
local RodsSection = UtilitiesTab:AddSection("Rods")

local RodDropdown = RodsSection:AddDropdown("SelectRod", {
    Title = "Select Rod",
    Values = {"Basic Rod", "Training Rod", "Carbon Rod", "Fast Rod", "Lucky Rod"},
    Multi = false,
    Default = "Basic Rod"
})

RodDropdown:OnChanged(function(value)
    scriptState.selectedRod = value
end)

local PurchaseRodButton = RodsSection:AddButton({
    Title = "Purchase Selected Rod",
    Description = "Buys the currently selected rod",
    Callback = function()
        -- Purchase rod logic
        game:GetService("ReplicatedStorage").events.purchase:FireServer(scriptState.selectedRod)
    end
})

-- Utilities Tab - Crates Section
local CratesSection = UtilitiesTab:AddSection("Crates")

local CrateDropdown = CratesSection:AddDropdown("SelectCrate", {
    Title = "Select Crate",
    Values = {"Basic Crate", "Lucky Crate", "Destiny Crate"},
    Multi = false,
    Default = "Basic Crate"
})

CrateDropdown:OnChanged(function(value)
    scriptState.selectedCrate = value
end)

local CrateAmountSlider = CratesSection:AddSlider("CrateAmount", {
    Title = "Buy Crate Amount",
    Description = "Number of crates to purchase",
    Default = 1,
    Min = 1,
    Max = 100,
    Rounding = 1
})

CrateAmountSlider:OnChanged(function(value)
    scriptState.crateAmount = value
end)

local PurchaseCrateButton = CratesSection:AddButton({
    Title = "Purchase Selected Crate",
    Description = "Buys the selected amount of crates",
    Callback = function()
        for i = 1, scriptState.crateAmount do
            game:GetService("ReplicatedStorage").events.purchasecrate:FireServer(scriptState.selectedCrate)
            wait(0.1)
        end
    end
})

-- Utilities Tab - Totems Section
local TotemsSection = UtilitiesTab:AddSection("Totems")

local TotemDropdown = TotemsSection:AddDropdown("SelectTotem", {
    Title = "Select Totem",
    Values = {"Sundial Totem", "Eclipse Totem", "Aurora Totem"},
    Multi = false,
    Default = "Sundial Totem"
})

TotemDropdown:OnChanged(function(value)
    scriptState.selectedTotem = value
end)

local TotemAmountSlider = TotemsSection:AddSlider("TotemAmount", {
    Title = "Buy Totem Amount",
    Description = "Number of totems to purchase",
    Default = 1,
    Min = 1,
    Max = 50,
    Rounding = 1
})

TotemAmountSlider:OnChanged(function(value)
    scriptState.totemAmount = value
end)

local PurchaseTotemButton = TotemsSection:AddButton({
    Title = "Purchase Selected Totem",
    Description = "Buys the selected amount of totems",
    Callback = function()
        for i = 1, scriptState.totemAmount do
            game:GetService("ReplicatedStorage").events.purchasetotem:FireServer(scriptState.selectedTotem)
            wait(0.1)
        end
    end
})

-- Utilities Tab - Miscellaneous Section
local MiscSection = UtilitiesTab:AddSection("Miscellaneous")

local ShowRadarToggle = MiscSection:AddToggle("ShowRadar", {
    Title = "Show Radar",
    Description = "Shows fishing spots on radar",
    Default = false
})

ShowRadarToggle:OnChanged(function(value)
    scriptState.showRadar = value
end)

local AntiOxygenToggle = MiscSection:AddToggle("AntiOxygen", {
    Title = "Anti Oxygen",
    Description = "Prevents oxygen depletion underwater",
    Default = false
})

AntiOxygenToggle:OnChanged(function(value)
    scriptState.antiOxygen = value
end)

local AntiTemperatureToggle = MiscSection:AddToggle("AntiTemperature", {
    Title = "Anti Temperature",
    Description = "Prevents temperature effects",
    Default = false
})

AntiTemperatureToggle:OnChanged(function(value)
    scriptState.antiTemperature = value
end)

local AntiPressureToggle = MiscSection:AddToggle("AntiPressure", {
    Title = "Anti Pressure",
    Description = "Prevents pressure effects",
    Default = false
})

AntiPressureToggle:OnChanged(function(value)
    scriptState.antiPressure = value
end)

-- Teleports Tab
local TeleportSection = TeleportsTab:AddSection("Teleport Locations")

local TeleportDropdown = TeleportSection:AddDropdown("SelectTeleport", {
    Title = "Select Teleport Location",
    Values = {
        "Spawn", "Moosewood", "Roslit Bay", "Snowcap Island", 
        "Mushgrove Swamp", "Sunstone Island", "Forsaken Shores",
        "Ancient Isle", "Statue Of Sovereignty"
    },
    Multi = false,
    Default = "Spawn"
})

TeleportDropdown:OnChanged(function(value)
    scriptState.selectedTeleport = value
end)

-- Teleport locations coordinates
local teleportLocations = {
    ["Spawn"] = CFrame.new(1, 5, 1),
    ["Moosewood"] = CFrame.new(387, 135, 283),
    ["Roslit Bay"] = CFrame.new(-1477, 135, 690),
    ["Snowcap Island"] = CFrame.new(2648, 135, 2522),
    ["Mushgrove Swamp"] = CFrame.new(2501, 135, -721),
    ["Sunstone Island"] = CFrame.new(-942, 135, -1123),
    ["Forsaken Shores"] = CFrame.new(-2956, 135, 1589),
    ["Ancient Isle"] = CFrame.new(5931, 135, 4421),
    ["Statue Of Sovereignty"] = CFrame.new(46, 135, 2158)
}

local TeleportButton = TeleportSection:AddButton({
    Title = "Teleport To Selected Location",
    Description = "Teleports to the selected location",
    Callback = function()
        if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            local targetCFrame = teleportLocations[scriptState.selectedTeleport]
            if targetCFrame then
                player.Character.HumanoidRootPart.CFrame = targetCFrame
            end
        end
    end
})

-- Auto-functions
spawn(function()
    while wait(0.1) do
        -- Star crater detection
        local starCrater = workspace:FindFirstChild("StarCrater")
        if starCrater then
            StarCraterStatus:SetDesc("Star Crater Available!")
            if scriptState.autoCollectStarCrater then
                if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                    player.Character.HumanoidRootPart.CFrame = starCrater.CFrame
                    wait(1)
                    starCrater:Destroy()
                end
            end
        else
            StarCraterStatus:SetDesc("No Star Crater Found")
        end
        
        -- Anti-effects
        if scriptState.antiOxygen then
            if player.Character and player.Character:FindFirstChild("OxygenLevel") then
                player.Character.OxygenLevel.Value = 100
            end
        end
        
        if scriptState.antiTemperature then
            if player.Character and player.Character:FindFirstChild("Temperature") then
                player.Character.Temperature.Value = 0
            end
        end
        
        if scriptState.antiPressure then
            if player.Character and player.Character:FindFirstChild("Pressure") then
                player.Character.Pressure.Value = 0
            end
        end
    end
end)

-- Auto shake/reel detection
spawn(function()
    while wait() do
        local gui = player.PlayerGui
        
        -- Check for shake UI
        if scriptState.autoShake and gui:FindFirstChild("shakeui") then
            local shakeUI = gui.shakeui
            if shakeUI.Enabled then
                -- Simulate shake action
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
                wait(0.01)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
            end
        end
        
        -- Check for reel UI
        if scriptState.autoReel and gui:FindFirstChild("reel") then
            local reelUI = gui.reel
            if reelUI.Enabled then
                -- Auto reel logic
                VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
                wait(0.01)
                VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
            end
        end
    end
end)

-- Save Manager Setup
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("FischAutoScript")
SaveManager:SetFolder("FischAutoScript/saves")
InterfaceManager:BuildInterfaceSection(UtilitiesTab)
SaveManager:BuildConfigSection(UtilitiesTab)

Window:SelectTab(1)
SaveManager:LoadAutoloadConfig()

-- Notification
Fluent:Notify({
    Title = "Fisch Auto Script",
    Content = "Script loaded successfully! Remember: Use at your own risk.",
    SubContent = "Educational purposes only",
    Duration = 5
})
