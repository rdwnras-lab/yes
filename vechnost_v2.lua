--[[
    FILE: vechnost_v3.lua
    BRAND: Vechnost
    VERSION: 3.0.0
    DESC: Fish It - Webhook Logger + Auto Trading System
          BAC (Blox Anti Cheat) Bypass included
          Uses RF/CanSendTrade (correct Fish It remote)
          Sidebar navigation (Webhook | Trading | Settings)
]]

-- =====================================================
-- BAGIAN 0: BAC BYPASS SYSTEM
-- =====================================================
-- Blox Anti Cheat mendeteksi: getfenv, hookfunction,
-- metatable hooks, dan suspicious remote fire patterns.
-- Bypass: localize semua globals, random delays,
-- SafeFire wrapper, task.defer untuk break stack trace.

local _rawget    = rawget
local _rawset    = rawset
local _pairs     = pairs
local _ipairs    = ipairs
local _pcall     = pcall
local _tostring  = tostring
local _type      = type
local _math      = math
local _string    = string
local _table     = table
local _task      = task
local _game      = game
local _workspace = workspace

-- Random delay helper: humanizes timing agar BAC tidak detect pattern
local function RandDelay(base, variance)
    variance = variance or 0.15
    return base + (_math.random() * variance * 2) - variance
end

-- SafeFire: wrap remote call dalam task.spawn + pcall
-- Ini break call-stack chain yang BAC gunakan untuk detect exploit
local function SafeFire(remote, ...)
    if not remote then return false end
    local args = {...}
    local success = false
    local done    = false
    _task.spawn(function()
        _task.wait(RandDelay(0.04, 0.02))
        _pcall(function()
            if remote:IsA("RemoteFunction") then
                remote:InvokeServer(_table.unpack(args))
            else
                remote:FireServer(_table.unpack(args))
            end
            success = true
        end)
        done = true
    end)
    local t = 0
    repeat _task.wait(0.05); t = t + 0.05 until done or t >= 3
    return success
end

-- =====================================================
-- BAGIAN 1: CLEANUP SYSTEM
-- =====================================================
local CoreGui   = _game:GetService("CoreGui")
local GUI_NAMES = { Main="Vechnost_Main_UI", Mobile="Vechnost_Mobile_Button" }

for _, v in _pairs(CoreGui:GetChildren()) do
    for _, name in _pairs(GUI_NAMES) do
        if v.Name == name then _pcall(function() v:Destroy() end) end
    end
end

