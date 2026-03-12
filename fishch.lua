-- Craft A World Auto Script with Fluent UI
-- Game: Craft A World (Roblox) - Growtopia-inspired 2D Sandbox MMO
-- WARNING: Using this script may result in account suspension/ban
-- Use at your own risk for educational purposes only

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

-- Variables
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local hrp = character:WaitForChild("HumanoidRootPart")

-- Re-reference on character respawn
player.CharacterAdded:Connect(function(char)
    character = char
    humanoid = char:WaitForChild("Humanoid")
    hrp = char:WaitForChild("HumanoidRootPart")
end)

-- Script State
local scriptState = {
    -- Farming
    autoBreak = false,
    autoPlace = false,
    autoPlant = false,
    autoCollectDrops = false,
    farmDelay = 0.1,
    breakOffsetX = 0,
    breakOffsetY = 0,
    placeOffsetX = 0,
    placeOffsetY = 1,
    selectedBlock = "Dirt",
    selectedSapling = "Dirt Sapling",

    -- Crafting
    autoCraft = false,
    craftIngredient1 = "Dirt",
    craftIngredient2 = "Water",
    craftAmount = 1,
    craftDelay = 0.5,

    -- Player
    walkSpeed = 16,
    jumpPower = 50,
    noClip = false,
    infiniteJump = false,
    antiKick = false,
    autoRespawn = false,

    -- ESP
    blockESP = false,
    playerESP = false,
    dropESP = false,
    espFillColor = Color3.fromRGB(255, 0, 0),
    espTextColor = Color3.fromRGB(255, 255, 255),

    -- Gems
    autoGemFarm = false,
    gemFarmDelay = 0.3,

    -- Misc
    showStatus = true,
    selectedWorld = "",
}

