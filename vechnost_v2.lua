--[[ 
    FILE: vechnost_v2.lua
    BRAND: Vechnost
    VERSION: 2.0.0
    DESC: Full-Featured Hub for Roblox "Fish It"
          Tabs: INFO | FISHING | TRADING | TELEPORT | WEBHOOK | CONFIG
          - Auto Fish (Always Perfect)
          - Auto Sell (Inf Range)
          - Auto Trade (Accept/Decline Filter)
          - Teleport to All Islands / NPCs / Players
          - Server-Wide Fish Webhook Logger
          - Config Save/Load
]]

-- =====================================================
-- BAGIAN 1: CLEANUP SYSTEM
-- =====================================================
local CoreGui = game:GetService("CoreGui")
local GUI_NAMES = {
    Main = "Vechnost_Hub_UI",
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
local Players          = game:GetService("Players")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local HttpService      = game:GetService("HttpService")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local Workspace        = game:GetService("Workspace")
local TextChatService  = game:GetService("TextChatService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- =====================================================
-- BAGIAN 3: GAME REMOTES
-- =====================================================
local net, ObtainedNewFish, SellRemote, TradeRemote
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

    pcall(function()
        for _, child in pairs(net:GetDescendants()) do
            local n = child.Name:lower()
            if n:find("sell") and (child:IsA("RemoteEvent") or child:IsA("RemoteFunction")) then
                SellRemote = child
            end
            if n:find("trade") and (child:IsA("RemoteEvent") or child:IsA("RemoteFunction")) then
                TradeRemote = child
            end
        end
    end)
end

-- =====================================================
-- BAGIAN 4: LOAD RAYFIELD
-- =====================================================
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
-- BAGIAN 5: HTTP REQUEST
-- =====================================================
local HttpRequest =
    syn and syn.request
    or http_request
    or request
    or (fluxus and fluxus.request)
    or (krnl and krnl.request)

if not HttpRequest then
    warn("[Vechnost][FATAL] HttpRequest not available")
end

-- =====================================================
-- BAGIAN 6: SETTINGS STATE
-- =====================================================
local Settings = {
    -- Webhook
    Active            = false,
    Url               = "",
    SentUUID          = {},
    SelectedRarities  = {},
    ServerWide        = true,
    LogCount          = 0,

    -- Fishing
    AutoFish          = false,
    AutoSell          = false,
    AutoFishDelay     = 0.1,
    AutoSellDelay     = 5,
    AlwaysPerfect     = true,

    -- Trading
    AutoAcceptTrade   = false,
    AutoDeclineTrade  = false,
    TradeMinRarity    = 5,
    LogTrades         = false,

    -- Config
    ESP_Enabled       = false,
    AntiAFK           = false,
    InfJump           = false,
    WalkSpeed         = 16,
    JumpPower         = 50,
    RemoveFog         = false,
}

-- =====================================================
-- BAGIAN 7: FISH DATABASE
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
                        Name      = mod.Data.Name,
                        Tier      = mod.Data.Tier,
                        Icon      = mod.Data.Icon,
                        SellPrice = mod.Data.SellPrice or mod.Data.Value or mod.Data.Price or mod.Data.Worth or 0
                    }
                end
            end
        end
    end)
    if not ok then warn("[Vechnost] ERROR loading FishDB:", err) end
    local c = 0; for _ in pairs(FishDB) do c=c+1 end
    warn("[Vechnost] FishDB loaded:", c, "fish")
end

local FishNameToId = {}
for fishId, fishData in pairs(FishDB) do
    if fishData.Name then
        FishNameToId[fishData.Name]                  = fishId
        FishNameToId[string.lower(fishData.Name)]    = fishId
    end
end

-- =====================================================
-- BAGIAN 8: PLAYER DATA (Replion)
-- =====================================================
local PlayerData = nil
do
    pcall(function()
        local Replion = require(ReplicatedStorage.Packages.Replion)
        PlayerData = Replion.Client:WaitReplion("Data")
        if PlayerData then warn("[Vechnost] Replion Data loaded OK") end
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
    local stats = { Coins=0, TotalCaught=0, BackpackCount=0, BackpackMax=0 }
    if not PlayerData then return stats end
    pcall(function()
        for _, key in ipairs({"Coins","Currency","Money","Gold","Cash"}) do
            local ok, val = pcall(function() return PlayerData:Get(key) end)
            if ok and val and type(val)=="number" then stats.Coins=val; break end
        end
        for _, key in ipairs({"TotalCaught","FishCaught","TotalFish"}) do
            local ok, val = pcall(function() return PlayerData:Get(key) end)
            if ok and val and type(val)=="number" then stats.TotalCaught=val; break end
        end
        pcall(function()
            local inv = PlayerData:Get("Inventory")
            if inv and typeof(inv)=="table" then
                if inv.Items and typeof(inv.Items)=="table" then
                    local c=0; for _ in pairs(inv.Items) do c=c+1 end; stats.BackpackCount=c
                else
                    local c=0; for _ in pairs(inv) do c=c+1 end; stats.BackpackCount=c
                end
                stats.BackpackMax = inv.Capacity or inv.Size or inv.MaxSize or inv.Max or inv.Limit or 0
            end
        end)
        for _, key in ipairs({"BackpackSize","MaxBackpack","BackpackMax","InventorySize","MaxInventory"}) do
            local ok, val = pcall(function() return PlayerData:Get(key) end)
            if ok and val and type(val)=="number" and val>0 then stats.BackpackMax=val; break end
        end
    end)
    return stats
end

-- =====================================================
-- BAGIAN 9: RARITY SYSTEM
-- =====================================================
local RARITY_MAP = {
    [1]="Common",[2]="Uncommon",[3]="Rare",[4]="Epic",
    [5]="Legendary",[6]="Mythic",[7]="Secret",
}
local RARITY_NAME_TO_TIER = {
    Common=1,Uncommon=2,Rare=3,Epic=4,Legendary=5,Mythic=6,Secret=7,
}
local RarityList = {"Common","Uncommon","Rare","Epic","Legendary","Mythic","Secret"}

local function IsRarityAllowed(fishId)
    local fish = FishDB[fishId]
    if not fish then return false end
    local tier = fish.Tier
    if type(tier) ~= "number" then return false end
    if next(Settings.SelectedRarities) == nil then return true end
    return Settings.SelectedRarities[tier] == true
end

-- =====================================================
-- BAGIAN 10: TELEPORT LOCATIONS
-- =====================================================
-- NOTE: Koordinat di bawah adalah estimasi berdasarkan layout map Fish It.
-- Setelah run, kamu bisa fine-tune koordinat dengan melihat posisi HRP di Workspace.
local TeleportLocations = {
    { Name = "🏝️ Fisherman Island (Spawn)", Position = Vector3.new(0, 5, 0) },
    { Name = "🌴 Tropical Grove",            Position = Vector3.new(850, 5, -200) },
    { Name = "🌋 Kohana Volcano",            Position = Vector3.new(-600, 5, 400) },
    { Name = "🪸 Coral Reef",               Position = Vector3.new(1200, 5, 500) },
    { Name = "🏴‍☠️ Pirate Cove",              Position = Vector3.new(-900, 5, -300) },
    { Name = "🌊 Lost Isle",                Position = Vector3.new(1800, 5, -800) },
    { Name = "🌿 Ancient Jungle",           Position = Vector3.new(-1500, 5, 600) },
    { Name = "⚓ Esoteric Depths",          Position = Vector3.new(300, -50, 800) },
    { Name = "🎣 Lava Fisherman NPC",       Position = Vector3.new(-580, 8, 380) },
    { Name = "🛒 Rod Shop (Spawn)",         Position = Vector3.new(15, 5, 25) },
    { Name = "💰 Sell NPC (Spawn)",         Position = Vector3.new(30, 5, 40) },
    { Name = "⚗️ Enchant Altar",            Position = Vector3.new(305, -48, 810) },
    { Name = "🚢 Boat Shop",               Position = Vector3.new(20, 5, -15) },
}

-- =====================================================
-- BAGIAN 11: ICON CACHE
-- =====================================================
local IconCache  = {}
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
        local api = ("https://thumbnails.roblox.com/v1/assets?assetIds=%s&size=420x420&format=Png&isCircular=false"):format(assetId)
        local ok, res = pcall(function() return HttpRequest({ Url=api, Method="GET" }) end)
        if not ok or not res or not res.Body then callback(""); return end
        local ok2, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
        if not ok2 then callback(""); return end
        local imageUrl = data and data.data and data.data[1] and data.data[1].imageUrl
        IconCache[fishId] = imageUrl or ""
        for _, cb in ipairs(IconWaiter[fishId]) do cb(IconCache[fishId]) end
        IconWaiter[fishId] = nil
    end)
