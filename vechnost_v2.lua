--[[ 
    FILE: vechnost_v2.lua
    BRAND: Vechnost
    VERSION: 2.0.0
    DESC: Server-Wide Fish Webhook Logger + Auto Trading System for Roblox "Fish It"
          Custom GUI Design - ShieldTeam Style
]]

-- =====================================================
-- BAGIAN 1: CLEANUP SYSTEM
-- =====================================================
local CoreGui = game:GetService("CoreGui")
local GUI_NAMES = {
    Main = "Vechnost_Main_UI",
    Mobile = "Vechnost_Mobile_Button",
}

for _, v in pairs(CoreGui:GetChildren()) do
    for _, name in pairs(GUI_NAMES) do
        if v.Name == name then v:Destroy() end
    end
end

-- =====================================================
-- BAGIAN 2: SERVICES & GLOBALS
-- =====================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Safe load game-specific remotes
local net, ObtainedNewFish
do
    local ok, err = pcall(function()
        net = ReplicatedStorage:WaitForChild("Packages", 10)
            :WaitForChild("_Index", 5)
            :WaitForChild("sleitnick_net@0.2.0", 5)
            :WaitForChild("net", 5)
        ObtainedNewFish = net:WaitForChild("RE/ObtainedNewFishNotification", 5)
    end)
    if not ok then
        warn("[Vechnost] ERROR loading game remotes:", err)
    else
        warn("[Vechnost] Game remotes loaded OK")
    end
end

-- =====================================================
-- BAGIAN 3: SETTINGS STATE
-- =====================================================
local Settings = {
    Active = false,
    Url = "",
    SentUUID = {},
    SelectedRarities = {},
    ServerWide = true,
    LogCount = 0,
}

-- =====================================================
-- BAGIAN 4: FISH DATABASE
-- =====================================================
local FishDB = {}
do
    local ok, err = pcall(function()
        local Items = ReplicatedStorage:WaitForChild("Items", 10)
        if not Items then return end
        for _, module in ipairs(Items:GetChildren()) do
            if module:IsA("ModuleScript") then
                local ok2, mod = pcall(require, module)
                if ok2 and mod and mod.Data and mod.Data.Type == "Fish" then
                    FishDB[mod.Data.Id] = {
                        Name = mod.Data.Name,
                        Tier = mod.Data.Tier,
                        Icon = mod.Data.Icon,
                        SellPrice = mod.Data.SellPrice or mod.Data.Value or mod.Data.Price or mod.Data.Worth or 0
                    }
                end
            end
        end
    end)
    if not ok then
        warn("[Vechnost] ERROR loading FishDB:", err)
    end
end

local FishNameToId = {}
for fishId, fishData in pairs(FishDB) do
    if fishData.Name then
        FishNameToId[fishData.Name] = fishId
        FishNameToId[string.lower(fishData.Name)] = fishId
    end
end

-- =====================================================
-- BAGIAN 4B: REPLION PLAYER DATA
-- =====================================================
local PlayerData = nil
do
    pcall(function()
        local Replion = require(ReplicatedStorage.Packages.Replion)
        PlayerData = Replion.Client:WaitReplion("Data")
    end)
end

local function FormatNumber(n)
    if not n or type(n) ~= "number" then return "0" end
    local formatted = tostring(math.floor(n))
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return formatted
end

