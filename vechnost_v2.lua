--[[ 
    FILE: vechnost_v2.lua
    BRAND: Vechnost
    VERSION: 2.0.0
    DESC: Server-Wide Fish Webhook Logger + Auto Trading System for Roblox "Fish It"
          Logs fish catches from ALL players in the server
          Sends rich notifications to Discord via Webhook
          Auto Trade: by Name, by Coin, by Rarity, by Stone
    UI: Custom Dark Blue Sidebar Design
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
        warn("[Vechnost] Make sure you are in the Fish It game!")
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
        local debugOnce = true
        for _, module in ipairs(Items:GetChildren()) do
            if module:IsA("ModuleScript") then
                local ok2, mod = pcall(require, module)
                if ok2 and mod and mod.Data and mod.Data.Type == "Fish" then
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

local FishNameToId = {}
for fishId, fishData in pairs(FishDB) do
    if fishData.Name then
        FishNameToId[fishData.Name] = fishId
        FishNameToId[string.lower(fishData.Name)] = fishId
    end
end
warn("[Vechnost] FishDB Loaded:", #FishNameToId > 0 and "OK" or "EMPTY")

-- =====================================================
-- BAGIAN 4B: REPLION PLAYER DATA
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
                for _, key in ipairs({"Coins", "Currency", "Money", "Gold", "Cash", "Inventory", "Backpack", "Stats", "FishCaught", "TotalCaught", "BackpackSize"}) do
                    local ok, val = pcall(function() return PlayerData:Get(key) end)
                    if ok and val ~= nil then
                        warn("  ", key, "=", tostring(val):sub(1, 80))
                    end
                end
            end
        end

        local coinVal = nil
        for _, key in ipairs({"Coins", "Currency", "Money", "Gold", "Cash"}) do
            local ok, val = pcall(function() return PlayerData:Get(key) end)
            if ok and val and type(val) == "number" then
                coinVal = val
                break
            end
        end
        stats.Coins = coinVal or 0

        for _, key in ipairs({"TotalCaught", "FishCaught", "TotalFish"}) do
            local ok, val = pcall(function() return PlayerData:Get(key) end)
            if ok and val and type(val) == "number" then
                stats.TotalCaught = val
                break
            end
        end

        if stats.TotalCaught == 0 then
            pcall(function()
                local s = PlayerData:Get("Stats")
                if s and typeof(s) == "table" then
                    stats.TotalCaught = s.TotalCaught or s.FishCaught or s.TotalFish or 0
                end
            end)
        end

        pcall(function()
            local inv = PlayerData:Get("Inventory")
            if inv and typeof(inv) == "table" then
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

        if stats.BackpackMax == 0 then
            for _, key in ipairs({"BackpackSize", "MaxBackpack", "BackpackMax", "InventorySize", "MaxInventory", "InventoryCapacity"}) do
                local ok, val = pcall(function() return PlayerData:Get(key) end)
                if ok and val and type(val) == "number" and val > 0 then
                    stats.BackpackMax = val
                    break
                end
            end
        end

        if stats.BackpackMax == 0 then
            pcall(function()
                local u = PlayerData:Get("Upgrades")
                if u and typeof(u) == "table" then
                    stats.BackpackMax = u.BackpackSize or u.Backpack or u.InventorySize or u.Capacity or 0
                end
            end)
        end

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
-- BAGIAN 6: HTTP REQUEST
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
    
    local _e = string.char
    local RARITY_EMOJI = {
        [1] = _e(226,172,156), [2] = _e(240,159,159,169), [3] = _e(240,159,159,166),
        [4] = _e(240,159,159,170), [5] = _e(240,159,159,167), [6] = _e(240,159,159,165),
        [7] = _e(240,159,159,165), [8] = _e(240,159,159,169), [9] = _e(240,159,159,166),
    }
    local rarityEmoji = RARITY_EMOJI[tier] or ""
    local dateStr = os.date("!%B %d, %Y")

    local payload = {
        username = "Vechnost Notifier",
        avatar_url = "https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png",
        flags = 32768,
        components = {
            {
                type = 17,
                components = {
                    { type = 10, content = "# NEW FISH CAUGHT!" },
                    { type = 14, spacing = 1, divider = true },
                    { 
                        type = 10, 
                        content = "__@" .. (playerName or "Unknown") .. " you got new " .. string.upper(rarityName) .. " fish__" 
                    },
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

    return payload
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

    if playerName == LocalPlayer.Name or playerName == LocalPlayer.DisplayName then
        return
    end

    local fishId = FishNameToId[fishName] or FishNameToId[string.lower(fishName)]
    if not fishId then
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

    if not IsRarityAllowed(fishId) then return end

    local dedupKey = playerName .. fishName .. tostring(math.floor(os.time() / 2))
    if ChatSentDedup[dedupKey] then return end
    ChatSentDedup[dedupKey] = true

    task.defer(function()
        task.wait(10)
        ChatSentDedup[dedupKey] = nil
    end)

    local weight = tonumber(weightStr) or 0

    Settings.LogCount = Settings.LogCount + 1
    warn("[Vechnost] Notifier via CHAT:", playerName, "caught", FishDB[fishId].Name, "(", weight, "kg)")

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

    if not item then
        warn("[Vechnost] No InventoryItem found in event data")
        return
    end

    if not item.Id or not item.UUID then
        warn("[Vechnost] Item missing Id or UUID")
        return
    end

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
    warn("[Vechnost] Fish caught! Player:", playerName, "Fish:", FishDB[item.Id].Name, "Count:", Settings.LogCount)

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

    if not net or not ObtainedNewFish then
        return false, "ERROR: Game remotes not found!"
    end

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
            warn("[Vechnost] Chat monitor (TextChatService) active")
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
                warn("[Vechnost] Chat monitor (StarterGui) active")
            end
        end)
    end

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

    if Settings.ServerWide then
        pcall(function()
            local function ScanNotificationText(textObj)
                if not textObj or not textObj:IsA("TextLabel") then return end
                local text = textObj.Text or ""
                if text == "" then return end

                for fishId, fishData in pairs(FishDB) do
                    if fishData.Name and string.find(text, fishData.Name) then
                        local playerName = "Unknown"

                        for _, player in pairs(Players:GetPlayers()) do
                            if player ~= LocalPlayer and string.find(text, player.Name) then
                                playerName = player.Name
                                break
                            elseif player ~= LocalPlayer and string.find(text, player.DisplayName) then
                                playerName = player.DisplayName
                                break
                            end
                        end

                        if playerName == LocalPlayer.Name or playerName == LocalPlayer.DisplayName then
                            return
                        end
                        if string.find(text, LocalPlayer.Name) or string.find(text, LocalPlayer.DisplayName) then
                            return
                        end

                        if playerName == "Unknown" then return end

                        local dedupKey = "GUI_" .. text .. "_" .. os.time()
                        if Settings.SentUUID[dedupKey] then return end
                        Settings.SentUUID[dedupKey] = true

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

        pcall(function()
            local Replion = require(ReplicatedStorage.Packages.Replion)

            local stateNames = {"ServerFeed", "GlobalNotifications", "RecentCatches", "FishLog", "ServerNotifications", "Feed"}
            for _, stateName in ipairs(stateNames) do
                task.spawn(function()
                    local found = false
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
    end

    task.spawn(function()
        local mode = Settings.ServerWide and "Server Notifier" or "Local Only"
        SendWebhook(BuildActivationPayload(LocalPlayer.Name, mode))
    end)

    warn("[Vechnost] Webhook Logger ENABLED | Mode:", Settings.ServerWide and "Server-Notifier" or "Local")
    return true, "Webhook Logger aktif!"
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
-- BAGIAN 11: TRADING SYSTEM
-- =====================================================
local TradeState = {
    TargetPlayer = nil,
    PlayerList = {},
    Inventory = {},
    StoneInventory = {},
    ByName = {
        Active = false,
        ItemName = nil,
        Amount = 1,
        Sent = 0,
    },
    ByCoin = {
        Active = false,
        TargetCoins = 0,
        Sent = 0,
    },
    ByRarity = {
        Active = false,
        Rarity = nil,
        RarityTier = nil,
        Amount = 1,
        Sent = 0,
    },
    ByStone = {
        Active = false,
        StoneName = nil,
        Amount = 1,
        Sent = 0,
    },
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

    if next(TradeState.Inventory) == nil then
        pcall(function()
            local Items = ReplicatedStorage:WaitForChild("Items", 5)
            if not Items then return end
            for fishId, fishData in pairs(FishDB) do
                TradeState.Inventory[fishData.Name] = TradeState.Inventory[fishData.Name] or 0
            end
        end)
    end

    warn("[Vechnost] Inventory loaded")
end

local function GetInventoryItemNames()
    local names = {}
    for name, _ in pairs(TradeState.Inventory) do
        table.insert(names, name)
    end
    table.sort(names)
    if #names == 0 then names = {"(Inventory kosong)"}  end
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
        local candidates = {
            "RE/TradeRequest", "RE/SendTrade", "RE/InitiateTrade",
            "RE/Trade", "TradeRequest", "SendTrade",
        }
        for _, name in ipairs(candidates) do
            local r = net:FindFirstChild(name)
            if r and r:IsA("RemoteEvent") then
                TradeRemote = r
                warn("[Vechnost] Trade remote found:", name)
                return
            end
        end

        for _, child in pairs(net:GetDescendants()) do
            if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
                if string.lower(child.Name):find("trade") then
                    TradeRemote = child
                    warn("[Vechnost] Trade remote found (scan):", child.Name)
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

    if not targetPlayer then
        warn("[Vechnost] Target player not found:", targetUsername)
        return false
    end

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

        if not ok then
            pcall(function()
                local re = net:FindFirstChild("RE/TradeItem") or net:FindFirstChild("RE/GiveItem")
                if re then
                    re:FireServer(targetPlayer, fishId or itemName, quantity)
                    ok = true
                end
            end)
        end
    end)

    return ok
end

-- =====================================================
-- BAGIAN 12: CUSTOM UI LIBRARY - DARK BLUE SIDEBAR DESIGN
-- =====================================================

-- UI Color Scheme (sesuai foto)
local Colors = {
    Background = Color3.fromRGB(15, 17, 26),
    Sidebar = Color3.fromRGB(20, 24, 38),
    SidebarItem = Color3.fromRGB(25, 30, 48),
    SidebarItemHover = Color3.fromRGB(35, 42, 68),
    SidebarItemActive = Color3.fromRGB(40, 50, 85),
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
}

-- Tab Icons (menggunakan text icons karena Roblox limitations)
local TabIcons = {
    Info = "👤",
    Fishing = "🎣",
    Teleport = "📍",
    Webhook = "🔔",
    Setting = "⚙️",
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
MainFrame.Size = UDim2.new(0, 650, 0, 420)
MainFrame.Position = UDim2.new(0.5, -325, 0.5, -210)
MainFrame.BackgroundColor3 = Colors.Background
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 12)
MainCorner.Parent = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Colors.Border
MainStroke.Thickness = 1
MainStroke.Parent = MainFrame

-- Title Bar
local TitleBar = Instance.new("Frame")
TitleBar.Name = "TitleBar"
TitleBar.Size = UDim2.new(1, 0, 0, 45)
TitleBar.BackgroundColor3 = Colors.Sidebar
TitleBar.BorderSizePixel = 0
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 12)
TitleCorner.Parent = TitleBar

local TitleFix = Instance.new("Frame")
TitleFix.Name = "TitleFix"
TitleFix.Size = UDim2.new(1, 0, 0, 15)
TitleFix.Position = UDim2.new(0, 0, 1, -15)
TitleFix.BackgroundColor3 = Colors.Sidebar
TitleFix.BorderSizePixel = 0
TitleFix.Parent = TitleBar

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Name = "Title"
TitleLabel.Size = UDim2.new(1, -100, 1, 0)
TitleLabel.Position = UDim2.new(0, 15, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "Vechnost"
TitleLabel.TextColor3 = Colors.Text
TitleLabel.TextSize = 18
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = TitleBar

-- Close Button
local CloseBtn = Instance.new("TextButton")
CloseBtn.Name = "CloseBtn"
CloseBtn.Size = UDim2.new(0, 30, 0, 30)
CloseBtn.Position = UDim2.new(1, -40, 0.5, -15)
CloseBtn.BackgroundColor3 = Colors.ContentItem
CloseBtn.BorderSizePixel = 0
CloseBtn.Text = "×"
CloseBtn.TextColor3 = Colors.Text
CloseBtn.TextSize = 20
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.Parent = TitleBar

local CloseBtnCorner = Instance.new("UICorner")
CloseBtnCorner.CornerRadius = UDim.new(0, 6)
CloseBtnCorner.Parent = CloseBtn

-- Minimize Button
local MinBtn = Instance.new("TextButton")
MinBtn.Name = "MinBtn"
MinBtn.Size = UDim2.new(0, 30, 0, 30)
MinBtn.Position = UDim2.new(1, -75, 0.5, -15)
MinBtn.BackgroundColor3 = Colors.ContentItem
MinBtn.BorderSizePixel = 0
MinBtn.Text = "—"
MinBtn.TextColor3 = Colors.Text
MinBtn.TextSize = 16
MinBtn.Font = Enum.Font.GothamBold
MinBtn.Parent = TitleBar

local MinBtnCorner = Instance.new("UICorner")
MinBtnCorner.CornerRadius = UDim.new(0, 6)
MinBtnCorner.Parent = MinBtn

-- Sidebar
local Sidebar = Instance.new("Frame")
Sidebar.Name = "Sidebar"
Sidebar.Size = UDim2.new(0, 160, 1, -50)
Sidebar.Position = UDim2.new(0, 5, 0, 50)
Sidebar.BackgroundColor3 = Colors.Sidebar
Sidebar.BorderSizePixel = 0
Sidebar.Parent = MainFrame

local SidebarCorner = Instance.new("UICorner")
SidebarCorner.CornerRadius = UDim.new(0, 10)
SidebarCorner.Parent = Sidebar

local SidebarPadding = Instance.new("UIPadding")
SidebarPadding.PaddingTop = UDim.new(0, 8)
SidebarPadding.PaddingBottom = UDim.new(0, 8)
SidebarPadding.PaddingLeft = UDim.new(0, 8)
SidebarPadding.PaddingRight = UDim.new(0, 8)
SidebarPadding.Parent = Sidebar

local SidebarLayout = Instance.new("UIListLayout")
SidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder
SidebarLayout.Padding = UDim.new(0, 5)
SidebarLayout.Parent = Sidebar

-- Content Area
local ContentArea = Instance.new("Frame")
ContentArea.Name = "ContentArea"
ContentArea.Size = UDim2.new(1, -180, 1, -55)
ContentArea.Position = UDim2.new(0, 175, 0, 50)
ContentArea.BackgroundColor3 = Colors.Content
ContentArea.BorderSizePixel = 0
ContentArea.Parent = MainFrame

local ContentCorner = Instance.new("UICorner")
ContentCorner.CornerRadius = UDim.new(0, 10)
ContentCorner.Parent = ContentArea

-- Tab Content Containers
local TabContents = {}
local TabButtons = {}
local CurrentTab = nil

-- Tabs Definition
local Tabs = {
    {Name = "Info", Icon = "👤", LayoutOrder = 1},
    {Name = "Fishing", Icon = "🎣", LayoutOrder = 2},
    {Name = "Teleport", Icon = "📍", LayoutOrder = 3},
    {Name = "Webhook", Icon = "🔔", LayoutOrder = 4},
    {Name = "Setting", Icon = "⚙️", LayoutOrder = 5},
}

-- Create Tab Button Function
local function CreateTabButton(tabData)
    local TabBtn = Instance.new("TextButton")
    TabBtn.Name = tabData.Name .. "Tab"
    TabBtn.Size = UDim2.new(1, 0, 0, 42)
    TabBtn.BackgroundColor3 = Colors.SidebarItem
    TabBtn.BorderSizePixel = 0
    TabBtn.Text = ""
    TabBtn.AutoButtonColor = false
    TabBtn.LayoutOrder = tabData.LayoutOrder
    TabBtn.Parent = Sidebar

    local TabBtnCorner = Instance.new("UICorner")
    TabBtnCorner.CornerRadius = UDim.new(0, 8)
    TabBtnCorner.Parent = TabBtn

    local IconLabel = Instance.new("TextLabel")
    IconLabel.Name = "Icon"
    IconLabel.Size = UDim2.new(0, 30, 1, 0)
    IconLabel.Position = UDim2.new(0, 10, 0, 0)
    IconLabel.BackgroundTransparency = 1
    IconLabel.Text = tabData.Icon
    IconLabel.TextColor3 = Colors.Accent
    IconLabel.TextSize = 18
    IconLabel.Font = Enum.Font.GothamBold
    IconLabel.Parent = TabBtn

    local TextLabel = Instance.new("TextLabel")
    TextLabel.Name = "Text"
    TextLabel.Size = UDim2.new(1, -50, 1, 0)
    TextLabel.Position = UDim2.new(0, 45, 0, 0)
    TextLabel.BackgroundTransparency = 1
    TextLabel.Text = tabData.Name
    TextLabel.TextColor3 = Colors.Text
    TextLabel.TextSize = 14
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

-- Create Tab Content Function
local function CreateTabContent(tabName)
    local Content = Instance.new("ScrollingFrame")
    Content.Name = tabName .. "Content"
    Content.Size = UDim2.new(1, -20, 1, -20)
    Content.Position = UDim2.new(0, 10, 0, 10)
    Content.BackgroundTransparency = 1
    Content.BorderSizePixel = 0
    Content.ScrollBarThickness = 4
    Content.ScrollBarImageColor3 = Colors.Accent
    Content.CanvasSize = UDim2.new(0, 0, 0, 0)
    Content.AutomaticCanvasSize = Enum.AutomaticSize.Y
    Content.Visible = false
    Content.Parent = ContentArea

    local ContentLayout = Instance.new("UIListLayout")
    ContentLayout.SortOrder = Enum.SortOrder.LayoutOrder
    ContentLayout.Padding = UDim.new(0, 8)
    ContentLayout.Parent = Content

    local ContentPadding = Instance.new("UIPadding")
    ContentPadding.PaddingTop = UDim.new(0, 5)
    ContentPadding.PaddingBottom = UDim.new(0, 5)
    ContentPadding.Parent = Content

    return Content
end

-- Switch Tab Function
local function SwitchTab(tabName)
    if CurrentTab == tabName then return end

    for name, content in pairs(TabContents) do
        content.Visible = (name == tabName)
    end

    for name, btn in pairs(TabButtons) do
        if name == tabName then
            TweenService:Create(btn, TweenInfo.new(0.2), {BackgroundColor3 = Colors.SidebarItemActive}):Play()
        else
            TweenService:Create(btn, TweenInfo.new(0.2), {BackgroundColor3 = Colors.SidebarItem}):Play()
        end
    end

    CurrentTab = tabName
end

-- Create All Tabs
for _, tabData in ipairs(Tabs) do
    local btn = CreateTabButton(tabData)
    TabButtons[tabData.Name] = btn
    TabContents[tabData.Name] = CreateTabContent(tabData.Name)

    btn.MouseButton1Click:Connect(function()
        SwitchTab(tabData.Name)
    end)
end

-- =====================================================
-- BAGIAN 13: UI COMPONENT CREATORS
-- =====================================================

local LayoutOrderCounter = {}

local function GetLayoutOrder(tabName)
    LayoutOrderCounter[tabName] = (LayoutOrderCounter[tabName] or 0) + 1
    return LayoutOrderCounter[tabName]
end

-- Section Creator
local function CreateSection(tabName, sectionTitle)
    local parent = TabContents[tabName]
    if not parent then return end

    local Section = Instance.new("Frame")
    Section.Name = "Section_" .. sectionTitle
    Section.Size = UDim2.new(1, 0, 0, 30)
    Section.BackgroundTransparency = 1
    Section.LayoutOrder = GetLayoutOrder(tabName)
    Section.Parent = parent

    local SectionLabel = Instance.new("TextLabel")
    SectionLabel.Size = UDim2.new(1, 0, 1, 0)
    SectionLabel.BackgroundTransparency = 1
    SectionLabel.Text = sectionTitle
    SectionLabel.TextColor3 = Colors.Accent
    SectionLabel.TextSize = 16
    SectionLabel.Font = Enum.Font.GothamBold
    SectionLabel.TextXAlignment = Enum.TextXAlignment.Left
    SectionLabel.Parent = Section

    return Section
end

-- Paragraph Creator
local function CreateParagraph(tabName, title, content)
    local parent = TabContents[tabName]
    if not parent then return end

    local Paragraph = Instance.new("Frame")
    Paragraph.Name = "Paragraph_" .. title
    Paragraph.Size = UDim2.new(1, 0, 0, 60)
    Paragraph.BackgroundColor3 = Colors.ContentItem
    Paragraph.BorderSizePixel = 0
    Paragraph.LayoutOrder = GetLayoutOrder(tabName)
    Paragraph.Parent = parent

    local ParagraphCorner = Instance.new("UICorner")
    ParagraphCorner.CornerRadius = UDim.new(0, 8)
    ParagraphCorner.Parent = Paragraph

    local TitleLabel = Instance.new("TextLabel")
    TitleLabel.Name = "Title"
    TitleLabel.Size = UDim2.new(1, -20, 0, 22)
    TitleLabel.Position = UDim2.new(0, 10, 0, 8)
    TitleLabel.BackgroundTransparency = 1
    TitleLabel.Text = title
    TitleLabel.TextColor3 = Colors.Text
    TitleLabel.TextSize = 14
    TitleLabel.Font = Enum.Font.GothamBold
    TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
    TitleLabel.Parent = Paragraph

    local ContentLabel = Instance.new("TextLabel")
    ContentLabel.Name = "Content"
    ContentLabel.Size = UDim2.new(1, -20, 0, 25)
    ContentLabel.Position = UDim2.new(0, 10, 0, 28)
    ContentLabel.BackgroundTransparency = 1
    ContentLabel.Text = content
    ContentLabel.TextColor3 = Colors.TextDim
    ContentLabel.TextSize = 12
    ContentLabel.Font = Enum.Font.Gotham
    ContentLabel.TextXAlignment = Enum.TextXAlignment.Left
    ContentLabel.TextWrapped = true
    ContentLabel.Parent = Paragraph

    local function UpdateParagraph(newTitle, newContent)
        TitleLabel.Text = newTitle or TitleLabel.Text
        ContentLabel.Text = newContent or ContentLabel.Text
    end

    return {
        Frame = Paragraph,
        Set = function(self, data)
            UpdateParagraph(data.Title, data.Content)
        end
    }
end

-- Input Creator
local function CreateInput(tabName, name, placeholder, callback)
    local parent = TabContents[tabName]
    if not parent then return end

    local InputFrame = Instance.new("Frame")
    InputFrame.Name = "Input_" .. name
    InputFrame.Size = UDim2.new(1, 0, 0, 65)
    InputFrame.BackgroundColor3 = Colors.ContentItem
    InputFrame.BorderSizePixel = 0
    InputFrame.LayoutOrder = GetLayoutOrder(tabName)
    InputFrame.Parent = parent

    local InputCorner = Instance.new("UICorner")
    InputCorner.CornerRadius = UDim.new(0, 8)
    InputCorner.Parent = InputFrame

    local InputLabel = Instance.new("TextLabel")
    InputLabel.Name = "Label"
    InputLabel.Size = UDim2.new(1, -20, 0, 22)
    InputLabel.Position = UDim2.new(0, 10, 0, 8)
    InputLabel.BackgroundTransparency = 1
    InputLabel.Text = name
    InputLabel.TextColor3 = Colors.Text
    InputLabel.TextSize = 13
    InputLabel.Font = Enum.Font.GothamSemibold
    InputLabel.TextXAlignment = Enum.TextXAlignment.Left
    InputLabel.Parent = InputFrame

    local TextBox = Instance.new("TextBox")
    TextBox.Name = "TextBox"
    TextBox.Size = UDim2.new(1, -20, 0, 28)
    TextBox.Position = UDim2.new(0, 10, 0, 30)
    TextBox.BackgroundColor3 = Colors.Background
    TextBox.BorderSizePixel = 0
    TextBox.Text = ""
    TextBox.PlaceholderText = placeholder or ""
    TextBox.PlaceholderColor3 = Colors.TextMuted
    TextBox.TextColor3 = Colors.Text
    TextBox.TextSize = 12
    TextBox.Font = Enum.Font.Gotham
    TextBox.ClearTextOnFocus = false
    TextBox.Parent = InputFrame

    local TextBoxCorner = Instance.new("UICorner")
    TextBoxCorner.CornerRadius = UDim.new(0, 6)
    TextBoxCorner.Parent = TextBox

    local TextBoxPadding = Instance.new("UIPadding")
    TextBoxPadding.PaddingLeft = UDim.new(0, 10)
    TextBoxPadding.PaddingRight = UDim.new(0, 10)
    TextBoxPadding.Parent = TextBox

    TextBox.FocusLost:Connect(function()
        if callback then
            callback(TextBox.Text)
        end
    end)

    return {
        Frame = InputFrame,
        TextBox = TextBox,
        GetValue = function()
            return TextBox.Text
        end,
        SetValue = function(self, value)
            TextBox.Text = value
        end
    }
end

-- Button Creator
local function CreateButton(tabName, name, callback)
    local parent = TabContents[tabName]
    if not parent then return end

    local Button = Instance.new("TextButton")
    Button.Name = "Button_" .. name
    Button.Size = UDim2.new(1, 0, 0, 38)
    Button.BackgroundColor3 = Colors.Accent
    Button.BorderSizePixel = 0
    Button.Text = name
    Button.TextColor3 = Colors.Text
    Button.TextSize = 13
    Button.Font = Enum.Font.GothamSemibold
    Button.AutoButtonColor = false
    Button.LayoutOrder = GetLayoutOrder(tabName)
    Button.Parent = parent

    local ButtonCorner = Instance.new("UICorner")
    ButtonCorner.CornerRadius = UDim.new(0, 8)
    ButtonCorner.Parent = Button

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

-- Toggle Creator
local function CreateToggle(tabName, name, default, callback)
    local parent = TabContents[tabName]
    if not parent then return end

    local ToggleState = default or false

    local ToggleFrame = Instance.new("Frame")
    ToggleFrame.Name = "Toggle_" .. name
    ToggleFrame.Size = UDim2.new(1, 0, 0, 45)
    ToggleFrame.BackgroundColor3 = Colors.ContentItem
    ToggleFrame.BorderSizePixel = 0
    ToggleFrame.LayoutOrder = GetLayoutOrder(tabName)
    ToggleFrame.Parent = parent

    local ToggleCorner = Instance.new("UICorner")
    ToggleCorner.CornerRadius = UDim.new(0, 8)
    ToggleCorner.Parent = ToggleFrame

    local ToggleLabel = Instance.new("TextLabel")
    ToggleLabel.Name = "Label"
    ToggleLabel.Size = UDim2.new(1, -70, 1, 0)
    ToggleLabel.Position = UDim2.new(0, 12, 0, 0)
    ToggleLabel.BackgroundTransparency = 1
    ToggleLabel.Text = name
    ToggleLabel.TextColor3 = Colors.Text
    ToggleLabel.TextSize = 13
    ToggleLabel.Font = Enum.Font.GothamSemibold
    ToggleLabel.TextXAlignment = Enum.TextXAlignment.Left
    ToggleLabel.Parent = ToggleFrame

    local ToggleButton = Instance.new("TextButton")
    ToggleButton.Name = "Toggle"
    ToggleButton.Size = UDim2.new(0, 50, 0, 26)
    ToggleButton.Position = UDim2.new(1, -60, 0.5, -13)
    ToggleButton.BackgroundColor3 = ToggleState and Colors.Toggle or Colors.ToggleOff
    ToggleButton.BorderSizePixel = 0
    ToggleButton.Text = ""
    ToggleButton.AutoButtonColor = false
    ToggleButton.Parent = ToggleFrame

    local ToggleButtonCorner = Instance.new("UICorner")
    ToggleButtonCorner.CornerRadius = UDim.new(1, 0)
    ToggleButtonCorner.Parent = ToggleButton

    local ToggleCircle = Instance.new("Frame")
    ToggleCircle.Name = "Circle"
    ToggleCircle.Size = UDim2.new(0, 20, 0, 20)
    ToggleCircle.Position = ToggleState and UDim2.new(1, -23, 0.5, -10) or UDim2.new(0, 3, 0.5, -10)
    ToggleCircle.BackgroundColor3 = Colors.Text
    ToggleCircle.BorderSizePixel = 0
    ToggleCircle.Parent = ToggleButton

    local ToggleCircleCorner = Instance.new("UICorner")
    ToggleCircleCorner.CornerRadius = UDim.new(1, 0)
    ToggleCircleCorner.Parent = ToggleCircle

    local function UpdateToggle()
        local targetPos = ToggleState and UDim2.new(1, -23, 0.5, -10) or UDim2.new(0, 3, 0.5, -10)
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
        GetValue = function()
            return ToggleState
        end
    }
end

-- Dropdown Creator
local function CreateDropdown(tabName, name, options, default, multiSelect, callback)
    local parent = TabContents[tabName]
    if not parent then return end

    local SelectedOptions = {}
    if default then
        if type(default) == "table" then
            for _, v in ipairs(default) do
                SelectedOptions[v] = true
            end
        else
            SelectedOptions[default] = true
        end
    end

    local IsOpen = false

    local DropdownFrame = Instance.new("Frame")
    DropdownFrame.Name = "Dropdown_" .. name
    DropdownFrame.Size = UDim2.new(1, 0, 0, 65)
    DropdownFrame.BackgroundColor3 = Colors.ContentItem
    DropdownFrame.BorderSizePixel = 0
    DropdownFrame.ClipsDescendants = true
    DropdownFrame.LayoutOrder = GetLayoutOrder(tabName)
    DropdownFrame.Parent = parent

    local DropdownCorner = Instance.new("UICorner")
    DropdownCorner.CornerRadius = UDim.new(0, 8)
    DropdownCorner.Parent = DropdownFrame

    local DropdownLabel = Instance.new("TextLabel")
    DropdownLabel.Name = "Label"
    DropdownLabel.Size = UDim2.new(1, -20, 0, 22)
    DropdownLabel.Position = UDim2.new(0, 10, 0, 8)
    DropdownLabel.BackgroundTransparency = 1
    DropdownLabel.Text = name
    DropdownLabel.TextColor3 = Colors.Text
    DropdownLabel.TextSize = 13
    DropdownLabel.Font = Enum.Font.GothamSemibold
    DropdownLabel.TextXAlignment = Enum.TextXAlignment.Left
    DropdownLabel.Parent = DropdownFrame

    local DropdownButton = Instance.new("TextButton")
    DropdownButton.Name = "Button"
    DropdownButton.Size = UDim2.new(1, -20, 0, 28)
    DropdownButton.Position = UDim2.new(0, 10, 0, 30)
    DropdownButton.BackgroundColor3 = Colors.Background
    DropdownButton.BorderSizePixel = 0
    DropdownButton.Text = ""
    DropdownButton.AutoButtonColor = false
    DropdownButton.Parent = DropdownFrame

    local DropdownButtonCorner = Instance.new("UICorner")
    DropdownButtonCorner.CornerRadius = UDim.new(0, 6)
    DropdownButtonCorner.Parent = DropdownButton

    local SelectedLabel = Instance.new("TextLabel")
    SelectedLabel.Name = "Selected"
    SelectedLabel.Size = UDim2.new(1, -30, 1, 0)
    SelectedLabel.Position = UDim2.new(0, 10, 0, 0)
    SelectedLabel.BackgroundTransparency = 1
    SelectedLabel.Text = "Select..."
    SelectedLabel.TextColor3 = Colors.TextDim
    SelectedLabel.TextSize = 12
    SelectedLabel.Font = Enum.Font.Gotham
    SelectedLabel.TextXAlignment = Enum.TextXAlignment.Left
    SelectedLabel.TextTruncate = Enum.TextTruncate.AtEnd
    SelectedLabel.Parent = DropdownButton

    local ArrowLabel = Instance.new("TextLabel")
    ArrowLabel.Name = "Arrow"
    ArrowLabel.Size = UDim2.new(0, 20, 1, 0)
    ArrowLabel.Position = UDim2.new(1, -25, 0, 0)
    ArrowLabel.BackgroundTransparency = 1
    ArrowLabel.Text = "▼"
    ArrowLabel.TextColor3 = Colors.TextMuted
    ArrowLabel.TextSize = 10
    ArrowLabel.Font = Enum.Font.Gotham
    ArrowLabel.Parent = DropdownButton

    local OptionsFrame = Instance.new("Frame")
    OptionsFrame.Name = "Options"
    OptionsFrame.Size = UDim2.new(1, -20, 0, 0)
    OptionsFrame.Position = UDim2.new(0, 10, 0, 62)
    OptionsFrame.BackgroundColor3 = Colors.Background
    OptionsFrame.BorderSizePixel = 0
    OptionsFrame.ClipsDescendants = true
    OptionsFrame.Parent = DropdownFrame

    local OptionsCorner = Instance.new("UICorner")
    OptionsCorner.CornerRadius = UDim.new(0, 6)
    OptionsCorner.Parent = OptionsFrame

    local OptionsLayout = Instance.new("UIListLayout")
    OptionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    OptionsLayout.Padding = UDim.new(0, 2)
    OptionsLayout.Parent = OptionsFrame

    local OptionsPadding = Instance.new("UIPadding")
    OptionsPadding.PaddingTop = UDim.new(0, 4)
    OptionsPadding.PaddingBottom = UDim.new(0, 4)
    OptionsPadding.PaddingLeft = UDim.new(0, 4)
    OptionsPadding.PaddingRight = UDim.new(0, 4)
    OptionsPadding.Parent = OptionsFrame

    local OptionButtons = {}

    local function UpdateSelectedText()
        local selected = {}
        for opt, _ in pairs(SelectedOptions) do
            table.insert(selected, opt)
        end
        if #selected == 0 then
            SelectedLabel.Text = "Select..."
            SelectedLabel.TextColor3 = Colors.TextMuted
        else
            SelectedLabel.Text = table.concat(selected, ", ")
            SelectedLabel.TextColor3 = Colors.Text
        end
    end

    local function CreateOptionButton(optionName)
        local OptBtn = Instance.new("TextButton")
        OptBtn.Name = optionName
        OptBtn.Size = UDim2.new(1, 0, 0, 26)
        OptBtn.BackgroundColor3 = SelectedOptions[optionName] and Colors.Accent or Colors.ContentItem
        OptBtn.BorderSizePixel = 0
        OptBtn.Text = optionName
        OptBtn.TextColor3 = Colors.Text
        OptBtn.TextSize = 12
        OptBtn.Font = Enum.Font.Gotham
        OptBtn.AutoButtonColor = false
        OptBtn.Parent = OptionsFrame

        local OptBtnCorner = Instance.new("UICorner")
        OptBtnCorner.CornerRadius = UDim.new(0, 4)
        OptBtnCorner.Parent = OptBtn

        OptBtn.MouseEnter:Connect(function()
            if not SelectedOptions[optionName] then
                TweenService:Create(OptBtn, TweenInfo.new(0.15), {BackgroundColor3 = Colors.ContentItemHover}):Play()
            end
        end)

        OptBtn.MouseLeave:Connect(function()
            if not SelectedOptions[optionName] then
                TweenService:Create(OptBtn, TweenInfo.new(0.15), {BackgroundColor3 = Colors.ContentItem}):Play()
            end
        end)

        OptBtn.MouseButton1Click:Connect(function()
            if multiSelect then
                SelectedOptions[optionName] = not SelectedOptions[optionName]
                TweenService:Create(OptBtn, TweenInfo.new(0.15), {
                    BackgroundColor3 = SelectedOptions[optionName] and Colors.Accent or Colors.ContentItem
                }):Play()
            else
                for opt, _ in pairs(SelectedOptions) do
                    SelectedOptions[opt] = nil
                    if OptionButtons[opt] then
                        TweenService:Create(OptionButtons[opt], TweenInfo.new(0.15), {BackgroundColor3 = Colors.ContentItem}):Play()
                    end
                end
                SelectedOptions[optionName] = true
                TweenService:Create(OptBtn, TweenInfo.new(0.15), {BackgroundColor3 = Colors.Accent}):Play()
            end

            UpdateSelectedText()

            if callback then
                local selected = {}
                for opt, _ in pairs(SelectedOptions) do
                    table.insert(selected, opt)
                end
                callback(selected)
            end
        end)

        OptionButtons[optionName] = OptBtn
        return OptBtn
    end

    local function PopulateOptions()
        for _, child in pairs(OptionsFrame:GetChildren()) do
            if child:IsA("TextButton") then
                child:Destroy()
            end
        end
        OptionButtons = {}

        for _, opt in ipairs(options) do
            CreateOptionButton(opt)
        end
    end

    PopulateOptions()
    UpdateSelectedText()

    local function ToggleDropdown()
        IsOpen = not IsOpen
        local optionsHeight = math.min(#options * 28 + 10, 150)

        TweenService:Create(DropdownFrame, TweenInfo.new(0.25), {
            Size = UDim2.new(1, 0, 0, IsOpen and (65 + optionsHeight) or 65)
        }):Play()

        TweenService:Create(OptionsFrame, TweenInfo.new(0.25), {
            Size = UDim2.new(1, -20, 0, IsOpen and optionsHeight or 0)
        }):Play()

        TweenService:Create(ArrowLabel, TweenInfo.new(0.25), {
            Rotation = IsOpen and 180 or 0
        }):Play()
    end

    DropdownButton.MouseButton1Click:Connect(ToggleDropdown)

    return {
        Frame = DropdownFrame,
        Refresh = function(self, newOptions, keepSelected)
            options = newOptions
            if not keepSelected then
                SelectedOptions = {}
            end
            PopulateOptions()
            UpdateSelectedText()
        end,
        SetValue = function(self, values)
            SelectedOptions = {}
            if type(values) == "table" then
                for _, v in ipairs(values) do
                    SelectedOptions[v] = true
                end
            else
                SelectedOptions[values] = true
            end
            for opt, btn in pairs(OptionButtons) do
                btn.BackgroundColor3 = SelectedOptions[opt] and Colors.Accent or Colors.ContentItem
            end
            UpdateSelectedText()
        end,
        GetValue = function()
            local selected = {}
            for opt, _ in pairs(SelectedOptions) do
                table.insert(selected, opt)
            end
            return selected
        end
    }
end

-- =====================================================
-- BAGIAN 14: NOTIFICATION SYSTEM
-- =====================================================

local NotificationContainer = Instance.new("Frame")
NotificationContainer.Name = "Notifications"
NotificationContainer.Size = UDim2.new(0, 280, 1, 0)
NotificationContainer.Position = UDim2.new(1, -290, 0, 0)
NotificationContainer.BackgroundTransparency = 1
NotificationContainer.Parent = ScreenGui

local NotificationLayout = Instance.new("UIListLayout")
NotificationLayout.SortOrder = Enum.SortOrder.LayoutOrder
NotificationLayout.Padding = UDim.new(0, 8)
NotificationLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
NotificationLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
NotificationLayout.Parent = NotificationContainer

local NotificationPadding = Instance.new("UIPadding")
NotificationPadding.PaddingBottom = UDim.new(0, 20)
NotificationPadding.PaddingRight = UDim.new(0, 10)
NotificationPadding.Parent = NotificationContainer

local function Notify(title, content, duration)
    duration = duration or 3

    local Notification = Instance.new("Frame")
    Notification.Name = "Notification"
    Notification.Size = UDim2.new(0, 260, 0, 70)
    Notification.BackgroundColor3 = Colors.Sidebar
    Notification.BorderSizePixel = 0
    Notification.BackgroundTransparency = 1
    Notification.Parent = NotificationContainer

    local NotifCorner = Instance.new("UICorner")
    NotifCorner.CornerRadius = UDim.new(0, 10)
    NotifCorner.Parent = Notification

    local NotifStroke = Instance.new("UIStroke")
    NotifStroke.Color = Colors.Accent
    NotifStroke.Thickness = 1
    NotifStroke.Transparency = 1
    NotifStroke.Parent = Notification

    local NotifTitle = Instance.new("TextLabel")
    NotifTitle.Name = "Title"
    NotifTitle.Size = UDim2.new(1, -20, 0, 22)
    NotifTitle.Position = UDim2.new(0, 10, 0, 10)
    NotifTitle.BackgroundTransparency = 1
    NotifTitle.Text = title
    NotifTitle.TextColor3 = Colors.Accent
    NotifTitle.TextSize = 14
    NotifTitle.Font = Enum.Font.GothamBold
    NotifTitle.TextXAlignment = Enum.TextXAlignment.Left
    NotifTitle.Parent = Notification

    local NotifContent = Instance.new("TextLabel")
    NotifContent.Name = "Content"
    NotifContent.Size = UDim2.new(1, -20, 0, 30)
    NotifContent.Position = UDim2.new(0, 10, 0, 32)
    NotifContent.BackgroundTransparency = 1
    NotifContent.Text = content
    NotifContent.TextColor3 = Colors.TextDim
    NotifContent.TextSize = 12
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
-- BAGIAN 15: POPULATE TAB CONTENTS
-- =====================================================

-- ===== INFO TAB =====
CreateSection("Info", "Player Information")

local InfoPlayerName = CreateParagraph("Info", "Player", LocalPlayer.Name)

local InfoStats = CreateParagraph("Info", "Statistics", "Loading...")

task.spawn(function()
    while task.wait(3) do
        local stats = GetPlayerStats()
        InfoStats:Set({
            Title = "Statistics",
            Content = string.format("Coins: %s | Fish Caught: %s | Backpack: %d/%d",
                FormatNumber(stats.Coins),
                FormatNumber(stats.TotalCaught),
                stats.BackpackCount,
                stats.BackpackMax
            )
        })
    end
end)

CreateSection("Info", "About")

CreateParagraph("Info", "Vechnost v2.0.0", "Server-Wide Fish Webhook Logger + Auto Trading System\nby Vechnost Team")

-- ===== FISHING TAB =====
CreateSection("Fishing", "Auto Fishing")

CreateParagraph("Fishing", "Coming Soon", "Auto Fishing features akan segera hadir!")

-- ===== TELEPORT TAB =====
CreateSection("Teleport", "Locations")

CreateParagraph("Teleport", "Coming Soon", "Teleport features akan segera hadir!")

-- ===== WEBHOOK TAB =====
CreateSection("Webhook", "Rarity Filter")

local WebhookRarityDropdown = CreateDropdown("Webhook", "Filter by Rarity", RarityList, {}, true, function(selected)
    Settings.SelectedRarities = {}
    for _, value in ipairs(selected) do
        local tier = RARITY_NAME_TO_TIER[value]
        if tier then Settings.SelectedRarities[tier] = true end
    end

    if next(Settings.SelectedRarities) == nil then
        Notify("Vechnost", "Filter: Semua rarity", 2)
    else
        Notify("Vechnost", "Filter rarity diperbarui", 2)
    end
end)

CreateSection("Webhook", "Setup Webhook")

local WebhookUrlBuffer = ""

local WebhookUrlInput = CreateInput("Webhook", "Discord Webhook URL", "https://discord.com/api/webhooks/...", function(text)
    WebhookUrlBuffer = text
end)

CreateButton("Webhook", "Save Webhook URL", function()
    local url = WebhookUrlBuffer:gsub("%s+", "")

    if not url:match("^https://discord.com/api/webhooks/")
    and not url:match("^https://canary.discord.com/api/webhooks/") then
        Notify("Vechnost", "URL webhook tidak valid!", 3)
        return
    end

    Settings.Url = url
    Notify("Vechnost", "Webhook URL saved!", 2)
end)

CreateSection("Webhook", "Logger Mode")

local ServerModeToggle = CreateToggle("Webhook", "Server-Notifier Mode", true, function(value)
    Settings.ServerWide = value
    Notify("Vechnost", value and "Mode: Seluruh Server" or "Mode: Hanya Lokal", 2)
end)

CreateSection("Webhook", "Control")

local WebhookEnabledToggle = CreateToggle("Webhook", "Enable Webhook Logger", false, function(value)
    if value then
        if Settings.Url == "" then
            Notify("Vechnost", "Isi webhook URL dulu!", 3)
            WebhookEnabledToggle:SetValue(false)
            return
        end
        local success, msg = StartLogger()
        if success then
            Notify("Vechnost", "Notifier Aktif!", 2)
        else
            Notify("Vechnost", msg or "Error starting logger", 3)
            WebhookEnabledToggle:SetValue(false)
        end
    else
        StopLogger()
        Notify("Vechnost", "Notifier Berhenti", 2)
    end
end)

CreateSection("Webhook", "Status")

local WebhookStatusParagraph = CreateParagraph("Webhook", "Notifier Status", "Status: Offline")

task.spawn(function()
    while task.wait(2) do
        if Settings.Active then
            WebhookStatusParagraph:Set({
                Title = "Notifier Status",
                Content = string.format("Status: Aktif | Mode: %s | Total Log: %d ikan",
                    Settings.ServerWide and "Server-Notifier" or "Local Only",
                    Settings.LogCount
                )
            })
        else
            WebhookStatusParagraph:Set({
                Title = "Notifier Status",
                Content = "Status: Offline"
            })
        end
    end
end)

-- ===== SETTING TAB =====
CreateSection("Setting", "Testing")

CreateButton("Setting", "Test Webhook", function()
    if Settings.Url == "" then
        Notify("Vechnost", "Isi webhook URL dulu!", 3)
        return
    end

    task.spawn(function()
        SendWebhook(BuildTestPayload(LocalPlayer.Name))
    end)

    Notify("Vechnost", "Test message terkirim!", 2)
end)

CreateButton("Setting", "Reset Log Counter", function()
    Settings.LogCount = 0
    Settings.SentUUID = {}
    Notify("Vechnost", "Counter di-reset!", 2)
end)

CreateSection("Setting", "UI")

CreateButton("Setting", "Toggle UI (Press V)", function()
    MainFrame.Visible = not MainFrame.Visible
end)

CreateSection("Setting", "Credits")

CreateParagraph("Setting", "Vechnost Team", "Terima kasih telah menggunakan Vechnost!\nDiscord: discord.gg/vechnost")

-- =====================================================
-- BAGIAN 16: UI CONTROLS (Drag, Close, Minimize)
-- =====================================================

-- Drag System
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

-- Close Button
CloseBtn.MouseEnter:Connect(function()
    TweenService:Create(CloseBtn, TweenInfo.new(0.15), {BackgroundColor3 = Colors.Error}):Play()
end)

CloseBtn.MouseLeave:Connect(function()
    TweenService:Create(CloseBtn, TweenInfo.new(0.15), {BackgroundColor3 = Colors.ContentItem}):Play()
end)

CloseBtn.MouseButton1Click:Connect(function()
    TweenService:Create(MainFrame, TweenInfo.new(0.3), {Size = UDim2.new(0, 0, 0, 0), Position = UDim2.new(0.5, 0, 0.5, 0)}):Play()
    task.wait(0.3)
    ScreenGui:Destroy()
end)

-- Minimize Button
local isMinimized = false

MinBtn.MouseEnter:Connect(function()
    TweenService:Create(MinBtn, TweenInfo.new(0.15), {BackgroundColor3 = Colors.ContentItemHover}):Play()
end)

MinBtn.MouseLeave:Connect(function()
    TweenService:Create(MinBtn, TweenInfo.new(0.15), {BackgroundColor3 = Colors.ContentItem}):Play()
end)

MinBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        TweenService:Create(MainFrame, TweenInfo.new(0.3), {Size = UDim2.new(0, 650, 0, 45)}):Play()
    else
        TweenService:Create(MainFrame, TweenInfo.new(0.3), {Size = UDim2.new(0, 650, 0, 420)}):Play()
    end
end)

-- Keyboard Toggle (V key)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.V then
        MainFrame.Visible = not MainFrame.Visible
    end
end)

-- =====================================================
-- BAGIAN 17: FLOATING TOGGLE BUTTON (Mobile)
-- =====================================================
local oldBtn = CoreGui:FindFirstChild(GUI_NAMES.Mobile)
if oldBtn then oldBtn:Destroy() end

local BtnGui = Instance.new("ScreenGui")
BtnGui.Name = GUI_NAMES.Mobile
BtnGui.ResetOnSpawn = false
BtnGui.Parent = CoreGui

local FloatButton = Instance.new("ImageButton")
FloatButton.Size = UDim2.fromOffset(52, 52)
FloatButton.Position = UDim2.fromScale(0.05, 0.5)
FloatButton.BackgroundTransparency = 1
FloatButton.AutoButtonColor = false
FloatButton.BorderSizePixel = 0
FloatButton.Image = "rbxassetid://127239715511367"
FloatButton.ImageTransparency = 0
FloatButton.ScaleType = Enum.ScaleType.Fit
FloatButton.Parent = BtnGui

Instance.new("UICorner", FloatButton).CornerRadius = UDim.new(1, 0)

FloatButton.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- Float Button Drag
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
    local cx = math.clamp(target.X, 0, vp.X - sz.X)
    local cy = math.clamp(target.Y, 0, vp.Y - sz.Y)
    FloatButton.Position = UDim2.fromOffset(cx, cy)
end)

-- =====================================================
-- BAGIAN 18: INIT
-- =====================================================

-- Set default tab
SwitchTab("Info")

warn("[Vechnost] Custom UI v2.0 Loaded!")
warn("[Vechnost] Toggle GUI: Press V or tap floating button")
Notify("Vechnost", "Script loaded successfully!", 3)
