--[[ 
    FILE: vechnost_v2.lua
    BRAND: Vechnost
    VERSION: 2.5.0 (Bypassed Version)
    DESC: Complete Fish It Automation Suite
          - Auto Fishing + Clicker
          - Island Teleport
          - Auto Trading (Coin, Rarity, Stone, Name)
          - Auto Shop (Charm, Weather, Bait, Merchant)
          - Server-Wide Webhook Logger
    UI: Custom Dark Blue Sidebar Design
]]

-- =====================================================
-- BAGIAN 1: CLEANUP SYSTEM & BAC BYPASS
-- =====================================================
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- BAC Bypass: Gunakan gethui() untuk menyembunyikan UI dari deteksi game (CoreGui scan).
local function GetSafeParent()
    local success, parent = pcall(function() return gethui() end)
    if success and parent then return parent end
    -- Fallback jika executor tidak support gethui
    return game:GetService("CoreGui")
end

local SafeParent = GetSafeParent()

-- BAC Bypass: Pengacakan nama GUI agar tidak terdeteksi oleh string scan anti-cheat.
local function RandomString(len)
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local str = ""
    for i = 1, len do
        local rand = math.random(1, #chars)
        str = str .. string.sub(chars, rand, rand)
    end
    return str
end

local GUI_NAMES = {
    Main = RandomString(16),
    Mobile = RandomString(16),
}

-- Cleanup menggunakan custom identifier yang aman, karna nama GUI sekarang diacak
for _, v in pairs(SafeParent:GetChildren()) do
    if v:IsA("ScreenGui") and v:FindFirstChild("VechnostIdentifier") then
        v:Destroy()
    end
end

-- =====================================================
-- BAGIAN 2: SERVICES & GLOBALS
-- =====================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

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

local FishingSettings = {
    AutoCast = false,
    AutoReel = false,
    AutoShake = false,
    PerfectCatch = false,
    AntiAFK = false,
    AutoSell = false,
    ClickSpeed = 50,
}

local ShopSettings = {
    AutoBuyCharm = false,
    AutoBuyWeather = false,
    AutoBuyBait = false,
    AutoBuyMerchant = false,
    SelectedCharm = nil,
    SelectedWeather = nil,
    SelectedBait = nil,
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
                        SellPrice = mod.Data.SellPrice or mod.Data.Value or 0
                    }
                end
            end
        end
    end)
end

local FishNameToId = {}
for fishId, fishData in pairs(FishDB) do
    if fishData.Name then
        FishNameToId[fishData.Name] = fishId
        FishNameToId[string.lower(fishData.Name)] = fishId
    end
end

-- =====================================================
-- BAGIAN 5: REPLION PLAYER DATA
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

local function GetPlayerStats()
    local stats = { Coins = 0, TotalCaught = 0, BackpackCount = 0, BackpackMax = 0 }
    if not PlayerData then return stats end
    
    pcall(function()
        for _, key in ipairs({"Coins", "Currency", "Money"}) do
            local ok, val = pcall(function() return PlayerData:Get(key) end)
            if ok and val and type(val) == "number" then
                stats.Coins = val
                break
            end
        end
        
        for _, key in ipairs({"TotalCaught", "FishCaught"}) do
            local ok, val = pcall(function() return PlayerData:Get(key) end)
            if ok and val and type(val) == "number" then
                stats.TotalCaught = val
                break
            end
        end
        
        local inv = PlayerData:Get("Inventory")
        if inv and typeof(inv) == "table" then
            local items = inv.Items or inv
            if typeof(items) == "table" then
                local count = 0
                for _ in pairs(items) do count = count + 1 end
                stats.BackpackCount = count
            end
            stats.BackpackMax = inv.Capacity or inv.Size or inv.Max or 100
        end
    end)
    
    return stats
end

-- =====================================================
-- BAGIAN 6: RARITY SYSTEM
-- =====================================================
local RARITY_MAP = {
    [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic",
    [5] = "Legendary", [6] = "Mythic", [7] = "Secret",
}

local RARITY_NAME_TO_TIER = {
    Common = 1, Uncommon = 2, Rare = 3, Epic = 4,
    Legendary = 5, Mythic = 6, Secret = 7,
}

local RarityList = {"Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret"}

-- =====================================================
-- BAGIAN 7: TELEPORT LOCATIONS - FISH IT ISLANDS
-- =====================================================
local TeleportLocations = {}

local FishItIslands = {
    {Name = "Moosewood", Keywords = {"moosewood", "starter", "spawn", "hub"}},
    {Name = "Roslit Bay", Keywords = {"roslit", "bay"}},
    {Name = "Mushgrove Swamp", Keywords = {"mushgrove", "swamp", "mushroom"}},
    {Name = "Snowcap Island", Keywords = {"snowcap", "snow", "ice", "frozen"}},
    {Name = "Terrapin Island", Keywords = {"terrapin", "turtle"}},
    {Name = "Forsaken Shores", Keywords = {"forsaken", "shores"}},
    {Name = "Sunstone Island", Keywords = {"sunstone", "sun"}},
    {Name = "Kepler Island", Keywords = {"kepler"}},
    {Name = "Ancient Isle", Keywords = {"ancient", "isle"}},
    {Name = "Volcanic Island", Keywords = {"volcanic", "volcano", "lava", "magma"}},
    {Name = "Crystal Caverns", Keywords = {"crystal", "caverns", "cave"}},
    {Name = "Brine Pool", Keywords = {"brine", "pool"}},
    {Name = "Vertigo", Keywords = {"vertigo"}},
    {Name = "Atlantis", Keywords = {"atlantis", "underwater"}},
    {Name = "The Depths", Keywords = {"depths", "deep", "abyss"}},
    {Name = "Monster's Borough", Keywords = {"monster", "borough"}},
    {Name = "Event Island", Keywords = {"event", "special"}},
}

local function ScanIslands()
    TeleportLocations = {}
    
    pcall(function()
        local zones = Workspace:FindFirstChild("Zones") or Workspace:FindFirstChild("Islands") or Workspace:FindFirstChild("Locations")
        if zones then
            for _, zone in pairs(zones:GetChildren()) do
                if zone:IsA("Model") or zone:IsA("Folder") or zone:IsA("Part") then
                    local pos = nil
                    if zone:IsA("BasePart") then
                        pos = zone.Position
                    elseif zone:IsA("Model") and zone.PrimaryPart then
                        pos = zone.PrimaryPart.Position
                    elseif zone:FindFirstChildWhichIsA("BasePart") then
                        pos = zone:FindFirstChildWhichIsA("BasePart").Position
                    end
                    
                    if pos then
                        table.insert(TeleportLocations, {
                            Name = zone.Name,
                            Position = pos,
                            CFrame = CFrame.new(pos + Vector3.new(0, 5, 0))
                        })
                    end
                end
            end
        end
        
        for _, obj in pairs(Workspace:GetDescendants()) do
            if obj:IsA("BasePart") then
                local name = string.lower(obj.Name)
                for _, island in pairs(FishItIslands) do
                    for _, keyword in pairs(island.Keywords) do
                        if string.find(name, keyword) then
                            local exists = false
                            for _, loc in pairs(TeleportLocations) do
                                if loc.Name == island.Name then
                                    exists = true
                                    break
                                end
                            end
                            if not exists then
                                table.insert(TeleportLocations, {
                                    Name = island.Name,
                                    Position = obj.Position,
                                    CFrame = CFrame.new(obj.Position + Vector3.new(0, 5, 0))
                                })
                            end
                            break
                        end
                    end
                end
            end
        end
        
        local spawnLocation = Workspace:FindFirstChildOfClass("SpawnLocation")
        if spawnLocation then
            local exists = false
            for _, loc in pairs(TeleportLocations) do
                if string.find(string.lower(loc.Name), "spawn") then
                    exists = true
                    break
                end
            end
            if not exists then
                table.insert(TeleportLocations, {
                    Name = "Spawn Point",
                    Position = spawnLocation.Position,
                    CFrame = spawnLocation.CFrame + Vector3.new(0, 5, 0)
                })
            end
        end
    end)
    
    if #TeleportLocations == 0 then
        for _, island in pairs(FishItIslands) do
            table.insert(TeleportLocations, {
                Name = island.Name,
                Position = Vector3.new(0, 50, 0),
                CFrame = CFrame.new(0, 50, 0)
            })
        end
    end
    
    table.sort(TeleportLocations, function(a, b) return a.Name < b.Name end)
    return TeleportLocations
end

local function TeleportTo(locationName)
    local character = LocalPlayer.Character
    if not character then return false, "No character" end
    
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false, "No HumanoidRootPart" end
    
    for _, loc in pairs(TeleportLocations) do
        if loc.Name == locationName then
            hrp.CFrame = loc.CFrame
            return true, "Teleported to " .. locationName
        end
    end
    
    return false, "Location not found"
end

local function GetTeleportLocationNames()
    local names = {}
    for _, loc in pairs(TeleportLocations) do
        table.insert(names, loc.Name)
    end
    if #names == 0 then names = {"(Scan locations first)"} end
    return names
end

ScanIslands()

-- =====================================================
-- BAGIAN 8: SHOP DATABASE - FISH IT
-- =====================================================
local ShopDB = {
    Charms = {
        "Lucky Charm", "Mythical Charm", "Shiny Charm", "Magnetic Charm",
        "Celestial Charm", "Fortune Charm", "Ocean Charm", "Treasure Charm"
    },
    Weather = {
        "Sunny", "Rainy", "Stormy", "Foggy", "Snowy", 
        "Blood Moon", "Aurora", "Eclipse"
    },
    Bait = {
        "Basic Bait", "Worm", "Minnow", "Shrimp",
        "Premium Bait", "Legendary Bait", "Mythic Bait"
    },
    Merchant = {
        "Mystery Box", "Premium Crate", "Rod Upgrade",
        "Backpack Upgrade", "Enchant Stone", "Evolved Stone"
    }
}

local function GetShopRemote(shopType)
    local remoteNames = {
        Charm = {"RE/BuyCharm", "RE/PurchaseCharm", "RE/EquipCharm"},
        Weather = {"RE/BuyWeather", "RE/ChangeWeather", "RE/SetWeather"},
        Bait = {"RE/BuyBait", "RE/PurchaseBait", "RE/SelectBait"},
        Merchant = {"RE/BuyItem", "RE/Purchase", "RE/BuyMerchant"}
    }
    
    if not net then return nil end
    
    for _, name in ipairs(remoteNames[shopType] or {}) do
        local remote = net:FindFirstChild(name)
        if remote then return remote end
    end
    
    for _, child in ipairs(net:GetDescendants()) do
        if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
            local lname = string.lower(child.Name)
            if string.find(lname, string.lower(shopType)) or string.find(lname, "buy") then
                return child
            end
        end
    end
    
    return nil
end

local function BuyShopItem(shopType, itemName)
    local remote = GetShopRemote(shopType)
    if not remote then return false end
    
    pcall(function()
        if remote:IsA("RemoteEvent") then
            remote:FireServer(itemName)
        elseif remote:IsA("RemoteFunction") then
            remote:InvokeServer(itemName)
        end
    end)
    
    return true
end

-- =====================================================
-- BAGIAN 9: HTTP REQUEST
-- =====================================================
local HttpRequest = syn and syn.request or http_request or request or (fluxus and fluxus.request)

-- =====================================================
-- BAGIAN 10: ICON CACHE & WEBHOOK
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
        if not fish or not fish.Icon then
            callback("")
            return
        end
        
        local assetId = tostring(fish.Icon):match("%d+")
        if not assetId then
            callback("")
            return
        end
        
        local ok, res = pcall(function()
            return HttpRequest({
                Url = "https://thumbnails.roblox.com/v1/assets?assetIds=" .. assetId .. "&size=420x420&format=Png",
                Method = "GET"
            })
        end)
        
        if ok and res and res.Body then
            local ok2, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
            if ok2 and data and data.data and data.data[1] then
                IconCache[fishId] = data.data[1].imageUrl or ""
            end
        end
        
        for _, cb in ipairs(IconWaiter[fishId] or {}) do
            cb(IconCache[fishId] or "")
        end
        IconWaiter[fishId] = nil
    end)