-- =====================================================
-- BAGIAN 5: RARITY SYSTEM
-- =====================================================
local RARITY_MAP = {
    [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic",
    [5] = "Legendary", [6] = "Mythic", [7] = "Secret",
}

local RARITY_NAME_TO_TIER = {
    Common = 1, Uncommon = 2, Rare = 3, Epic = 4,
    Legendary = 5, Mythic = 6, Secret = 7,
}

local RARITY_COLOR = {
    [1] = 0x9e9e9e, [2] = 0x4caf50, [3] = 0x2196f3, [4] = 0x9c27b0,
    [5] = 0xff9800, [6] = 0xf44336, [7] = 0xff1744,
}

local RarityList = {"Common","Uncommon","Rare","Epic","Legendary","Mythic","Secret"}

-- =====================================================
-- BAGIAN 6: HTTP REQUEST
-- =====================================================
local HttpRequest =
    syn and syn.request
    or http_request
    or request
    or (fluxus and fluxus.request)
    or (krnl and krnl.request)

-- =====================================================
-- BAGIAN 7: ICON CACHE
-- =====================================================
local IconCache = {}
local IconWaiter = {}

local function FetchFishIconAsync(fishId, callback)
    if IconCache[fishId] then
        callback(IconCache[fishId])
        return
    end
    if IconWaiter[fishId] then
        table.insert(IconWaiter[fishId], callback)
        return
    end
    IconWaiter[fishId] = { callback }
    task.spawn(function()
        local fish = FishDB[fishId]
        if not fish or not fish.Icon then callback("") return end
        local assetId = tostring(fish.Icon):match("%d+")
        if not assetId then callback("") return end
        local api = ("https://thumbnails.roblox.com/v1/assets?assetIds=%s&size=420x420&format=Png&isCircular=false"):format(assetId)
        local ok, res = pcall(function()
            return HttpRequest({ Url = api, Method = "GET" })
        end)
        if not ok or not res or not res.Body then callback("") return end
        local ok2, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
        if not ok2 then callback("") return end
        local imageUrl = data and data.data and data.data[1] and data.data[1].imageUrl
        IconCache[fishId] = imageUrl or ""
        for _, cb in ipairs(IconWaiter[fishId]) do cb(IconCache[fishId]) end
        IconWaiter[fishId] = nil
    end)
end

-- =====================================================
-- BAGIAN 8: FILTER & HELPERS
-- =====================================================
local function IsRarityAllowed(fishId)
    local fish = FishDB[fishId]
    if not fish then return false end
    local tier = fish.Tier
    if type(tier) ~= "number" then return false end
    if next(Settings.SelectedRarities) == nil then return true end
    return Settings.SelectedRarities[tier] == true
end

local function ExtractMutation(weightData, item)
    local mutation = nil
    if weightData and typeof(weightData) == "table" then
        mutation = weightData.Mutation or weightData.Variant or weightData.VariantID
    end
    if not mutation and item then
        mutation = item.Mutation or item.Variant or item.VariantID
        if not mutation and item.Properties then
            mutation = item.Properties.Mutation or item.Properties.Variant
        end
    end
    return mutation
end

local function ResolvePlayerName(arg)
    if typeof(arg) == "Instance" and arg:IsA("Player") then
        return arg.Name
    elseif typeof(arg) == "string" then
        return arg
    elseif typeof(arg) == "table" and arg.Name then
        return tostring(arg.Name)
    end
    return LocalPlayer.Name
end

-- =====================================================
-- BAGIAN 9: WEBHOOK ENGINE
-- =====================================================
local function BuildPayload(playerName, fishId, weight, mutation)
    local fish = FishDB[fishId]
    if not fish then return nil end
    local tier = fish.Tier
    local rarityName = RARITY_MAP[tier] or "Unknown"
    local mutText = (mutation ~= nil) and tostring(mutation) or "None"
    local weightText = string.format("%.1fkg", weight or 0)
    local iconUrl = IconCache[fishId] or ""
    local dateStr = os.date("!%B %d, %Y")

    return {
        username = "Vechnost Notifier",
        avatar_url = "https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png",
        flags = 32768,
        components = {
            {
                type = 17,
                components = {
                    { type = 10, content = "# NEW FISH CAUGHT!" },
                    { type = 14, spacing = 1, divider = true },
                    { type = 10, content = "__@" .. (playerName or "Unknown") .. " you got new " .. string.upper(rarityName) .. " fish__" },
                    {
                        type = 9,
                        components = {
                            { type = 10, content = "**Fish Name**" },
                            { type = 10, content = "> " .. (fish.Name or "Unknown") }
                        },
                        accessory = iconUrl ~= "" and { type = 11, media = { url = iconUrl } } or nil
                    },
                    { type = 10, content = "**Fish Tier**" },
                    { type = 10, content = "> " .. string.upper(rarityName) },
                    { type = 10, content = "**Weight**" },
                    { type = 10, content = "> " .. weightText },
                    { type = 10, content = "**Mutation**" },
                    { type = 10, content = "> " .. mutText },
                    { type = 14, spacing = 1, divider = true },
                    { type = 10, content = "> Notification by discord.gg/vechnost" },
                    { type = 10, content = "-# " .. dateStr }
                }
            }
        }
    }
end

local function BuildActivationPayload(playerName, mode)
    local dateStr = os.date("!%B %d, %Y")
    return {
        username = "Vechnost Notifier",
        avatar_url = "https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png",
        flags = 32768,
        components = {
            {
                type = 17,
                accent_color = 0x30ff6a,
                components = {
                    { type = 10, content = "**" .. playerName .. "  Webhook Activated !**" },
                    { type = 14, spacing = 1, divider = true },
                    { type = 10, content = "### Vechnost Webhook Notifier" },
                    { type = 10, content = "- **Account Name:** " .. playerName .. "\n- **Mode:** " .. mode .. "\n- **Status:** Online" },
                    { type = 14, spacing = 1, divider = true },
                    { type = 10, content = "-# " .. dateStr }
                }
            }
        }
    }
end

local function BuildTestPayload(playerName)
    local dateStr = os.date("!%B %d, %Y")
    return {
        username = "Vechnost Notifier",
        avatar_url = "https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png",
        flags = 32768,
        components = {
            {
                type = 17,
                accent_color = 0x5865f2,
                components = {
                    { type = 10, content = "**Test Message**" },
                    { type = 14, spacing = 1, divider = true },
                    { type = 10, content = "Webhook berfungsi dengan baik!\n\n- **Dikirim oleh:** " .. playerName },
                    { type = 14, spacing = 1, divider = true },
                    { type = 10, content = "-# " .. dateStr }
                }
            }
        }
    }
end

local function SendWebhook(payload)
    if Settings.Url == "" then return end
    if not HttpRequest then return end
    if not payload then return end
    pcall(function()
        local url = Settings.Url
        if string.find(url, "?") then
            url = url .. "&with_components=true"
        else
            url = url .. "?with_components=true"
        end
        HttpRequest({
            Url = url,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode(payload)
        })
    end)
end

-- =====================================================
-- BAGIAN 10: SERVER-WIDE FISH DETECTION
-- =====================================================
local Connections = {}
local ChatSentDedup = {}

local function ParseChatForFish(messageText)
    if not Settings.Active then return end
    if not Settings.ServerWide then return end
    if not messageText or messageText == "" then return end

    local playerName, fishName, weightStr = string.match(messageText, "(%S+)%s+obtained%s+a%s+(.-)%s*%(([%d%.]+)kg%)")
    if not playerName then
        playerName, fishName, weightStr = string.match(messageText, "(%S+)%s+obtained%s+(.-)%s*%(([%d%.]+)kg%)")
    end
    if not playerName then
        playerName, fishName = string.match(messageText, "(%S+)%s+obtained%s+a%s+(.-)%s*with")
    end
    if not playerName then
        playerName, fishName = string.match(messageText, "(%S+)%s+obtained%s+(.-)%s*with")
    end
    if not playerName or not fishName then return end

    fishName = string.gsub(fishName, "%s+$", "")
    if playerName == LocalPlayer.Name or playerName == LocalPlayer.DisplayName then return end

    local fishId = FishNameToId[fishName] or FishNameToId[string.lower(fishName)]
    if not fishId then
        for name, id in pairs(FishNameToId) do
            if string.find(string.lower(fishName), string.lower(name)) or string.find(string.lower(name), string.lower(fishName)) then
                fishId = id
                break
            end
        end
    end
    if not fishId then return end
    if not IsRarityAllowed(fishId) then return end

    local dedupKey = playerName .. fishName .. tostring(math.floor(os.time() / 2))
    if ChatSentDedup[dedupKey] then return end
    ChatSentDedup[dedupKey] = true
    task.defer(function() task.wait(10) ChatSentDedup[dedupKey] = nil end)

    local weight = tonumber(weightStr) or 0
    Settings.LogCount = Settings.LogCount + 1

    FetchFishIconAsync(fishId, function()
        SendWebhook(BuildPayload(playerName, fishId, weight, nil))
    end)
end

local function HandleFishCaught(playerArg, weightData, wrapper)
    if not Settings.Active then return end

    local item = nil
    if wrapper and typeof(wrapper) == "table" and wrapper.InventoryItem then
        item = wrapper.InventoryItem
    end
    if not item and weightData and typeof(weightData) == "table" and weightData.InventoryItem then
        item = weightData.InventoryItem
    end
    if not item then return end
    if not item.Id or not item.UUID then return end
    if not FishDB[item.Id] then return end
    if not IsRarityAllowed(item.Id) then return end
    if Settings.SentUUID[item.UUID] then return end
    Settings.SentUUID[item.UUID] = true

    local playerName = ResolvePlayerName(playerArg)
    if not Settings.ServerWide and playerName ~= LocalPlayer.Name then return end

    local weight = 0
    if weightData and typeof(weightData) == "table" and weightData.Weight then
        weight = weightData.Weight
    end
    local mutation = ExtractMutation(weightData, item)
    Settings.LogCount = Settings.LogCount + 1

    FetchFishIconAsync(item.Id, function()
        SendWebhook(BuildPayload(playerName, item.Id, weight, mutation))
    end)
end

local function TryProcessGeneric(remoteName, ...)
    if not Settings.Active then return end
    local args = {...}
    for i = 1, #args do
        local arg = args[i]
        if typeof(arg) == "table" then
            local item = nil
            if arg.InventoryItem then
                item = arg.InventoryItem
            elseif arg.Id and arg.UUID then
                item = arg
            end
            if item and item.Id and item.UUID and FishDB[item.Id] then
                local playerArg = (i > 1) and args[1] or nil
                local weightArg = nil
                for j = 1, #args do
                    if typeof(args[j]) == "table" and args[j].Weight then
                        weightArg = args[j]
                        break
                    end
                end
                HandleFishCaught(playerArg, weightArg, arg)
                return
            end
        end
    end
end

local function StartLogger()
    if Settings.Active then return end
    if not net or not ObtainedNewFish then return end

    Settings.Active = true
    Settings.SentUUID = {}
    Settings.LogCount = 0

    if Settings.ServerWide then
        pcall(function()
            local TextChatService = game:GetService("TextChatService")
            Connections[#Connections + 1] = TextChatService.MessageReceived:Connect(function(textChatMessage)
                pcall(function()
                    local text = textChatMessage.Text or ""
                    if string.find(text, "obtained") then
                        ParseChatForFish(text)
                    end
                end)
            end)
        end)

        pcall(function()
            local chatFrame = PlayerGui:WaitForChild("Chat", 3)
            if chatFrame then
                chatFrame.DescendantAdded:Connect(function(desc)
                    if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                        task.defer(function()
                            local text = desc.Text or ""
                            if string.find(text, "obtained") then
                                ParseChatForFish(text)
                            end
                        end)
                    end
                end)
            end
        end)
    end

    pcall(function()
        Connections[#Connections + 1] = ObtainedNewFish.OnClientEvent:Connect(function(playerArg, weightData, wrapper)
            HandleFishCaught(playerArg, weightData, wrapper)
        end)
    end)

    if Settings.ServerWide then
        pcall(function()
            Connections[#Connections + 1] = PlayerGui.DescendantAdded:Connect(function(desc)
                if not Settings.Active then return end
                if desc:IsA("TextLabel") then
                    task.defer(function()
                        local text = desc.Text or ""
                        for fishId, fishData in pairs(FishDB) do
                            if fishData.Name and string.find(text, fishData.Name) then
                                local playerName = "Unknown"
                                for _, player in pairs(Players:GetPlayers()) do
                                    if player ~= LocalPlayer and string.find(text, player.Name) then
                                        playerName = player.Name
                                        break
                                    end
                                end
                                if playerName == LocalPlayer.Name then return end
                                if playerName == "Unknown" then return end
                                local dedupKey = "GUI_" .. text .. "_" .. os.time()
                                if Settings.SentUUID[dedupKey] then return end
                                Settings.SentUUID[dedupKey] = true
                                if not IsRarityAllowed(fishId) then return end
                                Settings.LogCount = Settings.LogCount + 1
                                FetchFishIconAsync(fishId, function()
                                    SendWebhook(BuildPayload(playerName, fishId, 0, nil))
                                end)
                                return
                            end
                        end
                    end)
                end
            end)
        end)

        pcall(function()
            for _, child in pairs(net:GetChildren()) do
                if child:IsA("RemoteEvent") and child ~= ObtainedNewFish then
                    Connections[#Connections + 1] = child.OnClientEvent:Connect(function(...)
                        TryProcessGeneric(child.Name, ...)
                    end)
                end
            end
        end)
    end

    task.spawn(function()
        local mode = Settings.ServerWide and "Server Notifier" or "Local Only"
        SendWebhook(BuildActivationPayload(LocalPlayer.Name, mode))
    end)
end

local function StopLogger()
    Settings.Active = false
    for _, conn in ipairs(Connections) do
        pcall(function() conn:Disconnect() end)
    end
    Connections = {}
end

-- =====================================================
-- BAGIAN 11: TRADING SYSTEM
-- =====================================================
local TradeState = {
    TargetPlayer = nil,
    PlayerList = {},
    Inventory = {},
    StoneInventory = {},
    ByName = { Active = false, ItemName = nil, Amount = 1, Sent = 0 },
    ByCoin = { Active = false, TargetCoins = 0, Sent = 0 },
    ByRarity = { Active = false, Rarity = nil, RarityTier = nil, Amount = 1, Sent = 0 },
    ByStone = { Active = false, StoneName = nil, Amount = 1, Sent = 0 },
}

local STONE_LIST = { "Enchant Stone", "Evolved Stone" }

local function LoadInventory()
    TradeState.Inventory = {}
    TradeState.StoneInventory = {}
    pcall(function()
        local inv = PlayerData:Get("Inventory")
        if not inv then return end
        local items = inv.Items or inv
        if typeof(items) ~= "table" then return end
        for _, item in pairs(items) do
            if typeof(item) == "table" then
                local name = nil
                if item.Id and FishDB[item.Id] then
                    name = FishDB[item.Id].Name
                elseif item.Name then
                    name = tostring(item.Name)
                end
                if name then
                    local isStone = false
                    for _, sName in ipairs(STONE_LIST) do
                        if string.lower(name) == string.lower(sName) then
                            isStone = true
                            TradeState.StoneInventory[sName] = (TradeState.StoneInventory[sName] or 0) + 1
                            break
                        end
                    end
                    if not isStone then
                        TradeState.Inventory[name] = (TradeState.Inventory[name] or 0) + 1
                    end
                end
            end
        end
    end)
end

local function GetInventoryItemNames()
    local names = {}
    for name, _ in pairs(TradeState.Inventory) do
        table.insert(names, name)
    end
    table.sort(names)
    if #names == 0 then names = {"(Inventory kosong)"} end
    return names
end

local function GetFishNamesByRarity(tier)
    local names = {}
    for _, fishData in pairs(FishDB) do
        if fishData.Tier == tier then
            table.insert(names, fishData.Name)
        end
    end
    return names
end

local TradeRemote = nil
local function GetTradeRemote()
    if TradeRemote then return TradeRemote end
    pcall(function()
        local candidates = {"RE/TradeRequest", "RE/SendTrade", "RE/InitiateTrade", "RE/Trade", "TradeRequest", "SendTrade"}
        for _, name in ipairs(candidates) do
            local r = net:FindFirstChild(name)
            if r and r:IsA("RemoteEvent") then
                TradeRemote = r
                return
            end
        end
        for _, child in pairs(net:GetDescendants()) do
            if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
                if string.lower(child.Name):find("trade") then
                    TradeRemote = child
                    return
                end
            end
        end
    end)
    return TradeRemote
end

local function FireTradeItem(targetUsername, itemName, quantity)
    quantity = quantity or 1
    local remote = GetTradeRemote()
    local targetPlayer = nil
    for _, p in pairs(Players:GetPlayers()) do
        if p.Name == targetUsername or p.DisplayName == targetUsername then
            targetPlayer = p
            break
        end
    end
    if not targetPlayer then return false end
    local fishId = FishNameToId[itemName] or FishNameToId[string.lower(itemName)]
    local ok = false
    pcall(function()
        if remote then
            if remote:IsA("RemoteEvent") then
                remote:FireServer(targetPlayer, fishId or itemName, quantity)
                ok = true
            elseif remote:IsA("RemoteFunction") then
                remote:InvokeServer(targetPlayer, fishId or itemName, quantity)
                ok = true
            end
        end
    end)
    return ok
end

-- =====================================================
-- BAGIAN 12: TELEPORT LOCATIONS
-- =====================================================
local TeleportLocations = {
    { Name = "Spawn", Position = Vector3.new(0, 50, 0) },
    { Name = "Shop", Position = Vector3.new(100, 50, 100) },
    { Name = "Fishing Spot 1", Position = Vector3.new(-200, 50, 150) },
    { Name = "Fishing Spot 2", Position = Vector3.new(300, 50, -100) },
    { Name = "Secret Area", Position = Vector3.new(-500, 100, 500) },
}

local function TeleportTo(position)
    pcall(function()
        local character = LocalPlayer.Character
        if character then
            local hrp = character:FindFirstChild("HumanoidRootPart")
            if hrp then
                hrp.CFrame = CFrame.new(position)
            end
        end
    end)
end

-- =====================================================
-- BAGIAN 13: CUSTOM GUI DESIGN (ShieldTeam Style)
-- =====================================================

-- Color Palette
local Colors = {
    Background = Color3.fromRGB(15, 17, 26),
    Sidebar = Color3.fromRGB(20, 22, 35),
    SidebarHover = Color3.fromRGB(30, 35, 55),
    SidebarActive = Color3.fromRGB(35, 40, 65),
    Content = Color3.fromRGB(25, 28, 42),
    ContentItem = Color3.fromRGB(32, 36, 55),
    ContentItemHover = Color3.fromRGB(40, 45, 70),
    Accent = Color3.fromRGB(59, 130, 246),
    AccentHover = Color3.fromRGB(96, 165, 250),
    Text = Color3.fromRGB(255, 255, 255),
    TextSecondary = Color3.fromRGB(156, 163, 175),
    TextMuted = Color3.fromRGB(107, 114, 128),
    Border = Color3.fromRGB(55, 65, 81),
    Success = Color3.fromRGB(34, 197, 94),
    Error = Color3.fromRGB(239, 68, 68),
    Toggle = Color3.fromRGB(59, 130, 246),
    ToggleOff = Color3.fromRGB(75, 85, 99),
}

-- Create Main ScreenGui
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = GUI_NAMES.Main
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = CoreGui

-- Main Container
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 700, 0, 450)
MainFrame.Position = UDim2.new(0.5, -350, 0.5, -225)
MainFrame.BackgroundColor3 = Colors.Background
MainFrame.BorderSizePixel = 0
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 12)
MainCorner.Parent = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Colors.Border
MainStroke.Thickness = 1
MainStroke.Parent = MainFrame

-- Dragging functionality
local dragging, dragInput, dragStart, startPos

MainFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = MainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

MainFrame.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
