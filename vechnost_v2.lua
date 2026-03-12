--[[ 
    FILE: vechnost_webhook.lua
    BRAND: Vechnost
    VERSION: 1.0.0
    DESC: Server-Wide Fish Webhook Logger for Roblox "Fish It"
          Logs fish catches from ALL players in the server
          Sends rich notifications to Discord via Webhook
]]

-- =====================================================
-- BAGIAN 1: CLEANUP SYSTEM
-- =====================================================
local CoreGui = game:GetService("CoreGui")
local GUI_NAMES = {
    Main = "Vechnost_Webhook_UI",
    Mobile = "Vechnost_Mobile_Button",
}

for _, v in pairs(CoreGui:GetChildren()) do
    for _, name in pairs(GUI_NAMES) do
        if v.Name == name then v:Destroy() end
    end
end

for _, v in pairs(CoreGui:GetDescendants()) do
    if v:IsA("TextLabel") and v.Text == "Vechnost" then
        local container = v
        for i = 1, 10 do
            if typeof(container) ~= "Instance" then break end
            local parent = container.Parent
            if not parent then break end
            container = parent
            if typeof(container) == "Instance" and container:IsA("ScreenGui") then
                container:Destroy()
                break
            end
        end
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
        warn("[Vechnost] Make sure you are in the Fish It game!")
    else
        warn("[Vechnost] Game remotes loaded OK")
    end
end

-- Safe load Rayfield
local Rayfield
do
    local ok, result = pcall(function()
        return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
    end)
    if ok and result then
        Rayfield = result
        warn("[Vechnost] Rayfield loaded OK")
    else
        warn("[Vechnost] ERROR loading Rayfield:", result)
        return
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
    ServerWide = false,  -- Local only
    LogCount = 0,
    -- Main Features
    AutoUseRod = false,
    AutoSell = false,
    DisablePopups = false,
    DisableMinigame = false,
    LegitFishing = false,
    -- Utility (backend-only)
    AntiAFK = false,
    AutoReconnect = false,
    PingMonitor = false,
}

