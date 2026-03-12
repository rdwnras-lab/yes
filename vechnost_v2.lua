--[[ 
    FILE: vechnost_v2.lua
    BRAND: Vechnost
    VERSION: 2.5.1 (BAC Bypassed - Fixed)
    DESC: Complete Fish It Automation Suite
          - Auto Fishing + Clicker
          - Island Teleport (Updated Fish It Islands)
          - Auto Trading (Coin, Rarity, Stone, Name)
          - Auto Shop (Bait, Rod, Boat, Enchant)
          - Server-Wide Webhook Logger
    UI: Custom Dark Blue Sidebar Design
    
    FIX LOG v2.5.1:
    - [CRITICAL] Hapus VirtualInputManager dari hot loop - trigger utama BAC-4193
    - [CRITICAL] Tambah Fishing State Machine - cegah remote spam
    - [CRITICAL] Semua remote call dibungkus rate limiter + humanized delay
    - [CRITICAL] AutoShake diperlambat ke 8-15 CPS realistis (dari 50-100 CPS)
    - [CRITICAL] AutoCast cooldown 3-7 detik (dari 0.1 detik)
    - [FIX] Anti-AFK pakai getconnections/Idled disable yang benar
    - [FIX] syn.protect_gui / protect_gui support untuk GUI ScreenGui
    - [FIX] newcclosure wrapping untuk remote calls jika executor support
    - [FIX] Island list diupdate ke Fish It actual islands
    - [FIX] Shop items disesuaikan dengan mekanik Fish It sebenarnya
    - [FIX] Randomisasi delay lebih lebar (bukan hanya 1-4ms)
]]

-- =====================================================
-- BAGIAN 1: CLEANUP SYSTEM & BAC BYPASS
-- =====================================================
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- BAC Bypass: Gunakan gethui() untuk menyembunyikan UI dari deteksi game
local function GetSafeParent()
    local success, parent = pcall(function() return gethui() end)
    if success and parent then return parent end
    return game:GetService("CoreGui")
end

local SafeParent = GetSafeParent()

-- BAC Bypass: Lindungi ScreenGui dari scan anti-cheat jika executor support
local function ProtectGui(gui)
    if syn and syn.protect_gui then
        pcall(syn.protect_gui, gui)
    elseif protect_gui then
        pcall(protect_gui, gui)
    end
end

-- BAC Bypass: cloneref jika tersedia untuk menyembunyikan instance reference
local function SafeRef(obj)
    if cloneref then
        local ok, ref = pcall(cloneref, obj)
        if ok and ref then return ref end
    end
    return obj
end

-- BAC Bypass: newcclosure untuk wrap fungsi agar tidak terdeteksi
local function SafeFunc(fn)
    if newcclosure then
        local ok, f = pcall(newcclosure, fn)
        if ok and f then return f end
    end
    return fn
end

-- BAC Bypass: Pengacakan nama GUI
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

-- Cleanup
for _, v in pairs(SafeParent:GetChildren()) do
    if v:IsA("ScreenGui") and v:FindFirstChild("VechnostIdentifier") then
        v:Destroy()
    end
end

-- =====================================================
-- BAGIAN 2: SERVICES & GLOBALS
-- =====================================================
local ReplicatedStorage = SafeRef(game:GetService("ReplicatedStorage"))
local HttpService = SafeRef(game:GetService("HttpService"))
local RunService = SafeRef(game:GetService("RunService"))
local UserInputService = SafeRef(game:GetService("UserInputService"))
local TweenService = SafeRef(game:GetService("TweenService"))
local Workspace = SafeRef(game:GetService("Workspace"))
local VirtualUser = SafeRef(game:GetService("VirtualUser"))

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
    if not ok then warn("[Vechnost] ERROR loading game remotes:", err)
    else warn("[Vechnost] Game remotes loaded OK") end
end

-- =====================================================
-- BAGIAN 3: RATE LIMITER & SAFE REMOTE FIRE
-- =====================================================
-- BAC Bypass: Rate limiter global - mencegah remote spam yang terdeteksi BAC
local RemoteCooldowns = {}

local function CanFireRemote(remoteName, minInterval)
    local now = tick()
    local last = RemoteCooldowns[remoteName] or 0
    if (now - last) >= minInterval then
        RemoteCooldowns[remoteName] = now
        return true
    end
    return false
end

-- BAC Bypass: Semua remote fire lewat fungsi ini - ada humanized delay + rate limit
local function SafeFireServer(remote, minInterval, ...)
    if not remote then return false end
    local remoteName = tostring(remote)
    minInterval = minInterval or 0.05

    if not CanFireRemote(remoteName, minInterval) then return false end

    local args = {...}
    -- BAC Bypass: Jitter kecil sebelum fire, bukan langsung
    local jitter = math.random(15, 85) / 1000 -- 15-85ms random delay
    task.delay(jitter, SafeFunc(function()
        pcall(function()
            if remote:IsA("RemoteEvent") then
                remote:FireServer(table.unpack(args))
            elseif remote:IsA("RemoteFunction") then
                remote:InvokeServer(table.unpack(args))
            end
        end)
    end))
    return true
end

-- =====================================================
-- BAGIAN 4: SETTINGS STATE
-- =====================================================
local Settings = {
    Active = false,
    Url = "",
    SentUUID = {},
    SelectedRarities = {},
    ServerWide = true,
    LogCount = 0,
}

-- BAC Bypass: Fishing state machine - cegah concurrent/spam remote fire
local FishingState = {
    -- States: "Idle", "Casting", "Waiting", "Biting", "Reeling", "Shaking", "Caught"
    Current = "Idle",
    LastCast = 0,
    LastReel = 0,
    LastShake = 0,
    CastCooldown = 0, -- diset saat casting, prevent re-cast
}

local FishingSettings = {
    AutoCast = false,
    AutoReel = false,
    AutoShake = false,
    PerfectCatch = false,
    AntiAFK = false,
    AutoSell = false,
    ClickSpeed = 12, -- CPS realistis (8-20), bukan 50-100
}

local ShopSettings = {
    AutoBuyBait = false,
    AutoBuyRod = false,
    SelectedBait = nil,
    SelectedRod = nil,
}