end

local function IsRarityAllowed(fishId)
    local fish = FishDB[fishId]
    if not fish then return false end
    if next(Settings.SelectedRarities) == nil then return true end
    return Settings.SelectedRarities[fish.Tier] == true
end

local function BuildPayload(playerName, fishId, weight, mutation)
    local fish = FishDB[fishId]
    if not fish then return nil end
    
    local tier = fish.Tier
    local rarityName = RARITY_MAP[tier] or "Unknown"
    local iconUrl = IconCache[fishId] or ""
    local dateStr = os.date("!%B %d, %Y")
    
    return {
        username = "Vechnost Notifier",
        avatar_url = "https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png",
        flags = 32768,
        components = {{
            type = 17,
            components = {
                { type = 10, content = "# NEW FISH CAUGHT!" },
                { type = 14, spacing = 1, divider = true },
                { type = 10, content = "__@" .. playerName .. " caught " .. string.upper(rarityName) .. " fish__" },
                {
                    type = 9,
                    components = {
                        { type = 10, content = "**Fish Name**" },
                        { type = 10, content = "> " .. fish.Name }
                    },
                    accessory = iconUrl ~= "" and { type = 11, media = { url = iconUrl } } or nil
                },
                { type = 10, content = "**Rarity:** " .. rarityName },
                { type = 10, content = "**Weight:** " .. string.format("%.1fkg", weight or 0) },
                { type = 10, content = "**Mutation:** " .. (mutation or "None") },
                { type = 14, spacing = 1, divider = true },
                { type = 10, content = "-# " .. dateStr }
            }
        }}
    }
end

local function SendWebhook(payload)
    if Settings.Url == "" or not HttpRequest or not payload then return end
    
    pcall(function()
        local url = Settings.Url
        url = string.find(url, "?") and (url .. "&with_components=true") or (url .. "?with_components=true")
        
        HttpRequest({
            Url = url,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode(payload)
        })
    end)
end

-- =====================================================
-- BAGIAN 11: FISH DETECTION & LOGGER
-- =====================================================
local Connections = {}
local ChatSentDedup = {}

local function HandleFishCaught(playerArg, weightData, wrapper)
    if not Settings.Active then return end
    
    local item = nil
    if wrapper and typeof(wrapper) == "table" and wrapper.InventoryItem then
        item = wrapper.InventoryItem
    elseif weightData and typeof(weightData) == "table" and weightData.InventoryItem then
        item = weightData.InventoryItem
    end
    
    if not item or not item.Id or not item.UUID then return end
    if not FishDB[item.Id] then return end
    if not IsRarityAllowed(item.Id) then return end
    if Settings.SentUUID[item.UUID] then return end
    
    Settings.SentUUID[item.UUID] = true
    
    local playerName = LocalPlayer.Name
    if typeof(playerArg) == "Instance" and playerArg:IsA("Player") then
        playerName = playerArg.Name
    elseif typeof(playerArg) == "string" then
        playerName = playerArg
    end
    
    if not Settings.ServerWide and playerName ~= LocalPlayer.Name then return end
    
    local weight = weightData and typeof(weightData) == "table" and weightData.Weight or 0
    local mutation = weightData and typeof(weightData) == "table" and weightData.Mutation or nil
    
    Settings.LogCount = Settings.LogCount + 1
    
    FetchFishIconAsync(item.Id, function()
        SendWebhook(BuildPayload(playerName, item.Id, weight, mutation))
    end)
end

local function StartLogger()
    if Settings.Active then return true, "Already running" end
    if not net or not ObtainedNewFish then return false, "Game remotes not found" end
    
    Settings.Active = true
    Settings.SentUUID = {}
    Settings.LogCount = 0
    
    pcall(function()
        Connections[#Connections + 1] = ObtainedNewFish.OnClientEvent:Connect(HandleFishCaught)
    end)
    
    return true, "Logger started"
end

local function StopLogger()
    Settings.Active = false
    for _, conn in ipairs(Connections) do
        pcall(function() conn:Disconnect() end)
    end
    Connections = {}
end

-- =====================================================
-- BAGIAN 12: FISHING AUTOMATION
-- =====================================================
local FishingRemotes = {}

local function FindFishingRemotes()
    if not net then return end
    
    for _, child in ipairs(net:GetDescendants()) do
        if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
            local lname = string.lower(child.Name)
            if string.find(lname, "cast") or string.find(lname, "throw") then
                FishingRemotes.Cast = FishingRemotes.Cast or child
            elseif string.find(lname, "reel") or string.find(lname, "pull") or string.find(lname, "catch") then
                FishingRemotes.Reel = FishingRemotes.Reel or child
            elseif string.find(lname, "shake") then
                FishingRemotes.Shake = FishingRemotes.Shake or child
            elseif string.find(lname, "sell") then
                FishingRemotes.Sell = FishingRemotes.Sell or child
            end
        end
    end
end

FindFishingRemotes()

local function SimulateClick()
    pcall(function()
        -- BAC Bypass: Menambahkan Humanized Click Delay. Pengiriman klik ke server tidak akan terlalu robotik.
        task.wait(math.random(1, 4) / 100)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
        task.wait(math.random(1, 3) / 100)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
    end)
end

local function IsFishBiting()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return false end
    
    for _, gui in ipairs(pg:GetDescendants()) do
        if gui:IsA("GuiObject") and gui.Visible then
            local lname = string.lower(gui.Name)
            if string.find(lname, "bite") or string.find(lname, "catch") or string.find(lname, "!") or string.find(lname, "reel") then
                return true
            end
        end
    end
    return false
end

local function IsShakeActive()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return false end
    
    for _, gui in ipairs(pg:GetDescendants()) do
        if gui:IsA("GuiObject") and gui.Visible then
            local lname = string.lower(gui.Name)
            if string.find(lname, "shake") or string.find(lname, "struggle") or string.find(lname, "minigame") then
                return true
            end
        end
    end
    return false
end

task.spawn(function()
    while true do
        task.wait(0.1)
        
        -- Fallback Anti-AFK kecil, meminimalisir pendeteksian
        if FishingSettings.AntiAFK then
            pcall(function()
                if not (getconnections or get_signal_cons) then
                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Unknown, false, game)
                end
            end)
        end
        
        if FishingSettings.AutoCast then
            pcall(function()
                if FishingRemotes.Cast then
                    if FishingRemotes.Cast:IsA("RemoteEvent") then
                        FishingRemotes.Cast:FireServer()
                    end
                end
                SimulateClick()
            end)
        end
        
        if FishingSettings.AutoReel and IsFishBiting() then
            pcall(function()
                if FishingRemotes.Reel then
                    if FishingRemotes.Reel:IsA("RemoteEvent") then
                        FishingRemotes.Reel:FireServer()
                    end
                end
                SimulateClick()
            end)
        end
        
        if FishingSettings.AutoShake and IsShakeActive() then
            for i = 1, FishingSettings.ClickSpeed do
                if not FishingSettings.AutoShake then break end
                pcall(function()
                    if FishingRemotes.Shake then
                        FishingRemotes.Shake:FireServer()
                    end
                    SimulateClick()
                end)
                task.wait((1 / FishingSettings.ClickSpeed) + (math.random(1, 10)/1000)) -- BAC Bypass: Humanize Shake Delay
            end
        end
        
        if FishingSettings.AutoSell then
            pcall(function()
                if FishingRemotes.Sell then
                    FishingRemotes.Sell:FireServer("All")
                end
            end)
        end
    end
end)