-- ==============================
-- CREATE WINDOW
-- ==============================
local Window = Fluent:CreateWindow({
    Title = "Craft A World Script v1.0",
    SubTitle = "Sandbox MMO Automation",
    TabWidth = 160,
    Size = UDim2.fromOffset(600, 480),
    Acrylic = true,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

-- ==============================
-- TABS
-- ==============================
local FarmingTab   = Window:AddTab({ Title = "Farming",   Icon = "🌱" })
local CraftingTab  = Window:AddTab({ Title = "Crafting",  Icon = "⚒️" })
local PlayerTab    = Window:AddTab({ Title = "Player",    Icon = "🧍" })
local ESPTab       = Window:AddTab({ Title = "ESP",       Icon = "👁️" })
local WorldTab     = Window:AddTab({ Title = "World",     Icon = "🌍" })
local MiscTab      = Window:AddTab({ Title = "Misc",      Icon = "⚙️" })

-- ==============================
-- FARMING TAB
-- ==============================

-- Status Info
local FarmStatusSection = FarmingTab:AddSection("Status")
local FarmStatusParagraph = FarmStatusSection:AddParagraph({
    Title = "Farm Status",
    Content = "Idle - No automation running"
})

-- Auto Break
local AutoBreakSection = FarmingTab:AddSection("Auto Break (Punch Blocks)")

local AutoBreakToggle = AutoBreakSection:AddToggle("AutoBreak", {
    Title = "Auto Break Blocks",
    Description = "Automatically punches/breaks blocks to collect saplings & gems",
    Default = false
})
AutoBreakToggle:OnChanged(function(v)
    scriptState.autoBreak = v
    FarmStatusParagraph:SetDesc(v and "Auto Break is ACTIVE" or "Idle")
end)

local BreakOffsetXSlider = AutoBreakSection:AddSlider("BreakOffsetX", {
    Title = "Break Target Offset X",
    Description = "Horizontal offset from player position to break block",
    Default = 0, Min = -10, Max = 10, Rounding = 1
})
BreakOffsetXSlider:OnChanged(function(v) scriptState.breakOffsetX = v end)

local BreakOffsetYSlider = AutoBreakSection:AddSlider("BreakOffsetY", {
    Title = "Break Target Offset Y",
    Description = "Vertical offset from player position to break block",
    Default = 0, Min = -5, Max = 5, Rounding = 1
})
BreakOffsetYSlider:OnChanged(function(v) scriptState.breakOffsetY = v end)

-- Auto Place
local AutoPlaceSection = FarmingTab:AddSection("Auto Place (Build Blocks)")

local BlockDropdown = AutoPlaceSection:AddDropdown("SelectBlock", {
    Title = "Select Block to Place",
    Values = {
        "Dirt", "Grass", "Stone", "Sand", "Lava", "Water",
        "Wooden Block", "Wooden BG", "Concrete", "Glass Pane",
        "Blue Block", "Red Block", "Green Block", "Yellow Block",
        "Dark Block", "White Block", "Purple Block", "Pink Block",
        "Orange Block", "Cyan Block"
    },
    Multi = false,
    Default = "Dirt"
})
BlockDropdown:OnChanged(function(v) scriptState.selectedBlock = v end)

local AutoPlaceToggle = AutoPlaceSection:AddToggle("AutoPlace", {
    Title = "Auto Place Blocks",
    Description = "Automatically places selected block at offset position",
    Default = false
})
AutoPlaceToggle:OnChanged(function(v) scriptState.autoPlace = v end)

local PlaceOffsetXSlider = AutoPlaceSection:AddSlider("PlaceOffsetX", {
    Title = "Place Target Offset X",
    Description = "Horizontal offset for block placement",
    Default = 0, Min = -10, Max = 10, Rounding = 1
})
PlaceOffsetXSlider:OnChanged(function(v) scriptState.placeOffsetX = v end)

local PlaceOffsetYSlider = AutoPlaceSection:AddSlider("PlaceOffsetY", {
    Title = "Place Target Offset Y",
    Description = "Vertical offset for block placement",
    Default = 1, Min = -5, Max = 5, Rounding = 1
})
PlaceOffsetYSlider:OnChanged(function(v) scriptState.placeOffsetY = v end)

-- Auto Plant Sapling
local AutoPlantSection = FarmingTab:AddSection("Auto Plant Sapling")

local SaplingDropdown = AutoPlantSection:AddDropdown("SelectSapling", {
    Title = "Select Sapling to Plant",
    Values = {
        "Dirt Sapling", "Grass Sapling", "Stone Sapling", "Sand Sapling",
        "Lava Sapling", "Water Sapling", "Tree Sapling", "Flower Sapling",
        "Mushroom Sapling", "Cactus Sapling", "Sunflower Sapling",
        "Blue Sapling", "Purple Sapling", "Crystal Sapling"
    },
    Multi = false,
    Default = "Dirt Sapling"
})
SaplingDropdown:OnChanged(function(v) scriptState.selectedSapling = v end)

local AutoPlantToggle = AutoPlantSection:AddToggle("AutoPlant", {
    Title = "Auto Plant Sapling",
    Description = "Automatically plants selected sapling on empty tiles",
    Default = false
})
AutoPlantToggle:OnChanged(function(v) scriptState.autoPlant = v end)

-- Auto Collect Drops
local AutoCollectSection = FarmingTab:AddSection("Auto Collect")

local AutoCollectToggle = AutoCollectSection:AddToggle("AutoCollect", {
    Title = "Auto Collect Item Drops",
    Description = "Automatically walks to and collects item drops on the ground",
    Default = false
})
AutoCollectToggle:OnChanged(function(v) scriptState.autoCollectDrops = v end)

local AutoGemFarmToggle = AutoCollectSection:AddToggle("AutoGemFarm", {
    Title = "Auto Gem Farm",
    Description = "Breaks blocks in sequence to maximize gem collection",
    Default = false
})
AutoGemFarmToggle:OnChanged(function(v) scriptState.autoGemFarm = v end)

local FarmDelaySlider = AutoCollectSection:AddSlider("FarmDelay", {
    Title = "Farm Action Delay (seconds)",
    Description = "Delay between each automated farm action",
    Default = 0.1, Min = 0.05, Max = 2.0, Rounding = 2
})
FarmDelaySlider:OnChanged(function(v) scriptState.farmDelay = v end)

-- ==============================
-- CRAFTING TAB
-- ==============================

local CraftInfoSection = CraftingTab:AddSection("Craft Info")
local CraftStatusPara = CraftInfoSection:AddParagraph({
    Title = "Craft A World - Crafting Info",
    Content = "Every recipe uses exactly 2 ingredients.\nStand near a Crafting Station to craft items."
})

local AutoCraftSection = CraftingTab:AddSection("Auto Craft")

local CraftIngredient1Dropdown = AutoCraftSection:AddDropdown("CraftIngredient1", {
    Title = "Ingredient 1",
    Values = {
        "Dirt", "Grass", "Stone", "Sand", "Lava", "Water", "Seed",
        "Wooden Block", "Wooden BG", "Concrete", "Glass Pane",
        "Blue", "Red", "Green", "Yellow", "Dark", "White", "Purple",
        "Sunflower", "Cactus", "Mushroom", "Crystal", "Coal", "Iron",
        "Gold", "Diamond"
    },
    Multi = false,
    Default = "Dirt"
})
CraftIngredient1Dropdown:OnChanged(function(v) scriptState.craftIngredient1 = v end)

local CraftIngredient2Dropdown = AutoCraftSection:AddDropdown("CraftIngredient2", {
    Title = "Ingredient 2",
    Values = {
        "Dirt", "Grass", "Stone", "Sand", "Lava", "Water", "Seed",
        "Wooden Block", "Wooden BG", "Concrete", "Glass Pane",
        "Blue", "Red", "Green", "Yellow", "Dark", "White", "Purple",
        "Sunflower", "Cactus", "Mushroom", "Crystal", "Coal", "Iron",
        "Gold", "Diamond"
    },
    Multi = false,
    Default = "Water"
})
CraftIngredient2Dropdown:OnChanged(function(v) scriptState.craftIngredient2 = v end)

local CraftAmountSlider = AutoCraftSection:AddSlider("CraftAmount", {
    Title = "Craft Amount",
    Description = "How many times to craft the recipe",
    Default = 1, Min = 1, Max = 999, Rounding = 1
})
CraftAmountSlider:OnChanged(function(v) scriptState.craftAmount = v end)

local CraftDelaySlider = AutoCraftSection:AddSlider("CraftDelay", {
    Title = "Craft Delay (seconds)",
    Description = "Delay between each craft action",
    Default = 0.5, Min = 0.1, Max = 3.0, Rounding = 1
})
CraftDelaySlider:OnChanged(function(v) scriptState.craftDelay = v end)

local AutoCraftToggle = AutoCraftSection:AddToggle("AutoCraft", {
    Title = "Auto Craft",
    Description = "Automatically crafts the selected recipe",
    Default = false
})
AutoCraftToggle:OnChanged(function(v) scriptState.autoCraft = v end)

local CraftOnceButton = AutoCraftSection:AddButton({
    Title = "Craft Once Now",
    Description = "Craft the selected recipe one time immediately",
    Callback = function()
        local remote = ReplicatedStorage:FindFirstChild("events") and ReplicatedStorage.events:FindFirstChild("craft")
        if remote then
            remote:FireServer(scriptState.craftIngredient1, scriptState.craftIngredient2)
        end
        Fluent:Notify({ Title = "Craft A World", Content = "Craft action sent!", Duration = 2 })
    end
})

-- Recipe Reference Section
local RecipeRefSection = CraftingTab:AddSection("Common Recipes Reference")
local RecipePara = RecipeRefSection:AddParagraph({
    Title = "Key Recipes",
    Content = [[
Concrete = Stone + Sand
Glass Pane = Sand + Lava
Wooden Block = Tree + Tree
Wooden BG = Wooden Block + Wooden Block
Sunflower = Flower + Flower
Door = Wooden Block + Concrete
Fence = Wooden Block + Stone
Ladder = Wooden Block + Rope
Chest = Wooden Block + Iron
Torch = Wooden Block + Coal
Lantern = Glass Pane + Coal
Tesla Coil = Crystal + Iron
Small Lock = Iron + Gold (100 Gems)
    ]]
})

-- ==============================
-- PLAYER TAB
-- ==============================

local SpeedSection = PlayerTab:AddSection("Movement")

local WalkSpeedSlider = SpeedSection:AddSlider("WalkSpeed", {
    Title = "Walk Speed",
    Description = "Player movement speed (default: 16)",
    Default = 16, Min = 1, Max = 200, Rounding = 1
})
WalkSpeedSlider:OnChanged(function(v)
    scriptState.walkSpeed = v
    if character and humanoid then
        humanoid.WalkSpeed = v
    end
end)

local JumpPowerSlider = SpeedSection:AddSlider("JumpPower", {
    Title = "Jump Power",
    Description = "Player jump height (default: 50)",
    Default = 50, Min = 1, Max = 500, Rounding = 1
})
JumpPowerSlider:OnChanged(function(v)
    scriptState.jumpPower = v
    if character and humanoid then
        humanoid.JumpPower = v
    end
end)

local ResetSpeedButton = SpeedSection:AddButton({
    Title = "Reset Speed & Jump to Default",
    Description = "Returns walk speed and jump power to normal",
    Callback = function()
        if character and humanoid then
            humanoid.WalkSpeed = 16
            humanoid.JumpPower = 50
            scriptState.walkSpeed = 16
            scriptState.jumpPower = 50
        end
        Fluent:Notify({ Title = "Player", Content = "Speed reset to default!", Duration = 2 })
    end
})

local AbilitiesSection = PlayerTab:AddSection("Abilities")

local InfiniteJumpToggle = AbilitiesSection:AddToggle("InfiniteJump", {
    Title = "Infinite Jump",
    Description = "Jump again in mid-air repeatedly",
    Default = false
})
InfiniteJumpToggle:OnChanged(function(v)
    scriptState.infiniteJump = v
end)

local NoClipToggle = AbilitiesSection:AddToggle("NoClip", {
    Title = "No Clip",
    Description = "Walk through walls and blocks",
    Default = false
})
NoClipToggle:OnChanged(function(v)
    scriptState.noClip = v
    if not v then
        -- Re-enable collision on all parts
        if character then
            for _, part in ipairs(character:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = true
                end
            end
        end
    end
end)

local AntiKickToggle = AbilitiesSection:AddToggle("AntiKick", {
    Title = "Anti Kick / Anti AFK",
    Description = "Prevents being kicked for inactivity",
    Default = false
})
AntiKickToggle:OnChanged(function(v)
    scriptState.antiKick = v
end)

local AutoRespawnToggle = AbilitiesSection:AddToggle("AutoRespawn", {
    Title = "Auto Respawn",
    Description = "Automatically respawns if character dies",
    Default = false
})
AutoRespawnToggle:OnChanged(function(v) scriptState.autoRespawn = v end)

local PlayerInfoSection = PlayerTab:AddSection("Player Info")
local PlayerInfoPara = PlayerInfoSection:AddParagraph({
    Title = "Your Info",
    Content = "Name: " .. player.Name .. "\nDisplay: " .. player.DisplayName .. "\nWorld: Loading..."
})

-- ==============================
-- ESP TAB
-- ==============================

local ESPBlockSection = ESPTab:AddSection("Block & Drop ESP")

local BlockESPToggle = ESPBlockSection:AddToggle("BlockESP", {
    Title = "Rare Block ESP",
    Description = "Highlights rare/valuable blocks through walls with boxes",
    Default = false
})
BlockESPToggle:OnChanged(function(v)
    scriptState.blockESP = v
    if not v then
        -- Remove existing ESP labels
        for _, label in ipairs(Workspace:GetDescendants()) do
            if label.Name == "CAW_BlockESP" then label:Destroy() end
        end
    end
end)

local DropESPToggle = ESPBlockSection:AddToggle("DropESP", {
    Title = "Item Drop ESP",
    Description = "Shows dropped items on the ground with labels",
    Default = false
})
DropESPToggle:OnChanged(function(v)
    scriptState.dropESP = v
    if not v then
        for _, label in ipairs(Workspace:GetDescendants()) do
            if label.Name == "CAW_DropESP" then label:Destroy() end
        end
    end
end)

local PlayerESPSection = ESPTab:AddSection("Player ESP")

local PlayerESPToggle = PlayerESPSection:AddToggle("PlayerESP", {
    Title = "Player ESP",
    Description = "Shows all players through walls with name labels",
    Default = false
})
PlayerESPToggle:OnChanged(function(v)
    scriptState.playerESP = v
    if not v then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= player and plr.Character then
                local existing = plr.Character:FindFirstChild("CAW_PlayerESP")
                if existing then existing:Destroy() end
            end
        end
    end
end)

-- ESP helper function
local function createBillboard(parent, text, name, color)
    local existing = parent:FindFirstChild(name)
    if existing then existing:Destroy() end

    local bb = Instance.new("BillboardGui")
    bb.Name = name
    bb.AlwaysOnTop = true
    bb.Size = UDim2.new(0, 100, 0, 40)
    bb.StudsOffset = Vector3.new(0, 3, 0)
    bb.Parent = parent

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.TextColor3 = color or Color3.fromRGB(255, 255, 255)
    label.TextStrokeTransparency = 0
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Text = text
    label.Parent = bb

    return bb
end

-- ==============================
-- WORLD TAB
-- ==============================

local WorldNavSection = WorldTab:AddSection("World Navigation")

local WorldNameInput = WorldNavSection:AddInput("WorldName", {
    Title = "Enter World Name",
    Description = "Type the world name to navigate (e.g. PlayerNameRBX)",
    Default = "",
    Placeholder = "PlayerNameRBX"
})
WorldNameInput:OnChanged(function(v) scriptState.selectedWorld = v end)

local GoToWorldButton = WorldNavSection:AddButton({
    Title = "Go To World",
    Description = "Attempts to navigate to the entered world name",
    Callback = function()
        if scriptState.selectedWorld == "" then
            Fluent:Notify({ Title = "World", Content = "Please enter a world name first!", Duration = 3 })
            return
        end
        local remote = ReplicatedStorage:FindFirstChild("events") and ReplicatedStorage.events:FindFirstChild("joinWorld")
        if remote then
            remote:FireServer(scriptState.selectedWorld)
            Fluent:Notify({ Title = "World", Content = "Joining: " .. scriptState.selectedWorld, Duration = 3 })
        else
            -- Attempt via RemoteFunction
            local rf = ReplicatedStorage:FindFirstChild("functions") and ReplicatedStorage.functions:FindFirstChild("joinWorld")
            if rf then
                rf:InvokeServer(scriptState.selectedWorld)
                Fluent:Notify({ Title = "World", Content = "Joining: " .. scriptState.selectedWorld, Duration = 3 })
            else
                Fluent:Notify({ Title = "World", Content = "Could not find join world remote. Try manually.", Duration = 4 })
            end
        end
    end
})

local QuickWorldsSection = WorldTab:AddSection("Quick Join - Famous Worlds")

local FamousWorldDropdown = QuickWorldsSection:AddDropdown("FamousWorld", {
    Title = "Famous Public Worlds",
    Values = {
        "RECIPES",
        "BUYRARESAPLINGS",
        "GAMBLES",
        "START",
        "HELP",
        "MARKET",
        "GEMS",
        "TRADE"
    },
    Multi = false,
    Default = "RECIPES"
})
FamousWorldDropdown:OnChanged(function(v) scriptState.selectedWorld = v end)

local JoinFamousButton = QuickWorldsSection:AddButton({
    Title = "Join Selected Famous World",
    Description = "Quickly joins well-known public worlds",
    Callback = function()
        local remote = ReplicatedStorage:FindFirstChild("events") and ReplicatedStorage.events:FindFirstChild("joinWorld")
        if remote then
            remote:FireServer(scriptState.selectedWorld)
            Fluent:Notify({ Title = "World", Content = "Joining: " .. scriptState.selectedWorld, Duration = 3 })
        else
            Fluent:Notify({ Title = "World", Content = "Remote not found. Try entering the world manually in the main menu.", Duration = 4 })
        end
    end
})

local JoinMyWorldButton = QuickWorldsSection:AddButton({
    Title = "Join MY World",
    Description = "Auto-joins your personal world (YourNameRBX)",
    Callback = function()
        local myWorld = player.Name .. "RBX"
        local remote = ReplicatedStorage:FindFirstChild("events") and ReplicatedStorage.events:FindFirstChild("joinWorld")
        if remote then
            remote:FireServer(myWorld)
            Fluent:Notify({ Title = "World", Content = "Joining your world: " .. myWorld, Duration = 3 })
        else
            Fluent:Notify({ Title = "World", Content = "Your world name: " .. myWorld .. "\n(Enter this in the world menu)", Duration = 5 })
        end
    end
})

-- Lock Buyer Section
local LockSection = WorldTab:AddSection("Lock Buyer")
local LockPara = LockSection:AddParagraph({
    Title = "Lock Prices",
    Content = "Small Lock: 100 Gems\nMedium Lock: 250 Gems\nLarge Lock: 500 Gems\nWorld Lock: 1000 Gems"
})

local LockDropdown = LockSection:AddDropdown("SelectLock", {
    Title = "Select Lock Type",
    Values = { "Small Lock", "Medium Lock", "Large Lock", "World Lock" },
    Multi = false,
    Default = "Small Lock"
})
local selectedLock = "Small Lock"
LockDropdown:OnChanged(function(v) selectedLock = v end)

local BuyLockButton = LockSection:AddButton({
    Title = "Purchase Selected Lock",
    Description = "Buys the chosen lock type with Gems",
    Callback = function()
        local remote = ReplicatedStorage:FindFirstChild("events") and ReplicatedStorage.events:FindFirstChild("purchaseItem")
        if remote then
            remote:FireServer(selectedLock, 1)
            Fluent:Notify({ Title = "Shop", Content = "Purchased: " .. selectedLock, Duration = 3 })
        else
            Fluent:Notify({ Title = "Shop", Content = "Purchase remote not found!", Duration = 3 })
        end
    end
})

-- ==============================
-- MISC TAB
-- ==============================

local NotifSection = MiscTab:AddSection("Notifications & Status")
local StatusPara = NotifSection:AddParagraph({
    Title = "Script Info",
    Content = "Craft A World Script v1.0\nGame: Craft A World (Roblox)\nMinimize: Right Ctrl"
})

local AntiAFKSection = MiscTab:AddSection("Anti-Detection")

local AntiAFKToggle = AntiAFKSection:AddToggle("AntiAFK2", {
    Title = "Anti AFK (Anti Kick)",
    Description = "Sends periodic virtual input to prevent AFK kick",
    Default = false
})
AntiAFKToggle:OnChanged(function(v) scriptState.antiKick = v end)

local RandomWalkToggle = AntiAFKSection:AddToggle("RandomWalk", {
    Title = "Random Walk (Anti-Detect)",
    Description = "Randomly moves character every few seconds to appear human",
    Default = false
})
local randomWalk = false
RandomWalkToggle:OnChanged(function(v) randomWalk = v end)

-- Teleport to Players
local TpPlayersSection = MiscTab:AddSection("Teleport to Player")

local function getPlayerNames()
    local names = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player then
            table.insert(names, plr.Name)
        end
    end
    if #names == 0 then table.insert(names, "No Players Found") end
    return names
end

local TargetPlayerDropdown = TpPlayersSection:AddDropdown("TargetPlayer", {
    Title = "Select Player to Teleport To",
    Values = getPlayerNames(),
    Multi = false,
    Default = getPlayerNames()[1]
})
local targetPlayerName = getPlayerNames()[1]
TargetPlayerDropdown:OnChanged(function(v) targetPlayerName = v end)

local RefreshPlayersButton = TpPlayersSection:AddButton({
    Title = "Refresh Player List",
    Description = "Updates the player list",
    Callback = function()
        -- Fluent doesn't support dynamic dropdown refresh natively; notify user
        Fluent:Notify({ Title = "Players", Content = "There are " .. #Players:GetPlayers() .. " players in this server.", Duration = 3 })
    end
})

local TeleportToPlayerButton = TpPlayersSection:AddButton({
    Title = "Teleport To Selected Player",
    Description = "Instantly moves to selected player's position",
    Callback = function()
        local target = Players:FindFirstChild(targetPlayerName)
        if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
            if hrp then
                hrp.CFrame = target.Character.HumanoidRootPart.CFrame + Vector3.new(3, 0, 0)
                Fluent:Notify({ Title = "Teleport", Content = "Teleported to " .. targetPlayerName, Duration = 2 })
            end
        else
            Fluent:Notify({ Title = "Teleport", Content = "Player not found or has no character.", Duration = 3 })
        end
    end
})

-- Credits
local CreditsSection = MiscTab:AddSection("Credits")
local CreditsPara = CreditsSection:AddParagraph({
    Title = "Credits",
    Content = "Script: Craft A World Auto Script v1.0\nUI: Fluent Library by dawid-scripts\nPurpose: Educational / Testing Only\n\nWARNING: Using exploits in Roblox can\nresult in permanent account bans."
})

-- ==============================
-- BACKGROUND LOOPS
-- ==============================

-- Main farming loop
spawn(function()
    while wait(scriptState.farmDelay) do
        -- Auto Break
        if scriptState.autoBreak then
            if hrp then
                local targetPos = hrp.Position + Vector3.new(scriptState.breakOffsetX, scriptState.breakOffsetY, 0)
                -- Find block at target position and punch it
                local blockFound = false
                for _, obj in ipairs(Workspace:GetDescendants()) do
                    if obj:IsA("BasePart") and obj.Name ~= "HumanoidRootPart"
                        and not obj:IsDescendantOf(character) then
                        if (obj.Position - targetPos).Magnitude < 3 then
                            -- Attempt to fire break remote
                            local breakRemote = ReplicatedStorage:FindFirstChild("events") and ReplicatedStorage.events:FindFirstChild("breakBlock")
                            if breakRemote then
                                breakRemote:FireServer(obj)
                                blockFound = true
                                break
                            end
                            -- Fallback: use touch
                            if obj:FindFirstChild("ClickDetector") then
                                fireclickdetector(obj.ClickDetector)
                                blockFound = true
                                break
                            end
                        end
                    end
                end
            end
        end

        -- Auto Place
        if scriptState.autoPlace then
            if hrp then
                local targetPos = hrp.Position + Vector3.new(scriptState.placeOffsetX, scriptState.placeOffsetY, 0)
                local placeRemote = ReplicatedStorage:FindFirstChild("events") and ReplicatedStorage.events:FindFirstChild("placeBlock")
                if placeRemote then
                    placeRemote:FireServer(scriptState.selectedBlock, targetPos)
                end
            end
        end

        -- Auto Plant
        if scriptState.autoPlant then
            if hrp then
                local plantRemote = ReplicatedStorage:FindFirstChild("events") and ReplicatedStorage.events:FindFirstChild("plantSapling")
                if plantRemote then
                    local targetPos = hrp.Position + Vector3.new(scriptState.placeOffsetX, scriptState.placeOffsetY, 0)
                    plantRemote:FireServer(scriptState.selectedSapling, targetPos)
                end
            end
        end

        -- Auto Collect Drops
        if scriptState.autoCollectDrops then
            for _, obj in ipairs(Workspace:GetDescendants()) do
                if obj.Name == "Drop" or obj.Name == "ItemDrop" or obj.Name == "Pickup" then
                    if obj:IsA("BasePart") and hrp then
                        if (obj.Position - hrp.Position).Magnitude < 50 then
                            hrp.CFrame = CFrame.new(obj.Position)
                            wait(0.1)
                        end
                    end
                end
            end
        end

        -- Auto Gem Farm (break blocks in a sweeping pattern)
        if scriptState.autoGemFarm then
            if hrp then
                local gemRemote = ReplicatedStorage:FindFirstChild("events") and ReplicatedStorage.events:FindFirstChild("breakBlock")
                if gemRemote then
                    for x = -3, 3 do
                        for y = -1, 2 do
                            local targetPos = hrp.Position + Vector3.new(x, y, 0)
                            for _, obj in ipairs(Workspace:GetDescendants()) do
                                if obj:IsA("BasePart") and (obj.Position - targetPos).Magnitude < 1.5
                                    and not obj:IsDescendantOf(character) then
                                    gemRemote:FireServer(obj)
                                end
                            end
                        end
                    end
                end
            end
        end

        wait(scriptState.farmDelay)
    end
end)

-- Auto Craft loop
spawn(function()
    while wait(scriptState.craftDelay) do
        if scriptState.autoCraft then
            local craftRemote = ReplicatedStorage:FindFirstChild("events") and ReplicatedStorage.events:FindFirstChild("craft")
            if craftRemote then
                for i = 1, scriptState.craftAmount do
                    craftRemote:FireServer(scriptState.craftIngredient1, scriptState.craftIngredient2)
                    wait(scriptState.craftDelay)
                end
            end
        end
    end
end)

-- No Clip + Infinite Jump + Anti Kick loop
RunService.Stepped:Connect(function()
    if character and humanoid then
        -- No Clip
        if scriptState.noClip then
            for _, part in ipairs(character:GetDescendants()) do
                if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                    part.CanCollide = false
                end
            end
        end

        -- Anti Kick (move randomly every 2 minutes effectively)
        if scriptState.antiKick then
            if humanoid.MoveDirection == Vector3.new(0, 0, 0) then
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.W, false, game)
                task.delay(0.1, function()
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.W, false, game)
                end)
            end
        end
    end
end)

-- Infinite Jump
UserInputService.JumpRequest:Connect(function()
    if scriptState.infiniteJump and character and humanoid then
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end)

-- Auto Respawn
Players.LocalPlayer.CharacterRemoving:Connect(function()
    if scriptState.autoRespawn then
        task.delay(1, function()
            player:LoadCharacter()
        end)
    end
end)

-- Player ESP loop
spawn(function()
    while wait(1) do
        if scriptState.playerESP then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= player and plr.Character then
                    local root = plr.Character:FindFirstChild("HumanoidRootPart")
                    if root then
                        createBillboard(root, plr.Name, "CAW_PlayerESP", Color3.fromRGB(0, 200, 255))
                    end
                end
            end
        end

        -- Drop ESP
        if scriptState.dropESP then
            for _, obj in ipairs(Workspace:GetDescendants()) do
                if (obj.Name == "Drop" or obj.Name == "ItemDrop" or obj.Name == "Pickup")
                    and obj:IsA("BasePart") then
                    createBillboard(obj, "⬆ DROP", "CAW_DropESP", Color3.fromRGB(255, 220, 0))
                end
            end
        end
    end
end)

-- Random Walk anti-detection
spawn(function()
    local directions = {
        Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0),
        Vector3.new(0, 0, 1), Vector3.new(0, 0, -1)
    }
    while wait(math.random(4, 10)) do
        if randomWalk and humanoid and character then
            local dir = directions[math.random(1, #directions)]
            humanoid:Move(dir)
            wait(0.3)
            humanoid:Move(Vector3.new(0, 0, 0))
        end
    end
end)

-- ==============================
-- SAVE MANAGER SETUP
-- ==============================
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("CraftAWorldScript")
SaveManager:SetFolder("CraftAWorldScript/saves")
InterfaceManager:BuildInterfaceSection(MiscTab)
SaveManager:BuildConfigSection(MiscTab)

Window:SelectTab(1)
SaveManager:LoadAutoloadConfig()

-- ==============================
-- STARTUP NOTIFICATION
-- ==============================
Fluent:Notify({
    Title = "Craft A World Script",
    Content = "Script loaded! v1.0\nMinimize: Right Ctrl",
    SubContent = "For educational purposes only — use at own risk",
    Duration = 6
})