-- =====================================================
-- BAGIAN 4: FISH DATABASE
-- =====================================================
local FishDB = {}
do
    local ok, err = pcall(function()
        local Items = ReplicatedStorage:WaitForChild("Items", 10)
        if not Items then return end
        local debugOnce = true
        for _, module in ipairs(Items:GetChildren()) do
            if module:IsA("ModuleScript") then
                local ok2, mod = pcall(require, module)
                if ok2 and mod and mod.Data and mod.Data.Type == "Fish" then
                    -- Debug: print all data keys for first fish
                    if debugOnce then
                        debugOnce = false
                        warn("[Vechnost] FishDB sample keys for:", mod.Data.Name)
                        for k, v in pairs(mod.Data) do
                            warn("  ", k, "=", tostring(v))
                        end
                    end
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


-- Secret Fish Asset IDs for Fallback/Proxy Images
local SecretFishData = {
    ["Crystal Crab"] = 18335072046, ["Orca"] = 18335061483, ["Zombie Shark"] = 18335056722,
    ["Zombie Megalodon"] = 18335056551, ["Dead Zombie Shark"] = 18335056722, ["Blob Shark"] = 18335068212,
    ["Ghost Shark"] = 18335059639, ["Skeleton Narwhal"] = 18335057177, ["Ghost Worm Fish"] = 18335059511,
    ["Worm Fish"] = 18335057406, ["Megalodon"] = 18335063073, ["1x1x1x1 Comet Shark"] = 18335068832,
    ["Bloodmoon Whale"] = 18335067980, ["Lochness Monster"] = 18335063708, ["Monster Shark"] = 18335062145,
    ["Eerie Shark"] = 18335060416, ["Great Whale"] = 18335058867, ["Frostborn Shark"] = 18335059957,
    ["Armored Shark"] = 18335068417, ["Scare"] = 18335058097, ["Queen Crab"] = 18335058252,
    ["King Crab"] = 18335064431, ["Cryoshade Glider"] = 18335066928, ["Panther Eel"] = 18335060799,
    ["Giant Squid"] = 18335059345, ["Depthseeker Ray"] = 18335066551, ["Robot Kraken"] = 18335058448,
    ["Mosasaur Shark"] = 18335061981, ["King Jelly"] = 18335064243, ["Bone Whale"] = 18335067645,
    ["Elshark Gran Maja"] = 18335060241, ["Elpirate Gran Maja"] = 18335060241, ["Ancient Whale"] = 18335068612,
    ["Gladiator Shark"] = 18335059068, ["Ancient Lochness Monster"] = 18335063708, ["Talon Serpent"] = 18335057777,
    ["Hacker Shark"] = 18335059223, ["ElRetro Gran Maja"] = 18335060241, ["Strawberry Choc Megalodon"] = 18335063073,
    ["Krampus Shark"] = 18335062145, ["Emerald Winter Whale"] = 18335058867, ["Winter Frost Shark"] = 18335059957,
    ["Icebreaker Whale"] = 18335067645, ["Leviathan"] = 18335063983, ["Pirate Megalodon"] = 18335063073,
    ["Viridis Lurker"] = 18335060799, ["Cursed Kraken"] = 18335058448, ["Ancient Magma Whale"] = 18335068612,
    ["Rainbow Comet Shark"] = 18335118712, ["Love Nessie"] = 18335063708, ["Broken Heart Nessie"] = 18335063708
}
local PROXY = "https://square-haze-a007.remediashop.workers.dev"

-- Build reverse lookup: Fish Name -> Fish ID (for chat parsing)
local FishNameToId = {}
for fishId, fishData in pairs(FishDB) do
    if fishData.Name then
        FishNameToId[fishData.Name] = fishId
        FishNameToId[string.lower(fishData.Name)] = fishId
    end
end
warn("[Vechnost] FishDB Loaded:", #FishNameToId > 0 and "OK" or "EMPTY")

-- =====================================================
-- BAGIAN 4B: REPLION PLAYER DATA (Coins, Stats, Backpack)
-- =====================================================
local PlayerData = nil
do
    pcall(function()
        local Replion = require(ReplicatedStorage.Packages.Replion)
        PlayerData = Replion.Client:WaitReplion("Data")
        if PlayerData then
            warn("[Vechnost] Player Replion Data loaded OK")
        end
    end)
end

-- Helper: Format number with commas (1234567 -> 1,234,567)
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

-- Helper: Get player stats from Replion data (uses :Get() API)
local _debugStatsDone = false
local function GetPlayerStats()
    local stats = {
        Coins = 0,
        TotalCaught = 0,
        BackpackCount = 0,
        BackpackMax = 0,
    }

    if not PlayerData then return stats end

    pcall(function()
        -- Debug: print all top-level keys on first call
        if not _debugStatsDone then
            _debugStatsDone = true
            warn("[Vechnost] Replion Data top-level keys:")
            local allData = nil
            pcall(function()
                if PlayerData.GetData then
                    allData = PlayerData:GetData()
                end
            end)
            if allData then
                for k, v in pairs(allData) do
                    local vType = typeof(v)
                    if vType == "table" then
                        warn("  ", k, "= [table]")
                        for k2, v2 in pairs(v) do
                            warn("    ", k2, "=", tostring(v2):sub(1, 80))
                        end
                    else
                        warn("  ", k, "=", tostring(v))
                    end
                end
            else
                -- Try :Get() for common keys
                for _, key in ipairs({"Coins", "Currency", "Money", "Gold", "Cash", "Inventory", "Backpack", "Stats", "FishCaught", "TotalCaught", "BackpackSize"}) do
                    local ok, val = pcall(function() return PlayerData:Get(key) end)
                    if ok and val ~= nil then
                        warn("  ", key, "=", tostring(val):sub(1, 80))
                    end
                end
            end
        end

        -- Try :Get() API (Fish It uses Replion :Get())
        local coinVal = nil
        for _, key in ipairs({"Coins", "Currency", "Money", "Gold", "Cash"}) do
            local ok, val = pcall(function() return PlayerData:Get(key) end)
            if ok and val and type(val) == "number" then
                coinVal = val
                break
            end
        end
        stats.Coins = coinVal or 0

        -- Total caught
        for _, key in ipairs({"TotalCaught", "FishCaught", "TotalFish"}) do
            local ok, val = pcall(function() return PlayerData:Get(key) end)
            if ok and val and type(val) == "number" then
                stats.TotalCaught = val
                break
            end
        end
        -- Nested in Stats
        if stats.TotalCaught == 0 then
            pcall(function()
                local s = PlayerData:Get("Stats")
                if s and typeof(s) == "table" then
                    stats.TotalCaught = s.TotalCaught or s.FishCaught or s.TotalFish or 0
                end
            end)
        end

        -- Inventory/Backpack count + max
        pcall(function()
            local inv = PlayerData:Get("Inventory")
            if inv and typeof(inv) == "table" then
                -- Debug: print ALL inventory keys (once)
                if not _debugStatsDone then
                    warn("[Vechnost] Inventory table keys:")
                    for k, v in pairs(inv) do
                        local t = typeof(v)
                        if t == "table" then
                            local c = 0
                            for _ in pairs(v) do c = c + 1 end
                            warn("  Inv." .. tostring(k) .. " = [table:" .. c .. "]")
                        else
                            warn("  Inv." .. tostring(k) .. " = " .. tostring(v))
                        end
                    end
                end
                if inv.Items and typeof(inv.Items) == "table" then
                    local count = 0
                    for _ in pairs(inv.Items) do count = count + 1 end
                    stats.BackpackCount = count
                else
                    local count = 0
                    for _ in pairs(inv) do count = count + 1 end
                    stats.BackpackCount = count
                end
                -- BackpackMax from Inventory table
                if inv.Capacity and type(inv.Capacity) == "number" then
                    stats.BackpackMax = inv.Capacity
                elseif inv.Size and type(inv.Size) == "number" then
                    stats.BackpackMax = inv.Size
                elseif inv.MaxSize and type(inv.MaxSize) == "number" then
                    stats.BackpackMax = inv.MaxSize
                elseif inv.Max and type(inv.Max) == "number" then
                    stats.BackpackMax = inv.Max
                elseif inv.Limit and type(inv.Limit) == "number" then
                    stats.BackpackMax = inv.Limit
                end
            end
        end)

        -- Backpack max from top-level keys
        if stats.BackpackMax == 0 then
            for _, key in ipairs({"BackpackSize", "MaxBackpack", "BackpackMax", "InventorySize", "MaxInventory", "InventoryCapacity"}) do
                local ok, val = pcall(function() return PlayerData:Get(key) end)
                if ok and val and type(val) == "number" and val > 0 then
                    stats.BackpackMax = val
                    break
                end
            end
        end
        -- Nested in Upgrades
        if stats.BackpackMax == 0 then
            pcall(function()
                local u = PlayerData:Get("Upgrades")
                if u and typeof(u) == "table" then
                    stats.BackpackMax = u.BackpackSize or u.Backpack or u.InventorySize or u.Capacity or 0
                end
            end)
        end

        -- Scan PlayerGui for backpack label (e.g. "914 / 4500")
        if stats.BackpackMax == 0 then
            pcall(function()
                local function scanGui(parent)
                    for _, child in ipairs(parent:GetDescendants()) do
                        if (child:IsA("TextLabel") or child:IsA("TextButton")) and child.Text then
                            local cur, mx = string.match(child.Text, "(%d+)%s*/%s*(%d+)")
                            if cur and mx then
                                local maxNum = tonumber(mx)
                                if maxNum and maxNum >= 100 then
                                    stats.BackpackMax = maxNum
                                    return true
                                end
                            end
                        end
                    end
                    return false
                end
                local pg = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
                if pg then scanGui(pg) end
            end)
        end

        -- TotalCaught fallback: count Inventory items if no direct field
        if stats.TotalCaught == 0 and stats.BackpackCount > 0 then
            stats.TotalCaught = stats.BackpackCount
        end
    end)

    return stats
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
    [8] = 0x00e5ff, [9] = 0x448aff,
}

local RARITY_EMOJI = {
    [1] = "⬜", [2] = "🟩", [3] = "🟦", [4] = "🟪",
    [5] = "🟧", [6] = "🟥", [7] = "⬛", [8] = "🔷", [9] = "💠",
}

local RarityList = {"Common","Uncommon","Rare","Epic","Legendary","Mythic","Secret"}

-- =====================================================
-- BAGIAN 6: HTTP REQUEST (Executor Compatible)
-- =====================================================
local HttpRequest =
    syn and syn.request
    or http_request
    or request
    or (fluxus and fluxus.request)
    or (krnl and krnl.request)

if not HttpRequest then
    warn("[Vechnost][FATAL] HttpRequest not available in this executor")
end

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
        if not fish or not fish.Icon then
            callback("")
            return
        end

        -- Check SecretFishData for direct proxy link fallback
        if fish.Name and SecretFishData[fish.Name] then
            local proxyUrl = PROXY .. "/asset/" .. tostring(SecretFishData[fish.Name])
            IconCache[fishId] = proxyUrl
            for _, cb in ipairs(IconWaiter[fishId]) do cb(proxyUrl) end
            IconWaiter[fishId] = nil
            return
        end

        local assetId = tostring(fish.Icon):match("%d+")
        if not assetId then
            callback("")
            return
        end

        local api = ("https://thumbnails.roblox.com/v1/assets?assetIds=%s&size=420x420&format=Png&isCircular=false"):format(assetId)

        local ok, res = pcall(function()
            return HttpRequest({ Url = api, Method = "GET" })
        end)

        if not ok or not res or not res.Body then
            callback("")
            return
        end

        local ok2, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
        if not ok2 then
            callback("")
            return
        end

        local imageUrl = data and data.data and data.data[1] and data.data[1].imageUrl
        IconCache[fishId] = imageUrl or ""

        for _, cb in ipairs(IconWaiter[fishId]) do
            cb(IconCache[fishId])
        end
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
        if not mutation then
            for k, v in pairs(weightData) do
                local lk = string.lower(tostring(k))
                if lk == "variant" or lk == "variantid" or lk == "mutation" then
                    mutation = v
                    break
                end
            end
        end
    end

    if not mutation and item then
        mutation = item.Mutation or item.Variant or item.VariantID
        if not mutation and item.Properties then
            mutation = item.Properties.Mutation or item.Properties.Variant or item.Properties.VariantID
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
-- BAGIAN 9: WEBHOOK ENGINE (Discord Components V2)
-- =====================================================

-- Helper: Build a Components V2 fish catch payload (Vechnost Style)
local function BuildPayload(playerName, fishId, weight, mutation)
    local fish = FishDB[fishId]
    if not fish then return nil end

    local tier = fish.Tier
    local rarityName = RARITY_MAP[tier] or "Unknown"
    local mutText = (mutation ~= nil) and tostring(mutation) or "None"
    local weightText = string.format("%.1fkg", weight or 0)
    local iconUrl = IconCache[fishId] or ""
    
    -- Rarity emoji by tier
    local _e = string.char
    local RARITY_EMOJI = {
        [1] = _e(226,172,156), [2] = _e(240,159,159,169), [3] = _e(240,159,159,166),
        [4] = _e(240,159,159,170), [5] = _e(240,159,159,167), [6] = _e(240,159,159,165),
        [7] = _e(240,159,159,165), [8] = _e(240,159,159,169), [9] = _e(240,159,159,166),
    }
    local rarityEmoji = RARITY_EMOJI[tier] or ""
    local dateStr = os.date("!%B %d, %Y")

    -- Components V2 payload
    local payload = {
        username = "Vechnost Notifier",
        avatar_url = "https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png",
        flags = 32768,
        components = {
            {
                type = 17,
                components = {
                    -- Header baru: # NEW FISH CAUGHT!
                    { type = 10, content = "# NEW FISH CAUGHT!" },
                    
                    -- Pembatas garis pertama
                    { type = 14, spacing = 1, divider = true },
                    
                    -- Text: __@username you got new [RARITY] fish__
                    { 
                        type = 10, 
                        content = "__@" .. (playerName or "Unknown") .. " you got new " .. string.upper(rarityName) .. " fish__" 
                    },
                    
                    -- Section Fish Name & Thumbnail
                    {
                        type = 9,
                        components = {
                            { type = 10, content = "**Fish Name**" },
                            { type = 10, content = "> " .. (fish.Name or "Unknown") }
                        },
                        accessory = iconUrl ~= "" and {
                            type = 11,
                            media = { url = iconUrl }
                        } or nil
                    },
                    
                    -- Section Fish Tier
                    { type = 10, content = "**Fish Tier**" },
                    { type = 10, content = "> " .. string.upper(rarityName) },
                    
                    -- Section Weight
                    { type = 10, content = "**Weight**" },
                    { type = 10, content = "> " .. weightText },
                    
                    -- Section Mutation
                    { type = 10, content = "**Mutation**" },
                    { type = 10, content = "> " .. mutText },

                    -- Pembatas garis kedua
                    { type = 14, spacing = 1, divider = true },

                    -- Footer baru
                    { type = 10, content = "> Notification by discord.gg/vechnost" },
                    { type = 10, content = "-# " .. dateStr }
                }
            }
        }
    }

    return payload
end


-- Helper: Build activation payload (Vechnost Style)
local function BuildActivationPayload(playerName, mode)
    local dateStr = os.date("!%B %d, %Y")
    return {
        username = "Vechnost Notifier",
        avatar_url = "https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png?ex=69a96593&is=69a81413&hm=04e442b9e2b765e68e0f73bb0d6de014c6060b67b0bf0d7bb2bace70bfa4ff19&",
        flags = 32768,
        components = {
            {
                type = 17,
                accent_color = 0x30ff6a,
                components = {
                    {
                        type = 10,
                        content = "**" .. playerName .. "  Webhook Activated !**"
                    },
                    { type = 14, spacing = 1, divider = true },
                    {
                        type = 10,
                        content = "### Vechnost Webhook Notifier"
                    },
                    {
                        type = 10,
                        content = "- **Account Name:** " .. playerName .. "\n- **Mode:** " .. mode .. "\n- **Status:** Online"
                    },
                    { type = 14, spacing = 1, divider = true },
                    {
                        type = 10,
                        content = "-# " .. dateStr
                    }
                }
            }
        }
    }
end

-- Helper: Build test payload (Vechnost Style)
local function BuildTestPayload(playerName)
    local dateStr = os.date("!%B %d, %Y")
    return {
        username = "Vechnost Notifier",
        avatar_url = "https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png?ex=69a96593&is=69a81413&hm=04e442b9e2b765e68e0f73bb0d6de014c6060b67b0bf0d7bb2bace70bfa4ff19&",
        flags = 32768,
        components = {
            {
                type = 17,
                accent_color = 0x5865f2,
                components = {
                    {
                        type = 10,
                        content = "**Test Message**"
                    },
                    { type = 14, spacing = 1, divider = true },
                    {
                        type = 10,
                        content = "Webhook berfungsi dengan baik!\n\n- **Dikirim oleh:** " .. playerName
                    },
                    { type = 14, spacing = 1, divider = true },
                    {
                        type = 10,
                        content = "-# " .. dateStr
                    }
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
        -- Append ?with_components=true for Components V2
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
local RecentChatWeights = {} -- Cache: fishName -> weight from chat messages

-- CHAT MONITOR: Parse server chat messages
-- Format: "[Server]: PLAYER obtained a FISHNAME (WEIGHTkg) with a 1 in X chance!"
local function ParseChatForFish(messageText)
    if not Settings.Active then return end
    if not Settings.ServerWide then return end
    if not messageText or messageText == "" then return end

    -- Pattern: "PLAYER obtained a FISHNAME (WEIGHTkg)"
    -- Also try: "PLAYER obtained FISHNAME" without "a"
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

    -- Clean up fish name (remove trailing spaces)
    fishName = string.gsub(fishName, "%s+$", "")

    -- Cache weight from chat for all players (event handler can use this)
    local weight = tonumber(weightStr) or 0
    if weight > 0 and fishName then
        RecentChatWeights[fishName] = weight
        task.defer(function()
            task.wait(10)
            if RecentChatWeights[fishName] == weight then
                RecentChatWeights[fishName] = nil
            end
        end)
    end

    -- Skip own catches (handled by primary hook which uses cached weight)
    if playerName == LocalPlayer.Name or playerName == LocalPlayer.DisplayName then
        return
    end

    -- Lookup fish in database by name
    local fishId = FishNameToId[fishName] or FishNameToId[string.lower(fishName)]
    if not fishId then
        -- Try partial match
        for name, id in pairs(FishNameToId) do
            if string.find(string.lower(fishName), string.lower(name)) or string.find(string.lower(name), string.lower(fishName)) then
                fishId = id
                break
            end
        end
    end

    if not fishId then
        warn("[Vechnost] Chat fish not in DB:", fishName)
        return
    end

    -- Rarity filter
    if not IsRarityAllowed(fishId) then return end

    -- Dedup by message content + timestamp
    local dedupKey = playerName .. fishName .. tostring(math.floor(os.time() / 2))
    if ChatSentDedup[dedupKey] then return end
    ChatSentDedup[dedupKey] = true

    -- Clean up old dedup entries periodically
    task.defer(function()
        task.wait(10)
        ChatSentDedup[dedupKey] = nil
    end)

    Settings.LogCount = Settings.LogCount + 1
    warn("[Vechnost] Notifier via CHAT:", playerName, "caught", FishDB[fishId].Name, "(", weight, "kg)")

    FetchFishIconAsync(fishId, function()
        SendWebhook(BuildPayload(playerName, fishId, weight, nil))
    end)
end

-- DIRECT HANDLER: Matches exact UQiLL data format
-- ObtainedNewFishNotification fires with: (playerOrNil, weightData, wrapper)
local function HandleFishCaught(playerArg, weightData, wrapper)
    if not Settings.Active then return end

    -- Extract item from wrapper
    local item = nil
    if wrapper and typeof(wrapper) == "table" and wrapper.InventoryItem then
        item = wrapper.InventoryItem
    end

    -- If wrapper didn't work, maybe weightData IS the wrapper
    if not item and weightData and typeof(weightData) == "table" and weightData.InventoryItem then
        item = weightData.InventoryItem
    end

    if not item then
        warn("[Vechnost] No InventoryItem found in event data")
        return
    end

    if not item.Id or not item.UUID then
        warn("[Vechnost] Item missing Id or UUID")
        return
    end

    -- Check if fish exists in database
    if not FishDB[item.Id] then return end

    -- Rarity filter
    if not IsRarityAllowed(item.Id) then return end

    -- UUID dedup
    if Settings.SentUUID[item.UUID] then return end
    Settings.SentUUID[item.UUID] = true

    -- Resolve player name
    local playerName = ResolvePlayerName(playerArg)

    -- Skip non-local if not server-wide
    if not Settings.ServerWide and playerName ~= LocalPlayer.Name then return end

    -- Extract weight (try multiple sources)
    local weight = 0
    -- Debug: log weightData and item keys on first catch
    if Settings.LogCount == 0 then
        if weightData and typeof(weightData) == "table" then
            warn("[Vechnost] weightData keys:")
            for k, v in pairs(weightData) do
                warn("  wD." .. tostring(k) .. " = " .. tostring(v))
            end
        elseif weightData then
            warn("[Vechnost] weightData type:", typeof(weightData), "val:", tostring(weightData))
        end
        if item then
            warn("[Vechnost] item keys:")
            for k, v in pairs(item) do
                warn("  item." .. tostring(k) .. " = " .. tostring(v))
            end
        end
    end

    if weightData and typeof(weightData) == "table" then
        weight = weightData.Weight or weightData.weight or weightData.Size or weightData.size or 0
    elseif weightData and type(weightData) == "number" then
        weight = weightData
    end
    -- Fallback: weight might be in the item itself
    if weight == 0 and item then
        weight = item.Weight or item.weight or item.Size or item.size or 0
    end

    -- Fallback 2: check chat cache if weight is still 0
    if weight == 0 then
        local fishInfo = FishDB[item.Id]
        if fishInfo and fishInfo.Name then
            local cachedWeight = RecentChatWeights[fishInfo.Name]
            if cachedWeight then
                weight = cachedWeight
                warn("[Vechnost] Weight recovered from chat cache:", weight)
            end
        end
    end

    -- Extract mutation
    local mutation = ExtractMutation(weightData, item)

    Settings.LogCount = Settings.LogCount + 1
    warn("[Vechnost] Fish caught! Player:", playerName, "Fish:", FishDB[item.Id].Name, "Count:", Settings.LogCount)

    FetchFishIconAsync(item.Id, function()
        SendWebhook(BuildPayload(playerName, item.Id, weight, mutation))
    end)
end

-- GENERIC SCANNER: For other remotes that might carry fish data
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
                -- Found fish data, delegate to main handler
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

    if not net or not ObtainedNewFish then
            Rayfield:Notify({ Title = "Vechnost", Content = "ERROR: Game remotes not found! Are you in Fish It?", Duration = 5 })
        return
    end

    Settings.Active = true
    Settings.SentUUID = {}
    Settings.LogCount = 0

    -- CHAT MONITOR: Listen to server chat for fish catch announcements
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
            warn("[Vechnost] Chat monitor (TextChatService) active")
        end)

        -- Fallback: Old chat system via StarterGui
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
                warn("[Vechnost] Chat monitor (StarterGui) active")
            end
        end)
    end

    -- PRIMARY: ObtainedNewFishNotification (exact format from UQiLL)
    local ok1, err1 = pcall(function()
        Connections[#Connections + 1] = ObtainedNewFish.OnClientEvent:Connect(function(playerArg, weightData, wrapper)
            HandleFishCaught(playerArg, weightData, wrapper)
        end)
    end)
    if ok1 then
        warn("[Vechnost] Primary hook connected OK")
    else
        warn("[Vechnost] Primary hook error:", err1)
    end

    -- SECONDARY: GUI Notification Scanner
    -- Fish It shows server-wide notifications when players catch rare fish
    -- We scan PlayerGui for these notification GUIs and parse the text
    if Settings.ServerWide then
        pcall(function()
            local function ScanNotificationText(textObj)
                if not textObj or not textObj:IsA("TextLabel") then return end
                local text = textObj.Text or ""
                if text == "" then return end

                -- Look for patterns like "PlayerName caught FishName" or similar
                -- Check if any fish name from our DB appears in the text
                for fishId, fishData in pairs(FishDB) do
                    if fishData.Name and string.find(text, fishData.Name) then
                        -- Found a fish name in notification text!
                        -- Try to extract player name (usually before the fish name)
                        local playerName = "Unknown"

                        -- Try common patterns
                        for _, player in pairs(Players:GetPlayers()) do
                            if player ~= LocalPlayer and string.find(text, player.Name) then
                                playerName = player.Name
                                break
                            elseif player ~= LocalPlayer and string.find(text, player.DisplayName) then
                                playerName = player.DisplayName
                                break
                            end
                        end

                        -- Skip if it's our own catch (already handled by primary hook)
                        if playerName == LocalPlayer.Name or playerName == LocalPlayer.DisplayName then
                            return
                        end
                        if string.find(text, LocalPlayer.Name) or string.find(text, LocalPlayer.DisplayName) then
                            return
                        end

                        -- Skip if we can't identify another player
                        if playerName == "Unknown" then return end

                        -- Create dedup key from text
                        local dedupKey = "GUI_" .. text .. "_" .. os.time()
                        if Settings.SentUUID[dedupKey] then return end
                        Settings.SentUUID[dedupKey] = true

                        -- Rarity filter
                        if not IsRarityAllowed(fishId) then return end

                        Settings.LogCount = Settings.LogCount + 1
                        warn("[Vechnost] Notifier catch detected via GUI!", playerName, fishData.Name)

                        FetchFishIconAsync(fishId, function()
                            SendWebhook(BuildPayload(playerName, fishId, 0, nil))
                        end)
                        return
                    end
                end
            end

            -- Watch for new GUI elements appearing in PlayerGui
            Connections[#Connections + 1] = PlayerGui.DescendantAdded:Connect(function(desc)
                if not Settings.Active then return end
                if desc:IsA("TextLabel") then
                    task.defer(function()
                        ScanNotificationText(desc)
                    end)
                end
            end)
            warn("[Vechnost] GUI notification scanner active")
        end)

        -- TERTIARY: Replion shared state listener (NON-BLOCKING)
        -- Runs in background threads so it never blocks the main script
        pcall(function()
            local Replion = require(ReplicatedStorage.Packages.Replion)

            local stateNames = {"ServerFeed", "GlobalNotifications", "RecentCatches", "FishLog", "ServerNotifications", "Feed"}
            for _, stateName in ipairs(stateNames) do
                task.spawn(function()
                    local found = false
                    -- Timeout: cancel after 3 seconds
                    task.delay(3, function()
                        if not found then return end
                    end)
                    local ok, state = pcall(function()
                        return Replion.Client:WaitReplion(stateName)
                    end)
                    if ok and state then
                        found = true
                        warn("[Vechnost] Found Replion state:", stateName)
                        pcall(function()
                            state:OnChange(function(key, value)
                                if not Settings.Active then return end
                                if typeof(value) == "table" then
                                    if value.InventoryItem or (value.Id and value.UUID) then
                                        HandleFishCaught(value.Player or value.PlayerName, value, {InventoryItem = value.InventoryItem or value})
                                    end
                                end
                            end)
                        end)
                    end
                end)
            end
        end)

        -- QUATERNARY: Hook ALL RemoteEvents for fish data
        local hookCount = 0
        pcall(function()
            for _, child in pairs(net:GetChildren()) do
                if child:IsA("RemoteEvent") and child ~= ObtainedNewFish then
                    Connections[#Connections + 1] = child.OnClientEvent:Connect(function(...)
                        TryProcessGeneric(child.Name, ...)
                    end)
                    hookCount = hookCount + 1
                end
            end
        end)
        warn("[Vechnost] Remote hooks:", hookCount, "events connected")

        -- QUINARY: Join/Leave & Backpack hooks
        local function WatchBackpack(player)
            Connections[#Connections + 1] = player.CharacterAdded:Connect(function()
                local bp = player:WaitForChild("Backpack", 15)
                if not bp then return end
                Connections[#Connections + 1] = bp.ChildAdded:Connect(function(item)
                    if not Settings.Active then return end
                    local fishId = FishNameToId[item.Name] or FishNameToId[string.lower(item.Name)]
                    if fishId and IsRarityAllowed(fishId) then
                        local playerName = player.Name
                        if not Settings.ServerWide and playerName ~= LocalPlayer.Name then return end
                        task.defer(function()
                            task.wait(2)
                            local dedupKey = playerName .. item.Name .. tostring(math.floor(os.time() / 2))
                            if ChatSentDedup[dedupKey] then return end
                            local fallbackWeight = 0
                            if RecentChatWeights[item.Name] then fallbackWeight = RecentChatWeights[item.Name] end
                            HandleFishCaught(player, fallbackWeight, {InventoryItem = {Id = fishId, UUID = "Fallback_"..fishId..tick()}})
                        end)
                    end
                end)
            end)
        end

        Connections[#Connections + 1] = Players.PlayerAdded:Connect(function(newPlayer)
            WatchBackpack(newPlayer)
        end)

        -- Watch existing players' backpack too
        for _, p in ipairs(Players:GetPlayers()) do
            WatchBackpack(p)
        end
    end

    -- Send activation message
    task.spawn(function()
        SendWebhook(BuildActivationPayload(LocalPlayer.Name, "Local"))
    end)

    warn("[Vechnost] Webhook Logger ENABLED | Mode: Local")
end

local function StopLogger()
    Settings.Active = false

    for _, conn in ipairs(Connections) do
        pcall(function() conn:Disconnect() end)
    end
    Connections = {}

    warn("[Vechnost] Webhook Logger DISABLED | Total logged:", Settings.LogCount)
end

-- =====================================================
-- BAGIAN 10B: AUTOMATION (MACROS)
-- =====================================================
local TeleportService = game:GetService("TeleportService")
local GuiService = game:GetService("GuiService")

-- Helper: get rnet reference
local function getRnet()
    local pkg = game:GetService("ReplicatedStorage"):FindFirstChild("Packages")
    if not pkg then return nil end
    local idx = pkg:FindFirstChild("_Index")
    if not idx then return nil end
    local sleit = idx:FindFirstChild("sleitnick_net@0.2.0")
    if not sleit then return nil end
    return sleit:FindFirstChild("net")
end

-- 1. Anti-AFK (backend, no UI toggle)
local afkConn = Players.LocalPlayer.Idled:Connect(function()
    if Settings.AntiAFK then
        pcall(function() UserInputService.InputBegan:Fire(Enum.KeyCode.F20, false) end)
    end
end)
if getconnections then
    for _, v in pairs(getconnections(Players.LocalPlayer.Idled)) do
        if v.Disable then v:Disable() end
    end
end

-- 2. Auto Use Rod (baru) - equip + cast rod otomatis
task.spawn(function()
    while true do
        task.wait(0.6)
        if Settings.AutoUseRod then
            pcall(function()
                local rnet = getRnet()
                if rnet then
                    local equipEnv = rnet:FindFirstChild("RE/EquipToolFromHotbar")
                    local chargeEnv = rnet:FindFirstChild("RF/ChargeFishingRod")
                    if equipEnv and chargeEnv then
                        equipEnv:FireServer()
                        task.wait(0.2)
                        chargeEnv:InvokeServer(1)
                    end
                end
            end)
        end
    end
end)

-- 3. Legit Fishing (auto cast + auto click, dengan delay acak)
task.spawn(function()
    local FishingController = nil
    pcall(function()
        FishingController = require(ReplicatedStorage:WaitForChild("Controllers", 10):WaitForChild("FishingController", 10))
    end)
    while true do
        task.wait(0.1)
        if Settings.LegitFishing then
            -- Auto click minigame dengan delay acak agar terlihat natural
            if FishingController then
                pcall(function() FishingController:RequestFishingMinigameClick() end)
                task.wait(math.random(80, 180) / 1000)
            end
            -- Auto cast jika tidak sedang memancing
            pcall(function()
                local rnet = getRnet()
                if rnet then
                    local chargeEnv = rnet:FindFirstChild("RF/ChargeFishingRod")
                    if chargeEnv then chargeEnv:InvokeServer(1) end
                end
            end)
        end
    end
end)

-- 4. Disable Minigame - langsung complete saat minigame aktif
task.spawn(function()
    while true do
        task.wait(0.15)
        if Settings.DisableMinigame then
            pcall(function()
                local rnet = getRnet()
                if rnet then
                    local completeEnv = rnet:FindFirstChild("RE/FishingCompleted")
                    if completeEnv then
                        completeEnv:FireServer()
                    end
                end
            end)
        end
    end
end)

-- 5. Block Notifications
task.spawn(function()
    local _pg = Players.LocalPlayer:WaitForChild("PlayerGui", 10)
    local SmallNotification = _pg and _pg:WaitForChild("Small Notification", 10)
    RunService.RenderStepped:Connect(function()
        if Settings.DisablePopups and SmallNotification then
            pcall(function() SmallNotification.Enabled = false end)
        end
    end)
end)

-- 6. Auto Sell (setiap 30 detik)
task.spawn(function()
    while true do
        task.wait(30)
        if Settings.AutoSell then
            pcall(function()
                local rnet = getRnet()
                if rnet then
                    local sellEvent = rnet:FindFirstChild("RF/SellAllItems")
                    if sellEvent then
                        sellEvent:InvokeServer()
                        Rayfield:Notify({ Title = "Vechnost", Content = "Auto Sell: Ikan berhasil dijual!", Duration = 2 })
                    else
                        -- fallback path
                        local fallback = game:GetService("ReplicatedStorage"):FindFirstChild("RF/SellAllItems")
                        if fallback then fallback:InvokeServer() end
                    end
                end
            end)
        end
    end
end)

-- 7. Ping Monitor (backend)
task.spawn(function()
    local LastPingAlert = 0
    while true do
        task.wait(5)
        if Settings.PingMonitor and Settings.Url ~= "" then
            pcall(function()
                local ping = game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()
                if ping > 500 and (tick() - LastPingAlert > 60) then
                    LastPingAlert = tick()
                    SendWebhook({
                        username = "Vechnost Alert",
                        avatar_url = "https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png",
                        embeds = {{
                            title = "⚠️ SERVER LAG ALERT",
                            description = "High Ping: " .. math.floor(ping) .. " ms | Player: " .. LocalPlayer.Name,
                            color = 16776960
                        }}
                    })
                end
            end)
        end
    end
end)

-- 8. Auto Reconnect (backend)
local isReconnecting = false
local function triggerReconnect(kickMsg)
    if not Settings.AutoReconnect or isReconnecting then return end
    isReconnecting = true
    warn("[Vechnost] Auto Reconnect triggered: " .. tostring(kickMsg))
    task.wait(5)
    pcall(function()
        if #Players:GetPlayers() <= 1 then
            TeleportService:Teleport(game.PlaceId, LocalPlayer)
        else
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
        end
    end)
end
GuiService.ErrorMessageChanged:Connect(function(msg) triggerReconnect(msg) end)

-- =====================================================
-- BAGIAN 11: RAYFIELD UI
-- =====================================================
local Window = Rayfield:CreateWindow({
    Name = "Vechnost",
    Icon = "fish",
    LoadingTitle = "Vechnost",
    LoadingSubtitle = "v2.0.0",
    Theme = "Default",
    ToggleUIKeybind = "V",
    DisableRayfieldPrompts = true,
    DisableBuildWarnings = true,
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "Vechnost",
        FileName = "VechnostConfig"
    },
    KeySystem = true,
    KeySettings = {
        Title = "Vechnost Access",
        Subtitle = "Authentication Required",
        Note = "Join our discord to get key\n https://discord.gg/pFhdW9ZwwY",
        FileName = "VechnostKey",
        SaveKey = true,
        GrabKeyFromSite = false,
        Key = {"Vechnost-Notifier-9999"}
    },
})

-- =====================================================
-- BAGIAN 12: FLOATING TOGGLE BUTTON
-- =====================================================
local oldBtn = CoreGui:FindFirstChild(GUI_NAMES.Mobile)
if oldBtn then oldBtn:Destroy() end

local BtnGui = Instance.new("ScreenGui")
BtnGui.Name = GUI_NAMES.Mobile
BtnGui.ResetOnSpawn = false
BtnGui.Parent = CoreGui

local Button = Instance.new("ImageButton")
Button.Size = UDim2.fromOffset(52, 52)
Button.Position = UDim2.fromScale(0.05, 0.5)
Button.BackgroundTransparency = 1
Button.AutoButtonColor = false
Button.BorderSizePixel = 0
Button.Image = "rbxassetid://127239715511367"
Button.ImageTransparency = 0
Button.ScaleType = Enum.ScaleType.Fit
Button.Parent = BtnGui

Instance.new("UICorner", Button).CornerRadius = UDim.new(1, 0)

local windowVisible = true
Button.MouseButton1Click:Connect(function()
    windowVisible = not windowVisible
    pcall(function() Rayfield:SetVisibility(windowVisible) end)
end)

local dragging = false
local dragOffset = Vector2.zero

Button.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragOffset = UserInputService:GetMouseLocation() - Button.AbsolutePosition
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

RunService.RenderStepped:Connect(function()
    if not dragging then return end
    local mouse = UserInputService:GetMouseLocation()
    local target = mouse - dragOffset
    local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
    local sz = Button.AbsoluteSize
    local cx = math.clamp(target.X, 0, vp.X - sz.X)
    local cy = math.clamp(target.Y, 0, vp.Y - sz.Y)
    Button.Position = UDim2.fromOffset(cx, cy)
end)

-- =====================================================
-- BAGIAN 13: TABS (urutan: Info, Main, Teleport, Webhook, Config)
-- =====================================================
local TabInfo     = Window:CreateTab("Information", "info")
local TabMain     = Window:CreateTab("Main",        "home")
local TabTeleport = Window:CreateTab("Teleport",    "map-pin")
local TabWebhook  = Window:CreateTab("Webhook",     "send")
local TabConfig   = Window:CreateTab("Config",      "file")

-- =====================================================
-- TAB: INFORMATION
-- =====================================================
TabInfo:CreateSection("Vechnost Information")

TabInfo:CreateParagraph({
    Title = "⚠️ Warning",
    Content = "Script are under development, use at your own risk!"
})

TabInfo:CreateSection("Welcome")

local WelcomeParagraph = TabInfo:CreateParagraph({
    Title = "Welcome / Welcome back, @" .. LocalPlayer.Name,
    Content = "Loading inventory data..."
})

-- Helper: format angka besar
local function FormatShort(n)
    n = tonumber(n) or 0
    if n >= 1000000000 then return string.format("%.1fb", n / 1000000000)
    elseif n >= 1000000 then return string.format("%.1fm", n / 1000000)
    elseif n >= 1000    then return string.format("%.1fk", n / 1000)
    else return tostring(math.floor(n)) end
end

-- Update inventory info setiap 5 detik
task.spawn(function()
    while true do
        task.wait(5)
        pcall(function()
            local secretCount      = 0
            local evolvedStoneCount = 0
            local mythicCoinValue  = 0

            if PlayerData then
                pcall(function()
                    local inv = PlayerData:Get("Inventory")
                    if inv and typeof(inv) == "table" then
                        local items = inv.Items or inv
                        for _, item in pairs(items) do
                            if typeof(item) == "table" then
                                local itemId   = item.Id or item.id
                                local itemName = tostring(item.Name or item.name or "")
                                -- Secret fish (Tier 7)
                                if itemId and FishDB[itemId] and FishDB[itemId].Tier == 7 then
                                    secretCount = secretCount + 1
                                end
                                -- Mythic fish (Tier 6) -> nilai koin
                                if itemId and FishDB[itemId] and FishDB[itemId].Tier == 6 then
                                    mythicCoinValue = mythicCoinValue + (FishDB[itemId].SellPrice or 0)
                                end
                                -- Evolved Stone
                                if string.find(string.lower(itemName), "evolved stone") then
                                    evolvedStoneCount = evolvedStoneCount + 1
                                end
                            end
                        end
                    end
                end)
            end

            WelcomeParagraph:Set({
                Title = "Welcome / Welcome back, @" .. LocalPlayer.Name,
                Content = "Your Inventory\n" ..
                    "Secret : " .. tostring(secretCount) .. "\n" ..
                    "Coin Via Mitos : " .. FormatShort(mythicCoinValue) .. "\n" ..
                    "Evolved Stone : " .. tostring(evolvedStoneCount)
            })
        end)
    end
end)

TabInfo:CreateSection("Join our Community")

TabInfo:CreateButton({
    Name = "COPY LINK",
    Callback = function()
        pcall(function()
            setclipboard("https://discord.gg/pFhdW9ZwwY")
        end)
        Rayfield:Notify({ Title = "Vechnost", Content = "Discord link copied to clipboard!", Duration = 3 })
    end
})

TabInfo:CreateSection("Server Tool's")

TabInfo:CreateButton({
    Name = "Rejoin Server",
    Callback = function()
        Rayfield:Notify({ Title = "Vechnost", Content = "Rejoining server...", Duration = 2 })
        task.wait(1)
        pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
        end)
    end
})

-- =====================================================
-- TAB: MAIN
-- =====================================================
TabMain:CreateSection("Support Feature")

TabMain:CreateToggle({
    Name = "Auto Use Rod",
    CurrentValue = false,
    Flag = "AutoUseRod",
    Callback = function(Value)
        Settings.AutoUseRod = Value
        Rayfield:Notify({ Title = "Vechnost", Content = Value and "Auto Use Rod: ON" or "Auto Use Rod: OFF", Duration = 2 })
    end
})

TabMain:CreateToggle({
    Name = "Auto Sell",
    CurrentValue = false,
    Flag = "AutoSell",
    Callback = function(Value)
        Settings.AutoSell = Value
        Rayfield:Notify({ Title = "Vechnost", Content = Value and "Auto Sell: ON (tiap 30s)" or "Auto Sell: OFF", Duration = 2 })
    end
})

TabMain:CreateToggle({
    Name = "Disable Popup",
    CurrentValue = false,
    Flag = "DisablePopups",
    Callback = function(Value)
        Settings.DisablePopups = Value
        Rayfield:Notify({ Title = "Vechnost", Content = Value and "Popup dinonaktifkan" or "Popup diaktifkan", Duration = 2 })
    end
})

TabMain:CreateToggle({
    Name = "Disable Minigame",
    CurrentValue = false,
    Flag = "DisableMinigame",
    Callback = function(Value)
        Settings.DisableMinigame = Value
        Rayfield:Notify({ Title = "Vechnost", Content = Value and "Disable Minigame: ON" or "Disable Minigame: OFF", Duration = 2 })
    end
})

TabMain:CreateSection("Legit Fishing")

TabMain:CreateToggle({
    Name = "Legit Fishing",
    CurrentValue = false,
    Flag = "LegitFishing",
    Callback = function(Value)
        Settings.LegitFishing = Value
        Rayfield:Notify({
            Title = "Vechnost",
            Content = Value and "Legit Fishing: ON (auto cast + auto click)" or "Legit Fishing: OFF",
            Duration = 2
        })
    end
})

-- =====================================================
-- TAB: TELEPORT
-- =====================================================
TabTeleport:CreateSection("Teleport")

local teleportLocations = {
    ["🏝️ Fisherman Island"] = Vector3.new(13.06, 24.53, 2911.16),
    ["🏝️ Tropical Grove"]   = Vector3.new(-2092.897, 6.268, 3693.929),
    ["🏝️ Coral Reefs"]      = Vector3.new(-2949.359, 63.25, 2213.966),
    ["🏝️ Crater Island"]    = Vector3.new(1012.045, 22.676, 5080.221),
    ["🏝️ Kohana"]           = Vector3.new(-643.14, 16.03, 623.61),
    ["🏝️ Kohana Lava"]      = Vector3.new(-593.32, 59.0, 130.82),
    ["🏝️ Ice Island"]       = Vector3.new(1766.46, 19.16, 3086.23),
    ["🏝️ Lost Isle"]        = Vector3.new(-3660.07, 5.426, -1053.02),
    ["⛩️ Sacred Temple"]    = Vector3.new(1476.232, -21.850, -630.892),
    ["⛩️ Ancient Jungle"]   = Vector3.new(1281.761, 7.791, -202.018),
    ["⛩️ Esoteric Depths"]  = Vector3.new(2024.49, 27.397, 1391.62),
    ["⚙️ Weather Machine"]  = Vector3.new(-1495.25, 6.5, 1889.92),
    ["🗿 Sisyphus Statue"]   = Vector3.new(-3693.96, -135.57, -1027.28),
    ["💎 Treasure Hall"]    = Vector3.new(-3598.39, -275.82, -1641.46),
    ["🔄 Enchant Area"]     = Vector3.new(3236.12, -1302.855, 1399.491),
}
local teleportNames = {}
for name, _ in pairs(teleportLocations) do table.insert(teleportNames, name) end
table.sort(teleportNames)

-- Location dropdown: langsung teleport saat dipilih
TabTeleport:CreateDropdown({
    Name = "Location",
    Options = teleportNames,
    CurrentOption = {""},
    MultipleOptions = false,
    Flag = "TeleportLocation",
    Callback = function(Option)
        if Option[1] and Option[1] ~= "" then
            local pos = teleportLocations[Option[1]]
            local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if hrp and pos then
                hrp.CFrame = CFrame.new(pos)
                Rayfield:Notify({ Title = "Teleported", Content = "→ " .. Option[1], Duration = 2 })
            end
        end
    end
})

-- Player teleport
local SelectedPlayerTarget = ""

local function GetCurrentPlayerNames()
    local names = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            table.insert(names, p.Name)
        end
    end
    return names
end

local function TeleportToPlayer(targetName)
    local target = Players:FindFirstChild(targetName)
    if target and target.Character then
        local hrp    = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        local tHrp   = target.Character:FindFirstChild("HumanoidRootPart")
        if hrp and tHrp then
            hrp.CFrame = tHrp.CFrame + Vector3.new(3, 0, 0)
            Rayfield:Notify({ Title = "Teleported", Content = "→ Player: " .. targetName, Duration = 2 })
            return true
        end
    end
    Rayfield:Notify({ Title = "Vechnost", Content = "Player tidak ditemukan / belum spawn", Duration = 3 })
    return false
end

TabTeleport:CreateDropdown({
    Name = "Player",
    Options = GetCurrentPlayerNames(),
    CurrentOption = {""},
    MultipleOptions = false,
    Flag = "TeleportPlayer",
    Callback = function(Option)
        if Option[1] and Option[1] ~= "" then
            SelectedPlayerTarget = Option[1]
            TeleportToPlayer(SelectedPlayerTarget)
        end
    end
})

TabTeleport:CreateButton({
    Name = "Refresh Player",
    Callback = function()
        -- Refresh list player saat ini
        local updated = GetCurrentPlayerNames()
        Rayfield:Notify({
            Title = "Vechnost",
            Content = "Player list refreshed! (" .. tostring(#updated) .. " players)",
            Duration = 2
        })
        -- Jika sudah ada player yang dipilih, teleport ulang
        if SelectedPlayerTarget ~= "" then
            TeleportToPlayer(SelectedPlayerTarget)
        end
    end
})

-- =====================================================
-- TAB: WEBHOOK
-- =====================================================
TabWebhook:CreateSection("Webhook Fish Caught")

TabWebhook:CreateDropdown({
    Name = "Filter Rarity",
    Options = RarityList,
    CurrentOption = {},
    MultipleOptions = false,
    Flag = "RarityFilter",
    Callback = function(Option)
        Settings.SelectedRarities = {}
        if Option and Option[1] and Option[1] ~= "" then
            local tier = RARITY_NAME_TO_TIER[Option[1]]
            if tier then
                Settings.SelectedRarities[tier] = true
                Rayfield:Notify({ Title = "Vechnost", Content = "Filter: " .. Option[1], Duration = 2 })
            end
        else
            Rayfield:Notify({ Title = "Vechnost", Content = "Filter: Semua rarity", Duration = 2 })
        end
    end
})

local WebhookUrlBuffer = ""

TabWebhook:CreateInput({
    Name = "Webhook URL",
    CurrentValue = "",
    PlaceholderText = "https://discord.com/api/webhooks/...",
    RemoveTextAfterFocusLost = false,
    Flag = "WebhookUrl",
    Callback = function(Text)
        local url = tostring(Text):gsub("%s+", "")
        WebhookUrlBuffer = url
        if url:match("^https://discord.com/api/webhooks/") or
           url:match("^https://canary.discord.com/api/webhooks/") then
            Settings.Url = url
        end
    end
})

TabWebhook:CreateToggle({
    Name = "Send Fish Webhook",
    CurrentValue = false,
    Flag = "LoggerEnabled",
    Callback = function(Value)
        if Value then
            if Settings.Url == "" then
                Rayfield:Notify({ Title = "Vechnost", Content = "Isi webhook URL dulu!", Duration = 3 })
                return
            end
            StartLogger()
            Rayfield:Notify({ Title = "Vechnost", Content = "Webhook Aktif!", Duration = 2 })
        else
            StopLogger()
            Rayfield:Notify({ Title = "Vechnost", Content = "Webhook Berhenti", Duration = 2 })
        end
    end
})

TabWebhook:CreateButton({
    Name = "Test Webhook Connection",
    Callback = function()
        if Settings.Url == "" then
            Rayfield:Notify({ Title = "Vechnost", Content = "Isi webhook URL dulu!", Duration = 3 })
            return
        end
        task.spawn(function()
            SendWebhook(BuildTestPayload(LocalPlayer.Name))
        end)
        Rayfield:Notify({ Title = "Vechnost", Content = "Test message terkirim!", Duration = 2 })
    end
})

local StatusLabel = TabWebhook:CreateParagraph({
    Title = "Notifier Status",
    Content = "Status: Offline ❌"
})

task.spawn(function()
    while true do
        task.wait(2)
        if StatusLabel then
            pcall(function()
                if Settings.Active then
                    StatusLabel:Set({
                        Title = "Notifier Status",
                        Content = string.format("Status: Online ✅\nTotal Log: %d ikan", Settings.LogCount)
                    })
                else
                    StatusLabel:Set({
                        Title = "Notifier Status",
                        Content = "Status: Offline ❌"
                    })
                end
            end)
        end
    end
end)

-- =====================================================
-- TAB: CONFIG
-- =====================================================
TabConfig:CreateSection("Tentang")

TabConfig:CreateParagraph({
    Title = "Vechnost",
    Content = "Version 2.0.0\nFish Catch Webhook Notifier\nby Vechnost\ndiscord.gg/pFhdW9ZwwY"
})

TabConfig:CreateSection("Tools")

TabConfig:CreateButton({
    Name = "Reset Log Counter",
    Callback = function()
        Settings.LogCount = 0
        Settings.SentUUID = {}
        Rayfield:Notify({ Title = "Vechnost", Content = "Log counter di-reset!", Duration = 2 })
    end
})

-- =====================================================
-- BAGIAN 14: INIT
-- =====================================================
Rayfield:LoadConfiguration()
warn("[Vechnost] v2.0.0 Loaded!")
warn("[Vechnost] Toggle GUI: tekan V atau tap tombol floating")