-- =====================================================
-- BAGIAN 13: TRADING SYSTEM
-- =====================================================
local TradeState = {
    TargetPlayer = nil,
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
    if #names == 0 then names = {"(Load inventory first)"} end
    return names
end

local TradeRemote = nil
local function GetTradeRemote()
    if TradeRemote then return TradeRemote end
    
    pcall(function()
        for _, child in pairs(net:GetDescendants()) do
            if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
                if string.lower(child.Name):find("trade") then
                    TradeRemote = child
                    break
                end
            end
        end
    end)
    
    return TradeRemote
end

local function FireTradeItem(targetUsername, itemName, quantity)
    local remote = GetTradeRemote()
    if not remote then return false end
    
    local targetPlayer = nil
    for _, p in pairs(Players:GetPlayers()) do
        if p.Name == targetUsername or p.DisplayName == targetUsername then
            targetPlayer = p
            break
        end
    end
    
    if not targetPlayer then return false end
    
    local fishId = FishNameToId[itemName] or FishNameToId[string.lower(itemName)]
    
    pcall(function()
        if remote:IsA("RemoteEvent") then
            remote:FireServer(targetPlayer, fishId or itemName, quantity or 1)
        elseif remote:IsA("RemoteFunction") then
            remote:InvokeServer(targetPlayer, fishId or itemName, quantity or 1)
        end
    end)
    
    return true
end

-- =====================================================
-- BAGIAN 14: UI COLOR SCHEME
-- =====================================================
local Colors = {
    Background = Color3.fromRGB(15, 17, 26),
    Sidebar = Color3.fromRGB(20, 24, 38),
    SidebarItem = Color3.fromRGB(30, 36, 58),
    SidebarItemHover = Color3.fromRGB(40, 48, 75),
    SidebarItemActive = Color3.fromRGB(45, 55, 90),
    Content = Color3.fromRGB(25, 28, 42),
    ContentItem = Color3.fromRGB(35, 40, 60),
    ContentItemHover = Color3.fromRGB(45, 52, 78),
    Accent = Color3.fromRGB(70, 130, 255),
    AccentHover = Color3.fromRGB(90, 150, 255),
    Text = Color3.fromRGB(255, 255, 255),
    TextDim = Color3.fromRGB(180, 180, 200),
    TextMuted = Color3.fromRGB(120, 125, 150),
    Border = Color3.fromRGB(50, 55, 80),
    Success = Color3.fromRGB(80, 200, 120),
    Error = Color3.fromRGB(255, 100, 100),
    Toggle = Color3.fromRGB(70, 130, 255),
    ToggleOff = Color3.fromRGB(60, 65, 90),
    DropdownBg = Color3.fromRGB(20, 22, 35),
}

-- =====================================================
-- BAGIAN 15: CREATE MAIN GUI
-- =====================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = GUI_NAMES.Main
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = SafeParent

-- BAC Bypass Identifier (Untuk Cleanup tanpa harus memakai nama pasti)
local Identifier = Instance.new("StringValue")
Identifier.Name = "VechnostIdentifier"
Identifier.Parent = ScreenGui

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 720, 0, 480)
MainFrame.Position = UDim2.new(0.5, -360, 0.5, -240)
MainFrame.BackgroundColor3 = Colors.Background
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui

Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 12)

local MainStroke = Instance.new("UIStroke", MainFrame)
MainStroke.Color = Colors.Border
MainStroke.Thickness = 1

-- Title Bar
local TitleBar = Instance.new("Frame")
TitleBar.Name = "TitleBar"
TitleBar.Size = UDim2.new(1, 0, 0, 45)
TitleBar.BackgroundColor3 = Colors.Sidebar
TitleBar.BorderSizePixel = 0
TitleBar.Parent = MainFrame

Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 12)

local TitleFix = Instance.new("Frame")
TitleFix.Size = UDim2.new(1, 0, 0, 15)
TitleFix.Position = UDim2.new(0, 0, 1, -15)
TitleFix.BackgroundColor3 = Colors.Sidebar
TitleFix.BorderSizePixel = 0
TitleFix.Parent = TitleBar

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -100, 1, 0)
TitleLabel.Position = UDim2.new(0, 15, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "Vechnost (BAC Bypassed)"
TitleLabel.TextColor3 = Colors.Text
TitleLabel.TextSize = 18
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = TitleBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 30, 0, 30)
CloseBtn.Position = UDim2.new(1, -40, 0.5, -15)
CloseBtn.BackgroundColor3 = Colors.ContentItem
CloseBtn.BorderSizePixel = 0
CloseBtn.Text = "×"
CloseBtn.TextColor3 = Colors.Text
CloseBtn.TextSize = 20
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.Parent = TitleBar
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)

local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 30, 0, 30)
MinBtn.Position = UDim2.new(1, -75, 0.5, -15)
MinBtn.BackgroundColor3 = Colors.ContentItem
MinBtn.BorderSizePixel = 0
MinBtn.Text = "—"
MinBtn.TextColor3 = Colors.Text
MinBtn.TextSize = 16
MinBtn.Font = Enum.Font.GothamBold
MinBtn.Parent = TitleBar
Instance.new("UICorner", MinBtn).CornerRadius = UDim.new(0, 6)

-- Sidebar
local Sidebar = Instance.new("Frame")
Sidebar.Name = "Sidebar"
Sidebar.Size = UDim2.new(0, 150, 1, -55)
Sidebar.Position = UDim2.new(0, 5, 0, 50)
Sidebar.BackgroundColor3 = Colors.Sidebar
Sidebar.BorderSizePixel = 0
Sidebar.Parent = MainFrame
Instance.new("UICorner", Sidebar).CornerRadius = UDim.new(0, 10)

local SidebarPadding = Instance.new("UIPadding", Sidebar)
SidebarPadding.PaddingTop = UDim.new(0, 8)
SidebarPadding.PaddingBottom = UDim.new(0, 8)
SidebarPadding.PaddingLeft = UDim.new(0, 8)
SidebarPadding.PaddingRight = UDim.new(0, 8)

local SidebarLayout = Instance.new("UIListLayout", Sidebar)
SidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder
SidebarLayout.Padding = UDim.new(0, 4)

-- Content Area
local ContentArea = Instance.new("Frame")
ContentArea.Name = "ContentArea"
ContentArea.Size = UDim2.new(1, -170, 1, -60)
ContentArea.Position = UDim2.new(0, 165, 0, 55)
ContentArea.BackgroundColor3 = Colors.Content
ContentArea.BorderSizePixel = 0
ContentArea.Parent = MainFrame
Instance.new("UICorner", ContentArea).CornerRadius = UDim.new(0, 10)

-- Dropdown Container
local DropdownContainer = Instance.new("Frame")
DropdownContainer.Name = "DropdownContainer"
DropdownContainer.Size = UDim2.new(1, 0, 1, 0)
DropdownContainer.BackgroundTransparency = 1
DropdownContainer.ZIndex = 100
DropdownContainer.Parent = ScreenGui

-- =====================================================
-- BAGIAN 16: TAB SYSTEM
-- =====================================================
local TabContents = {}
local TabButtons = {}
local CurrentTab = nil

local Tabs = {
    {Name = "Info", Icon = "👤", LayoutOrder = 1},
    {Name = "Fishing", Icon = "🎣", LayoutOrder = 2},
    {Name = "Teleport", Icon = "📍", LayoutOrder = 3},
    {Name = "Trading", Icon = "🔄", LayoutOrder = 4},
    {Name = "Shop", Icon = "🛒", LayoutOrder = 5},
    {Name = "Webhook", Icon = "🔔", LayoutOrder = 6},
    {Name = "Setting", Icon = "⚙️", LayoutOrder = 7},
}

local function CreateTabButton(tabData)
    local TabBtn = Instance.new("TextButton")
    TabBtn.Name = tabData.Name .. "Tab"
    TabBtn.Size = UDim2.new(1, 0, 0, 38)
    TabBtn.BackgroundColor3 = Colors.SidebarItem
    TabBtn.BorderSizePixel = 0
    TabBtn.Text = ""
    TabBtn.AutoButtonColor = false
    TabBtn.LayoutOrder = tabData.LayoutOrder
    TabBtn.Parent = Sidebar
    Instance.new("UICorner", TabBtn).CornerRadius = UDim.new(0, 8)
    
    local IconLabel = Instance.new("TextLabel")
    IconLabel.Size = UDim2.new(0, 28, 1, 0)
    IconLabel.Position = UDim2.new(0, 8, 0, 0)
    IconLabel.BackgroundTransparency = 1
    IconLabel.Text = tabData.Icon
    IconLabel.TextColor3 = Colors.Accent
    IconLabel.TextSize = 16
    IconLabel.Font = Enum.Font.GothamBold
    IconLabel.Parent = TabBtn
    
    local TextLabel = Instance.new("TextLabel")
    TextLabel.Size = UDim2.new(1, -42, 1, 0)
    TextLabel.Position = UDim2.new(0, 38, 0, 0)
    TextLabel.BackgroundTransparency = 1
    TextLabel.Text = tabData.Name
    TextLabel.TextColor3 = Colors.Text
    TextLabel.TextSize = 13
    TextLabel.Font = Enum.Font.GothamSemibold
    TextLabel.TextXAlignment = Enum.TextXAlignment.Left
    TextLabel.Parent = TabBtn
    
    TabBtn.MouseEnter:Connect(function()
        if CurrentTab ~= tabData.Name then
            TweenService:Create(TabBtn, TweenInfo.new(0.2), {BackgroundColor3 = Colors.SidebarItemHover}):Play()
        end
    end)
    
    TabBtn.MouseLeave:Connect(function()
        if CurrentTab ~= tabData.Name then
            TweenService:Create(TabBtn, TweenInfo.new(0.2), {BackgroundColor3 = Colors.SidebarItem}):Play()
        end
    end)
    
    return TabBtn