end

-- =====================================================
-- BAGIAN 12: HELPERS
-- =====================================================
local function ExtractMutation(weightData, item)
    local mutation = nil
    if weightData and typeof(weightData) == "table" then
        mutation = weightData.Mutation or weightData.Variant or weightData.VariantID
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
    if typeof(arg) == "Instance" and arg:IsA("Player") then return arg.Name
    elseif typeof(arg) == "string" then return arg
    elseif typeof(arg) == "table" and arg.Name then return tostring(arg.Name)
    end
    return LocalPlayer.Name
end

-- =====================================================
-- BAGIAN 13: WEBHOOK PAYLOADS (Discord Components V2)
-- =====================================================
local function BuildPayload(playerName, fishId, weight, mutation)
    local fish = FishDB[fishId]
    if not fish then return nil end
    local tier       = fish.Tier
    local rarityName = RARITY_MAP[tier] or "Unknown"
    local mutText    = (mutation ~= nil) and tostring(mutation) or "None"
    local weightText = string.format("%.1fkg", weight or 0)
    local iconUrl    = IconCache[fishId] or ""
    local dateStr    = os.date("!%B %d, %Y")

    return {
        username   = "Vechnost Notifier",
        avatar_url = "https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png",
        flags      = 32768,
        components = {
            {
                type = 17,
                components = {
                    { type=10, content="# NEW FISH CAUGHT!" },
                    { type=14, spacing=1, divider=true },
                    { type=10, content="__@" .. (playerName or "Unknown") .. " you got new " .. string.upper(rarityName) .. " fish__" },
                    {
                        type=9,
                        components = {
                            { type=10, content="**Fish Name**" },
                            { type=10, content="> " .. (fish.Name or "Unknown") }
                        },
                        accessory = iconUrl ~= "" and { type=11, media={ url=iconUrl } } or nil
                    },
                    { type=10, content="**Fish Tier**" },
                    { type=10, content="> " .. string.upper(rarityName) },
                    { type=10, content="**Weight**" },
                    { type=10, content="> " .. weightText },
                    { type=10, content="**Mutation**" },
                    { type=10, content="> " .. mutText },
                    { type=10, content="**Est. Sell Price**" },
                    { type=10, content="> ~" .. FormatNumber(fish.SellPrice) .. " coins" },
                    { type=14, spacing=1, divider=true },
                    { type=10, content="> Notification by discord.gg/vechnost" },
                    { type=10, content="-# " .. dateStr }
                }
            }
        }
    }
end

local function BuildActivationPayload(playerName, mode)
    local dateStr = os.date("!%B %d, %Y")
    return {
        username   = "Vechnost Notifier",
        avatar_url = "https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png",
        flags      = 32768,
        components = {
            {
                type=17, accent_color=0x30ff6a,
                components = {
                    { type=10, content="**" .. playerName .. "  Webhook Activated!**" },
                    { type=14, spacing=1, divider=true },
                    { type=10, content="### Vechnost Hub v2.0" },
                    { type=10, content="- **Account Name:** "..playerName.."\n- **Mode:** "..mode.."\n- **Status:** Online" },
                    { type=14, spacing=1, divider=true },
                    { type=10, content="-# " .. dateStr }
                }
            }
        }
    }
end

local function BuildTestPayload(playerName)
    local dateStr = os.date("!%B %d, %Y")
    return {
        username   = "Vechnost Notifier",
        avatar_url = "https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png",
        flags      = 32768,
        components = {
            {
                type=17, accent_color=0x5865f2,
                components = {
                    { type=10, content="**Test Message**" },
                    { type=14, spacing=1, divider=true },
                    { type=10, content="Webhook berfungsi dengan baik!\n\n- **Dikirim oleh:** " .. playerName },
                    { type=14, spacing=1, divider=true },
                    { type=10, content="-# " .. dateStr }
                }
            }
        }
    }
end