-- =====================================================
-- BAGIAN 2: SERVICES & GLOBALS
-- =====================================================
local Players           = _game:GetService("Players")
local ReplicatedStorage = _game:GetService("ReplicatedStorage")
local HttpService       = _game:GetService("HttpService")
local RunService        = _game:GetService("RunService")
local UserInputService  = _game:GetService("UserInputService")
local TextChatService   = _game:GetService("TextChatService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- =====================================================
-- BAGIAN 3: LOAD GAME REMOTES
-- =====================================================
local net, ObtainedNewFish, CanSendTradeRemote

do
    _pcall(function()
        net = ReplicatedStorage
            :WaitForChild("Packages", 10)
            :WaitForChild("_Index", 5)
            :WaitForChild("sleitnick_net@0.2.0", 5)
            :WaitForChild("net", 5)
        ObtainedNewFish = net:WaitForChild("RE/ObtainedNewFishNotification", 5)
    end)

    -- Load RF/CanSendTrade (confirmed dari console Fish It)
    if net then
        _pcall(function()
            CanSendTradeRemote = net:WaitForChild("RF/CanSendTrade", 5)
            if CanSendTradeRemote then
                warn("[Vechnost] Trade remote loaded: RF/CanSendTrade")
            end
        end)
    end

    -- Fallback scan jika nama berubah
    if not CanSendTradeRemote and net then
        _pcall(function()
            for _, child in _ipairs(net:GetDescendants()) do
                if child:IsA("RemoteFunction") or child:IsA("RemoteEvent") then
                    local ln = _string.lower(child.Name)
                    if ln:find("trade") or ln:find("senditem") or ln:find("giveitem") then
                        CanSendTradeRemote = child
                        warn("[Vechnost] Trade remote (scan):", child.Name)
                        break
                    end
                end
            end
        end)
    end

    if not CanSendTradeRemote then
        warn("[Vechnost] WARNING: Trade remote tidak ditemukan")
    end
end

-- =====================================================
-- BAGIAN 4: LOAD RAYFIELD
-- =====================================================
local Rayfield
do
    local ok, result = _pcall(function()
        return loadstring(_game:HttpGet("https://sirius.menu/rayfield"))()
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
-- BAGIAN 5: FISH DATABASE
-- =====================================================
local FishDB       = {}  -- [id] = {Name, Tier, Icon, SellPrice, ItemType}
local FishNameToId = {}  -- [name/lowercase] = id

do
    _pcall(function()
        local Items = ReplicatedStorage:WaitForChild("Items", 10)
        if not Items then return end
        for _, module in _ipairs(Items:GetChildren()) do
            if module:IsA("ModuleScript") then
                local ok2, mod = _pcall(require, module)
                if ok2 and mod and mod.Data then
                    local d = mod.Data
                    if d.Id and d.Name then
                        FishDB[d.Id] = {
                            Name      = d.Name,
                            Tier      = d.Tier or 0,
                            Icon      = d.Icon,
                            SellPrice = d.SellPrice or d.Value or d.Price or d.Worth or 0,
                            ItemType  = d.Type or "Unknown",
                        }
                        FishNameToId[d.Name]                    = d.Id
                        FishNameToId[_string.lower(d.Name)]     = d.Id
                    end
                end
            end
        end
    end)
    local count = 0
    for _ in _pairs(FishDB) do count = count + 1 end
    warn("[Vechnost] FishDB:", count, "items")
end

-- =====================================================
-- BAGIAN 6: REPLION PLAYER DATA
-- =====================================================
local PlayerData = nil
do
    _pcall(function()
        local Replion = require(ReplicatedStorage.Packages.Replion)
        PlayerData = Replion.Client:WaitReplion("Data")
        if PlayerData then warn("[Vechnost] Replion PlayerData OK") end
    end)
end

-- =====================================================
-- BAGIAN 7: RARITY SYSTEM
-- =====================================================
local RARITY_MAP = {
    [1]="Common", [2]="Uncommon", [3]="Rare",   [4]="Epic",
    [5]="Legendary", [6]="Mythic", [7]="Secret",
}
local RARITY_NAME_TO_TIER = {
    Common=1, Uncommon=2, Rare=3, Epic=4, Legendary=5, Mythic=6, Secret=7,
}
local RarityList = {"Common","Uncommon","Rare","Epic","Legendary","Mythic","Secret"}

-- =====================================================
-- BAGIAN 8: HTTP REQUEST (multi-executor compatible)
-- =====================================================
local HttpRequest =
    (syn and syn.request)
    or http_request or request
    or (fluxus and fluxus.request)
    or (krnl and krnl.request)
    or (getgenv and getgenv().request)

if not HttpRequest then warn("[Vechnost][FATAL] HttpRequest tidak tersedia") end

-- =====================================================
-- BAGIAN 9: HELPERS
-- =====================================================
local function FormatNumber(n)
    if not n or _type(n) ~= "number" then return "0" end
    local s = _tostring(_math.floor(n))
    local k
    repeat s, k = _string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
    return s
end

local function IsRarityAllowed(fishId, allowedRarities)
    local fish = FishDB[fishId]; if not fish then return false end
    if not allowedRarities or not next(allowedRarities) then return true end
    return allowedRarities[fish.Tier] == true
end

local function ResolvePlayerName(arg)
    if typeof(arg) == "Instance" and arg:IsA("Player") then return arg.Name end
    if _type(arg) == "string" then return arg end
    if _type(arg) == "table" and arg.Name then return _tostring(arg.Name) end
    return LocalPlayer.Name
end

local function ExtractMutation(weightData, item)
    local mutation
    if weightData and _type(weightData) == "table" then
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

-- =====================================================
-- BAGIAN 10: INVENTORY SCAN (Fixed - handles semua format)
-- =====================================================
local STONE_LIST  = {"Enchant Stone", "Evolved Stone"}
local STONE_LOWER = {}
for _, s in _ipairs(STONE_LIST) do STONE_LOWER[_string.lower(s)] = s end

local function ScanInventory()
    local result = { items={}, stones={} }

    local function classifyItem(name, id)
        if not name then return end
        local lname     = _string.lower(name)
        local stoneCanon = STONE_LOWER[lname]
        if stoneCanon then
            result.stones[stoneCanon] = (result.stones[stoneCanon] or 0) + 1
        else
            -- Juga cek nama mengandung "stone" / "enchant" / "evolv"
            if lname:find("stone") or lname:find("enchant") or lname:find("evolv") then
                result.stones[name] = (result.stones[name] or 0) + 1
            else
                result.items[name] = (result.items[name] or 0) + 1
            end
        end
    end

    -- Method 1: Replion PlayerData
    if PlayerData then
        _pcall(function()
            local invData = nil
            for _, key in _ipairs({"Inventory","Backpack","Items","FishInventory","Pack"}) do
                local ok, val = _pcall(function() return PlayerData:Get(key) end)
                if ok and val and _type(val) == "table" then invData = val; break end
            end
            if not invData then
                _pcall(function()
                    if PlayerData.GetData then
                        local all = PlayerData:GetData()
                        if all then invData = all.Inventory or all.Backpack or all.Items end
                    end
                end)
            end
            if not invData then return end

            local function processEntry(entry)
                if _type(entry) ~= "table" then return end
                local name = nil
                local id   = entry.Id or entry.ItemId or entry.FishId
                if id and FishDB[id] then
                    name = FishDB[id].Name
                elseif entry.Name then
                    name = _tostring(entry.Name)
                end
                classifyItem(name, id)
            end

            local itemsTable = invData.Items or invData
            if _type(itemsTable) == "table" then
                for _, entry in _pairs(itemsTable) do
                    processEntry(entry)
                end
            end
        end)
    end

    -- Method 2: Scan backpack attribute
    if not next(result.items) and not next(result.stones) then
        _pcall(function()
            local bp = LocalPlayer:FindFirstChild("Backpack")
                or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Backpack"))
            if bp then
                for _, item in _ipairs(bp:GetChildren()) do
                    classifyItem(item.Name, nil)
                end
            end
        end)
    end

    -- Method 3: FishDB fallback (shows possible items, count=0)
    if not next(result.items) then
        for _, data in _pairs(FishDB) do
            if data.Tier and data.Tier > 0 then
                local lname = _string.lower(data.Name)
                if not lname:find("stone") and not lname:find("enchant") and not lname:find("evolv") then
                    result.items[data.Name] = result.items[data.Name] or 0
                end
            end
        end
    end

    local fc, sc = 0, 0
    for _ in _pairs(result.items)  do fc = fc + 1 end
    for _ in _pairs(result.stones) do sc = sc + 1 end
    warn("[Vechnost] Inventory: "..fc.." fish, "..sc.." stones")
    return result
end

-- =====================================================
-- BAGIAN 11: ICON CACHE
-- =====================================================
local IconCache  = {}
local IconWaiter = {}

local function FetchFishIconAsync(fishId, callback)
    if IconCache[fishId] then callback(IconCache[fishId]); return end
    if IconWaiter[fishId] then _table.insert(IconWaiter[fishId], callback); return end
    IconWaiter[fishId] = {callback}
    _task.spawn(function()
        local fish = FishDB[fishId]
        if not fish or not fish.Icon then callback(""); return end
        local assetId = _tostring(fish.Icon):match("%d+")
        if not assetId then callback(""); return end
        local api = ("https://thumbnails.roblox.com/v1/assets?assetIds=%s&size=420x420&format=Png"):format(assetId)
        local ok, res = _pcall(function() return HttpRequest({Url=api, Method="GET"}) end)
        if not ok or not res or not res.Body then callback(""); return end
        local ok2, data = _pcall(HttpService.JSONDecode, HttpService, res.Body)
        local url = ok2 and data and data.data and data.data[1] and data.data[1].imageUrl or ""
        IconCache[fishId] = url
        for _, cb in _ipairs(IconWaiter[fishId]) do cb(url) end
        IconWaiter[fishId] = nil
    end)
end

-- =====================================================
-- BAGIAN 12: WEBHOOK ENGINE
-- =====================================================
local Settings = {
    Active=false, Url="", SentUUID={},
    SelectedRarities={}, ServerWide=true, LogCount=0,
}

local function BuildPayload(playerName, fishId, weight, mutation)
    local fish = FishDB[fishId]; if not fish then return nil end
    local tier       = fish.Tier
    local rarityName = RARITY_MAP[tier] or "Unknown"
    local mutText    = mutation and _tostring(mutation) or "None"
    local weightText = _string.format("%.1fkg", weight or 0)
    local iconUrl    = IconCache[fishId] or ""
    return {
        username="Vechnost Notifier",
        avatar_url="https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png",
        flags=32768,
        components={{type=17, components={
            {type=10, content="# NEW FISH CAUGHT!"},
            {type=14, spacing=1, divider=true},
            {type=10, content="__@"..(playerName or "?").." you got new ".._string.upper(rarityName).." fish__"},
            {type=9,
                components={{type=10,content="**Fish Name**"},{type=10,content="> "..(fish.Name or "?")}},
                accessory = iconUrl~="" and {type=11,media={url=iconUrl}} or nil
            },
            {type=10,content="**Tier**"}, {type=10,content="> ".._string.upper(rarityName)},
            {type=10,content="**Weight**"}, {type=10,content="> "..weightText},
            {type=10,content="**Mutation**"}, {type=10,content="> "..mutText},
            {type=14,spacing=1,divider=true},
            {type=10,content="> discord.gg/vechnost"},
            {type=10,content="-# "..os.date("!%B %d, %Y")},
        }}}
    }
end

local function BuildActivationPayload(playerName, mode)
    return {
        username="Vechnost Notifier",
        avatar_url="https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png",
        flags=32768,
        components={{type=17,accent_color=0x30ff6a,components={
            {type=10,content="**"..playerName.." Webhook Activated!**"},
            {type=14,spacing=1,divider=true},
            {type=10,content="### Vechnost v3.0"},
            {type=10,content="- **Account:** "..playerName.."\n- **Mode:** "..mode.."\n- **Status:** Online"},
            {type=14,spacing=1,divider=true},
            {type=10,content="-# "..os.date("!%B %d, %Y")},
        }}}
    }
end

local function BuildTestPayload(playerName)
    return {
        username="Vechnost Notifier",
        avatar_url="https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png",
        flags=32768,
        components={{type=17,accent_color=0x5865f2,components={
            {type=10,content="**Test Message**"},
            {type=14,spacing=1,divider=true},
            {type=10,content="Webhook OK!\n- **Dari:** "..playerName},
            {type=14,spacing=1,divider=true},
            {type=10,content="-# "..os.date("!%B %d, %Y")},
        }}}
    }
end

local function SendWebhook(payload)
    if Settings.Url=="" or not HttpRequest or not payload then return end
    _pcall(function()
        local url = Settings.Url..(Settings.Url:find("?") and "&" or "?").."with_components=true"
        HttpRequest({Url=url, Method="POST",
            Headers={["Content-Type"]="application/json"},
            Body=HttpService:JSONEncode(payload)})
    end)
end

-- =====================================================
-- BAGIAN 13: FISH DETECTION (Server-Wide Logger)
-- =====================================================
local Connections   = {}
local ChatSentDedup = {}

local function ParseChatForFish(messageText)
    if not Settings.Active or not Settings.ServerWide then return end
    local playerName, fishName, weightStr =
        messageText:match("(%S+)%s+obtained%s+a%s+(.-)%s*%(([%d%.]+)kg%)")
    if not playerName then
        playerName,fishName,weightStr = messageText:match("(%S+)%s+obtained%s+(.-)%s*%(([%d%.]+)kg%)")
    end
    if not playerName or not fishName then return end
    fishName = fishName:gsub("%s+$","")
    if playerName==LocalPlayer.Name or playerName==LocalPlayer.DisplayName then return end
    local fishId = FishNameToId[fishName] or FishNameToId[_string.lower(fishName)]
    if not fishId then return end
    if not IsRarityAllowed(fishId, Settings.SelectedRarities) then return end
    local key = playerName..fishName.._tostring(_math.floor(os.time()/2))
    if ChatSentDedup[key] then return end
    ChatSentDedup[key] = true
    _task.delay(10, function() ChatSentDedup[key]=nil end)
    local weight = tonumber(weightStr) or 0
    Settings.LogCount = Settings.LogCount + 1
    FetchFishIconAsync(fishId, function() SendWebhook(BuildPayload(playerName,fishId,weight,nil)) end)
end

local function HandleFishCaught(playerArg, weightData, wrapper)
    if not Settings.Active then return end
    local item = nil
    if wrapper and _type(wrapper)=="table" and wrapper.InventoryItem then item=wrapper.InventoryItem end
    if not item and weightData and _type(weightData)=="table" and weightData.InventoryItem then item=weightData.InventoryItem end
    if not item or not item.Id or not item.UUID then return end
    if not FishDB[item.Id] then return end
    if not IsRarityAllowed(item.Id, Settings.SelectedRarities) then return end
    if Settings.SentUUID[item.UUID] then return end
    Settings.SentUUID[item.UUID] = true
    local playerName = ResolvePlayerName(playerArg)
    if not Settings.ServerWide and playerName~=LocalPlayer.Name then return end
    local weight   = (weightData and _type(weightData)=="table" and weightData.Weight) or 0
    local mutation = ExtractMutation(weightData, item)
    Settings.LogCount = Settings.LogCount + 1
    FetchFishIconAsync(item.Id, function() SendWebhook(BuildPayload(playerName,item.Id,weight,mutation)) end)
end

local function StartLogger()
    if Settings.Active then return end
    if not net or not ObtainedNewFish then
        Rayfield:Notify({Title="Vechnost", Content="ERROR: Game remotes not found!", Duration=5}); return
    end
    Settings.Active=true; Settings.SentUUID={}; Settings.LogCount=0
    if Settings.ServerWide then
        _pcall(function()
            Connections[#Connections+1] = TextChatService.MessageReceived:Connect(function(msg)
                _pcall(function()
                    if msg.Text and msg.Text:find("obtained") then ParseChatForFish(msg.Text) end
                end)
            end)
        end)
    end
    _pcall(function()
        Connections[#Connections+1] = ObtainedNewFish.OnClientEvent:Connect(function(p,w,r)
            HandleFishCaught(p,w,r)
        end)
    end)
    if Settings.ServerWide then
        _pcall(function()
            Connections[#Connections+1] = PlayerGui.DescendantAdded:Connect(function(desc)
                if not Settings.Active then return end
                if desc:IsA("TextLabel") then
                    _task.defer(function()
                        _pcall(function()
                            local text = desc.Text or ""
                            for fishId, fishData in _pairs(FishDB) do
                                if fishData.Name and text:find(fishData.Name, 1, true) then
                                    if not IsRarityAllowed(fishId, Settings.SelectedRarities) then return end
                                    local pName = "Unknown"
                                    for _, p in _pairs(Players:GetPlayers()) do
                                        if p~=LocalPlayer and (text:find(p.Name,1,true) or text:find(p.DisplayName,1,true)) then
                                            pName=p.Name; break
                                        end
                                    end
                                    if pName=="Unknown" then return end
                                    local key = "GUI_"..text..os.time()
                                    if Settings.SentUUID[key] then return end
                                    Settings.SentUUID[key]=true
                                    Settings.LogCount=Settings.LogCount+1
                                    FetchFishIconAsync(fishId, function() SendWebhook(BuildPayload(pName,fishId,0,nil)) end)
                                    return
                                end
                            end
                        end)
                    end)
                end
            end)
        end)
    end
    _task.spawn(function()
        SendWebhook(BuildActivationPayload(LocalPlayer.Name, Settings.ServerWide and "Server Notifier" or "Local Only"))
    end)
    warn("[Vechnost] Logger ENABLED")
end

local function StopLogger()
    Settings.Active=false
    for _,conn in _ipairs(Connections) do _pcall(function() conn:Disconnect() end) end
    Connections={}
    warn("[Vechnost] Logger DISABLED | Total:", Settings.LogCount)
end

-- =====================================================
-- BAGIAN 14: TRADING ENGINE
-- =====================================================
-- RF/CanSendTrade = RemoteFunction yang dikonfirmasi dari console
-- BAC bypass: SafeFire + random delay antar trade

local TradeState = {
    TargetPlayer = nil,
    ByName   = {Active=false, ItemName=nil,  Amount=1, Sent=0},
    ByCoin   = {Active=false, TargetCoins=0, Sent=0},
    ByRarity = {Active=false, Rarity=nil, RarityTier=1, Amount=1, Sent=0},
    ByStone  = {Active=false, StoneName=nil, Amount=1, Sent=0},
}

local InvCache = {items={}, stones={}}

local function RefreshInvCache()
    InvCache = ScanInventory()
end

local function GetItemNames()
    local names = {}
    for name in _pairs(InvCache.items) do _table.insert(names, name) end
    _table.sort(names)
    return #names > 0 and names or {"(Refresh dulu)"}
end

local function GetItemsByTier(tier)
    local names = {}
    for name, count in _pairs(InvCache.items) do
        if count > 0 then
            local id = FishNameToId[name] or FishNameToId[_string.lower(name)]
            if id and FishDB[id] and FishDB[id].Tier == tier then
                for _ = 1, count do _table.insert(names, name) end
            end
        end
    end
    if #names == 0 then
        for _, data in _pairs(FishDB) do
            if data.Tier == tier then _table.insert(names, data.Name) end
        end
    end
    return names
end

-- Core trade function - menggunakan RF/CanSendTrade
local function DoSendTrade(targetUsername, itemNameOrId, quantity)
    quantity = quantity or 1
    local targetPlayer = nil
    for _, p in _pairs(Players:GetPlayers()) do
        if p.Name==targetUsername or p.DisplayName==targetUsername then
            targetPlayer=p; break
        end
    end
    if not targetPlayer then
        warn("[Vechnost] Trade: player tidak ditemukan:", targetUsername)
        return false
    end

    local fishId = FishNameToId[itemNameOrId]
                or FishNameToId[_string.lower(_tostring(itemNameOrId))]
                or itemNameOrId

    -- Primary: RF/CanSendTrade
    if CanSendTradeRemote then
        SafeFire(CanSendTradeRemote, targetPlayer, fishId, quantity)
        return true
    end

    -- Fallback scan
    if net then
        _pcall(function()
            for _, child in _ipairs(net:GetDescendants()) do
                if child:IsA("RemoteFunction") or child:IsA("RemoteEvent") then
                    local ln = _string.lower(child.Name)
                    if ln:find("trade") or ln:find("send") or ln:find("give") then
                        SafeFire(child, targetPlayer, fishId, quantity)
                        break
                    end
                end
            end
        end)
    end
    return true
end

-- =====================================================
-- BAGIAN 15: RAYFIELD WINDOW
-- =====================================================
local Window = Rayfield:CreateWindow({
    Name                 = "Vechnost",
    Icon                 = "fish",
    LoadingTitle         = "Vechnost v3.0",
    LoadingSubtitle      = "Webhook + Trading System",
    Theme                = "Default",
    ToggleUIKeybind      = "V",
    DisableRayfieldPrompts = true,
    DisableBuildWarnings   = true,
    ConfigurationSaving  = {Enabled=true, FolderName="Vechnost", FileName="VechnostConfig_v3"},
    KeySystem            = true,
    KeySettings          = {
        Title    = "Vechnost Access",
        Subtitle = "Authentication Required",
        Note     = "Join discord: discord.gg/vechnost",
        FileName = "VechnostKey",
        SaveKey  = true,
        GrabKeyFromSite = false,
        Key      = {"Vechnost-Notifier-9999"},
    },
})

-- =====================================================
-- BAGIAN 16: FLOATING TOGGLE BUTTON
-- =====================================================
local oldBtn = CoreGui:FindFirstChild(GUI_NAMES.Mobile)
if oldBtn then oldBtn:Destroy() end
local BtnGui = Instance.new("ScreenGui")
BtnGui.Name=GUI_NAMES.Mobile; BtnGui.ResetOnSpawn=false; BtnGui.Parent=CoreGui

local Button = Instance.new("ImageButton")
Button.Size=UDim2.fromOffset(52,52); Button.Position=UDim2.fromScale(0.05,0.5)
Button.BackgroundTransparency=1; Button.AutoButtonColor=false; Button.BorderSizePixel=0
Button.Image="rbxassetid://127239715511367"; Button.ScaleType=Enum.ScaleType.Fit
Button.Parent=BtnGui
Instance.new("UICorner",Button).CornerRadius=UDim.new(1,0)

local windowVisible=true
Button.MouseButton1Click:Connect(function()
    windowVisible=not windowVisible
    _pcall(function() Rayfield:SetVisibility(windowVisible) end)
end)
local dragging,dragOffset=false,Vector2.zero
Button.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1
    or input.UserInputType==Enum.UserInputType.Touch then
        dragging=true; dragOffset=UserInputService:GetMouseLocation()-Button.AbsolutePosition
        input.Changed:Connect(function()
            if input.UserInputState==Enum.UserInputState.End then dragging=false end
        end)
    end
end)
RunService.RenderStepped:Connect(function()
    if not dragging then return end
    local mouse=UserInputService:GetMouseLocation()
    local target=mouse-dragOffset
    local vp=_workspace.CurrentCamera and _workspace.CurrentCamera.ViewportSize or Vector2.new(1920,1080)
    local sz=Button.AbsoluteSize
    Button.Position=UDim2.fromOffset(
        _math.clamp(target.X,0,vp.X-sz.X),
        _math.clamp(target.Y,0,vp.Y-sz.Y))
end)

-- =====================================================
-- BAGIAN 17: TABS (urutan sidebar: Webhook | Trading | Settings)
-- =====================================================
local TabWebhook  = Window:CreateTab("Webhook Logger",  "webhook")
local TabTrading  = Window:CreateTab("Trading",         "arrow-right-left")
local TabSettings = Window:CreateTab("Settings",        "settings")

-- ===========================================================
-- TAB 1 - WEBHOOK LOGGER
-- ===========================================================
TabWebhook:CreateSection("Rarity Filter")
TabWebhook:CreateDropdown({
    Name="Filter by Rarity", Options=RarityList, CurrentOption={},
    MultipleOptions=true, Flag="RarityFilter",
    Callback=function(Options)
        Settings.SelectedRarities={}
        for _,v in _ipairs(Options or {}) do
            local tier=RARITY_NAME_TO_TIER[v]
            if tier then Settings.SelectedRarities[tier]=true end
        end
        Rayfield:Notify({Title="Vechnost",Content="Filter rarity diperbarui",Duration=2})
    end
})

TabWebhook:CreateSection("Setup Webhook")
local WebhookUrlBuffer=""
TabWebhook:CreateInput({
    Name="Discord Webhook URL", CurrentValue="",
    PlaceholderText="https://discord.com/api/webhooks/...",
    RemoveTextAfterFocusLost=false, Flag="WebhookUrl",
    Callback=function(Text) WebhookUrlBuffer=_tostring(Text) end
})
TabWebhook:CreateButton({
    Name="Save Webhook URL",
    Callback=function()
        local url=WebhookUrlBuffer:gsub("%s+","")
        if not url:match("^https://discord.com/api/webhooks/") and
           not url:match("^https://canary.discord.com/api/webhooks/") then
            Rayfield:Notify({Title="Vechnost",Content="URL tidak valid!",Duration=3}); return
        end
        Settings.Url=url
        Rayfield:Notify({Title="Vechnost",Content="Webhook URL saved!",Duration=2})
    end
})

TabWebhook:CreateSection("Logger Mode")
TabWebhook:CreateToggle({
    Name="Server-Notifier Mode", CurrentValue=true, Flag="ServerNotifierMode",
    Callback=function(Value)
        Settings.ServerWide=Value
        Rayfield:Notify({Title="Vechnost",Content=Value and "Mode: Server Wide" or "Mode: Local Only",Duration=2})
    end
})

TabWebhook:CreateSection("Control")
TabWebhook:CreateToggle({
    Name="Enable Webhook Logger", CurrentValue=false, Flag="LoggerEnabled",
    Callback=function(Value)
        if Value then
            if Settings.Url=="" then
                Rayfield:Notify({Title="Vechnost",Content="Isi webhook URL dulu!",Duration=3}); return
            end
            StartLogger()
            Rayfield:Notify({Title="Vechnost",Content="Notifier Aktif!",Duration=2})
        else
            StopLogger()
            Rayfield:Notify({Title="Vechnost",Content="Notifier Berhenti",Duration=2})
        end
    end
})

local StatusLabelWebhook = TabWebhook:CreateParagraph({Title="Notifier Status",Content="Status: Offline"})
_task.spawn(function()
    while true do
        _task.wait(2)
        _pcall(function()
            if Settings.Active then
                StatusLabelWebhook:Set({Title="Notifier Status",Content=_string.format(
                    "Status: Aktif\nMode: %s\nTotal Log: %d ikan",
                    Settings.ServerWide and "Server-Notifier" or "Local Only", Settings.LogCount)})
            else
                StatusLabelWebhook:Set({Title="Notifier Status",Content="Status: Offline"})
            end
        end)
    end
end)

-- ===========================================================
-- TAB 2 - TRADING
-- ===========================================================

-- ---- SELECT PLAYER ----
TabTrading:CreateSection("Select Player")

local PlayerDropdown = TabTrading:CreateDropdown({
    Name="Select Player", Options={"(Loading...)"}, CurrentOption={"(Loading...)"},
    MultipleOptions=false, Flag="TradingTargetPlayer",
    Callback=function(Option)
        local sel=_type(Option)=="table" and Option[1] or Option
        if sel and sel~="(Loading...)" and sel~="(Tidak ada player)" then
            TradeState.TargetPlayer=sel
            Rayfield:Notify({Title="Vechnost",Content="Target: "..sel,Duration=2})
        end
    end
})

local function RefreshPlayerList()
    local list={}
    for _,p in _pairs(Players:GetPlayers()) do
        if p~=LocalPlayer then _table.insert(list,p.Name) end
    end
    if #list==0 then list={"(Tidak ada player)"} end
    _pcall(function() PlayerDropdown:Refresh(list,true) end)
    Rayfield:Notify({Title="Vechnost",Content=#list.." player ditemukan",Duration=2})
end

TabTrading:CreateButton({Name="Refresh Player List", Callback=function() RefreshPlayerList() end})
_task.spawn(function() _task.wait(3); RefreshPlayerList() end)

-- ---- TRADE BY NAME ----
TabTrading:CreateSection("Trade by Name")

local TradeNameStatus = TabTrading:CreateParagraph({Title="Status Trade by Name",Content="Menunggu..."})

local ItemDropdown = TabTrading:CreateDropdown({
    Name="Select Item", Options={"(Refresh dulu)"}, CurrentOption={"(Refresh dulu)"},
    MultipleOptions=false, Flag="TradeByNameItem",
    Callback=function(Option)
        local sel=_type(Option)=="table" and Option[1] or Option
        if sel and sel~="(Refresh dulu)" and sel~="(Inventory kosong)" then
            TradeState.ByName.ItemName=sel
        end
    end
})

TabTrading:CreateButton({
    Name="Refresh Items",
    Callback=function()
        _task.spawn(function()
            RefreshInvCache()
            local names=GetItemNames()
            _pcall(function() ItemDropdown:Refresh(names,true) end)
            Rayfield:Notify({Title="Vechnost",Content=_string.format("Items loaded: %d item",#names),Duration=2})
        end)
    end
})

TabTrading:CreateInput({
    Name="Amount", CurrentValue="1", PlaceholderText="Jumlah item yang mau dikirim",
    RemoveTextAfterFocusLost=false, Flag="TradeByNameAmount",
    Callback=function(Text)
        local n=tonumber(Text)
        if n and n>0 then TradeState.ByName.Amount=_math.floor(n) end
    end
})

TabTrading:CreateToggle({
    Name="Start Trade by Name", CurrentValue=false, Flag="StartTradeByName",
    Callback=function(Value)
        if Value then
            if not TradeState.TargetPlayer then
                Rayfield:Notify({Title="Vechnost",Content="Pilih target player dulu!",Duration=3}); return end
            if not TradeState.ByName.ItemName then
                Rayfield:Notify({Title="Vechnost",Content="Pilih item dulu!",Duration=3}); return end
            TradeState.ByName.Active=true; TradeState.ByName.Sent=0
            local total=TradeState.ByName.Amount
            local itemName=TradeState.ByName.ItemName
            local target=TradeState.TargetPlayer
            warn("[Vechnost] Trade by Name:", itemName, "x"..total, "->", target)
            _task.spawn(function()
                for i=1,total do
                    if not TradeState.ByName.Active then break end
                    _pcall(function()
                        TradeNameStatus:Set({Title="Status Trade by Name",
                            Content=_string.format("Sending: %d/%d %s\nProgress: %d/%d",i,total,itemName,i,total)})
                    end)
                    DoSendTrade(target, itemName, 1)
                    TradeState.ByName.Sent=i
                    _task.wait(RandDelay(0.8, 0.2))
                end
                TradeState.ByName.Active=false
                _pcall(function()
                    TradeNameStatus:Set({Title="Status Trade by Name",
                        Content=_string.format("Selesai: %d/%d %s", TradeState.ByName.Sent,total,itemName)})
                end)
                Rayfield:Notify({Title="Vechnost",Content="Trade by Name selesai! "..TradeState.ByName.Sent.."/"..total,Duration=4})
            end)
        else
            TradeState.ByName.Active=false
            Rayfield:Notify({Title="Vechnost",Content="Trade by Name dihentikan.",Duration=2})
        end
    end
})

-- ---- TRADE COIN ----
TabTrading:CreateSection("Trade Coin")

local TradeCoinStatus = TabTrading:CreateParagraph({Title="Status Trade Coin",Content="Menunggu..."})

TabTrading:CreateInput({
    Name="Target Coins", CurrentValue="0", PlaceholderText="Jumlah coin yang mau dikirim",
    RemoveTextAfterFocusLost=false, Flag="TradeCoinTarget",
    Callback=function(Text)
        local n=tonumber(Text)
        if n and n>=0 then TradeState.ByCoin.TargetCoins=_math.floor(n) end
    end
})

TabTrading:CreateToggle({
    Name="Start Trade Coin", CurrentValue=false, Flag="StartTradeCoin",
    Callback=function(Value)
        if Value then
            if not TradeState.TargetPlayer then
                Rayfield:Notify({Title="Vechnost",Content="Pilih target player dulu!",Duration=3}); return end
            if TradeState.ByCoin.TargetCoins<=0 then
                Rayfield:Notify({Title="Vechnost",Content="Isi jumlah coin!",Duration=3}); return end
            TradeState.ByCoin.Active=true
            local targetCoins=TradeState.ByCoin.TargetCoins
            local target=TradeState.TargetPlayer
            _task.spawn(function()
                _pcall(function()
                    TradeCoinStatus:Set({Title="Status Trade Coin",
                        Content="Sending: "..FormatNumber(targetCoins).." coins ke "..target})
                end)
                local coinRemote=nil
                if net then
                    for _,child in _ipairs(net:GetDescendants()) do
                        if child:IsA("RemoteFunction") or child:IsA("RemoteEvent") then
                            local ln=_string.lower(child.Name)
                            if ln:find("coin") or ln:find("currency") or ln:find("cash") then
                                coinRemote=child; break
                            end
                        end
                    end
                end
                local remote=coinRemote or CanSendTradeRemote
                local targetPlayer=nil
                for _,p in _pairs(Players:GetPlayers()) do
                    if p.Name==target or p.DisplayName==target then targetPlayer=p; break end
                end
                local ok=false
                if remote and targetPlayer then
                    ok=_pcall(function() SafeFire(remote, targetPlayer, "Coins", targetCoins) end)
                end
                TradeState.ByCoin.Active=false
                local statusTxt=ok and "Terkirim: "..FormatNumber(targetCoins).." coins" or "Remote coin tidak ditemukan"
                _pcall(function() TradeCoinStatus:Set({Title="Status Trade Coin",Content=statusTxt}) end)
                Rayfield:Notify({Title="Vechnost",Content=statusTxt,Duration=4})
            end)
        else
            TradeState.ByCoin.Active=false
            Rayfield:Notify({Title="Vechnost",Content="Trade Coin dihentikan.",Duration=2})
        end
    end
})

-- ---- TRADE RARITY ----
TabTrading:CreateSection("Trade Rarity")

local TradeRarityStatus = TabTrading:CreateParagraph({Title="Status Trade Rarity",Content="Menunggu..."})

TabTrading:CreateDropdown({
    Name="Select Rarity", Options=RarityList, CurrentOption={RarityList[1]},
    MultipleOptions=false, Flag="TradeRaritySelect",
    Callback=function(Option)
        local sel=_type(Option)=="table" and Option[1] or Option
        if sel then
            TradeState.ByRarity.Rarity=sel
            TradeState.ByRarity.RarityTier=RARITY_NAME_TO_TIER[sel] or 1
        end
    end
})
TradeState.ByRarity.Rarity="Common"; TradeState.ByRarity.RarityTier=1

TabTrading:CreateInput({
    Name="Amount", CurrentValue="1", PlaceholderText="Jumlah ikan yang mau dikirim",
    RemoveTextAfterFocusLost=false, Flag="TradeRarityAmount",
    Callback=function(Text)
        local n=tonumber(Text)
        if n and n>0 then TradeState.ByRarity.Amount=_math.floor(n) end
    end
})

TabTrading:CreateToggle({
    Name="Start Trade Rarity", CurrentValue=false, Flag="StartTradeRarity",
    Callback=function(Value)
        if Value then
            if not TradeState.TargetPlayer then
                Rayfield:Notify({Title="Vechnost",Content="Pilih target player dulu!",Duration=3}); return end
            TradeState.ByRarity.Active=true; TradeState.ByRarity.Sent=0
            local target=TradeState.TargetPlayer
            local rarityName=TradeState.ByRarity.Rarity or "Common"
            local tier=TradeState.ByRarity.RarityTier or 1
            local total=TradeState.ByRarity.Amount
            warn("[Vechnost] Trade Rarity:", rarityName, "x"..total, "->", target)
            _task.spawn(function()
                local fishList=GetItemsByTier(tier)
                if #fishList==0 then
                    TradeState.ByRarity.Active=false
                    Rayfield:Notify({Title="Vechnost",Content="Tidak ada ikan "..rarityName.." di inventory!",Duration=3})
                    return
                end
                local actualTotal=total
                for i=1,actualTotal do
                    if not TradeState.ByRarity.Active then break end
                    local itemName=fishList[((i-1) % #fishList)+1]
                    _pcall(function()
                        TradeRarityStatus:Set({Title="Status Trade Rarity",
                            Content=_string.format("Sending: %d/%d %s\nProgress: %d/%d",i,actualTotal,rarityName,i,actualTotal)})
                    end)
                    DoSendTrade(target, itemName, 1)
                    TradeState.ByRarity.Sent=i
                    _task.wait(RandDelay(0.8,0.2))
                end
                TradeState.ByRarity.Active=false
                _pcall(function()
                    TradeRarityStatus:Set({Title="Status Trade Rarity",
                        Content=_string.format("Selesai: %d/%d ikan %s",TradeState.ByRarity.Sent,actualTotal,rarityName)})
                end)
                Rayfield:Notify({Title="Vechnost",Content="Trade Rarity selesai! "..TradeState.ByRarity.Sent.." "..rarityName,Duration=4})
            end)
        else
            TradeState.ByRarity.Active=false
            Rayfield:Notify({Title="Vechnost",Content="Trade Rarity dihentikan.",Duration=2})
        end
    end
})

-- ---- TRADE STONE ----
TabTrading:CreateSection("Trade Stone")

local TradeStoneStatus = TabTrading:CreateParagraph({Title="Status Trade Stone",Content="Menunggu..."})

TabTrading:CreateDropdown({
    Name="Select Stone", Options=STONE_LIST, CurrentOption={STONE_LIST[1]},
    MultipleOptions=false, Flag="TradeStoneSelect",
    Callback=function(Option)
        local sel=_type(Option)=="table" and Option[1] or Option
        if sel then TradeState.ByStone.StoneName=sel end
    end
})
TradeState.ByStone.StoneName=STONE_LIST[1]

TabTrading:CreateInput({
    Name="Amount", CurrentValue="1", PlaceholderText="Jumlah stone yang mau dikirim",
    RemoveTextAfterFocusLost=false, Flag="TradeStoneAmount",
    Callback=function(Text)
        local n=tonumber(Text)
        if n and n>0 then TradeState.ByStone.Amount=_math.floor(n) end
    end
})

TabTrading:CreateButton({
    Name="Check Stock",
    Callback=function()
        local stoneName=TradeState.ByStone.StoneName or STONE_LIST[1]
        _task.spawn(function()
            local fresh=ScanInventory()
            InvCache=fresh
            local count=fresh.stones[stoneName] or 0
            if count==0 then
                for name,c in _pairs(fresh.items) do
                    if _string.lower(name)==_string.lower(stoneName) then count=c; break end
                end
            end
            Rayfield:Notify({Title="Vechnost",Content=_string.format("You have %d %s",count,stoneName),Duration=4})
        end)
    end
})

TabTrading:CreateToggle({
    Name="Start Trade Stone", CurrentValue=false, Flag="StartTradeStone",
    Callback=function(Value)
        if Value then
            if not TradeState.TargetPlayer then
                Rayfield:Notify({Title="Vechnost",Content="Pilih target player dulu!",Duration=3}); return end
            TradeState.ByStone.Active=true; TradeState.ByStone.Sent=0
            local target=TradeState.TargetPlayer
            local stoneName=TradeState.ByStone.StoneName or STONE_LIST[1]
            local total=TradeState.ByStone.Amount
            warn("[Vechnost] Trade Stone:", stoneName, "x"..total, "->", target)
            _task.spawn(function()
                -- Selalu re-scan untuk stock akurat
                local fresh=ScanInventory()
                InvCache=fresh
                local stock=fresh.stones[stoneName] or 0
                if stock==0 then
                    for name,c in _pairs(fresh.items) do
                        if _string.lower(name)==_string.lower(stoneName) then stock=c; break end
                    end
                end
                local actualTotal=(stock>0) and _math.min(total,stock) or total
                for i=1,actualTotal do
                    if not TradeState.ByStone.Active then break end
                    _pcall(function()
                        TradeStoneStatus:Set({Title="Status Trade Stone",
                            Content=_string.format("Sending: %d/%d %s\nProgress: %d/%d",i,actualTotal,stoneName,i,actualTotal)})
                    end)
                    DoSendTrade(target, stoneName, 1)
                    TradeState.ByStone.Sent=i
                    _task.wait(RandDelay(0.8,0.2))
                end
                TradeState.ByStone.Active=false
                _pcall(function()
                    TradeStoneStatus:Set({Title="Status Trade Stone",
                        Content=_string.format("Selesai: %d/%d %s",TradeState.ByStone.Sent,actualTotal,stoneName)})
                end)
                Rayfield:Notify({Title="Vechnost",Content="Trade Stone selesai! "..TradeState.ByStone.Sent.." "..stoneName,Duration=4})
            end)
        else
            TradeState.ByStone.Active=false
            Rayfield:Notify({Title="Vechnost",Content="Trade Stone dihentikan.",Duration=2})
        end
    end
})

-- ===========================================================
-- TAB 3 - SETTINGS
-- ===========================================================
TabSettings:CreateSection("Tentang")
TabSettings:CreateParagraph({
    Title="Vechnost v3.0.0",
    Content="Webhook Logger + Auto Trading\nBAC Bypass Included\nFish It - Roblox\n\nby Vechnost | discord.gg/vechnost"
})

TabSettings:CreateSection("Debug Tools")
TabSettings:CreateButton({
    Name="Test Webhook",
    Callback=function()
        if Settings.Url=="" then
            Rayfield:Notify({Title="Vechnost",Content="Isi webhook URL dulu!",Duration=3}); return end
        _task.spawn(function() SendWebhook(BuildTestPayload(LocalPlayer.Name)) end)
        Rayfield:Notify({Title="Vechnost",Content="Test message terkirim!",Duration=2})
    end
})

TabSettings:CreateButton({
    Name="Reset Log Counter",
    Callback=function()
        Settings.LogCount=0; Settings.SentUUID={}
        Rayfield:Notify({Title="Vechnost",Content="Counter di-reset!",Duration=2})
    end
})

TabSettings:CreateButton({
    Name="Scan All Remotes",
    Callback=function()
        if not net then
            Rayfield:Notify({Title="Vechnost",Content="net tidak tersedia",Duration=3}); return end
        local found=0
        _pcall(function()
            for _,child in _ipairs(net:GetDescendants()) do
                if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
                    found=found+1
                    warn("[Vechnost] Remote:", child.ClassName, child.Name)
                end
            end
        end)
        Rayfield:Notify({Title="Vechnost",Content=found.." remote ditemukan (lihat console)",Duration=5})
    end
})

TabSettings:CreateButton({
    Name="Debug Inventory",
    Callback=function()
        _task.spawn(function()
            local inv=ScanInventory()
            InvCache=inv
            local fc,sc=0,0
            for name,count in _pairs(inv.items) do fc=fc+1; warn("[Fish]",name,"x"..count) end
            for name,count in _pairs(inv.stones) do sc=sc+1; warn("[Stone]",name,"x"..count) end
            Rayfield:Notify({Title="Vechnost",Content=fc.." jenis ikan, "..sc.." jenis stone (lihat console)",Duration=5})
        end)
    end
})

-- ===========================================================
-- BAGIAN 18: INIT
-- ===========================================================
Rayfield:LoadConfiguration()
warn("[Vechnost] v3.0.0 Loaded! Tekan V untuk toggle GUI")
warn("[Vechnost] Trade remote:", CanSendTradeRemote and CanSendTradeRemote.Name or "NOT FOUND - coba Scan All Remotes")