end

local function CreateTabContent(tabName)
    local Content = Instance.new("ScrollingFrame")
    Content.Name = tabName .. "Content"
    Content.Size = UDim2.new(1, -16, 1, -16)
    Content.Position = UDim2.new(0, 8, 0, 8)
    Content.BackgroundTransparency = 1
    Content.BorderSizePixel = 0
    Content.ScrollBarThickness = 4
    Content.ScrollBarImageColor3 = Colors.Accent
    Content.CanvasSize = UDim2.new(0, 0, 0, 0)
    Content.AutomaticCanvasSize = Enum.AutomaticSize.Y
    Content.Visible = false
    Content.Parent = ContentArea
    
    local ContentLayout = Instance.new("UIListLayout", Content)
    ContentLayout.SortOrder = Enum.SortOrder.LayoutOrder
    ContentLayout.Padding = UDim.new(0, 8)
    
    Instance.new("UIPadding", Content).PaddingBottom = UDim.new(0, 10)
    
    return Content
end

local function SwitchTab(tabName)
    if CurrentTab == tabName then return end
    
    for name, content in pairs(TabContents) do
        content.Visible = (name == tabName)
    end
    
    for name, btn in pairs(TabButtons) do
        local color = name == tabName and Colors.SidebarItemActive or Colors.SidebarItem
        TweenService:Create(btn, TweenInfo.new(0.2), {BackgroundColor3 = color}):Play()
    end
    
    CurrentTab = tabName
end

for _, tabData in ipairs(Tabs) do
    local btn = CreateTabButton(tabData)
    TabButtons[tabData.Name] = btn
    TabContents[tabData.Name] = CreateTabContent(tabData.Name)
    
    btn.MouseButton1Click:Connect(function()
        SwitchTab(tabData.Name)
    end)
end

-- =====================================================
-- BAGIAN 17: UI COMPONENT CREATORS
-- =====================================================
local LayoutOrderCounter = {}

local function GetLayoutOrder(tabName)
    LayoutOrderCounter[tabName] = (LayoutOrderCounter[tabName] or 0) + 1
    return LayoutOrderCounter[tabName]
end

local function CreateSection(tabName, sectionTitle)
    local parent = TabContents[tabName]
    if not parent then return end
    
    local Section = Instance.new("Frame")
    Section.Name = "Section_" .. sectionTitle
    Section.Size = UDim2.new(1, 0, 0, 28)
    Section.BackgroundTransparency = 1
    Section.LayoutOrder = GetLayoutOrder(tabName)
    Section.Parent = parent
    
    local SectionLabel = Instance.new("TextLabel")
    SectionLabel.Size = UDim2.new(1, 0, 1, 0)
    SectionLabel.BackgroundTransparency = 1
    SectionLabel.Text = sectionTitle
    SectionLabel.TextColor3 = Colors.Accent
    SectionLabel.TextSize = 15
    SectionLabel.Font = Enum.Font.GothamBold
    SectionLabel.TextXAlignment = Enum.TextXAlignment.Left
    SectionLabel.Parent = Section
end

local function CreateParagraph(tabName, title, content)
    local parent = TabContents[tabName]
    if not parent then return end
    
    local Paragraph = Instance.new("Frame")
    Paragraph.Name = "Paragraph_" .. title
    Paragraph.Size = UDim2.new(1, 0, 0, 55)
    Paragraph.BackgroundColor3 = Colors.ContentItem
    Paragraph.BorderSizePixel = 0
    Paragraph.LayoutOrder = GetLayoutOrder(tabName)
    Paragraph.Parent = parent
    Instance.new("UICorner", Paragraph).CornerRadius = UDim.new(0, 8)
    
    local TitleLabel = Instance.new("TextLabel")
    TitleLabel.Name = "Title"
    TitleLabel.Size = UDim2.new(1, -20, 0, 20)
    TitleLabel.Position = UDim2.new(0, 10, 0, 6)
    TitleLabel.BackgroundTransparency = 1
    TitleLabel.Text = title
    TitleLabel.TextColor3 = Colors.Text
    TitleLabel.TextSize = 13
    TitleLabel.Font = Enum.Font.GothamBold
    TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
    TitleLabel.Parent = Paragraph
    
    local ContentLabel = Instance.new("TextLabel")
    ContentLabel.Name = "Content"
    ContentLabel.Size = UDim2.new(1, -20, 0, 22)
    ContentLabel.Position = UDim2.new(0, 10, 0, 26)
    ContentLabel.BackgroundTransparency = 1
    ContentLabel.Text = content
    ContentLabel.TextColor3 = Colors.TextDim
    ContentLabel.TextSize = 11
    ContentLabel.Font = Enum.Font.Gotham
    ContentLabel.TextXAlignment = Enum.TextXAlignment.Left
    ContentLabel.TextWrapped = true
    ContentLabel.Parent = Paragraph
    
    return {
        Frame = Paragraph,
        Set = function(self, data)
            TitleLabel.Text = data.Title or TitleLabel.Text
            ContentLabel.Text = data.Content or ContentLabel.Text
        end
    }
end

local function CreateInput(tabName, name, placeholder, callback)
    local parent = TabContents[tabName]
    if not parent then return end
    
    local InputFrame = Instance.new("Frame")
    InputFrame.Name = "Input_" .. name
    InputFrame.Size = UDim2.new(1, 0, 0, 58)
    InputFrame.BackgroundColor3 = Colors.ContentItem
    InputFrame.BorderSizePixel = 0
    InputFrame.LayoutOrder = GetLayoutOrder(tabName)
    InputFrame.Parent = parent
    Instance.new("UICorner", InputFrame).CornerRadius = UDim.new(0, 8)
    
    local InputLabel = Instance.new("TextLabel")
    InputLabel.Size = UDim2.new(1, -20, 0, 18)
    InputLabel.Position = UDim2.new(0, 10, 0, 6)
    InputLabel.BackgroundTransparency = 1
    InputLabel.Text = name
    InputLabel.TextColor3 = Colors.Text
    InputLabel.TextSize = 12
    InputLabel.Font = Enum.Font.GothamSemibold
    InputLabel.TextXAlignment = Enum.TextXAlignment.Left
    InputLabel.Parent = InputFrame
    
    local TextBox = Instance.new("TextBox")
    TextBox.Size = UDim2.new(1, -20, 0, 26)
    TextBox.Position = UDim2.new(0, 10, 0, 26)
    TextBox.BackgroundColor3 = Colors.Background
    TextBox.BorderSizePixel = 0
    TextBox.Text = ""
    TextBox.PlaceholderText = placeholder or ""
    TextBox.PlaceholderColor3 = Colors.TextMuted
    TextBox.TextColor3 = Colors.Text
    TextBox.TextSize = 11
    TextBox.Font = Enum.Font.Gotham
    TextBox.ClearTextOnFocus = false
    TextBox.Parent = InputFrame
    Instance.new("UICorner", TextBox).CornerRadius = UDim.new(0, 6)
    
    local TextBoxPadding = Instance.new("UIPadding", TextBox)
    TextBoxPadding.PaddingLeft = UDim.new(0, 10)
    TextBoxPadding.PaddingRight = UDim.new(0, 10)
    
    TextBox.FocusLost:Connect(function()
        if callback then callback(TextBox.Text) end
    end)
    
    return {
        Frame = InputFrame,
        TextBox = TextBox,
        GetValue = function() return TextBox.Text end,
        SetValue = function(self, value) TextBox.Text = value end
    }
end

local function CreateButton(tabName, name, callback)
    local parent = TabContents[tabName]
    if not parent then return end
    
    local Button = Instance.new("TextButton")
    Button.Name = "Button_" .. name
    Button.Size = UDim2.new(1, 0, 0, 36)
    Button.BackgroundColor3 = Colors.Accent
    Button.BorderSizePixel = 0
    Button.Text = name
    Button.TextColor3 = Colors.Text
    Button.TextSize = 12
    Button.Font = Enum.Font.GothamSemibold
    Button.AutoButtonColor = false
    Button.LayoutOrder = GetLayoutOrder(tabName)
    Button.Parent = parent
    Instance.new("UICorner", Button).CornerRadius = UDim.new(0, 8)
    
    Button.MouseEnter:Connect(function()
        TweenService:Create(Button, TweenInfo.new(0.2), {BackgroundColor3 = Colors.AccentHover}):Play()
    end)
    
    Button.MouseLeave:Connect(function()
        TweenService:Create(Button, TweenInfo.new(0.2), {BackgroundColor3 = Colors.Accent}):Play()
    end)
    
    Button.MouseButton1Click:Connect(function()
        if callback then callback() end
    end)
    
    return Button