local function BuildTradePayload(senderName, receiverName, sentItems, receivedItems)
    local dateStr = os.date("!%B %d, %Y")
    local sentText, recText = "", ""
    for _, item in ipairs(sentItems or {}) do sentText = sentText .. "\n- " .. tostring(item) end
    for _, item in ipairs(receivedItems or {}) do recText = recText .. "\n- " .. tostring(item) end
    if sentText == "" then sentText = "\n- (none)" end
    if recText  == "" then recText  = "\n- (none)" end
    return {
        username   = "Vechnost Notifier",
        avatar_url = "https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png",
        flags      = 32768,
        components = {
            {
                type=17, accent_color=0xffd700,
                components = {
                    { type=10, content="# TRADE COMPLETED" },
                    { type=14, spacing=1, divider=true },
                    { type=10, content="**" .. senderName .. "** traded with **" .. receiverName .. "**" },
                    { type=10, content="**You Sent:**" .. sentText },
                    { type=10, content="**You Received:**" .. recText },
                    { type=14, spacing=1, divider=true },
                    { type=10, content="-# " .. dateStr }
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
        url = url .. (string.find(url,"?") and "&" or "?") .. "with_components=true"
        HttpRequest({
            Url     = url,
            Method  = "POST",
            Headers = { ["Content-Type"]="application/json" },
            Body    = HttpService:JSONEncode(payload)
        })
    end)
end

-- =====================================================
-- BAGIAN 14: AUTO FISHING ENGINE
-- =====================================================
local FishingLoop   = nil
local AutoPerfectConn
local CastRemote, ReelRemote

do
    pcall(function()
        for _, child in pairs(net:GetDescendants()) do
            local n = child.Name:lower()
            if n:find("cast") and (child:IsA("RemoteEvent") or child:IsA("RemoteFunction")) then
                CastRemote = child
            elseif n:find("reel") and (child:IsA("RemoteEvent") or child:IsA("RemoteFunction")) then
                ReelRemote = child
            end
        end
    end)
end

local function EnableAutoPerfect()
    if AutoPerfectConn then pcall(function() AutoPerfectConn:Disconnect() end) end
    AutoPerfectConn = RunService.Heartbeat:Connect(function()
        if not Settings.AutoFish then return end
        pcall(function()
            for _, gui in pairs(PlayerGui:GetChildren()) do
                for _, desc in pairs(gui:GetDescendants()) do
                    if desc:IsA("Frame") and (
                        desc.Name:lower():find("indicator") or
                        desc.Name:lower():find("progress")  or
                        desc.Name:lower():find("reel")
                    ) then
                        if ReelRemote then
                            if ReelRemote:IsA("RemoteEvent") then
                                ReelRemote:FireServer({ Perfect=true })
                            elseif ReelRemote:IsA("RemoteFunction") then
                                ReelRemote:InvokeServer({ Perfect=true })
                            end
                        end
                    end
                end
            end
        end)
    end)
end

local function StartAutoFish()
    if FishingLoop then return end
    FishingLoop = task.spawn(function()
        while Settings.AutoFish do
            pcall(function()
                if CastRemote then
                    if CastRemote:IsA("RemoteEvent") then CastRemote:FireServer()
                    elseif CastRemote:IsA("RemoteFunction") then CastRemote:InvokeServer() end
                else
                    pcall(function()
                        local VIM = game:GetService("VirtualInputManager")
                        if VIM then
                            VIM:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                            task.wait(0.05)
                            VIM:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                        end
                    end)
                end
            end)
            task.wait(Settings.AutoFishDelay)
        end
        FishingLoop = nil
    end)
    EnableAutoPerfect()
    warn("[Vechnost] Auto Fish STARTED")
end

local function StopAutoFish()
    Settings.AutoFish = false
    if FishingLoop then task.cancel(FishingLoop); FishingLoop=nil end
    if AutoPerfectConn then pcall(function() AutoPerfectConn:Disconnect() end); AutoPerfectConn=nil end
    warn("[Vechnost] Auto Fish STOPPED")
end

-- =====================================================
-- BAGIAN 15: AUTO SELL ENGINE
-- =====================================================
local SellLoop = nil

local function TrySellAll()
    pcall(function()
        if SellRemote then
            if SellRemote:IsA("RemoteEvent") then SellRemote:FireServer()
            elseif SellRemote:IsA("RemoteFunction") then SellRemote:InvokeServer() end
            return
        end

        for _, obj in pairs(Workspace:GetDescendants()) do
            if obj:IsA("ProximityPrompt") and
               (obj.ActionText:lower():find("sell") or obj.ObjectText:lower():find("sell")) then
                local chr = LocalPlayer.Character
                if chr and chr:FindFirstChild("HumanoidRootPart") then
                    local hrp = chr.HumanoidRootPart
                    if obj.Parent:IsA("BasePart") then
                        hrp.CFrame = CFrame.new(obj.Parent.Position + Vector3.new(0,3,3))
                    end
                end
                pcall(function() fireproximityprompt(obj) end)
                return
            end
        end

        if net then
            for _, child in pairs(net:GetDescendants()) do
                if child.Name:lower():find("sell") then
                    pcall(function()
                        if child:IsA("RemoteEvent") then child:FireServer()
                        elseif child:IsA("RemoteFunction") then child:InvokeServer() end
                    end)
                end
            end
        end
    end)
end

local function StartAutoSell()
    if SellLoop then return end
    SellLoop = task.spawn(function()
        while Settings.AutoSell do
            TrySellAll()
            task.wait(Settings.AutoSellDelay)
        end
        SellLoop = nil
    end)
    warn("[Vechnost] Auto Sell STARTED")
end

local function StopAutoSell()
    Settings.AutoSell = false
    if SellLoop then task.cancel(SellLoop); SellLoop=nil end
    warn("[Vechnost] Auto Sell STOPPED")
end

-- =====================================================
-- BAGIAN 16: TRADING ENGINE
-- =====================================================
local TradeConnections = {}

local function GetTradeItems(tradeData)
    local items = {}
    if not tradeData then return items end
    pcall(function()
        local offered = tradeData.OfferedItems or tradeData.Items or tradeData.Offer or {}
        for _, item in pairs(offered) do
            local fish = item.Id and FishDB[item.Id]
            if fish then
                table.insert(items, fish.Name .. " (" .. (RARITY_MAP[fish.Tier] or "?") .. ")")
            else
                table.insert(items, tostring(item.Id or item.Name or "Unknown"))
            end
        end
    end)
    return items
end

local function ShouldAcceptTrade(tradeData)
    if not tradeData then return false end
    local accept = false
    pcall(function()
        local received = tradeData.ReceivedItems or tradeData.TheirItems or {}
        for _, item in pairs(received) do
            local fish = item.Id and FishDB[item.Id]
            if fish and fish.Tier and fish.Tier >= Settings.TradeMinRarity then
                accept = true; break
            end
        end
    end)
    return accept
end

local function StartAutoTrade()
    for _, conn in ipairs(TradeConnections) do pcall(function() conn:Disconnect() end) end
    TradeConnections = {}
    if not net then return end
    pcall(function()
        for _, child in pairs(net:GetDescendants()) do
            local n = child.Name:lower()
            if n:find("trade") and child:IsA("RemoteEvent") then
                local conn = child.OnClientEvent:Connect(function(...)
                    local args = {...}
                    local tradeData = args[1]

                    if Settings.LogTrades and Settings.Url ~= "" then
                        local sentItems, receivedItems = GetTradeItems(tradeData), {}
                        pcall(function()
                            local r = tradeData and (tradeData.ReceivedItems or tradeData.TheirItems) or {}
                            for _, item in pairs(r) do
                                local fish = item.Id and FishDB[item.Id]
                                table.insert(receivedItems, fish and (fish.Name.." ("..RARITY_MAP[fish.Tier]..")") or tostring(item.Id or "?"))
                            end
                        end)
                        local partner = "Unknown"
                        pcall(function() partner = tostring(tradeData.Partner or tradeData.PlayerName or tradeData.Sender or "Unknown") end)
                        task.spawn(function()
                            SendWebhook(BuildTradePayload(LocalPlayer.Name, partner, sentItems, receivedItems))
                        end)
                    end

                    if Settings.AutoAcceptTrade and ShouldAcceptTrade(tradeData) then
                        pcall(function()
                            for _, c in pairs(net:GetDescendants()) do
                                if c.Name:lower():find("accepttrade") or c.Name:lower():find("trade_accept") then
                                    if c:IsA("RemoteEvent") then c:FireServer(tradeData)
                                    elseif c:IsA("RemoteFunction") then c:InvokeServer(tradeData) end
                                end
                            end
                        end)
                    elseif Settings.AutoDeclineTrade then
                        pcall(function()
                            for _, c in pairs(net:GetDescendants()) do
                                if c.Name:lower():find("declinetrade") or c.Name:lower():find("trade_decline") then
                                    if c:IsA("RemoteEvent") then c:FireServer(tradeData)
                                    elseif c:IsA("RemoteFunction") then c:InvokeServer(tradeData) end
                                end
                            end
                        end)
                    end
                end)
                table.insert(TradeConnections, conn)
            end
        end
    end)
    warn("[Vechnost] Auto Trade monitor STARTED")
end

local function StopAutoTrade()
    for _, conn in ipairs(TradeConnections) do pcall(function() conn:Disconnect() end) end
    TradeConnections = {}
    warn("[Vechnost] Auto Trade monitor STOPPED")
end

-- =====================================================
-- BAGIAN 17: TELEPORT ENGINE
-- =====================================================
local function TeleportTo(position)
    local char = LocalPlayer.Character
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    hrp.CFrame = CFrame.new(position)
    return true
end

local function TeleportToPlayer(targetPlayer)
    if not targetPlayer or not targetPlayer.Character then return false end
    local targetHRP = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not targetHRP then return false end
    return TeleportTo(targetHRP.Position + Vector3.new(0, 3, 3))
end

-- =====================================================
-- BAGIAN 18: SERVER-WIDE FISH DETECTION (Webhook)
-- =====================================================
local WebhookConnections = {}
local ChatSentDedup      = {}

local function ParseChatForFish(messageText)
    if not Settings.Active or not Settings.ServerWide then return end
    if not messageText or messageText == "" then return end

    local playerName, fishName, weightStr =
        string.match(messageText, "(%S+)%s+obtained%s+a%s+(.-)%s*%(([%d%.]+)kg%)")
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
    if playerName==LocalPlayer.Name or playerName==LocalPlayer.DisplayName then return end

    local fishId = FishNameToId[fishName] or FishNameToId[string.lower(fishName)]
    if not fishId then
        for name, id in pairs(FishNameToId) do
            if string.find(string.lower(fishName), string.lower(name), 1, true)
            or string.find(string.lower(name), string.lower(fishName), 1, true) then
                fishId = id; break
            end
        end
    end
    if not fishId then return end
    if not IsRarityAllowed(fishId) then return end

    local dedupKey = playerName .. fishName .. tostring(math.floor(os.time()/2))
    if ChatSentDedup[dedupKey] then return end
    ChatSentDedup[dedupKey] = true
    task.defer(function() task.wait(10); ChatSentDedup[dedupKey]=nil end)

    local weight = tonumber(weightStr) or 0
    Settings.LogCount = Settings.LogCount + 1
    FetchFishIconAsync(fishId, function() SendWebhook(BuildPayload(playerName, fishId, weight, nil)) end)
end

local function HandleFishCaught(playerArg, weightData, wrapper)
    if not Settings.Active then return end
    local item = nil
    if wrapper and typeof(wrapper)=="table" and wrapper.InventoryItem then item=wrapper.InventoryItem end
    if not item and weightData and typeof(weightData)=="table" and weightData.InventoryItem then item=weightData.InventoryItem end
    if not item or not item.Id or not item.UUID then return end
    if not FishDB[item.Id] then return end
    if not IsRarityAllowed(item.Id) then return end
    if Settings.SentUUID[item.UUID] then return end
    Settings.SentUUID[item.UUID] = true

    local playerName = ResolvePlayerName(playerArg)
    if not Settings.ServerWide and playerName ~= LocalPlayer.Name then return end

    local weight   = (weightData and typeof(weightData)=="table" and weightData.Weight) and weightData.Weight or 0
    local mutation = ExtractMutation(weightData, item)

    Settings.LogCount = Settings.LogCount + 1
    warn("[Vechnost] Fish caught! Player:", playerName, "Fish:", FishDB[item.Id].Name)

    FetchFishIconAsync(item.Id, function() SendWebhook(BuildPayload(playerName, item.Id, weight, mutation)) end)
end

local function StartLogger()
    if Settings.Active then return end
    if not net or not ObtainedNewFish then
        Rayfield:Notify({ Title="Vechnost", Content="ERROR: Game remotes not found!", Duration=5 })
        return
    end
    Settings.Active   = true
    Settings.SentUUID = {}
    Settings.LogCount = 0

    if Settings.ServerWide then
        pcall(function()
            WebhookConnections[#WebhookConnections+1] =
                TextChatService.MessageReceived:Connect(function(msg)
                    pcall(function()
                        if string.find(msg.Text or "", "obtained") then ParseChatForFish(msg.Text) end
                    end)
                end)
        end)
    end

    pcall(function()
        WebhookConnections[#WebhookConnections+1] =
            ObtainedNewFish.OnClientEvent:Connect(function(pArg, wData, wrap)
                HandleFishCaught(pArg, wData, wrap)
            end)
    end)

    if Settings.ServerWide then
        pcall(function()
            WebhookConnections[#WebhookConnections+1] =
                PlayerGui.DescendantAdded:Connect(function(desc)
                    if not Settings.Active or not desc:IsA("TextLabel") then return end
                    task.defer(function()
                        local text = desc.Text or ""
                        for fishId, fishData in pairs(FishDB) do
                            if fishData.Name and string.find(text, fishData.Name, 1, true) then
                                if not IsRarityAllowed(fishId) then return end
                                for _, p in pairs(Players:GetPlayers()) do
                                    if p ~= LocalPlayer and
                                       (string.find(text, p.Name, 1, true) or string.find(text, p.DisplayName, 1, true)) then
                                        local key = "GUI_"..text:sub(1,40).."_"..os.time()
                                        if Settings.SentUUID[key] then return end
                                        Settings.SentUUID[key] = true
                                        Settings.LogCount = Settings.LogCount + 1
                                        FetchFishIconAsync(fishId, function() SendWebhook(BuildPayload(p.Name, fishId, 0, nil)) end)
                                        return
                                    end
                                end
                                return
                            end
                        end
                    end)
                end)
        end)

        pcall(function()
            for _, child in pairs(net:GetChildren()) do
                if child:IsA("RemoteEvent") and child ~= ObtainedNewFish then
                    WebhookConnections[#WebhookConnections+1] =
                        child.OnClientEvent:Connect(function(...)
                            for _, arg in ipairs({...}) do
                                if typeof(arg)=="table" then
                                    local item = arg.InventoryItem or (arg.Id and arg.UUID and arg)
                                    if item and item.Id and item.UUID and FishDB[item.Id] then
                                        HandleFishCaught(({...})[1], nil, arg)
                                    end
                                end
                            end
                        end)
                end
            end
        end)
    end

    task.spawn(function()
        SendWebhook(BuildActivationPayload(LocalPlayer.Name, Settings.ServerWide and "Server Notifier" or "Local Only"))
    end)
    warn("[Vechnost] Webhook Logger ENABLED")
end

local function StopLogger()
    Settings.Active = false
    for _, conn in ipairs(WebhookConnections) do pcall(function() conn:Disconnect() end) end
    WebhookConnections = {}
    warn("[Vechnost] Webhook Logger DISABLED | Total logged:", Settings.LogCount)
end

-- =====================================================
-- BAGIAN 19: CONFIG FEATURES
-- =====================================================
-- Anti-AFK
local AntiAFKThread
local function StartAntiAFK()
    if AntiAFKThread then return end
    AntiAFKThread = task.spawn(function()
        while Settings.AntiAFK do
            pcall(function()
                local VIM = game:GetService("VirtualInputManager")
                if VIM then
                    VIM:SendMouseButtonEvent(0,0,0,true,game,1)
                    VIM:SendMouseButtonEvent(0,0,0,false,game,1)
                end
            end)
            task.wait(60)
        end
        AntiAFKThread = nil
    end)
    warn("[Vechnost] Anti-AFK ENABLED")
end

local function StopAntiAFK()
    Settings.AntiAFK = false
    if AntiAFKThread then task.cancel(AntiAFKThread); AntiAFKThread=nil end
    warn("[Vechnost] Anti-AFK DISABLED")
end

-- Infinite Jump
local InfJumpConn
local function StartInfJump()
    if InfJumpConn then return end
    InfJumpConn = UserInputService.JumpRequest:Connect(function()
        local char = LocalPlayer.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end)
    warn("[Vechnost] Infinite Jump ENABLED")
end

local function StopInfJump()
    Settings.InfJump = false
    if InfJumpConn then pcall(function() InfJumpConn:Disconnect() end); InfJumpConn=nil end
    warn("[Vechnost] Infinite Jump DISABLED")
end

-- Walk / Jump speed
local function SetWalkSpeed(speed)
    local char = LocalPlayer.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = speed end
    end
    LocalPlayer.CharacterAdded:Connect(function(c)
        local h = c:WaitForChild("Humanoid", 5)
        if h then h.WalkSpeed = speed end
    end)
end

local function SetJumpPower(power)
    local char = LocalPlayer.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hum.JumpPower = power end
    end
    LocalPlayer.CharacterAdded:Connect(function(c)
        local h = c:WaitForChild("Humanoid", 5)
        if h then h.JumpPower = power end
    end)
end

-- Player ESP
local ESPFolder = Instance.new("Folder")
ESPFolder.Name  = "Vechnost_ESP"
ESPFolder.Parent = Workspace

local function ClearESP() ESPFolder:ClearAllChildren() end

local ESPLoop
local function StartESP()
    if ESPLoop then return end
    ESPLoop = task.spawn(function()
        while Settings.ESP_Enabled do
            pcall(function()
                ClearESP()
                for _, plr in pairs(Players:GetPlayers()) do
                    if plr ~= LocalPlayer and plr.Character then
                        local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
                        if hrp then
                            local bb = Instance.new("BillboardGui")
                            bb.Adornee                  = hrp
                            bb.Size                     = UDim2.fromOffset(150, 50)
                            bb.StudsOffsetWorldSpace    = Vector3.new(0, 3, 0)
                            bb.AlwaysOnTop              = true
                            bb.Parent                   = ESPFolder

                            local lbl        = Instance.new("TextLabel", bb)
                            lbl.Size         = UDim2.fromScale(1, 1)
                            lbl.BackgroundTransparency = 1
                            lbl.TextColor3   = Color3.fromRGB(255, 80, 80)
                            lbl.TextStrokeTransparency = 0
                            lbl.Font         = Enum.Font.GothamBold
                            lbl.TextSize     = 14
                            lbl.Text         = "👤 " .. plr.DisplayName
                            local myHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                            if myHRP then
                                local dist = math.floor((hrp.Position - myHRP.Position).Magnitude)
                                lbl.Text = lbl.Text .. "\n[" .. dist .. " studs]"
                            end
                        end
                    end
                end
            end)
            task.wait(0.5)
        end
        ClearESP()
        ESPLoop = nil
    end)
    warn("[Vechnost] ESP ENABLED")
end

local function StopESP()
    Settings.ESP_Enabled = false
    if ESPLoop then task.cancel(ESPLoop); ESPLoop=nil end
    ClearESP()
    warn("[Vechnost] ESP DISABLED")
end

-- =====================================================
-- BAGIAN 20: FLOATING BUTTON
-- =====================================================
local oldBtn = CoreGui:FindFirstChild(GUI_NAMES.Mobile)
if oldBtn then oldBtn:Destroy() end

local BtnGui        = Instance.new("ScreenGui")
BtnGui.Name         = GUI_NAMES.Mobile
BtnGui.ResetOnSpawn = false
BtnGui.Parent       = CoreGui

local Button = Instance.new("ImageButton")
Button.Size               = UDim2.fromOffset(52, 52)
Button.Position           = UDim2.fromScale(0.05, 0.5)
Button.BackgroundTransparency = 1
Button.AutoButtonColor    = false
Button.BorderSizePixel    = 0
Button.Image              = "rbxassetid://127239715511367"
Button.ScaleType          = Enum.ScaleType.Fit
Button.Parent             = BtnGui

Instance.new("UICorner", Button).CornerRadius = UDim.new(1,0)

local windowVisible = true
Button.MouseButton1Click:Connect(function()
    windowVisible = not windowVisible
    pcall(function() Rayfield:SetVisibility(windowVisible) end)
end)

local dragging, dragOffset = false, Vector2.zero
Button.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging   = true
        dragOffset = UserInputService:GetMouseLocation() - Button.AbsolutePosition
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging=false end
        end)
    end
end)

RunService.RenderStepped:Connect(function()
    if not dragging then return end
    local m  = UserInputService:GetMouseLocation()
    local t  = m - dragOffset
    local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920,1080)
    local sz = Button.AbsoluteSize
    Button.Position = UDim2.fromOffset(math.clamp(t.X,0,vp.X-sz.X), math.clamp(t.Y,0,vp.Y-sz.Y))
end)

-- =====================================================
-- BAGIAN 21: RAYFIELD WINDOW
-- =====================================================
local Window = Rayfield:CreateWindow({
    Name            = "Vechnost Hub",
    Icon            = "fish",
    LoadingTitle    = "Vechnost Hub",
    LoadingSubtitle = "v2.0.0 | Fish It",
    Theme           = "Default",
    ToggleUIKeybind = "V",
    DisableRayfieldPrompts  = true,
    DisableBuildWarnings    = true,
    ConfigurationSaving = {
        Enabled    = true,
        FolderName = "Vechnost",
        FileName   = "VechnostConfig_v2"
    },
    KeySystem = true,
    KeySettings = {
        Title    = "Vechnost Access",
        Subtitle = "Authentication Required",
        Note     = "Join our discord to get key\n https://discord.gg/vechnost",
        FileName = "VechnostKey",
        SaveKey  = true,
        GrabKeyFromSite = false,
        Key = {"Vechnost-Notifier-9999"}
    },
})

-- =====================================================
-- TAB 1: INFO
-- =====================================================
local TabInfo = Window:CreateTab("Info", "info")

TabInfo:CreateSection("Vechnost Hub v2.0")

TabInfo:CreateParagraph({
    Title   = "Selamat Datang!",
    Content = "Vechnost Hub adalah all-in-one script untuk Roblox Fish It.\n\n• Auto Fish (Always Perfect)\n• Auto Sell (Infinity Range)\n• Auto Trade Monitor + Webhook Log\n• Teleport ke semua Island, NPC, & Player\n• Server-Wide Webhook Logger\n• Player ESP\n• Anti-AFK, Inf Jump, Speed\n• Remove Fog\n\nby Vechnost | discord.gg/vechnost"
})

TabInfo:CreateSection("📊 Player Stats")

local StatsLabel = TabInfo:CreateParagraph({ Title="Stats", Content="Loading..." })

task.spawn(function()
    while true do
        task.wait(3)
        pcall(function()
            local stats = GetPlayerStats()
            if StatsLabel then
                StatsLabel:Set({
                    Title   = "📊 Player Stats",
                    Content = string.format(
                        "💰 Coins: %s\n🐟 Total Caught: %s\n🎒 Backpack: %s / %s\n👥 Server Players: %d",
                        FormatNumber(stats.Coins),
                        FormatNumber(stats.TotalCaught),
                        FormatNumber(stats.BackpackCount),
                        stats.BackpackMax > 0 and FormatNumber(stats.BackpackMax) or "?",
                        #Players:GetPlayers()
                    )
                })
            end
        end)
    end
end)

TabInfo:CreateSection("Server Actions")

TabInfo:CreateButton({
    Name = "🔄 Rejoin Server",
    Callback = function()
        pcall(function()
            game:GetService("TeleportService"):Teleport(game.PlaceId, LocalPlayer)
        end)
        Rayfield:Notify({ Title="Vechnost", Content="Rejoining...", Duration=3 })
    end
})

TabInfo:CreateButton({
    Name = "📋 Copy Game Link",
    Callback = function()
        local link = "https://www.roblox.com/games/" .. game.PlaceId
        pcall(function() setclipboard(link) end)
        Rayfield:Notify({ Title="Vechnost", Content="Link copied!\n"..link, Duration=3 })
    end
})

-- =====================================================
-- TAB 2: FISHING
-- =====================================================
local TabFishing = Window:CreateTab("Fishing", "fish")

TabFishing:CreateSection("Auto Fishing")

TabFishing:CreateToggle({
    Name="🎣 Auto Fish (Always Perfect)", CurrentValue=false, Flag="AutoFish",
    Callback=function(Value)
        Settings.AutoFish = Value
        if Value then StartAutoFish(); Rayfield:Notify({Title="Vechnost",Content="Auto Fish ON!",Duration=2})
        else StopAutoFish(); Rayfield:Notify({Title="Vechnost",Content="Auto Fish OFF",Duration=2}) end
    end
})

TabFishing:CreateSlider({
    Name="⏱️ Cast Delay (s)", Range={0.05,3}, Increment=0.05, Suffix="s",
    CurrentValue=0.1, Flag="AutoFishDelay",
    Callback=function(Value) Settings.AutoFishDelay=Value end
})

TabFishing:CreateSection("Auto Sell")

TabFishing:CreateToggle({
    Name="💰 Auto Sell (Inf Range)", CurrentValue=false, Flag="AutoSell",
    Callback=function(Value)
        Settings.AutoSell = Value
        if Value then StartAutoSell(); Rayfield:Notify({Title="Vechnost",Content="Auto Sell ON!",Duration=2})
        else StopAutoSell(); Rayfield:Notify({Title="Vechnost",Content="Auto Sell OFF",Duration=2}) end
    end
})

TabFishing:CreateSlider({
    Name="⏱️ Sell Interval (s)", Range={1,30}, Increment=1, Suffix="s",
    CurrentValue=5, Flag="AutoSellDelay",
    Callback=function(Value) Settings.AutoSellDelay=Value end
})

TabFishing:CreateButton({
    Name="💰 Sell Now (Manual)",
    Callback=function()
        TrySellAll()
        Rayfield:Notify({Title="Vechnost",Content="Sell triggered!",Duration=2})
    end
})

TabFishing:CreateSection("📈 Session Stats")

local FishStatsLabel = TabFishing:CreateParagraph({Title="Session Stats",Content="Waiting..."})

task.spawn(function()
    while true do
        task.wait(2)
        pcall(function()
            if FishStatsLabel then
                FishStatsLabel:Set({
                    Title   = "📈 Session Stats",
                    Content = string.format(
                        "🐟 Webhook Logged: %d\n🎣 Auto Fish: %s\n💰 Auto Sell: %s",
                        Settings.LogCount,
                        Settings.AutoFish and "ON ✅" or "OFF ❌",
                        Settings.AutoSell and "ON ✅" or "OFF ❌"
                    )
                })
            end
        end)
    end
end)

-- =====================================================
-- TAB 3: TRADING
-- =====================================================
local TabTrading = Window:CreateTab("Trading", "arrow-left-right")

TabTrading:CreateSection("Auto Trade")

TabTrading:CreateToggle({
    Name="✅ Auto Accept Trade", CurrentValue=false, Flag="AutoAcceptTrade",
    Callback=function(Value)
        Settings.AutoAcceptTrade  = Value
        if Value then Settings.AutoDeclineTrade=false end
        if Value then StartAutoTrade(); Rayfield:Notify({Title="Vechnost",Content="Auto Accept ON!",Duration=2})
        else Rayfield:Notify({Title="Vechnost",Content="Auto Accept OFF",Duration=2}) end
    end
})

TabTrading:CreateToggle({
    Name="❌ Auto Decline Trade", CurrentValue=false, Flag="AutoDeclineTrade",
    Callback=function(Value)
        Settings.AutoDeclineTrade = Value
        if Value then Settings.AutoAcceptTrade=false end
        if Value then StartAutoTrade(); Rayfield:Notify({Title="Vechnost",Content="Auto Decline ON!",Duration=2})
        else Rayfield:Notify({Title="Vechnost",Content="Auto Decline OFF",Duration=2}) end
    end
})

TabTrading:CreateSection("Trade Filter")

TabTrading:CreateDropdown({
    Name="🎯 Min Rarity to Accept", Options=RarityList,
    CurrentOption={"Legendary"}, MultipleOptions=false, Flag="TradeMinRarity",
    Callback=function(Option)
        Settings.TradeMinRarity = RARITY_NAME_TO_TIER[Option] or 5
        Rayfield:Notify({Title="Vechnost",Content="Min rarity: "..tostring(Option),Duration=2})
    end
})

TabTrading:CreateSection("Trade Log (Webhook)")

TabTrading:CreateToggle({
    Name="📤 Log Trades to Webhook", CurrentValue=false, Flag="LogTrades",
    Callback=function(Value)
        Settings.LogTrades = Value
        if Value then
            StartAutoTrade()
            Rayfield:Notify({Title="Vechnost",Content="Trade logging ON!",Duration=2})
        else
            Rayfield:Notify({Title="Vechnost",Content="Trade logging OFF",Duration=2})
        end
    end
})

TabTrading:CreateParagraph({
    Title   = "ℹ️ Info Trading",
    Content = "Auto Accept: Terima trade jika item yang kamu terima >= Min Rarity.\n\nAuto Decline: Tolak semua trade request.\n\nLog Trades: Kirim detail trade ke Discord webhook.\n\nPastikan Webhook URL sudah diisi di tab Webhook."
})

-- =====================================================
-- TAB 4: TELEPORT
-- =====================================================
local TabTeleport = Window:CreateTab("Teleport", "map-pin")

TabTeleport:CreateSection("Island & Location")

local TpOptions = {}
for _, loc in ipairs(TeleportLocations) do table.insert(TpOptions, loc.Name) end
local SelectedTpLocation = TeleportLocations[1].Name

TabTeleport:CreateDropdown({
    Name="📍 Select Location", Options=TpOptions,
    CurrentOption={TeleportLocations[1].Name}, MultipleOptions=false, Flag="TpLocation",
    Callback=function(Option) SelectedTpLocation=Option end
})

TabTeleport:CreateButton({
    Name="🚀 Teleport Now",
    Callback=function()
        for _, loc in ipairs(TeleportLocations) do
            if loc.Name == SelectedTpLocation then
                local ok = TeleportTo(loc.Position)
                Rayfield:Notify({
                    Title   = "Vechnost",
                    Content = ok and ("Teleported to "..loc.Name) or "Failed! Character not loaded.",
                    Duration = 2
                })
                return
            end
        end
        Rayfield:Notify({Title="Vechnost",Content="Location not found!",Duration=2})
    end
})

TabTeleport:CreateSection("Player Teleport")

local PlayerTpOptions = {}
local function RefreshPlayerList()
    PlayerTpOptions = {}
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then table.insert(PlayerTpOptions, p.Name) end
    end
    if #PlayerTpOptions == 0 then PlayerTpOptions = {"(no players)"} end
end
RefreshPlayerList()
Players.PlayerAdded:Connect(RefreshPlayerList)
Players.PlayerRemoving:Connect(RefreshPlayerList)

local SelectedPlayer = PlayerTpOptions[1]

TabTeleport:CreateDropdown({
    Name="👥 Select Player", Options=PlayerTpOptions,
    CurrentOption={PlayerTpOptions[1] or "(no players)"}, MultipleOptions=false, Flag="TpPlayer",
    Callback=function(Option) SelectedPlayer=Option end
})

TabTeleport:CreateButton({
    Name="🚀 Teleport to Selected Player",
    Callback=function()
        local target = Players:FindFirstChild(SelectedPlayer)
        if not target then
            Rayfield:Notify({Title="Vechnost",Content="Player not found!",Duration=2}); return
        end
        local ok = TeleportToPlayer(target)
        Rayfield:Notify({
            Title   = "Vechnost",
            Content = ok and ("Teleported to "..target.Name) or "Target has no character!",
            Duration = 2
        })
    end
})

TabTeleport:CreateButton({
    Name="🎲 Teleport to Random Player",
    Callback=function()
        local plrs = Players:GetPlayers()
        local targets = {}
        for _, p in pairs(plrs) do if p ~= LocalPlayer then table.insert(targets, p) end end
        if #targets == 0 then
            Rayfield:Notify({Title="Vechnost",Content="No other players!",Duration=2}); return
        end
        local target = targets[math.random(1, #targets)]
        local ok = TeleportToPlayer(target)
        Rayfield:Notify({
            Title   = "Vechnost",
            Content = ok and ("Teleported to "..target.Name) or "Target has no character!",
            Duration = 2
        })
    end
})

TabTeleport:CreateSection("Respawn")

TabTeleport:CreateButton({
    Name="🏠 Return to Spawn (Respawn)",
    Callback=function()
        local char = LocalPlayer.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then hum.Health=0 end
        end
        Rayfield:Notify({Title="Vechnost",Content="Respawning to spawn...",Duration=2})
    end
})

-- =====================================================
-- TAB 5: WEBHOOK
-- =====================================================
local TabWebhook = Window:CreateTab("Webhook", "webhook")

TabWebhook:CreateSection("Rarity Filter")

TabWebhook:CreateDropdown({
    Name="🎯 Filter by Rarity", Options=RarityList, CurrentOption={},
    MultipleOptions=true, Flag="RarityFilter",
    Callback=function(Options)
        Settings.SelectedRarities = {}
        for _, value in ipairs(Options or {}) do
            local tier = RARITY_NAME_TO_TIER[value]
            if tier then Settings.SelectedRarities[tier]=true end
        end
        local msg = next(Settings.SelectedRarities)==nil and "Filter: Semua rarity" or "Rarity filter diperbarui"
        Rayfield:Notify({Title="Vechnost",Content=msg,Duration=2})
    end
})

TabWebhook:CreateSection("Setup Webhook")

local WebhookUrlBuffer = ""

TabWebhook:CreateInput({
    Name="Discord Webhook URL", CurrentValue="",
    PlaceholderText="https://discord.com/api/webhooks/...",
    RemoveTextAfterFocusLost=false, Flag="WebhookUrl",
    Callback=function(Text) WebhookUrlBuffer=tostring(Text) end
})

TabWebhook:CreateButton({
    Name="💾 Save Webhook URL",
    Callback=function()
        local url = WebhookUrlBuffer:gsub("%s+","")
        if not url:match("^https://discord.com/api/webhooks/")
        and not url:match("^https://canary.discord.com/api/webhooks/") then
            Rayfield:Notify({Title="Vechnost",Content="URL webhook tidak valid!",Duration=3}); return
        end
        Settings.Url = url
        Rayfield:Notify({Title="Vechnost",Content="✅ Webhook URL saved!",Duration=2})
    end
})

TabWebhook:CreateSection("Logger Mode")

TabWebhook:CreateToggle({
    Name="🌐 Server-Notifier Mode", CurrentValue=true, Flag="ServerNotifierMode",
    Callback=function(Value)
        Settings.ServerWide = Value
        Rayfield:Notify({
            Title="Vechnost",
            Content=Value and "Mode: Seluruh Server" or "Mode: Hanya Lokal",
            Duration=2
        })
    end
})

TabWebhook:CreateSection("Control")

TabWebhook:CreateToggle({
    Name="✅ Enable Webhook Logger", CurrentValue=false, Flag="LoggerEnabled",
    Callback=function(Value)
        if Value then
            if Settings.Url=="" then
                Rayfield:Notify({Title="Vechnost",Content="Isi webhook URL dulu!",Duration=3}); return
            end
            StartLogger()
            Rayfield:Notify({Title="Vechnost",Content="🟢 Notifier Aktif!",Duration=2})
        else
            StopLogger()
            Rayfield:Notify({Title="Vechnost",Content="🔴 Notifier Berhenti",Duration=2})
        end
    end
})

local WebhookStatusLabel = TabWebhook:CreateParagraph({Title="Notifier Status",Content="Status: Offline"})

task.spawn(function()
    while true do
        task.wait(2)
        pcall(function()
            if WebhookStatusLabel then
                if Settings.Active then
                    WebhookStatusLabel:Set({
                        Title   = "📡 Notifier Status",
                        Content = string.format(
                            "Status: 🟢 Aktif\nMode: %s\nTotal Log: %d ikan\nWebhook: %s",
                            Settings.ServerWide and "Server-Notifier" or "Local Only",
                            Settings.LogCount,
                            Settings.Url~="" and "✅ Set" or "❌ Kosong"
                        )
                    })
                else
                    WebhookStatusLabel:Set({
                        Title="📡 Notifier Status",
                        Content="Status: 🔴 Offline\nWebhook: "..(Settings.Url~="" and "✅ Set" or "❌ Kosong")
                    })
                end
            end
        end)
    end
end)

TabWebhook:CreateSection("Testing")

TabWebhook:CreateButton({
    Name="🧪 Send Test Message",
    Callback=function()
        if Settings.Url=="" then
            Rayfield:Notify({Title="Vechnost",Content="Isi webhook URL dulu!",Duration=3}); return
        end
        task.spawn(function() SendWebhook(BuildTestPayload(LocalPlayer.Name)) end)
        Rayfield:Notify({Title="Vechnost",Content="Test message terkirim!",Duration=2})
    end
})

TabWebhook:CreateButton({
    Name="🔄 Reset Log Counter",
    Callback=function()
        Settings.LogCount=0; Settings.SentUUID={}
        Rayfield:Notify({Title="Vechnost",Content="Counter di-reset!",Duration=2})
    end
})

-- =====================================================
-- TAB 6: CONFIG
-- =====================================================
local TabConfig = Window:CreateTab("Config", "settings")

TabConfig:CreateSection("Movement")

TabConfig:CreateSlider({
    Name="🏃 Walk Speed", Range={16,500}, Increment=1, Suffix="",
    CurrentValue=16, Flag="WalkSpeed",
    Callback=function(Value) Settings.WalkSpeed=Value; SetWalkSpeed(Value) end
})

TabConfig:CreateSlider({
    Name="🦘 Jump Power", Range={50,500}, Increment=5, Suffix="",
    CurrentValue=50, Flag="JumpPower",
    Callback=function(Value) Settings.JumpPower=Value; SetJumpPower(Value) end
})

TabConfig:CreateToggle({
    Name="♾️ Infinite Jump", CurrentValue=false, Flag="InfJump",
    Callback=function(Value)
        Settings.InfJump=Value
        if Value then StartInfJump(); Rayfield:Notify({Title="Vechnost",Content="Infinite Jump ON!",Duration=2})
        else StopInfJump(); Rayfield:Notify({Title="Vechnost",Content="Infinite Jump OFF",Duration=2}) end
    end
})

TabConfig:CreateButton({
    Name="🔄 Reset Speed & Jump",
    Callback=function()
        Settings.WalkSpeed=16; Settings.JumpPower=50
        SetWalkSpeed(16); SetJumpPower(50)
        Rayfield:Notify({Title="Vechnost",Content="Speed & Jump reset!",Duration=2})
    end
})

TabConfig:CreateSection("Utility")

TabConfig:CreateToggle({
    Name="🤖 Anti-AFK", CurrentValue=false, Flag="AntiAFK",
    Callback=function(Value)
        Settings.AntiAFK=Value
        if Value then StartAntiAFK(); Rayfield:Notify({Title="Vechnost",Content="Anti-AFK ON!",Duration=2})
        else StopAntiAFK(); Rayfield:Notify({Title="Vechnost",Content="Anti-AFK OFF",Duration=2}) end
    end
})

TabConfig:CreateToggle({
    Name="👁️ Player ESP", CurrentValue=false, Flag="ESP",
    Callback=function(Value)
        Settings.ESP_Enabled=Value
        if Value then StartESP(); Rayfield:Notify({Title="Vechnost",Content="ESP ON!",Duration=2})
        else StopESP(); Rayfield:Notify({Title="Vechnost",Content="ESP OFF",Duration=2}) end
    end
})

TabConfig:CreateToggle({
    Name="🌙 Remove Fog", CurrentValue=false, Flag="RemoveFog",
    Callback=function(Value)
        Settings.RemoveFog=Value
        pcall(function()
            local L = game:GetService("Lighting")
            if Value then L.FogEnd=100000; L.FogStart=99999
            else L.FogEnd=100000; L.FogStart=0 end
        end)
        Rayfield:Notify({Title="Vechnost",Content=Value and "Fog removed!" or "Fog restored",Duration=2})
    end
})

TabConfig:CreateSection("Tentang")

TabConfig:CreateParagraph({
    Title   = "Vechnost Hub v2.0",
    Content = "Fish It All-in-One Hub\n\n✅ Auto Fish (Perfect)\n✅ Auto Sell\n✅ Auto Trade + Webhook Log\n✅ Teleport Islands, NPC, Player\n✅ Server-Wide Webhook\n✅ ESP Players\n✅ Anti-AFK\n✅ Speed & Jump\n✅ Remove Fog\n✅ Config Save/Load\n\nby Vechnost | discord.gg/vechnost"
})

TabConfig:CreateButton({
    Name="💾 Save Config",
    Callback=function()
        Rayfield:Notify({Title="Vechnost",Content="Config tersimpan!",Duration=2})
    end
})

TabConfig:CreateButton({
    Name="🗑️ Reset Config",
    Callback=function()
        pcall(function() Rayfield:ClearConfiguration() end)
        Rayfield:Notify({Title="Vechnost",Content="Config direset! Restart script.",Duration=3})
    end
})

-- =====================================================
-- BAGIAN 22: INIT
-- =====================================================
Rayfield:LoadConfiguration()

warn("[Vechnost] Hub v2.0 Loaded!")
warn("[Vechnost] Tabs: INFO | FISHING | TRADING | TELEPORT | WEBHOOK | CONFIG")
warn("[Vechnost] Toggle GUI: tekan V atau tap tombol floating")