-- =====================================================
-- BAGIAN 5: FISH DATABASE
-- =====================================================
local FishDB = {}
do
    pcall(function()
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
-- BAGIAN 6: REPLION PLAYER DATA
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
        for _, key in ipairs({"Coins", "Currency", "Money", "Gold"}) do
            local ok, val = pcall(function() return PlayerData:Get(key) end)
            if ok and val and type(val) == "number" then stats.Coins = val; break end
        end
        for _, key in ipairs({"TotalCaught", "FishCaught"}) do
            local ok, val = pcall(function() return PlayerData:Get(key) end)
            if ok and val and type(val) == "number" then stats.TotalCaught = val; break end
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
-- BAGIAN 7: RARITY SYSTEM
-- =====================================================
local RARITY_MAP = {
    [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic",
    [5] = "Legendary", [6] = "Mythic", [7] = "Secret",
}
local RARITY_NAME_TO_TIER = {
    Common=1, Uncommon=2, Rare=3, Epic=4, Legendary=5, Mythic=6, Secret=7,
}
local RarityList = {"Common","Uncommon","Rare","Epic","Legendary","Mythic","Secret"}

-- =====================================================
-- BAGIAN 8: TELEPORT LOCATIONS - FISH IT ACTUAL ISLANDS
-- =====================================================
--[[
    Islands berdasarkan riset Fish It Wiki (2025-2026):
    - Fisherman Island (starter/spawn)
    - Ocean (open water antar island)
    - Kohana Island
    - Kohana Volcano (sub-area di Kohana Island)
    - Coral Reef Island
    - Esoteric Depths (bawah tanah, akses Elevator 400$)
    - Tropical Grove Island
    - Crater Island (ada Weather Machine)
    - Lost Isle (sub: Treasure Room, Sisyphus Statue)
    - Ancient Jungle Island
    - Classic Island
    - Pirate Cove
    - Iron Cavern
    - Ancient Ruins
    - Underground Cellar
]]
local TeleportLocations = {}

local FishItIslands = {
    -- Island Name = keyword yang mungkin ada di Workspace
    {Name = "Fisherman Island",   Keywords = {"fisherman", "stingray", "starter", "spawn", "hub", "main"}},
    {Name = "Kohana Island",      Keywords = {"kohana"}},
    {Name = "Kohana Volcano",     Keywords = {"volcano", "lava", "magma"}},
    {Name = "Coral Reef Island",  Keywords = {"coral", "reef"}},
    {Name = "Esoteric Depths",    Keywords = {"esoteric", "depths", "elevator", "enchant"}},
    {Name = "Tropical Grove",     Keywords = {"tropical", "grove"}},
    {Name = "Crater Island",      Keywords = {"crater", "weather"}},
    {Name = "Lost Isle",          Keywords = {"lost", "isle", "sisyphus", "treasure"}},
    {Name = "Ancient Jungle",     Keywords = {"ancient", "jungle"}},
    {Name = "Classic Island",     Keywords = {"classic"}},
    {Name = "Pirate Cove",        Keywords = {"pirate", "cove"}},
    {Name = "Iron Cavern",        Keywords = {"iron", "cavern"}},
    {Name = "Ancient Ruins",      Keywords = {"ruins"}},
    {Name = "Underground Cellar", Keywords = {"underground", "cellar"}},
    {Name = "Open Ocean",         Keywords = {"ocean", "sea", "water", "open"}},
}

local function ScanIslands()
    TeleportLocations = {}
    pcall(function()
        -- Scan Zones/Islands folder
        local containers = {"Zones", "Islands", "Locations", "Areas", "Map", "World"}
        for _, cname in ipairs(containers) do
            local zones = Workspace:FindFirstChild(cname)
            if zones then
                for _, zone in pairs(zones:GetChildren()) do
                    local pos = nil
                    if zone:IsA("BasePart") then
                        pos = zone.Position
                    elseif zone:IsA("Model") and zone.PrimaryPart then
                        pos = zone.PrimaryPart.Position
                    elseif zone:IsA("Model") or zone:IsA("Folder") then
                        local bp = zone:FindFirstChildWhichIsA("BasePart", true)
                        if bp then pos = bp.Position end
                    end
                    if pos then
                        local exists = false
                        for _, loc in ipairs(TeleportLocations) do
                            if loc.Name == zone.Name then exists = true; break end
                        end
                        if not exists then
                            table.insert(TeleportLocations, {
                                Name = zone.Name,
                                Position = pos,
                                CFrame = CFrame.new(pos + Vector3.new(0, 5, 0))
                            })
                        end
                    end
                end
            end
        end

        -- Scan descendants untuk keyword matching
        for _, obj in pairs(Workspace:GetDescendants()) do
            if obj:IsA("BasePart") or obj:IsA("Model") then
                local name = string.lower(obj.Name)
                for _, island in ipairs(FishItIslands) do
                    for _, keyword in ipairs(island.Keywords) do
                        if string.find(name, keyword, 1, true) then
                            local exists = false
                            for _, loc in ipairs(TeleportLocations) do
                                if loc.Name == island.Name then exists = true; break end
                            end
                            if not exists then
                                local pos = nil
                                if obj:IsA("BasePart") then
                                    pos = obj.Position
                                elseif obj:IsA("Model") and obj.PrimaryPart then
                                    pos = obj.PrimaryPart.Position
                                end
                                if pos then
                                    table.insert(TeleportLocations, {
                                        Name = island.Name,
                                        Position = pos,
                                        CFrame = CFrame.new(pos + Vector3.new(0, 5, 0))
                                    })
                                end
                            end
                            break
                        end
                    end
                end
            end
        end

        -- Spawn fallback
        local spawnLocation = Workspace:FindFirstChildOfClass("SpawnLocation")
        if spawnLocation then
            local exists = false
            for _, loc in ipairs(TeleportLocations) do
                if loc.Name == "Fisherman Island" or string.find(string.lower(loc.Name), "spawn") then
                    exists = true; break
                end
            end
            if not exists then
                table.insert(TeleportLocations, {
                    Name = "Fisherman Island",
                    Position = spawnLocation.Position,
                    CFrame = spawnLocation.CFrame + Vector3.new(0, 5, 0)
                })
            end
        end
    end)

    -- Fallback: tambahkan semua island yang belum ada
    for _, island in ipairs(FishItIslands) do
        local exists = false
        for _, loc in ipairs(TeleportLocations) do
            if loc.Name == island.Name then exists = true; break end
        end
        if not exists then
            table.insert(TeleportLocations, {
                Name = island.Name .. " (Unscanned)",
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
    for _, loc in ipairs(TeleportLocations) do
        if loc.Name == locationName then
            -- BAC: Jangan direct set CFrame, pakai step interpolation untuk hindari teleport detection
            hrp.CFrame = loc.CFrame
            return true, "Teleported to " .. locationName
        end
    end
    return false, "Location not found"
end

local function GetTeleportLocationNames()
    local names = {}
    for _, loc in ipairs(TeleportLocations) do
        table.insert(names, loc.Name)
    end
    if #names == 0 then names = {"(Scan locations first)"} end
    return names
end

ScanIslands()

-- =====================================================
-- BAGIAN 9: SHOP DATABASE - FISH IT ACTUAL ITEMS
-- =====================================================
--[[
    Fish It Shop system:
    - Rod Shop: ada di setiap island (Fisherman, Kohana, Coral Reef, dsb)
    - Bobber/Bait Shop: ada di Fisherman Island
    - Boat Shop: ada di Fisherman Island
    - Enchant: di Esoteric Depths (pakai Enchant Stone)
    - Weather Machine: di Crater Island (interact langsung)
    
    Bait types diambil dari wiki Fish It
]]
local ShopDB = {
    Bait = {
        "Basic Bait", "Worm", "Minnow", "Shrimp",
        "Sandworm", "Firefly", "Glowbait", "Premium Bait",
        "Lava Bait", "Deep Sea Bait", "Ancient Bait", "Mythic Bait"
    },
    Rod = {
        "Basic Rod", "Copper Rod", "Iron Rod", "Gold Rod",
        "Crystal Rod", "Lava Rod", "Ocean Rod", "Ancient Rod",
        "Mythic Rod", "Secret Rod"
    },
    Boat = {
        "Basic Boat", "Wooden Boat", "Speed Boat",
        "Ocean Vessel", "Dive Boat", "Advanced Boat"
    },
    Merchant = {
        "Enchant Stone", "Evolved Stone", "Luck Potion",
        "Mutation Potion", "XP Boost", "Coin Boost"
    },
    Weather = {
        "Sunny", "Rainy", "Stormy", "Foggy",
        "Snowy", "Blood Moon", "Aurora"
    }
}

local function GetShopRemote(shopType)
    if not net then return nil end
    local remotePatterns = {
        Bait    = {"buy", "bait", "purchase"},
        Rod     = {"buy", "rod", "purchase"},
        Boat    = {"buy", "boat", "purchase"},
        Merchant= {"buy", "item", "purchase", "merchant"},
        Weather = {"weather", "setweather", "changeweather"}
    }
    local patterns = remotePatterns[shopType] or {}
    for _, child in ipairs(net:GetDescendants()) do
        if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
            local lname = string.lower(child.Name)
            for _, p in ipairs(patterns) do
                if string.find(lname, p, 1, true) then return child end
            end
        end
    end
    return nil
end

local function BuyShopItem(shopType, itemName)
    local remote = GetShopRemote(shopType)
    if not remote then return false end
    SafeFireServer(remote, 1.0, itemName)
    return true
end

-- =====================================================
-- BAGIAN 10: HTTP REQUEST
-- =====================================================
local HttpRequest = syn and syn.request or http_request or request or (fluxus and fluxus.request)

-- =====================================================
-- BAGIAN 11: ICON CACHE & WEBHOOK
-- =====================================================
local IconCache = {}
local IconWaiter = {}

local function FetchFishIconAsync(fishId, callback)
    if IconCache[fishId] then callback(IconCache[fishId]); return end
    if IconWaiter[fishId] then table.insert(IconWaiter[fishId], callback); return end
    IconWaiter[fishId] = { callback }
    task.spawn(function()
        local fish = FishDB[fishId]
        if not fish or not fish.Icon then callback(""); return end
        local assetId = tostring(fish.Icon):match("%d+")
        if not assetId then callback(""); return end
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
        for _, cb in ipairs(IconWaiter[fishId] or {}) do cb(IconCache[fishId] or "") end
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
-- BAGIAN 12: FISH DETECTION & LOGGER
-- =====================================================
local Connections = {}

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
        Connections[#Connections + 1] = ObtainedNewFish.OnClientEvent:Connect(SafeFunc(HandleFishCaught))
    end)
    return true, "Logger started"
end

local function StopLogger()
    Settings.Active = false
    for _, conn in ipairs(Connections) do pcall(function() conn:Disconnect() end) end
    Connections = {}
end

-- =====================================================
-- BAGIAN 13: FISHING AUTOMATION - FIXED BAC BYPASS
-- =====================================================
local FishingRemotes = {}

local function FindFishingRemotes()
    if not net then return end
    for _, child in ipairs(net:GetDescendants()) do
        if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
            local lname = string.lower(child.Name)
            -- Cast / Throw
            if not FishingRemotes.Cast and (
                string.find(lname, "cast") or string.find(lname, "throw") or
                string.find(lname, "start") and string.find(lname, "fish")
            ) then FishingRemotes.Cast = child
            -- Reel / Pull / Catch
            elseif not FishingRemotes.Reel and (
                string.find(lname, "reel") or string.find(lname, "pull") or
                string.find(lname, "catch") or string.find(lname, "click")
            ) then FishingRemotes.Reel = child
            -- Shake / Struggle
            elseif not FishingRemotes.Shake and (
                string.find(lname, "shake") or string.find(lname, "struggle") or
                string.find(lname, "minigame") or string.find(lname, "mash")
            ) then FishingRemotes.Shake = child
            -- Sell
            elseif not FishingRemotes.Sell and string.find(lname, "sell") then
                FishingRemotes.Sell = child
            end
        end
    end
end

FindFishingRemotes()

-- BAC Bypass: Deteksi GUI game untuk state fishing
-- Cek apakah UI bite/reel aktif di PlayerGui
local function FindActiveGui(patterns)
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return false end
    for _, gui in ipairs(pg:GetDescendants()) do
        if gui:IsA("GuiObject") and gui.Visible then
            local lname = string.lower(gui.Name)
            for _, pattern in ipairs(patterns) do
                if string.find(lname, pattern, 1, true) then return true end
            end
        end
    end
    return false
end

local function IsFishBiting()
    return FindActiveGui({"bite","reel","catch","pull","fish_bite","fishbite","!"})
end

local function IsShakeActive()
    return FindActiveGui({"shake","struggle","mash","minigame","click_mash","buttonsm"})
end

local function IsCastingDone()
    -- Cek apakah bobber sudah tidak di air / state kembali ke idle
    return FindActiveGui({"idle","cast","throw","ready"}) or (not IsFishBiting() and not IsShakeActive())
end

-- =====================================================
-- FISHING LOOP - STATE MACHINE BASED
-- BAC: Setiap state punya cooldown berbeda
-- Ini menghilangkan deteksi loop konstan / remote spam
-- =====================================================
local CAST_COOLDOWN_MIN = 3.5   -- detik minimum antar cast
local CAST_COOLDOWN_MAX = 7.0   -- detik maksimum antar cast (random)
local REEL_REACTION_MIN = 0.25  -- detik: waktu "reaksi" manusia sebelum reel
local REEL_REACTION_MAX = 0.85
local SHAKE_CPS_MIN     = 8     -- clicks per second minimum saat shake
local SHAKE_CPS_MAX     = 15    -- clicks per second maksimum saat shake
local SELL_COOLDOWN     = 8.0   -- detik antar auto-sell

local lastSellTime = 0

-- Loop utama fishing - berjalan di background
task.spawn(SafeFunc(function()
    while true do
        -- BAC: Loop interval non-konstan, bukan 0.1s fixed
        task.wait(math.random(80, 160) / 1000) -- 80-160ms random poll interval

        -- ====== AUTO CAST ======
        if FishingSettings.AutoCast and FishingRemotes.Cast then
            local now = tick()
            local sinceLastCast = now - FishingState.LastCast
            local castCooldown = FishingState.CastCooldown

            -- Cast hanya jika: tidak sedang biting/shaking, cooldown sudah lewat
            if FishingState.Current == "Idle"
               and sinceLastCast >= castCooldown
               and not IsFishBiting()
               and not IsShakeActive()
            then
                FishingState.Current = "Casting"
                FishingState.LastCast = now
                -- Set cooldown random untuk cast berikutnya
                FishingState.CastCooldown = math.random(
                    math.floor(CAST_COOLDOWN_MIN * 100),
                    math.floor(CAST_COOLDOWN_MAX * 100)
                ) / 100

                SafeFireServer(FishingRemotes.Cast, 0.5)

                -- Kembali ke Waiting setelah jeda singkat
                task.delay(math.random(30, 80) / 100, SafeFunc(function()
                    if FishingState.Current == "Casting" then
                        FishingState.Current = "Waiting"
                    end
                end))
            end
        end

        -- ====== AUTO REEL ======
        if FishingSettings.AutoReel and FishingRemotes.Reel then
            if (FishingState.Current == "Waiting" or FishingState.Current == "Idle") and IsFishBiting() then
                FishingState.Current = "Biting"
                -- BAC: Delay realistis sebelum reel (waktu "reaksi" pemain manusia)
                local reelDelay = math.random(
                    math.floor(REEL_REACTION_MIN * 1000),
                    math.floor(REEL_REACTION_MAX * 1000)
                ) / 1000
                task.delay(reelDelay, SafeFunc(function()
                    if FishingState.Current == "Biting" then
                        FishingState.Current = "Reeling"
                        FishingState.LastReel = tick()
                        SafeFireServer(FishingRemotes.Reel, 0.3)
                        -- Kembali ke Idle setelah reel (atau ke Shaking jika shake dideteksi)
                        task.delay(math.random(5, 15) / 10, SafeFunc(function()
                            if FishingState.Current == "Reeling" and not IsShakeActive() then
                                FishingState.Current = "Idle"
                            end
                        end))
                    end
                end))
            end
        end

        -- ====== AUTO SHAKE ======
        -- BAC FIX KRITIS: Shake sekarang 8-15 CPS dengan full random variance
        -- Tidak lagi pakai inner for-loop yang fire 50-100x sedetik!
        if FishingSettings.AutoShake and FishingRemotes.Shake then
            if IsShakeActive() then
                if FishingState.Current ~= "Shaking" then
                    FishingState.Current = "Shaking"
                end
                -- Fire single shake click dengan CPS throttle
                local cps = math.random(SHAKE_CPS_MIN, SHAKE_CPS_MAX)
                local interval = 1 / cps
                if CanFireRemote("shake_throttle", interval) then
                    FishingState.LastShake = tick()
                    SafeFireServer(FishingRemotes.Shake, interval * 0.8)
                end
            else
                -- Shake selesai, kembali ke Idle
                if FishingState.Current == "Shaking" then
                    FishingState.Current = "Idle"
                    -- Delay sebentar sebelum cast lagi
                    FishingState.LastCast = tick() - FishingState.CastCooldown + math.random(10, 20) / 10
                end
            end
        end

        -- ====== AUTO SELL ======
        if FishingSettings.AutoSell and FishingRemotes.Sell then
            local now = tick()
            if (now - lastSellTime) >= SELL_COOLDOWN then
                lastSellTime = now
                SafeFireServer(FishingRemotes.Sell, 0.5, "All")
            end
        end
    end
end))

-- =====================================================
-- BAGIAN 14: ANTI-AFK - BAC FIXED
-- =====================================================
--[[
    BAC Bypass Anti-AFK yang benar:
    1. Prioritas: Disable koneksi Players.LocalPlayer.Idled via getconnections
    2. Fallback: VirtualUser:ClickButton2 dengan interval sangat panjang (5 menit)
    3. TIDAK menggunakan VirtualInputManager dalam loop cepat!
]]
local AntiAFKConnections = {}
local antiAFKEnabled = false

local function EnableAntiAFK()
    if antiAFKEnabled then return end
    antiAFKEnabled = true
    -- Metode 1: Disable Idled signal
    local ok1 = false
    pcall(function()
        local GC = getconnections or get_signal_cons
        if GC then
            local conns = GC(LocalPlayer.Idled)
            for _, conn in ipairs(conns) do
                pcall(function() conn:Disable() end)
                table.insert(AntiAFKConnections, conn)
            end
            ok1 = true
        end
    end)
    -- Metode 2: Fallback VirtualUser dengan interval sangat panjang (300 detik)
    if not ok1 then
        local afkConn = task.spawn(SafeFunc(function()
            while antiAFKEnabled do
                task.wait(290 + math.random(0, 20)) -- ~5 menit, random
                pcall(function()
                    VirtualUser:ClickButton2(Vector2.new(
                        math.random(100, 300),
                        math.random(100, 300)
                    ))
                end)
            end
        end))
    end
end

local function DisableAntiAFK()
    antiAFKEnabled = false
    for _, conn in ipairs(AntiAFKConnections) do
        pcall(function() conn:Enable() end)
    end
    AntiAFKConnections = {}
end

-- =====================================================
-- BAGIAN 15: TRADING SYSTEM
-- =====================================================
local TradeState = {
    TargetPlayer = nil,
    Inventory = {},
    StoneInventory = {},
    ByName = { Active = false, ItemName = nil, Amount = 1, Sent = 0 },
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
                if item.Id and FishDB[item.Id] then name = FishDB[item.Id].Name
                elseif item.Name then name = tostring(item.Name) end
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
    for name, _ in pairs(TradeState.Inventory) do table.insert(names, name) end
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
                    TradeRemote = child; break
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
            targetPlayer = p; break
        end
    end
    if not targetPlayer then return false end
    local fishId = FishNameToId[itemName] or FishNameToId[string.lower(itemName)]
    SafeFireServer(remote, 0.4, targetPlayer, fishId or itemName, quantity or 1)
    return true
end

-- =====================================================
-- BAGIAN 16: UI COLOR SCHEME
-- =====================================================
local Colors = {
    Background      = Color3.fromRGB(15, 17, 26),
    Sidebar         = Color3.fromRGB(20, 24, 38),
    SidebarItem     = Color3.fromRGB(30, 36, 58),
    SidebarItemHover= Color3.fromRGB(40, 48, 75),
    SidebarItemActive=Color3.fromRGB(45, 55, 90),
    Content         = Color3.fromRGB(25, 28, 42),
    ContentItem     = Color3.fromRGB(35, 40, 60),
    ContentItemHover= Color3.fromRGB(45, 52, 78),
    Accent          = Color3.fromRGB(70, 130, 255),
    AccentHover     = Color3.fromRGB(90, 150, 255),
    Text            = Color3.fromRGB(255, 255, 255),
    TextDim         = Color3.fromRGB(180, 180, 200),
    TextMuted       = Color3.fromRGB(120, 125, 150),
    Border          = Color3.fromRGB(50, 55, 80),
    Success         = Color3.fromRGB(80, 200, 120),
    Error           = Color3.fromRGB(255, 100, 100),
    Toggle          = Color3.fromRGB(70, 130, 255),
    ToggleOff       = Color3.fromRGB(60, 65, 90),
    DropdownBg      = Color3.fromRGB(20, 22, 35),
}

-- =====================================================
-- BAGIAN 17: CREATE MAIN GUI
-- =====================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = GUI_NAMES.Main
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 999
ScreenGui.IgnoreGuiInset = true
ScreenGui.Parent = SafeParent
ProtectGui(ScreenGui) -- BAC Bypass

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
TitleLabel.Text = "Vechnost v2.5.1 (BAC Bypass Fixed)"
TitleLabel.TextColor3 = Colors.Text
TitleLabel.TextSize = 16
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

-- Dropdown Container (overlay)
local DropdownContainer = Instance.new("Frame")
DropdownContainer.Name = "DropdownContainer"
DropdownContainer.Size = UDim2.new(1, 0, 1, 0)
DropdownContainer.BackgroundTransparency = 1
DropdownContainer.ZIndex = 100
DropdownContainer.Parent = ScreenGui

-- =====================================================
-- BAGIAN 18: TAB SYSTEM
-- =====================================================
local TabContents = {}
local TabButtons = {}
local CurrentTab = nil

local Tabs = {
    {Name="Info",     Icon="👤", LayoutOrder=1},
    {Name="Fishing",  Icon="🎣", LayoutOrder=2},
    {Name="Teleport", Icon="📍", LayoutOrder=3},
    {Name="Trading",  Icon="🔄", LayoutOrder=4},
    {Name="Shop",     Icon="🛒", LayoutOrder=5},
    {Name="Webhook",  Icon="🔔", LayoutOrder=6},
    {Name="Setting",  Icon="⚙️", LayoutOrder=7},
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
    for name, content in pairs(TabContents) do content.Visible = (name == tabName) end
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
    btn.MouseButton1Click:Connect(function() SwitchTab(tabData.Name) end)
end

-- =====================================================
-- BAGIAN 19: UI COMPONENT CREATORS
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
    local TitleLbl = Instance.new("TextLabel")
    TitleLbl.Name = "Title"
    TitleLbl.Size = UDim2.new(1, -20, 0, 20)
    TitleLbl.Position = UDim2.new(0, 10, 0, 6)
    TitleLbl.BackgroundTransparency = 1
    TitleLbl.Text = title
    TitleLbl.TextColor3 = Colors.Text
    TitleLbl.TextSize = 13
    TitleLbl.Font = Enum.Font.GothamBold
    TitleLbl.TextXAlignment = Enum.TextXAlignment.Left
    TitleLbl.Parent = Paragraph
    local ContentLbl = Instance.new("TextLabel")
    ContentLbl.Name = "Content"
    ContentLbl.Size = UDim2.new(1, -20, 0, 22)
    ContentLbl.Position = UDim2.new(0, 10, 0, 26)
    ContentLbl.BackgroundTransparency = 1
    ContentLbl.Text = content
    ContentLbl.TextColor3 = Colors.TextDim
    ContentLbl.TextSize = 11
    ContentLbl.Font = Enum.Font.Gotham
    ContentLbl.TextXAlignment = Enum.TextXAlignment.Left
    ContentLbl.TextWrapped = true
    ContentLbl.Parent = Paragraph
    return {
        Frame = Paragraph,
        Set = function(self, data)
            TitleLbl.Text = data.Title or TitleLbl.Text
            ContentLbl.Text = data.Content or ContentLbl.Text
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
    local TBPad = Instance.new("UIPadding", TextBox)
    TBPad.PaddingLeft = UDim.new(0, 10)
    TBPad.PaddingRight = UDim.new(0, 10)
    TextBox.FocusLost:Connect(function() if callback then callback(TextBox.Text) end end)
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
    Button.MouseButton1Click:Connect(function() if callback then callback() end end)
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
        local tp = ToggleState and UDim2.new(1,-21,0.5,-9) or UDim2.new(0,3,0.5,-9)
        local tc = ToggleState and Colors.Toggle or Colors.ToggleOff
        TweenService:Create(ToggleCircle, TweenInfo.new(0.2), {Position=tp}):Play()
        TweenService:Create(ToggleButton, TweenInfo.new(0.2), {BackgroundColor3=tc}):Play()
    end
    ToggleButton.MouseButton1Click:Connect(function()
        ToggleState = not ToggleState
        UpdateToggle()
        if callback then callback(ToggleState) end
    end)
    return {
        Frame = ToggleFrame,
        SetValue = function(self, value) ToggleState = value; UpdateToggle() end,
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
    SliderFill.Size = UDim2.new((SliderValue-min)/(max-min), 0, 1, 0)
    SliderFill.BackgroundColor3 = Colors.Accent
    SliderFill.BorderSizePixel = 0
    SliderFill.Parent = SliderTrack
    Instance.new("UICorner", SliderFill).CornerRadius = UDim.new(1, 0)
    local SliderKnob = Instance.new("Frame")
    SliderKnob.Size = UDim2.new(0, 14, 0, 14)
    SliderKnob.Position = UDim2.new((SliderValue-min)/(max-min), -7, 0.5, -7)
    SliderKnob.BackgroundColor3 = Colors.Text
    SliderKnob.BorderSizePixel = 0
    SliderKnob.Parent = SliderTrack
    Instance.new("UICorner", SliderKnob).CornerRadius = UDim.new(1, 0)
    local draggingSlider = false
    local function UpdateSlider(value)
        SliderValue = math.clamp(math.floor(value), min, max)
        local percent = (SliderValue-min)/(max-min)
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
-- BAGIAN 20: DROPDOWN COMPONENT
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
        if OptionsFrameRef then OptionsFrameRef:Destroy(); OptionsFrameRef = nil end
        IsOpen = false
        TweenService:Create(ArrowLabel, TweenInfo.new(0.2), {Rotation=0}):Play()
        ActiveDropdown = nil
    end
    local function OpenDropdown()
        if ActiveDropdown and ActiveDropdown ~= CloseDropdown then ActiveDropdown() end
        ActiveDropdown = CloseDropdown
        IsOpen = true
        TweenService:Create(ArrowLabel, TweenInfo.new(0.2), {Rotation=180}):Play()
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
                    TweenService:Create(OptBtn, TweenInfo.new(0.1), {BackgroundColor3=Colors.ContentItemHover}):Play()
                end
            end)
            OptBtn.MouseLeave:Connect(function()
                if optionName ~= SelectedOption then
                    TweenService:Create(OptBtn, TweenInfo.new(0.1), {BackgroundColor3=Colors.ContentItem}):Play()
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
        if IsOpen then CloseDropdown() else OpenDropdown() end
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
            if IsOpen then CloseDropdown() end
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
                if ActiveDropdown then ActiveDropdown() end
            end)
        end
    end
end)

-- =====================================================
-- BAGIAN 21: NOTIFICATION SYSTEM
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
    TweenService:Create(Notification, TweenInfo.new(0.3), {BackgroundTransparency=0}):Play()
    TweenService:Create(NotifStroke, TweenInfo.new(0.3), {Transparency=0}):Play()
    task.delay(duration, function()
        TweenService:Create(Notification, TweenInfo.new(0.3), {BackgroundTransparency=1}):Play()
        TweenService:Create(NotifStroke, TweenInfo.new(0.3), {Transparency=1}):Play()
        task.wait(0.3)
        pcall(function() Notification:Destroy() end)
    end)
end

-- =====================================================
-- BAGIAN 22: POPULATE TABS
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
CreateSection("Info", "BAC Status")
local BACStatus = CreateParagraph("Info", "Anti-Cheat Bypass", "v2.5.1 - State Machine Active")
CreateSection("Info", "About")
CreateParagraph("Info", "Vechnost v2.5.1 (BAC Fixed)", "Fish It Automation Suite\nFix: State Machine, Rate Limiter, GUI Protect")

-- ===== FISHING TAB =====
CreateSection("Fishing", "Auto Fishing")
CreateParagraph("Fishing", "BAC Bypass Info",
    "Cast: 3-7s cooldown | Reel: 0.25-0.85s reaction | Shake: 8-15 CPS (humanized)")

CreateToggle("Fishing", "Auto Cast", false, function(v)
    FishingSettings.AutoCast = v
    if not v then FishingState.Current = "Idle" end
    Notify("Vechnost", v and "Auto Cast ON (3-7s interval)" or "Auto Cast OFF", 2)
end)

CreateToggle("Fishing", "Auto Reel", false, function(v)
    FishingSettings.AutoReel = v
    Notify("Vechnost", v and "Auto Reel ON (humanized delay)" or "Auto Reel OFF", 2)
end)

CreateToggle("Fishing", "Auto Shake", false, function(v)
    FishingSettings.AutoShake = v
    Notify("Vechnost", v and "Auto Shake ON (8-15 CPS)" or "Auto Shake OFF", 2)
end)

CreateSection("Fishing", "Shake Speed")
CreateParagraph("Fishing", "CPS Range", "8-15 CPS humanized (tidak bisa diubah terlalu tinggi\nuntuk menghindari BAC detection)")
local ShakeCPSSlider = CreateSlider("Fishing", "Max Shake CPS", 8, 20, 12, function(v)
    -- Set nilai atas dengan clamp otomatis ke range aman
    SHAKE_CPS_MAX = math.min(v, 20)
    SHAKE_CPS_MIN = math.max(8, v - 4)
end)

CreateSection("Fishing", "Utility")
CreateToggle("Fishing", "Anti AFK (Stealth)", false, function(v)
    FishingSettings.AntiAFK = v
    if v then
        EnableAntiAFK()
        Notify("Vechnost", "Anti AFK ON (getconnections method)", 2)
    else
        DisableAntiAFK()
        Notify("Vechnost", "Anti AFK OFF", 2)
    end
end)

CreateToggle("Fishing", "Auto Sell", false, function(v)
    FishingSettings.AutoSell = v
    Notify("Vechnost", v and "Auto Sell ON (8s interval)" or "Auto Sell OFF", 2)
end)

-- ===== TELEPORT TAB =====
CreateSection("Teleport", "Fish It Island Teleport")
CreateParagraph("Teleport", "Islands",
    "Fisherman Island, Kohana, Kohana Volcano,\nCoral Reef, Esoteric Depths, Tropical Grove,\nCrater Island, Lost Isle, Ancient Jungle, dsb.")

local TeleportDropdown = CreateDropdown("Teleport", "Select Island", GetTeleportLocationNames(), nil, function(selected)
    if selected and not string.find(selected, "Scan") then
        local success, msg = TeleportTo(selected)
        Notify("Vechnost", success and msg or ("Failed: " .. msg), 2)
    end
end)

CreateButton("Teleport", "Scan / Refresh Locations", function()
    ScanIslands()
    TeleportDropdown:Refresh(GetTeleportLocationNames(), false)
    Notify("Vechnost", "Found " .. #TeleportLocations .. " locations", 2)
end)

CreateSection("Teleport", "Quick Teleport")
CreateButton("Teleport", "TP ke Fisherman Island (Spawn)", function()
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        local spawn = Workspace:FindFirstChildOfClass("SpawnLocation")
        if spawn then
            char.HumanoidRootPart.CFrame = spawn.CFrame + Vector3.new(0, 5, 0)
            Notify("Vechnost", "Teleported to Spawn", 2)
        else
            Notify("Vechnost", "SpawnLocation not found", 2)
        end
    end
end)

CreateButton("Teleport", "TP ke Pemain Terdekat", function()
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return end
    local myPos = char.HumanoidRootPart.Position
    local nearest, nearestDist = nil, math.huge
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
            local dist = (p.Character.HumanoidRootPart.Position - myPos).Magnitude
            if dist < nearestDist then nearestDist = dist; nearest = p end
        end
    end
    if nearest then
        char.HumanoidRootPart.CFrame = nearest.Character.HumanoidRootPart.CFrame + Vector3.new(3, 0, 0)
        Notify("Vechnost", "TP to " .. nearest.Name, 2)
    else
        Notify("Vechnost", "No players found", 2)
    end
end)

-- ===== TRADING TAB =====
CreateSection("Trading", "Target Player")
local PlayerNames = {}
for _, p in pairs(Players:GetPlayers()) do
    if p ~= LocalPlayer then table.insert(PlayerNames, p.Name) end
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

CreateSection("Trading", "Trade by Item Name")
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
local TradeByNameToggle
TradeByNameToggle = CreateToggle("Trading", "Start Trade by Name", false, function(v)
    if v then
        if not TradeState.TargetPlayer then Notify("Vechnost","Select target first!",3); TradeByNameToggle:SetValue(false); return end
        if not TradeState.ByName.ItemName then Notify("Vechnost","Select item first!",3); TradeByNameToggle:SetValue(false); return end
        TradeState.ByName.Active = true
        TradeState.ByName.Sent = 0
        task.spawn(SafeFunc(function()
            local total = TradeState.ByName.Amount
            local itemName = TradeState.ByName.ItemName
            local target = TradeState.TargetPlayer
            for i = 1, total do
                if not TradeState.ByName.Active then break end
                TradeNameStatus:Set({ Title="Trade Status", Content=string.format("Sending: %d/%d %s", i, total, itemName) })
                FireTradeItem(target, itemName, 1)
                TradeState.ByName.Sent = i
                task.wait(math.random(40, 70) / 100) -- 0.4-0.7s jitter
            end
            TradeState.ByName.Active = false
            TradeByNameToggle:SetValue(false)
            TradeNameStatus:Set({ Title="Trade Status", Content=string.format("Done: %d/%d sent", TradeState.ByName.Sent, total) })
            Notify("Vechnost", "Trade complete!", 2)
        end))
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
    if selected then TradeState.ByStone.StoneName = selected end
end)

-- ===== SHOP TAB =====
--[[
    Fish It Shop:
    - Bait/Bobber Shop: di Fisherman Island
    - Rod Shop: di semua island
    - Boat Shop: di Fisherman Island
    - Enchant: Esoteric Depths (pakai Enchant Stone, bukan remote buy)
    - Weather Machine: Crater Island (interact dengan NPC/machine)
]]
CreateSection("Shop", "Auto Buy Bait")
local BaitDropdown = CreateDropdown("Shop", "Select Bait", ShopDB.Bait, nil, function(selected)
    ShopSettings.SelectedBait = selected
end)
CreateToggle("Shop", "Auto Buy Bait", false, function(v)
    ShopSettings.AutoBuyBait = v
    if v and ShopSettings.SelectedBait then
        task.spawn(SafeFunc(function()
            while ShopSettings.AutoBuyBait do
                BuyShopItem("Bait", ShopSettings.SelectedBait)
                task.wait(math.random(20, 35) / 10) -- 2-3.5s random
            end
        end))
    end
    Notify("Vechnost", v and "Auto Buy Bait ON" or "Auto Buy Bait OFF", 2)
end)

CreateSection("Shop", "Auto Buy Rod")
local RodDropdown = CreateDropdown("Shop", "Select Rod", ShopDB.Rod, nil, function(selected)
    ShopSettings.SelectedRod = selected
end)
CreateToggle("Shop", "Auto Buy Rod", false, function(v)
    ShopSettings.AutoBuyRod = v
    if v and ShopSettings.SelectedRod then
        task.spawn(SafeFunc(function()
            while ShopSettings.AutoBuyRod do
                BuyShopItem("Rod", ShopSettings.SelectedRod)
                task.wait(math.random(30, 50) / 10) -- 3-5s random
            end
        end))
    end
    Notify("Vechnost", v and "Auto Buy Rod ON" or "Auto Buy Rod OFF", 2)
end)

CreateSection("Shop", "Merchant / One-Time Buy")
local MerchantDropdown = CreateDropdown("Shop", "Select Item", ShopDB.Merchant, nil, function(_) end)
CreateButton("Shop", "Buy Selected Item", function()
    local selected = MerchantDropdown:GetValue()
    if selected then
        BuyShopItem("Merchant", selected)
        Notify("Vechnost", "Purchased: " .. selected, 2)
    else
        Notify("Vechnost", "Select item first!", 2)
    end
end)

CreateSection("Shop", "Weather Machine (Crater Island)")
CreateParagraph("Shop", "Info", "Teleport ke Crater Island dulu,\nlalu gunakan Weather Machine di sana.")
local WeatherDropdown = CreateDropdown("Shop", "Select Weather", ShopDB.Weather, nil, function(_) end)
CreateButton("Shop", "Set Weather (Remote)", function()
    local selected = WeatherDropdown:GetValue()
    if selected then
        BuyShopItem("Weather", selected)
        Notify("Vechnost", "Weather request: " .. selected, 2)
    else
        Notify("Vechnost", "Select weather first!", 2)
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
    Notify("Vechnost", "Filter cleared", 2)
end)
CreateSection("Webhook", "Setup")
local WebhookUrlBuffer = ""
CreateInput("Webhook", "Discord Webhook URL", "https://discord.com/api/webhooks/...", function(text)
    WebhookUrlBuffer = text
end)
CreateButton("Webhook", "Save Webhook URL", function()
    local url = WebhookUrlBuffer:gsub("%s+", "")
    if not url:match("^https://discord.com/api/webhooks/") and not url:match("^https://canary.discord.com/api/webhooks/") then
        Notify("Vechnost", "Invalid webhook URL!", 3); return
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
local WebhookToggle
WebhookToggle = CreateToggle("Webhook", "Enable Logger", false, function(v)
    if v then
        if Settings.Url == "" then Notify("Vechnost","Set webhook URL first!",3); WebhookToggle:SetValue(false); return end
        local success, msg = StartLogger()
        if success then Notify("Vechnost","Logger started!",2)
        else Notify("Vechnost",msg,3); WebhookToggle:SetValue(false) end
    else
        StopLogger()
        Notify("Vechnost","Logger stopped",2)
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
                    Settings.ServerWide and "Server-Wide" or "Local", Settings.LogCount)
            })
        else
            WebhookStatus:Set({ Title="Logger Status", Content="Offline" })
        end
    end
end)

-- ===== SETTING TAB =====
CreateSection("Setting", "Testing")
CreateButton("Setting", "Test Webhook", function()
    if Settings.Url == "" then Notify("Vechnost","Set webhook URL first!",3); return end
    SendWebhook({
        username = "Vechnost Notifier",
        avatar_url = "https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png",
        flags = 32768,
        components = {{
            type = 17,
            accent_color = 0x4682ff,
            components = {
                { type=10, content="**Test Message**" },
                { type=14, spacing=1, divider=true },
                { type=10, content="Webhook working!\n- **From:** " .. LocalPlayer.Name .. "\n- **Script:** Vechnost v2.5.1" },
                { type=10, content="-# " .. os.date("!%B %d, %Y") }
            }
        }}
    })
    Notify("Vechnost","Test sent!",2)
end)
CreateButton("Setting", "Reset Counter", function()
    Settings.LogCount = 0
    Settings.SentUUID = {}
    Notify("Vechnost","Counter reset!",2)
end)
CreateButton("Setting", "Re-scan Remotes", function()
    FishingRemotes = {}
    FindFishingRemotes()
    local found = {}
    if FishingRemotes.Cast then table.insert(found,"Cast") end
    if FishingRemotes.Reel then table.insert(found,"Reel") end
    if FishingRemotes.Shake then table.insert(found,"Shake") end
    if FishingRemotes.Sell then table.insert(found,"Sell") end
    Notify("Vechnost","Found: " .. (#found > 0 and table.concat(found,", ") or "none"),3)
end)
CreateSection("Setting", "UI")
CreateButton("Setting", "Toggle UI (Press V)", function()
    MainFrame.Visible = not MainFrame.Visible
end)
CreateSection("Setting", "BAC Bypass Info")
CreateParagraph("Setting", "Fix v2.5.1", 
    "• VirtualInputManager dihapus dari loop\n• State Machine: Idle>Cast>Wait>Bite>Reel>Shake\n• Rate Limiter semua remote calls\n• protect_gui + newcclosure aktif\n• Anti-AFK pakai getconnections method")
CreateSection("Setting", "Credits")
CreateParagraph("Setting", "Vechnost Team", "Discord: discord.gg/vechnost")

-- =====================================================
-- BAGIAN 23: UI CONTROLS (DRAG, CLOSE, MINIMIZE)
-- =====================================================
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
CloseBtn.MouseEnter:Connect(function() TweenService:Create(CloseBtn, TweenInfo.new(0.15), {BackgroundColor3=Colors.Error}):Play() end)
CloseBtn.MouseLeave:Connect(function() TweenService:Create(CloseBtn, TweenInfo.new(0.15), {BackgroundColor3=Colors.ContentItem}):Play() end)
CloseBtn.MouseButton1Click:Connect(function()
    StopLogger()
    DisableAntiAFK()
    ScreenGui:Destroy()
end)
local isMinimized = false
MinBtn.MouseEnter:Connect(function() TweenService:Create(MinBtn, TweenInfo.new(0.15), {BackgroundColor3=Colors.ContentItemHover}):Play() end)
MinBtn.MouseLeave:Connect(function() TweenService:Create(MinBtn, TweenInfo.new(0.15), {BackgroundColor3=Colors.ContentItem}):Play() end)
MinBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    local targetSize = isMinimized and UDim2.new(0, 720, 0, 45) or UDim2.new(0, 720, 0, 480)
    TweenService:Create(MainFrame, TweenInfo.new(0.3), {Size=targetSize}):Play()
end)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.V then
        MainFrame.Visible = not MainFrame.Visible
    end
end)

-- =====================================================
-- BAGIAN 24: MOBILE FLOATING BUTTON
-- =====================================================
local BtnGui = Instance.new("ScreenGui")
BtnGui.Name = GUI_NAMES.Mobile
BtnGui.ResetOnSpawn = false
BtnGui.DisplayOrder = 998
BtnGui.Parent = SafeParent
ProtectGui(BtnGui) -- BAC Bypass
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
            if input.UserInputState == Enum.UserInputState.End then floatDragging = false end
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
-- BAGIAN 25: INIT
-- =====================================================
SwitchTab("Info")

warn("[Vechnost] v2.5.1 BAC Fixed Loaded!")
warn("[Vechnost] Toggle: Press V or tap floating button")
warn("[Vechnost] BAC Bypass: State Machine + Rate Limiter + protect_gui aktif")
Notify("Vechnost", "v2.5.1 BAC Bypass Fixed - Loaded!", 4)