end

local function CreateToggle(tabName, name, default, callback)
    local parent = TabContents[tabName]
    if not parent then return end
    
    local ToggleState = default or false
    
    local ToggleFrame = Instance.new("Frame")
    ToggleFrame.Name = "Toggle_" .. name
    ToggleFrame.Size = UDim2.new(1, 0, 0, 42)
    ToggleFrame.BackgroundColor3 = Colors.ContentItem
    ToggleFrame.BorderSizePixel = 0
    ToggleFrame.LayoutOrder = GetLayoutOrder(tabName)
    ToggleFrame.Parent = parent
    Instance.new("UICorner", ToggleFrame).CornerRadius = UDim.new(0, 8)
    
    local ToggleLabel = Instance.new("TextLabel")
    ToggleLabel.Size = UDim2.new(1, -70, 1, 0)
    ToggleLabel.Position = UDim2.new(0, 12, 0, 0)
    ToggleLabel.BackgroundTransparency = 1
    ToggleLabel.Text = name
    ToggleLabel.TextColor3 = Colors.Text
    ToggleLabel.TextSize = 12
    ToggleLabel.Font = Enum.Font.GothamSemibold
    ToggleLabel.TextXAlignment = Enum.TextXAlignment.Left
    ToggleLabel.Parent = ToggleFrame
    
    local ToggleButton = Instance.new("TextButton")
    ToggleButton.Size = UDim2.new(0, 46, 0, 24)
    ToggleButton.Position = UDim2.new(1, -56, 0.5, -12)
    ToggleButton.BackgroundColor3 = ToggleState and Colors.Toggle or Colors.ToggleOff
    ToggleButton.BorderSizePixel = 0
    ToggleButton.Text = ""
    ToggleButton.AutoButtonColor = false
    ToggleButton.Parent = ToggleFrame
    Instance.new("UICorner", ToggleButton).CornerRadius = UDim.new(1, 0)
    
    local ToggleCircle = Instance.new("Frame")
    ToggleCircle.Size = UDim2.new(0, 18, 0, 18)
    ToggleCircle.Position = ToggleState and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
    ToggleCircle.BackgroundColor3 = Colors.Text
    ToggleCircle.BorderSizePixel = 0
    ToggleCircle.Parent = ToggleButton
    Instance.new("UICorner", ToggleCircle).CornerRadius = UDim.new(1, 0)
    
    local function UpdateToggle()
        local targetPos = ToggleState and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
        local targetColor = ToggleState and Colors.Toggle or Colors.ToggleOff
        TweenService:Create(ToggleCircle, TweenInfo.new(0.2), {Position = targetPos}):Play()
        TweenService:Create(ToggleButton, TweenInfo.new(0.2), {BackgroundColor3 = targetColor}):Play()
    end
    
    ToggleButton.MouseButton1Click:Connect(function()
        ToggleState = not ToggleState
        UpdateToggle()
        if callback then callback(ToggleState) end
    end)
    
    return {
        Frame = ToggleFrame,
        SetValue = function(self, value)
            ToggleState = value
            UpdateToggle()
        end,
        GetValue = function() return ToggleState end
    }
end

local function CreateSlider(tabName, name, min, max, default, callback)
    local parent = TabContents[tabName]
    if not parent then return end
    
    local SliderValue = default or min
    
    local SliderFrame = Instance.new("Frame")
    SliderFrame.Name = "Slider_" .. name
    SliderFrame.Size = UDim2.new(1, 0, 0, 52)
    SliderFrame.BackgroundColor3 = Colors.ContentItem
    SliderFrame.BorderSizePixel = 0
    SliderFrame.LayoutOrder = GetLayoutOrder(tabName)
    SliderFrame.Parent = parent
    Instance.new("UICorner", SliderFrame).CornerRadius = UDim.new(0, 8)
    
    local SliderLabel = Instance.new("TextLabel")
    SliderLabel.Size = UDim2.new(1, -60, 0, 18)
    SliderLabel.Position = UDim2.new(0, 10, 0, 6)
    SliderLabel.BackgroundTransparency = 1
    SliderLabel.Text = name
    SliderLabel.TextColor3 = Colors.Text
    SliderLabel.TextSize = 12
    SliderLabel.Font = Enum.Font.GothamSemibold
    SliderLabel.TextXAlignment = Enum.TextXAlignment.Left
    SliderLabel.Parent = SliderFrame
    
    local ValueLabel = Instance.new("TextLabel")
    ValueLabel.Size = UDim2.new(0, 45, 0, 18)
    ValueLabel.Position = UDim2.new(1, -55, 0, 6)
    ValueLabel.BackgroundTransparency = 1
    ValueLabel.Text = tostring(SliderValue)
    ValueLabel.TextColor3 = Colors.Accent
    ValueLabel.TextSize = 12
    ValueLabel.Font = Enum.Font.GothamBold
    ValueLabel.TextXAlignment = Enum.TextXAlignment.Right
    ValueLabel.Parent = SliderFrame
    
    local SliderTrack = Instance.new("Frame")
    SliderTrack.Size = UDim2.new(1, -20, 0, 8)
    SliderTrack.Position = UDim2.new(0, 10, 0, 34)
    SliderTrack.BackgroundColor3 = Colors.Background
    SliderTrack.BorderSizePixel = 0
    SliderTrack.Parent = SliderFrame
    Instance.new("UICorner", SliderTrack).CornerRadius = UDim.new(1, 0)
    
    local SliderFill = Instance.new("Frame")
    SliderFill.Size = UDim2.new((SliderValue - min) / (max - min), 0, 1, 0)
    SliderFill.BackgroundColor3 = Colors.Accent
    SliderFill.BorderSizePixel = 0
    SliderFill.Parent = SliderTrack
    Instance.new("UICorner", SliderFill).CornerRadius = UDim.new(1, 0)
    
    local SliderKnob = Instance.new("Frame")
    SliderKnob.Size = UDim2.new(0, 14, 0, 14)
    SliderKnob.Position = UDim2.new((SliderValue - min) / (max - min), -7, 0.5, -7)
    SliderKnob.BackgroundColor3 = Colors.Text
    SliderKnob.BorderSizePixel = 0
    SliderKnob.Parent = SliderTrack
    Instance.new("UICorner", SliderKnob).CornerRadius = UDim.new(1, 0)
    
    local draggingSlider = false
    
    local function UpdateSlider(value)
        SliderValue = math.clamp(math.floor(value), min, max)
        local percent = (SliderValue - min) / (max - min)
        SliderFill.Size = UDim2.new(percent, 0, 1, 0)
        SliderKnob.Position = UDim2.new(percent, -7, 0.5, -7)
        ValueLabel.Text = tostring(SliderValue)
        if callback then callback(SliderValue) end
    end
    
    SliderTrack.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = true
            local percent = math.clamp((input.Position.X - SliderTrack.AbsolutePosition.X) / SliderTrack.AbsoluteSize.X, 0, 1)
            UpdateSlider(min + percent * (max - min))
        end
    end)
    
    SliderTrack.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = false
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if draggingSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local percent = math.clamp((input.Position.X - SliderTrack.AbsolutePosition.X) / SliderTrack.AbsoluteSize.X, 0, 1)
            UpdateSlider(min + percent * (max - min))
        end
    end)
    
    return {
        Frame = SliderFrame,
        SetValue = function(self, value) UpdateSlider(value) end,
        GetValue = function() return SliderValue end
    }
end

-- =====================================================
-- BAGIAN 18: FIXED DROPDOWN COMPONENT
-- =====================================================
local ActiveDropdown = nil

local function CreateDropdown(tabName, name, options, default, callback)
    local parent = TabContents[tabName]
    if not parent then return end
    
    local SelectedOption = default
    local IsOpen = false
    local OptionsFrameRef = nil
    
    local DropdownFrame = Instance.new("Frame")
    DropdownFrame.Name = "Dropdown_" .. name
    DropdownFrame.Size = UDim2.new(1, 0, 0, 58)
    DropdownFrame.BackgroundColor3 = Colors.ContentItem
    DropdownFrame.BorderSizePixel = 0
    DropdownFrame.LayoutOrder = GetLayoutOrder(tabName)
    DropdownFrame.Parent = parent
    Instance.new("UICorner", DropdownFrame).CornerRadius = UDim.new(0, 8)
    
    local DropdownLabel = Instance.new("TextLabel")
    DropdownLabel.Size = UDim2.new(1, -20, 0, 18)
    DropdownLabel.Position = UDim2.new(0, 10, 0, 6)
    DropdownLabel.BackgroundTransparency = 1
    DropdownLabel.Text = name
    DropdownLabel.TextColor3 = Colors.Text
    DropdownLabel.TextSize = 12
    DropdownLabel.Font = Enum.Font.GothamSemibold
    DropdownLabel.TextXAlignment = Enum.TextXAlignment.Left
    DropdownLabel.Parent = DropdownFrame
    
    local DropdownButton = Instance.new("TextButton")
    DropdownButton.Size = UDim2.new(1, -20, 0, 26)
    DropdownButton.Position = UDim2.new(0, 10, 0, 26)
    DropdownButton.BackgroundColor3 = Colors.Background
    DropdownButton.BorderSizePixel = 0
    DropdownButton.Text = ""
    DropdownButton.AutoButtonColor = false
    DropdownButton.Parent = DropdownFrame
    Instance.new("UICorner", DropdownButton).CornerRadius = UDim.new(0, 6)
    
    local SelectedLabel = Instance.new("TextLabel")
    SelectedLabel.Size = UDim2.new(1, -30, 1, 0)
    SelectedLabel.Position = UDim2.new(0, 10, 0, 0)
    SelectedLabel.BackgroundTransparency = 1
    SelectedLabel.Text = SelectedOption or "Select..."
    SelectedLabel.TextColor3 = SelectedOption and Colors.Text or Colors.TextMuted
    SelectedLabel.TextSize = 11
    SelectedLabel.Font = Enum.Font.Gotham
    SelectedLabel.TextXAlignment = Enum.TextXAlignment.Left
    SelectedLabel.TextTruncate = Enum.TextTruncate.AtEnd
    SelectedLabel.Parent = DropdownButton
    
    local ArrowLabel = Instance.new("TextLabel")
    ArrowLabel.Size = UDim2.new(0, 20, 1, 0)
    ArrowLabel.Position = UDim2.new(1, -25, 0, 0)
    ArrowLabel.BackgroundTransparency = 1
    ArrowLabel.Text = "▼"
    ArrowLabel.TextColor3 = Colors.TextMuted
    ArrowLabel.TextSize = 10
    ArrowLabel.Font = Enum.Font.Gotham
    ArrowLabel.Parent = DropdownButton
    
    local function CloseDropdown()
        if OptionsFrameRef then
            OptionsFrameRef:Destroy()
            OptionsFrameRef = nil
        end
        IsOpen = false
        TweenService:Create(ArrowLabel, TweenInfo.new(0.2), {Rotation = 0}):Play()
        ActiveDropdown = nil
    end
    
    local function OpenDropdown()
        if ActiveDropdown and ActiveDropdown ~= CloseDropdown then
            ActiveDropdown()
        end
        
        ActiveDropdown = CloseDropdown
        IsOpen = true
        TweenService:Create(ArrowLabel, TweenInfo.new(0.2), {Rotation = 180}):Play()
        
        local buttonPos = DropdownButton.AbsolutePosition
        local buttonSize = DropdownButton.AbsoluteSize
        
        local OptionsFrame = Instance.new("Frame")
        OptionsFrame.Name = "DropdownOptions"
        OptionsFrame.Size = UDim2.new(0, buttonSize.X, 0, math.min(#options * 28 + 8, 150))
        OptionsFrame.Position = UDim2.fromOffset(buttonPos.X, buttonPos.Y + buttonSize.Y + 5)
        OptionsFrame.BackgroundColor3 = Colors.DropdownBg
        OptionsFrame.BorderSizePixel = 0
        OptionsFrame.ZIndex = 100
        OptionsFrame.Parent = DropdownContainer
        Instance.new("UICorner", OptionsFrame).CornerRadius = UDim.new(0, 6)
        
        local OptionsStroke = Instance.new("UIStroke", OptionsFrame)
        OptionsStroke.Color = Colors.Border
        OptionsStroke.Thickness = 1
        
        local OptionsScroll = Instance.new("ScrollingFrame")
        OptionsScroll.Size = UDim2.new(1, -8, 1, -8)
        OptionsScroll.Position = UDim2.new(0, 4, 0, 4)
        OptionsScroll.BackgroundTransparency = 1
        OptionsScroll.BorderSizePixel = 0
        OptionsScroll.ScrollBarThickness = 3
        OptionsScroll.ScrollBarImageColor3 = Colors.Accent
        OptionsScroll.CanvasSize = UDim2.new(0, 0, 0, #options * 28)
        OptionsScroll.ZIndex = 101
        OptionsScroll.Parent = OptionsFrame
        
        local OptionsLayout = Instance.new("UIListLayout", OptionsScroll)
        OptionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
        OptionsLayout.Padding = UDim.new(0, 2)
        
        OptionsFrameRef = OptionsFrame
        
        for i, optionName in ipairs(options) do
            local OptBtn = Instance.new("TextButton")
            OptBtn.Name = optionName
            OptBtn.Size = UDim2.new(1, 0, 0, 26)
            OptBtn.BackgroundColor3 = optionName == SelectedOption and Colors.Accent or Colors.ContentItem
            OptBtn.BorderSizePixel = 0
            OptBtn.Text = optionName
            OptBtn.TextColor3 = Colors.Text
            OptBtn.TextSize = 11
            OptBtn.Font = Enum.Font.Gotham
            OptBtn.AutoButtonColor = false
            OptBtn.LayoutOrder = i
            OptBtn.ZIndex = 102
            OptBtn.Parent = OptionsScroll
            Instance.new("UICorner", OptBtn).CornerRadius = UDim.new(0, 4)
            
            OptBtn.MouseEnter:Connect(function()
                if optionName ~= SelectedOption then
                    TweenService:Create(OptBtn, TweenInfo.new(0.1), {BackgroundColor3 = Colors.ContentItemHover}):Play()
                end
            end)
            
            OptBtn.MouseLeave:Connect(function()
                if optionName ~= SelectedOption then
                    TweenService:Create(OptBtn, TweenInfo.new(0.1), {BackgroundColor3 = Colors.ContentItem}):Play()
                end
            end)
            
            OptBtn.MouseButton1Click:Connect(function()
                SelectedOption = optionName
                SelectedLabel.Text = optionName
                SelectedLabel.TextColor3 = Colors.Text
                
                if callback then callback(optionName) end
                
                CloseDropdown()
            end)
        end
    end
    
    DropdownButton.MouseButton1Click:Connect(function()
        if IsOpen then
            CloseDropdown()
        else
            OpenDropdown()
        end
    end)
    
    return {
        Frame = DropdownFrame,
        Refresh = function(self, newOptions, keepSelected)
            options = newOptions
            if not keepSelected then
                SelectedOption = nil
                SelectedLabel.Text = "Select..."
                SelectedLabel.TextColor3 = Colors.TextMuted
            end
            if IsOpen then
                CloseDropdown()
            end
        end,
        SetValue = function(self, value)
            SelectedOption = value
            SelectedLabel.Text = value or "Select..."
            SelectedLabel.TextColor3 = value and Colors.Text or Colors.TextMuted
        end,
        GetValue = function() return SelectedOption end
    }
end

UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        if ActiveDropdown then
            task.defer(function()
                task.wait(0.05)
                if ActiveDropdown then
                    ActiveDropdown()
                end
            end)
        end
    end
end)

-- =====================================================
-- BAGIAN 19: NOTIFICATION SYSTEM
-- =====================================================
local NotificationContainer = Instance.new("Frame")
NotificationContainer.Name = "Notifications"
NotificationContainer.Size = UDim2.new(0, 280, 1, 0)
NotificationContainer.Position = UDim2.new(1, -290, 0, 0)
NotificationContainer.BackgroundTransparency = 1
NotificationContainer.Parent = ScreenGui

local NotificationLayout = Instance.new("UIListLayout", NotificationContainer)
NotificationLayout.SortOrder = Enum.SortOrder.LayoutOrder
NotificationLayout.Padding = UDim.new(0, 8)
NotificationLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom

Instance.new("UIPadding", NotificationContainer).PaddingBottom = UDim.new(0, 20)

local function Notify(title, content, duration)
    duration = duration or 3
    
    local Notification = Instance.new("Frame")
    Notification.Size = UDim2.new(0, 260, 0, 65)
    Notification.BackgroundColor3 = Colors.Sidebar
    Notification.BorderSizePixel = 0
    Notification.BackgroundTransparency = 1
    Notification.Parent = NotificationContainer
    Instance.new("UICorner", Notification).CornerRadius = UDim.new(0, 10)
    
    local NotifStroke = Instance.new("UIStroke", Notification)
    NotifStroke.Color = Colors.Accent
    NotifStroke.Transparency = 1
    
    local NotifTitle = Instance.new("TextLabel")
    NotifTitle.Size = UDim2.new(1, -20, 0, 20)
    NotifTitle.Position = UDim2.new(0, 10, 0, 8)
    NotifTitle.BackgroundTransparency = 1
    NotifTitle.Text = title
    NotifTitle.TextColor3 = Colors.Accent
    NotifTitle.TextSize = 13
    NotifTitle.Font = Enum.Font.GothamBold
    NotifTitle.TextXAlignment = Enum.TextXAlignment.Left
    NotifTitle.Parent = Notification
    
    local NotifContent = Instance.new("TextLabel")
    NotifContent.Size = UDim2.new(1, -20, 0, 28)
    NotifContent.Position = UDim2.new(0, 10, 0, 28)
    NotifContent.BackgroundTransparency = 1
    NotifContent.Text = content
    NotifContent.TextColor3 = Colors.TextDim
    NotifContent.TextSize = 11
    NotifContent.Font = Enum.Font.Gotham
    NotifContent.TextXAlignment = Enum.TextXAlignment.Left
    NotifContent.TextWrapped = true
    NotifContent.Parent = Notification
    
    TweenService:Create(Notification, TweenInfo.new(0.3), {BackgroundTransparency = 0}):Play()
    TweenService:Create(NotifStroke, TweenInfo.new(0.3), {Transparency = 0}):Play()
    
    task.delay(duration, function()
        TweenService:Create(Notification, TweenInfo.new(0.3), {BackgroundTransparency = 1}):Play()
        TweenService:Create(NotifStroke, TweenInfo.new(0.3), {Transparency = 1}):Play()
        task.wait(0.3)
        Notification:Destroy()
    end)
end

-- =====================================================
-- BAGIAN 20: POPULATE TAB CONTENTS
-- =====================================================

-- ===== INFO TAB =====
CreateSection("Info", "Player Information")
CreateParagraph("Info", "Player", LocalPlayer.Name)
local InfoStats = CreateParagraph("Info", "Statistics", "Loading...")

task.spawn(function()
    while task.wait(3) do
        local stats = GetPlayerStats()
        InfoStats:Set({
            Title = "Statistics",
            Content = string.format("Coins: %s | Fish: %s | Backpack: %d/%d",
                FormatNumber(stats.Coins), FormatNumber(stats.TotalCaught),
                stats.BackpackCount, stats.BackpackMax)
        })
    end
end)

CreateSection("Info", "About")
CreateParagraph("Info", "Vechnost v2.5.0 (Bypassed)", "Complete Fish It Automation Suite\nby Vechnost Team")

-- ===== FISHING TAB =====
CreateSection("Fishing", "Auto Fishing")

CreateToggle("Fishing", "Auto Cast", false, function(v)
    FishingSettings.AutoCast = v
    Notify("Vechnost", v and "Auto Cast ON" or "Auto Cast OFF", 2)
end)

CreateToggle("Fishing", "Auto Reel", false, function(v)
    FishingSettings.AutoReel = v
    Notify("Vechnost", v and "Auto Reel ON" or "Auto Reel OFF", 2)
end)

CreateToggle("Fishing", "Auto Shake", false, function(v)
    FishingSettings.AutoShake = v
    Notify("Vechnost", v and "Auto Shake ON" or "Auto Shake OFF", 2)
end)

CreateSection("Fishing", "Clicker Settings")
CreateSlider("Fishing", "Click Speed (CPS)", 10, 100, 50, function(v)
    FishingSettings.ClickSpeed = v
end)

CreateToggle("Fishing", "Perfect Catch", false, function(v)
    FishingSettings.PerfectCatch = v
    Notify("Vechnost", v and "Perfect Catch ON" or "Perfect Catch OFF", 2)
end)

CreateSection("Fishing", "Utility")
CreateToggle("Fishing", "Anti AFK", false, function(v)
    FishingSettings.AntiAFK = v
    -- BAC Bypass: Safely disable game idle kicker without firing VirtualUser constantly
    pcall(function()
        local GC = getconnections or get_signal_cons
        if GC then
            for _, conn in pairs(GC(LocalPlayer.Idled)) do
                if v then
                    conn:Disable()
                else
                    conn:Enable()
                end
            end
        end
    end)
    Notify("Vechnost", v and "Anti AFK ON (Stealth Mode)" or "Anti AFK OFF", 2)
end)

CreateToggle("Fishing", "Auto Sell", false, function(v)
    FishingSettings.AutoSell = v
    Notify("Vechnost", v and "Auto Sell ON" or "Auto Sell OFF", 2)
end)

-- ===== TELEPORT TAB =====
CreateSection("Teleport", "Island Teleport")

local TeleportDropdown = CreateDropdown("Teleport", "Select Island", GetTeleportLocationNames(), nil, function(selected)
    if selected and selected ~= "(Scan locations first)" then
        local success, msg = TeleportTo(selected)
        Notify("Vechnost", success and msg or ("Failed: " .. msg), 2)
    end
end)

CreateButton("Teleport", "Refresh Locations", function()
    ScanIslands()
    TeleportDropdown:Refresh(GetTeleportLocationNames(), false)
    Notify("Vechnost", "Found " .. #TeleportLocations .. " locations", 2)
end)

CreateSection("Teleport", "Quick Teleport")

CreateButton("Teleport", "TP to Spawn", function()
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        local spawn = Workspace:FindFirstChildOfClass("SpawnLocation")
        if spawn then
            char.HumanoidRootPart.CFrame = spawn.CFrame + Vector3.new(0, 5, 0)
            Notify("Vechnost", "Teleported to Spawn", 2)
        end
    end
end)

CreateButton("Teleport", "TP to Nearest Player", function()
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return end
    
    local myPos = char.HumanoidRootPart.Position
    local nearest, nearestDist = nil, math.huge
    
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
            local dist = (p.Character.HumanoidRootPart.Position - myPos).Magnitude
            if dist < nearestDist then
                nearestDist = dist
                nearest = p
            end
        end
    end
    
    if nearest then
        char.HumanoidRootPart.CFrame = nearest.Character.HumanoidRootPart.CFrame + Vector3.new(3, 0, 0)
        Notify("Vechnost", "Teleported to " .. nearest.Name, 2)
    else
        Notify("Vechnost", "No players found", 2)
    end
end)

-- ===== TRADING TAB =====
CreateSection("Trading", "Select Target Player")

local PlayerNames = {}
for _, p in pairs(Players:GetPlayers()) do
    if p ~= LocalPlayer then
        table.insert(PlayerNames, p.Name)
    end
end
if #PlayerNames == 0 then PlayerNames = {"(No players)"} end

local PlayerDropdown = CreateDropdown("Trading", "Select Player", PlayerNames, nil, function(selected)
    if selected and selected ~= "(No players)" then
        TradeState.TargetPlayer = selected
        Notify("Vechnost", "Target: " .. selected, 2)
    end
end)

CreateButton("Trading", "Refresh Player List", function()
    local list = {}
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then table.insert(list, p.Name) end
    end
    if #list == 0 then list = {"(No players)"} end
    PlayerDropdown:Refresh(list, false)
    Notify("Vechnost", "Found " .. #list .. " players", 2)
end)

CreateSection("Trading", "Trade by Name")

local TradeNameStatus = CreateParagraph("Trading", "Trade Status", "Ready")

local ItemDropdown = CreateDropdown("Trading", "Select Item", {"(Load inventory)"}, nil, function(selected)
    if selected and selected ~= "(Load inventory)" then
        TradeState.ByName.ItemName = selected
    end
end)

CreateButton("Trading", "Load Inventory", function()
    LoadInventory()
    local names = GetInventoryItemNames()
    ItemDropdown:Refresh(names, false)
    Notify("Vechnost", "Loaded " .. #names .. " items", 2)
end)

local TradeAmountBuffer = "1"
CreateInput("Trading", "Amount", "1", function(text)
    TradeAmountBuffer = text
    local n = tonumber(text)
    if n and n > 0 then TradeState.ByName.Amount = math.floor(n) end
end)

local TradeByNameToggle = CreateToggle("Trading", "Start Trade", false, function(v)
    if v then
        if not TradeState.TargetPlayer then
            Notify("Vechnost", "Select target first!", 3)
            TradeByNameToggle:SetValue(false)
            return
        end
        if not TradeState.ByName.ItemName then
            Notify("Vechnost", "Select item first!", 3)
            TradeByNameToggle:SetValue(false)
            return
        end
        
        TradeState.ByName.Active = true
        TradeState.ByName.Sent = 0
        
        task.spawn(function()
            local total = TradeState.ByName.Amount
            local itemName = TradeState.ByName.ItemName
            local target = TradeState.TargetPlayer
            
            for i = 1, total do
                if not TradeState.ByName.Active then break end
                
                TradeNameStatus:Set({
                    Title = "Trade Status",
                    Content = string.format("Sending: %d/%d %s", i, total, itemName)
                })
                
                FireTradeItem(target, itemName, 1)
                TradeState.ByName.Sent = i
                task.wait(0.5)
            end
            
            TradeState.ByName.Active = false
            TradeByNameToggle:SetValue(false)
            TradeNameStatus:Set({
                Title = "Trade Status",
                Content = string.format("Done: %d/%d sent", TradeState.ByName.Sent, total)
            })
            Notify("Vechnost", "Trade complete!", 2)
        end)
    else
        TradeState.ByName.Active = false
    end
end)

CreateSection("Trading", "Trade by Rarity")

local RarityDropdown = CreateDropdown("Trading", "Select Rarity", RarityList, nil, function(selected)
    if selected then
        TradeState.ByRarity.Rarity = selected
        TradeState.ByRarity.RarityTier = RARITY_NAME_TO_TIER[selected]
        Notify("Vechnost", "Selected: " .. selected, 2)
    end
end)

CreateSection("Trading", "Trade Stone")

local StoneDropdown = CreateDropdown("Trading", "Select Stone", STONE_LIST, nil, function(selected)
    if selected then
        TradeState.ByStone.StoneName = selected
    end
end)

-- ===== SHOP TAB =====
CreateSection("Shop", "Auto Buy Charm")

local CharmDropdown = CreateDropdown("Shop", "Select Charm", ShopDB.Charms, nil, function(selected)
    ShopSettings.SelectedCharm = selected
end)

CreateToggle("Shop", "Auto Buy Charm", false, function(v)
    ShopSettings.AutoBuyCharm = v
    if v and ShopSettings.SelectedCharm then
        task.spawn(function()
            while ShopSettings.AutoBuyCharm do
                BuyShopItem("Charm", ShopSettings.SelectedCharm)
                task.wait(1)
            end
        end)
    end
    Notify("Vechnost", v and "Auto Buy Charm ON" or "Auto Buy Charm OFF", 2)
end)

CreateSection("Shop", "Auto Buy Weather")

local WeatherDropdown = CreateDropdown("Shop", "Select Weather", ShopDB.Weather, nil, function(selected)
    ShopSettings.SelectedWeather = selected
end)

CreateToggle("Shop", "Auto Buy Weather", false, function(v)
    ShopSettings.AutoBuyWeather = v
    if v and ShopSettings.SelectedWeather then
        BuyShopItem("Weather", ShopSettings.SelectedWeather)
    end
    Notify("Vechnost", v and "Weather changed!" or "Auto Buy Weather OFF", 2)
end)

CreateSection("Shop", "Auto Buy Bait")

local BaitDropdown = CreateDropdown("Shop", "Select Bait", ShopDB.Bait, nil, function(selected)
    ShopSettings.SelectedBait = selected
end)

CreateToggle("Shop", "Auto Buy Bait", false, function(v)
    ShopSettings.AutoBuyBait = v
    if v and ShopSettings.SelectedBait then
        task.spawn(function()
            while ShopSettings.AutoBuyBait do
                BuyShopItem("Bait", ShopSettings.SelectedBait)
                task.wait(2)
            end
        end)
    end
    Notify("Vechnost", v and "Auto Buy Bait ON" or "Auto Buy Bait OFF", 2)
end)

CreateSection("Shop", "Merchant Shop")

local MerchantDropdown = CreateDropdown("Shop", "Select Item", ShopDB.Merchant, nil, function(selected)
    -- Item selected
end)

CreateButton("Shop", "Buy Selected Item", function()
    local selected = MerchantDropdown:GetValue()
    if selected then
        BuyShopItem("Merchant", selected)
        Notify("Vechnost", "Purchased: " .. selected, 2)
    else
        Notify("Vechnost", "Select item first!", 2)
    end
end)

-- ===== WEBHOOK TAB =====
CreateSection("Webhook", "Rarity Filter")

local WebhookRarityDropdown = CreateDropdown("Webhook", "Filter Rarity", RarityList, nil, function(selected)
    if selected then
        Settings.SelectedRarities = {}
        local tier = RARITY_NAME_TO_TIER[selected]
        if tier then Settings.SelectedRarities[tier] = true end
        Notify("Vechnost", "Filter: " .. selected, 2)
    end
end)

CreateButton("Webhook", "Clear Filter (All Rarity)", function()
    Settings.SelectedRarities = {}
    WebhookRarityDropdown:SetValue(nil)
    Notify("Vechnost", "Filter cleared - All rarities", 2)
end)

CreateSection("Webhook", "Setup")

local WebhookUrlBuffer = ""
CreateInput("Webhook", "Discord Webhook URL", "https://discord.com/api/webhooks/...", function(text)
    WebhookUrlBuffer = text
end)

CreateButton("Webhook", "Save Webhook URL", function()
    local url = WebhookUrlBuffer:gsub("%s+", "")
    if not url:match("^https://discord.com/api/webhooks/") and not url:match("^https://canary.discord.com/api/webhooks/") then
        Notify("Vechnost", "Invalid webhook URL!", 3)
        return
    end
    Settings.Url = url
    Notify("Vechnost", "Webhook URL saved!", 2)
end)

CreateSection("Webhook", "Mode")

CreateToggle("Webhook", "Server-Wide Mode", true, function(v)
    Settings.ServerWide = v
    Notify("Vechnost", v and "Mode: Server-Wide" or "Mode: Local Only", 2)
end)

CreateSection("Webhook", "Control")

local WebhookToggle = CreateToggle("Webhook", "Enable Logger", false, function(v)
    if v then
        if Settings.Url == "" then
            Notify("Vechnost", "Set webhook URL first!", 3)
            WebhookToggle:SetValue(false)
            return
        end
        local success, msg = StartLogger()
        if success then
            Notify("Vechnost", "Logger started!", 2)
        else
            Notify("Vechnost", msg, 3)
            WebhookToggle:SetValue(false)
        end
    else
        StopLogger()
        Notify("Vechnost", "Logger stopped", 2)
    end
end)

CreateSection("Webhook", "Status")

local WebhookStatus = CreateParagraph("Webhook", "Logger Status", "Offline")

task.spawn(function()
    while task.wait(2) do
        if Settings.Active then
            WebhookStatus:Set({
                Title = "Logger Status",
                Content = string.format("Active | Mode: %s | Logged: %d",
                    Settings.ServerWide and "Server-Wide" or "Local",
                    Settings.LogCount)
            })
        else
            WebhookStatus:Set({ Title = "Logger Status", Content = "Offline" })
        end
    end
end)

-- ===== SETTING TAB =====
CreateSection("Setting", "Testing")

CreateButton("Setting", "Test Webhook", function()
    if Settings.Url == "" then
        Notify("Vechnost", "Set webhook URL first!", 3)
        return
    end
    
    SendWebhook({
        username = "Vechnost Notifier",
        avatar_url = "https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png",
        flags = 32768,
        components = {{
            type = 17,
            accent_color = 0x5865f2,
            components = {
                { type = 10, content = "**Test Message**" },
                { type = 14, spacing = 1, divider = true },
                { type = 10, content = "Webhook is working!\n\n- **Sent by:** " .. LocalPlayer.Name },
                { type = 10, content = "-# " .. os.date("!%B %d, %Y") }
            }
        }}
    })
    
    Notify("Vechnost", "Test message sent!", 2)
end)

CreateButton("Setting", "Reset Counter", function()
    Settings.LogCount = 0
    Settings.SentUUID = {}
    Notify("Vechnost", "Counter reset!", 2)
end)

CreateSection("Setting", "UI")

CreateButton("Setting", "Toggle UI (Press V)", function()
    MainFrame.Visible = not MainFrame.Visible
end)

CreateSection("Setting", "Credits")
CreateParagraph("Setting", "Vechnost Team", "Thanks for using Vechnost!\nDiscord: discord.gg/vechnost")

-- =====================================================
-- BAGIAN 21: UI CONTROLS
-- =====================================================

-- Drag
local dragging = false
local dragOffset = Vector2.zero

TitleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragOffset = Vector2.new(input.Position.X, input.Position.Y) - Vector2.new(MainFrame.AbsolutePosition.X, MainFrame.AbsolutePosition.Y)
    end
end)

TitleBar.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local newPos = Vector2.new(input.Position.X, input.Position.Y) - dragOffset
        MainFrame.Position = UDim2.fromOffset(newPos.X, newPos.Y)
    end
end)

-- Close
CloseBtn.MouseEnter:Connect(function()
    TweenService:Create(CloseBtn, TweenInfo.new(0.15), {BackgroundColor3 = Colors.Error}):Play()
end)
CloseBtn.MouseLeave:Connect(function()
    TweenService:Create(CloseBtn, TweenInfo.new(0.15), {BackgroundColor3 = Colors.ContentItem}):Play()
end)
CloseBtn.MouseButton1Click:Connect(function()
    ScreenGui:Destroy()
end)

-- Minimize
local isMinimized = false
MinBtn.MouseEnter:Connect(function()
    TweenService:Create(MinBtn, TweenInfo.new(0.15), {BackgroundColor3 = Colors.ContentItemHover}):Play()
end)
MinBtn.MouseLeave:Connect(function()
    TweenService:Create(MinBtn, TweenInfo.new(0.15), {BackgroundColor3 = Colors.ContentItem}):Play()
end)
MinBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    local targetSize = isMinimized and UDim2.new(0, 720, 0, 45) or UDim2.new(0, 720, 0, 480)
    TweenService:Create(MainFrame, TweenInfo.new(0.3), {Size = targetSize}):Play()
end)

-- Keyboard toggle
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.V then
        MainFrame.Visible = not MainFrame.Visible
    end
end)

-- =====================================================
-- BAGIAN 22: MOBILE BUTTON
-- =====================================================
local oldBtn
for _, v in pairs(SafeParent:GetChildren()) do
    if v:IsA("ScreenGui") and v:FindFirstChild("VechnostIdentifier") and v.Name == GUI_NAMES.Mobile then
        v:Destroy()
    end
end

local BtnGui = Instance.new("ScreenGui")
BtnGui.Name = GUI_NAMES.Mobile
BtnGui.ResetOnSpawn = false
BtnGui.Parent = SafeParent

local MobIdentifier = Instance.new("StringValue")
MobIdentifier.Name = "VechnostIdentifier"
MobIdentifier.Parent = BtnGui

local FloatButton = Instance.new("ImageButton")
FloatButton.Size = UDim2.fromOffset(52, 52)
FloatButton.Position = UDim2.fromScale(0.05, 0.5)
FloatButton.BackgroundTransparency = 1
FloatButton.AutoButtonColor = false
FloatButton.Image = "rbxassetid://127239715511367"
FloatButton.Parent = BtnGui
Instance.new("UICorner", FloatButton).CornerRadius = UDim.new(1, 0)

FloatButton.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

local floatDragging = false
local floatDragOffset = Vector2.zero

FloatButton.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        floatDragging = true
        floatDragOffset = UserInputService:GetMouseLocation() - FloatButton.AbsolutePosition
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                floatDragging = false
            end
        end)
    end
end)

RunService.RenderStepped:Connect(function()
    if not floatDragging then return end
    local mouse = UserInputService:GetMouseLocation()
    local target = mouse - floatDragOffset
    local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
    local sz = FloatButton.AbsoluteSize
    FloatButton.Position = UDim2.fromOffset(
        math.clamp(target.X, 0, vp.X - sz.X),
        math.clamp(target.Y, 0, vp.Y - sz.Y)
    )
end)

-- =====================================================
-- BAGIAN 23: INIT
-- =====================================================
SwitchTab("Info")

warn("[Vechnost] v2.5.0 Bypassed Loaded!")
warn("[Vechnost] Toggle: Press V or tap floating button")
Notify("Vechnost", "Script bypassed & loaded successfully!", 3)
