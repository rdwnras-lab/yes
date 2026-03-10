--[[
    FILE: vechnost_v2.lua
    BRAND: Vechnost
    VERSION: 2.4.0
    DESC: Custom GUI (Glassmorphism Sidebar) + Full Webhook Logger
          - Clean re-execute (hapus instance lama)
          - Draggable window dari mana saja
          - Tab Webhook & Settings berfungsi penuh
          - Rarity FORGOTTEN (tier 8) ditambahkan
          - Discord Components V2 webhook
          - Server-wide fish detection (4 metode)
]]

-- =====================================================
-- BAGIAN 1: CLEAN RE-EXECUTE
-- Hapus SEMUA instance GUI lama sebelum buat baru
-- =====================================================
local CoreGui  = game:GetService("CoreGui")
local Players  = game:GetService("Players")

local GUI_NAME   = "VechnostGUI_v24"
local FLOAT_NAME = "VechnostFloat_v24"

-- Daftar nama GUI lama (semua versi)
local OLD_NAMES = {
    "VechnostGUI_v2", "VechnostFloat_v2",
    "VechnostGUI_v24","VechnostFloat_v24",
    "Vechnost_Webhook_UI","Vechnost_Mobile_Button",
}

local function DestroyAll()
    for _, name in ipairs(OLD_NAMES) do
        pcall(function()
            local g = CoreGui:FindFirstChild(name)
            if g then g:Destroy() end
        end)
        pcall(function()
            local lp = Players.LocalPlayer
            if lp and lp:FindFirstChild("PlayerGui") then
                local g = lp.PlayerGui:FindFirstChild(name)
                if g then g:Destroy() end
            end
        end)
    end
    -- Juga cari via gethui jika tersedia
    pcall(function()
        if gethui then
            for _, name in ipairs(OLD_NAMES) do
                local g = gethui():FindFirstChild(name)
                if g then g:Destroy() end
            end
        end
    end)
end
DestroyAll()

-- =====================================================
-- BAGIAN 2: SERVICES
-- =====================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- =====================================================
-- BAGIAN 3: GAME REMOTES
-- =====================================================
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
        warn("[Vechnost] Pastikan kamu di game Fish It!")
    else
        warn("[Vechnost] Game remotes OK")
    end
end

-- =====================================================
-- BAGIAN 4: SETTINGS STATE
-- =====================================================
local Settings = {
    Active           = false,
    Url              = "",
    SentUUID         = {},
    SelectedRarities = {},
    ServerWide       = true,
    LogCount         = 0,
}

-- =====================================================
-- BAGIAN 5: FISH DATABASE
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
                        warn("[Vechnost] FishDB sample:", mod.Data.Name)
                    end
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
    if not ok then warn("[Vechnost] ERROR FishDB:", err) end
end

-- Reverse lookup: Fish Name -> Fish ID
local FishNameToId = {}
for fishId, fishData in pairs(FishDB) do
    if fishData.Name then
        FishNameToId[fishData.Name]                    = fishId
        FishNameToId[string.lower(fishData.Name)]      = fishId
    end
end

-- =====================================================
-- BAGIAN 6: PLAYER DATA (Replion)
-- =====================================================
local PlayerData = nil
do
    pcall(function()
        local Replion = require(ReplicatedStorage.Packages.Replion)
        PlayerData = Replion.Client:WaitReplion("Data")
        if PlayerData then warn("[Vechnost] Replion Data OK") end
    end)
end

local function FormatNumber(n)
    if not n or type(n) ~= "number" then return "0" end
    local f = tostring(math.floor(n))
    local k
    repeat f, k = string.gsub(f, "^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
    return f
end

-- =====================================================
-- BAGIAN 7: RARITY SYSTEM
-- (Ditambahkan FORGOTTEN = tier 8)
-- =====================================================
local RARITY_MAP = {
    [1] = "Common",    [2] = "Uncommon", [3] = "Rare",
    [4] = "Epic",      [5] = "Legendary",[6] = "Mythic",
    [7] = "Secret",    [8] = "Forgotten",
}

local RARITY_NAME_TO_TIER = {
    Common=1, Uncommon=2, Rare=3, Epic=4,
    Legendary=5, Mythic=6, Secret=7, Forgotten=8,
}

local RARITY_COLOR = {
    [1]=0x9e9e9e, [2]=0x4caf50, [3]=0x2196f3, [4]=0x9c27b0,
    [5]=0xff9800, [6]=0xf44336, [7]=0xff1744, [8]=0xb000ff,
}

local RarityList = {
    "Common","Uncommon","Rare","Epic",
    "Legendary","Mythic","Secret","Forgotten"
}

-- =====================================================
-- BAGIAN 8: HTTP REQUEST
-- =====================================================
local HttpRequest =
    (syn and syn.request)
    or http_request
    or request
    or (fluxus and fluxus.request)
    or (krnl and krnl.request)

if not HttpRequest then
    warn("[Vechnost][FATAL] HttpRequest tidak tersedia di executor ini")
end

-- =====================================================
-- BAGIAN 9: ICON CACHE
-- =====================================================
local IconCache  = {}
local IconWaiter = {}

local function FetchFishIconAsync(fishId, callback)
    if IconCache[fishId] then callback(IconCache[fishId]); return end
    if IconWaiter[fishId] then table.insert(IconWaiter[fishId], callback); return end
    IconWaiter[fishId] = {callback}
    task.spawn(function()
        local fish = FishDB[fishId]
        if not fish or not fish.Icon then callback(""); return end
        local assetId = tostring(fish.Icon):match("%d+")
        if not assetId then callback(""); return end
        local api = ("https://thumbnails.roblox.com/v1/assets?assetIds=%s&size=420x420&format=Png&isCircular=false"):format(assetId)
        local ok, res = pcall(function() return HttpRequest({Url=api,Method="GET"}) end)
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
-- BAGIAN 10: FILTER & HELPERS
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
                if lk=="variant" or lk=="variantid" or lk=="mutation" then mutation=v; break end
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
    if typeof(arg)=="Instance" and arg:IsA("Player") then return arg.Name
    elseif typeof(arg)=="string" then return arg
    elseif typeof(arg)=="table" and arg.Name then return tostring(arg.Name) end
    return LocalPlayer.Name
end

-- =====================================================
-- BAGIAN 11: WEBHOOK ENGINE (Discord Components V2)
-- =====================================================
local AVATAR_URL = "https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png"

local function BuildPayload(playerName, fishId, weight, mutation)
    local fish = FishDB[fishId]
    if not fish then return nil end

    local tier       = fish.Tier
    local rarityName = RARITY_MAP[tier] or "Unknown"
    local mutText    = (mutation ~= nil) and tostring(mutation) or "None"
    local weightText = string.format("%.1fkg", weight or 0)
    local iconUrl    = IconCache[fishId] or ""
    local dateStr    = os.date("!%B %d, %Y")

    -- Rarity emoji (Unicode bytes)
    local _e = string.char
    local RE = {
        [1]=_e(226,172,156),      -- ⬜ (common)
        [2]=_e(240,159,159,169),  -- 🟩
        [3]=_e(240,159,159,166),  -- 🟦
        [4]=_e(240,159,159,170),  -- 🟪
        [5]=_e(240,159,159,167),  -- 🟧
        [6]=_e(240,159,159,165),  -- 🟥
        [7]=_e(240,159,159,165),  -- ⬛ secret
        [8]=_e(240,159,146,156),  -- 💜 forgotten (purple)
    }
    local rarityEmoji = RE[tier] or ""

    -- Accent color per rarity
    local accentColor = RARITY_COLOR[tier] or 0x5865f2

    return {
        username   = "Vechnost Notifier",
        avatar_url = AVATAR_URL,
        flags      = 32768,
        components = {
            {
                type         = 17,
                accent_color = accentColor,
                components   = {
                    { type=10, content="# " .. rarityEmoji .. " NEW FISH CAUGHT!" },
                    { type=14, spacing=1, divider=true },
                    { type=10, content="__@" .. (playerName or "Unknown") .. " you got new **" .. string.upper(rarityName) .. "** fish__" },
                    {
                        type = 9,
                        components = {
                            { type=10, content="**Fish Name**" },
                            { type=10, content="> " .. (fish.Name or "Unknown") },
                        },
                        accessory = iconUrl ~= "" and {
                            type  = 11,
                            media = { url = iconUrl }
                        } or nil,
                    },
                    { type=10, content="**Fish Tier**" },
                    { type=10, content="> " .. rarityEmoji .. " " .. string.upper(rarityName) },
                    { type=10, content="**Weight**" },
                    { type=10, content="> " .. weightText },
                    { type=10, content="**Mutation**" },
                    { type=10, content="> " .. mutText },
                    { type=14, spacing=1, divider=true },
                    { type=10, content="> Notification by discord.gg/vechnost" },
                    { type=10, content="-# " .. dateStr },
                }
            }
        }
    }
end

local function BuildActivationPayload(playerName, mode)
    local dateStr = os.date("!%B %d, %Y")
    return {
        username="Vechnost Notifier", avatar_url=AVATAR_URL, flags=32768,
        components={{
            type=17, accent_color=0x30ff6a,
            components={
                { type=10, content="**" .. playerName .. "  Webhook Activated!**" },
                { type=14, spacing=1, divider=true },
                { type=10, content="### Vechnost Webhook Notifier" },
                { type=10, content="- **Account Name:** "..playerName.."\n- **Mode:** "..mode.."\n- **Status:** Online" },
                { type=14, spacing=1, divider=true },
                { type=10, content="-# "..dateStr },
            }
        }}
    }
end

local function BuildTestPayload(playerName)
    local dateStr = os.date("!%B %d, %Y")
    return {
        username="Vechnost Notifier", avatar_url=AVATAR_URL, flags=32768,
        components={{
            type=17, accent_color=0x5865f2,
            components={
                { type=10, content="**Test Message**" },
                { type=14, spacing=1, divider=true },
                { type=10, content="Webhook berfungsi dengan baik!\n\n- **Dikirim oleh:** "..playerName },
                { type=14, spacing=1, divider=true },
                { type=10, content="-# "..dateStr },
            }
        }}
    }
end

local function SendWebhook(payload)
    if Settings.Url=="" or not HttpRequest or not payload then return end
    pcall(function()
        local url = Settings.Url
        url = url .. (string.find(url,"?") and "&" or "?") .. "with_components=true"
        HttpRequest({
            Url=url, Method="POST",
            Headers={["Content-Type"]="application/json"},
            Body=HttpService:JSONEncode(payload)
        })
    end)
end

-- =====================================================
-- BAGIAN 12: FISH DETECTION ENGINE
-- =====================================================
local Connections   = {}
local ChatSentDedup = {}

local function ParseChatForFish(messageText)
    if not Settings.Active or not Settings.ServerWide then return end
    if not messageText or messageText=="" then return end

    local playerName, fishName, weightStr
    playerName,fishName,weightStr = string.match(messageText,"(%S+)%s+obtained%s+a%s+(.-)%s*%(([%d%.]+)kg%)")
    if not playerName then playerName,fishName,weightStr = string.match(messageText,"(%S+)%s+obtained%s+(.-)%s*%(([%d%.]+)kg%)") end
    if not playerName then playerName,fishName = string.match(messageText,"(%S+)%s+obtained%s+a%s+(.-)%s*with") end
    if not playerName then playerName,fishName = string.match(messageText,"(%S+)%s+obtained%s+(.-)%s*with") end
    if not playerName or not fishName then return end

    fishName = string.gsub(fishName, "%s+$", "")
    if playerName==LocalPlayer.Name or playerName==LocalPlayer.DisplayName then return end

    local fishId = FishNameToId[fishName] or FishNameToId[string.lower(fishName)]
    if not fishId then
        for name, id in pairs(FishNameToId) do
            if string.find(string.lower(fishName),string.lower(name)) or string.find(string.lower(name),string.lower(fishName)) then
                fishId=id; break
            end
        end
    end
    if not fishId then return end
    if not IsRarityAllowed(fishId) then return end

    local dedupKey = playerName..fishName..tostring(math.floor(os.time()/2))
    if ChatSentDedup[dedupKey] then return end
    ChatSentDedup[dedupKey] = true
    task.defer(function() task.wait(10); ChatSentDedup[dedupKey]=nil end)

    local weight = tonumber(weightStr) or 0
    Settings.LogCount = Settings.LogCount + 1
    warn("[Vechnost] CHAT catch:", playerName, FishDB[fishId].Name, weight.."kg")
    FetchFishIconAsync(fishId, function() SendWebhook(BuildPayload(playerName,fishId,weight,nil)) end)
end

local function HandleFishCaught(playerArg, weightData, wrapper)
    if not Settings.Active then return end

    local item = nil
    if wrapper and typeof(wrapper)=="table" and wrapper.InventoryItem then item=wrapper.InventoryItem end
    if not item and weightData and typeof(weightData)=="table" and weightData.InventoryItem then item=weightData.InventoryItem end
    if not item then return end
    if not item.Id or not item.UUID then return end
    if not FishDB[item.Id] then return end
    if not IsRarityAllowed(item.Id) then return end
    if Settings.SentUUID[item.UUID] then return end
    Settings.SentUUID[item.UUID] = true

    local playerName = ResolvePlayerName(playerArg)
    if not Settings.ServerWide and playerName~=LocalPlayer.Name then return end

    local weight = 0
    if weightData and typeof(weightData)=="table" and weightData.Weight then weight=weightData.Weight end
    local mutation = ExtractMutation(weightData, item)

    Settings.LogCount = Settings.LogCount + 1
    warn("[Vechnost] Fish caught! Player:", playerName, "Fish:", FishDB[item.Id].Name, "Count:", Settings.LogCount)
    FetchFishIconAsync(item.Id, function() SendWebhook(BuildPayload(playerName,item.Id,weight,mutation)) end)
end

local function TryProcessGeneric(remoteName, ...)
    if not Settings.Active then return end
    local args = {...}
    for i=1,#args do
        local arg = args[i]
        if typeof(arg)=="table" then
            local item = nil
            if arg.InventoryItem then item=arg.InventoryItem
            elseif arg.Id and arg.UUID then item=arg end
            if item and item.Id and item.UUID and FishDB[item.Id] then
                local playerArg = (i>1) and args[1] or nil
                local weightArg = nil
                for j=1,#args do
                    if typeof(args[j])=="table" and args[j].Weight then weightArg=args[j]; break end
                end
                HandleFishCaught(playerArg, weightArg, arg); return
            end
        end
    end
end

local function StartLogger()
    if Settings.Active then return end
    if not net or not ObtainedNewFish then
        warn("[Vechnost] ERROR: Game remotes not found!")
        return
    end

    Settings.Active   = true
    Settings.SentUUID = {}
    Settings.LogCount = 0

    -- CHAT MONITOR
    if Settings.ServerWide then
        pcall(function()
            local TCS = game:GetService("TextChatService")
            Connections[#Connections+1] = TCS.MessageReceived:Connect(function(msg)
                pcall(function()
                    if string.find(msg.Text or "","obtained") then ParseChatForFish(msg.Text) end
                end)
            end)
        end)
        pcall(function()
            local chatFrame = PlayerGui:WaitForChild("Chat",3)
            if chatFrame then
                Connections[#Connections+1] = chatFrame.DescendantAdded:Connect(function(desc)
                    if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                        task.defer(function()
                            if string.find(desc.Text or "","obtained") then ParseChatForFish(desc.Text) end
                        end)
                    end
                end)
            end
        end)
    end

    -- PRIMARY HOOK
    pcall(function()
        Connections[#Connections+1] = ObtainedNewFish.OnClientEvent:Connect(function(playerArg,weightData,wrapper)
            HandleFishCaught(playerArg,weightData,wrapper)
        end)
        warn("[Vechnost] Primary hook OK")
    end)

    -- GUI SCANNER
    if Settings.ServerWide then
        pcall(function()
            local function ScanNotif(textObj)
                if not textObj or not textObj:IsA("TextLabel") then return end
                local text = textObj.Text or ""
                if text=="" then return end
                for fishId, fishData in pairs(FishDB) do
                    if fishData.Name and string.find(text, fishData.Name) then
                        local playerName = "Unknown"
                        for _, p in pairs(Players:GetPlayers()) do
                            if p~=LocalPlayer and (string.find(text,p.Name) or string.find(text,p.DisplayName)) then
                                playerName=p.Name; break
                            end
                        end
                        if playerName=="Unknown" then return end
                        if string.find(text,LocalPlayer.Name) or string.find(text,LocalPlayer.DisplayName) then return end
                        local dk = "GUI_"..text.."_"..os.time()
                        if Settings.SentUUID[dk] then return end
                        Settings.SentUUID[dk] = true
                        if not IsRarityAllowed(fishId) then return end
                        Settings.LogCount = Settings.LogCount+1
                        FetchFishIconAsync(fishId, function() SendWebhook(BuildPayload(playerName,fishId,0,nil)) end)
                        return
                    end
                end
            end
            Connections[#Connections+1] = PlayerGui.DescendantAdded:Connect(function(desc)
                if not Settings.Active then return end
                if desc:IsA("TextLabel") then task.defer(function() ScanNotif(desc) end) end
            end)
        end)

        -- REPLION STATE
        pcall(function()
            local Replion = require(ReplicatedStorage.Packages.Replion)
            for _, sname in ipairs({"ServerFeed","GlobalNotifications","RecentCatches","FishLog","ServerNotifications","Feed"}) do
                task.spawn(function()
                    local ok, state = pcall(function() return Replion.Client:WaitReplion(sname) end)
                    if ok and state then
                        pcall(function()
                            state:OnChange(function(key,value)
                                if not Settings.Active then return end
                                if typeof(value)=="table" then
                                    if value.InventoryItem or (value.Id and value.UUID) then
                                        HandleFishCaught(value.Player or value.PlayerName, value, {InventoryItem=value.InventoryItem or value})
                                    end
                                end
                            end)
                        end)
                    end
                end)
            end
        end)

        -- QUATERNARY: All remote events
        local hookCount = 0
        pcall(function()
            for _, child in pairs(net:GetChildren()) do
                if child:IsA("RemoteEvent") and child~=ObtainedNewFish then
                    Connections[#Connections+1] = child.OnClientEvent:Connect(function(...) TryProcessGeneric(child.Name,...) end)
                    hookCount = hookCount+1
                end
            end
        end)
        warn("[Vechnost] Remote hooks:", hookCount)
    end

    task.spawn(function()
        SendWebhook(BuildActivationPayload(LocalPlayer.Name, Settings.ServerWide and "Server Notifier" or "Local Only"))
    end)
    warn("[Vechnost] Logger AKTIF | Mode:", Settings.ServerWide and "Server-Wide" or "Local")
end

local function StopLogger()
    Settings.Active = false
    for _, conn in ipairs(Connections) do pcall(function() conn:Disconnect() end) end
    Connections = {}
    warn("[Vechnost] Logger BERHENTI | Total:", Settings.LogCount)
end

-- =====================================================
-- BAGIAN 13: CUSTOM GUI
-- =====================================================
local ICON_ASSET = "rbxassetid://127239715511367"
local WIN_W      = 530
local WIN_H      = 350
local SIDE_W     = 145
local HEAD_H     = 44
local TAB_H      = 36
local RADIUS     = 12

local T = {
    WinBg        = Color3.fromRGB(8, 15, 38),
    WinAlpha     = 0.50,
    SidebarBg    = Color3.fromRGB(5, 11, 30),
    SidebarAlpha = 0.45,
    GlowBlue     = Color3.fromRGB(75, 145, 255),
    TabActive    = Color3.fromRGB(38, 95, 235),
    TabActiveA   = 0.55,
    TabHover     = Color3.fromRGB(22, 55, 150),
    TabHoverA    = 0.60,
    Indicator    = Color3.fromRGB(110, 185, 255),
    TextWhite    = Color3.fromRGB(235, 242, 255),
    TextSub      = Color3.fromRGB(148, 178, 228),
    TextMuted    = Color3.fromRGB(85, 115, 175),
    TextAccent   = Color3.fromRGB(100, 168, 255),
    CardBg       = Color3.fromRGB(10, 20, 52),
    CardAlpha    = 0.50,
    InputBg      = Color3.fromRGB(6, 13, 40),
    InputAlpha   = 0.55,
    BtnBg        = Color3.fromRGB(33, 88, 218),
    BtnAlpha     = 0.58,
    BtnHover     = Color3.fromRGB(52, 118, 255),
    ToggleOn     = Color3.fromRGB(38, 185, 105),
    ToggleOff    = Color3.fromRGB(42, 55, 90),
    DivColor     = Color3.fromRGB(65, 135, 255),
    DivAlpha     = 0.42,
}

-- GUI Helpers
local function New(cls, props)
    local i = Instance.new(cls)
    for k,v in pairs(props or {}) do pcall(function() i[k]=v end) end
    return i
end
local function C(p,r) local c=Instance.new("UICorner"); c.CornerRadius=(type(r)=="number") and UDim.new(0,r) or (r or UDim.new(0,8)); c.Parent=p end
local function S(p,col,a,t) local s=Instance.new("UIStroke"); s.Color=col or T.GlowBlue; s.Transparency=a or 0.50; s.Thickness=t or 1; s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; s.Parent=p end
local function Pad(p,t,b,l,r) local u=Instance.new("UIPadding"); u.PaddingTop=UDim.new(0,t or 8); u.PaddingBottom=UDim.new(0,b or 8); u.PaddingLeft=UDim.new(0,l or 10); u.PaddingRight=UDim.new(0,r or 10); u.Parent=p end
local function LL(p,sp) local l=Instance.new("UIListLayout"); l.Padding=UDim.new(0,sp or 5); l.SortOrder=Enum.SortOrder.LayoutOrder; l.Parent=p end
local function Grad(p,c0,c1,rot) local g=Instance.new("UIGradient"); g.Color=ColorSequence.new(c0,c1); g.Rotation=rot or 180; g.Parent=p end
local function Tw(inst,props,dur,sty,dir) pcall(function() TweenService:Create(inst,TweenInfo.new(dur or 0.18,sty or Enum.EasingStyle.Quad,dir or Enum.EasingDirection.Out),props):Play() end) end

local function GetGuiParent()
    if gethui then return gethui() end
    return CoreGui
end

-- SCREEN
local Screen = New("ScreenGui",{Name=GUI_NAME,ResetOnSpawn=false,ZIndexBehavior=Enum.ZIndexBehavior.Sibling,DisplayOrder=100})
if syn and syn.protect_gui then pcall(syn.protect_gui,Screen) end
Screen.Parent = GetGuiParent()

-- WINDOW (gradient langsung di sini agar corner melengkung sempurna)
local Window = New("Frame",{
    Name="Window", Size=UDim2.fromOffset(WIN_W,WIN_H),
    Position=UDim2.new(0.5,-WIN_W/2,0.5,-WIN_H/2),
    BackgroundColor3=T.WinBg, BackgroundTransparency=T.WinAlpha,
    BorderSizePixel=0, ClipsDescendants=true,
})
Window.Parent = Screen
C(Window, RADIUS)
Grad(Window, Color3.fromRGB(13,24,62), Color3.fromRGB(4,8,24), 150)
S(Window, T.GlowBlue, 0.38, 1.5)

-- Glass rim
New("Frame",{Size=UDim2.new(1,-2*RADIUS,0,1),Position=UDim2.fromOffset(RADIUS,1),
    BackgroundColor3=Color3.fromRGB(200,225,255),BackgroundTransparency=0.72,BorderSizePixel=0,ZIndex=10}).Parent=Window

-- DRAG — aktif dari seluruh Window
local _drag,_dStart,_wStart=false,nil,nil
Window.InputBegan:Connect(function(inp)
    if inp.UserInputType==Enum.UserInputType.MouseButton1 then
        _drag=true; _dStart=inp.Position; _wStart=Window.Position
    end
end)
Window.InputEnded:Connect(function(inp)
    if inp.UserInputType==Enum.UserInputType.MouseButton1 then _drag=false end
end)
UserInputService.InputChanged:Connect(function(inp)
    if _drag and inp.UserInputType==Enum.UserInputType.MouseMovement then
        local d=inp.Position-_dStart
        local vp=workspace.CurrentCamera.ViewportSize
        Window.Position=UDim2.fromOffset(
            math.clamp(_wStart.X.Offset+d.X,0,vp.X-WIN_W),
            math.clamp(_wStart.Y.Offset+d.Y,0,vp.Y-WIN_H))
    end
end)

-- SIDEBAR
local Sidebar=New("Frame",{Size=UDim2.fromOffset(SIDE_W,WIN_H),
    BackgroundColor3=T.SidebarBg,BackgroundTransparency=T.SidebarAlpha,BorderSizePixel=0,ZIndex=2})
Sidebar.Parent=Window
Grad(Sidebar,Color3.fromRGB(9,20,52),Color3.fromRGB(3,8,25),180)

-- Sidebar divider glow
New("Frame",{Size=UDim2.fromOffset(1,WIN_H),Position=UDim2.fromOffset(SIDE_W-1,0),
    BackgroundColor3=T.DivColor,BackgroundTransparency=T.DivAlpha,BorderSizePixel=0,ZIndex=3}).Parent=Window

-- Sidebar header
local SHead=New("Frame",{Size=UDim2.new(1,0,0,HEAD_H),BackgroundTransparency=1,BorderSizePixel=0,ZIndex=3})
SHead.Parent=Sidebar

New("ImageLabel",{Image=ICON_ASSET,Size=UDim2.fromOffset(26,26),Position=UDim2.fromOffset(10,9),
    BackgroundTransparency=1,BorderSizePixel=0,ZIndex=4,ScaleType=Enum.ScaleType.Fit}).Parent=SHead

New("TextLabel",{Text="Vechnost",Font=Enum.Font.GothamBold,TextSize=13,TextColor3=T.TextWhite,
    BackgroundTransparency=1,Size=UDim2.fromOffset(88,16),Position=UDim2.fromOffset(42,8),
    TextXAlignment=Enum.TextXAlignment.Left,ZIndex=4}).Parent=SHead

New("TextLabel",{Text="Fish It • v2.4",Font=Enum.Font.Gotham,TextSize=9,TextColor3=T.TextMuted,
    BackgroundTransparency=1,Size=UDim2.fromOffset(88,12),Position=UDim2.fromOffset(42,25),
    TextXAlignment=Enum.TextXAlignment.Left,ZIndex=4}).Parent=SHead

New("Frame",{Size=UDim2.new(1,-12,0,1),Position=UDim2.fromOffset(6,HEAD_H-1),
    BackgroundColor3=T.GlowBlue,BackgroundTransparency=0.68,BorderSizePixel=0,ZIndex=3}).Parent=Sidebar

-- Tab list
local TabList=New("Frame",{Size=UDim2.new(1,0,1,-HEAD_H-2),Position=UDim2.fromOffset(0,HEAD_H+2),
    BackgroundTransparency=1,BorderSizePixel=0,ZIndex=3})
TabList.Parent=Sidebar
LL(TabList,3); Pad(TabList,4,4,5,5)

-- PANEL KANAN
local Panel=New("Frame",{Size=UDim2.new(1,-SIDE_W,1,0),Position=UDim2.fromOffset(SIDE_W,0),
    BackgroundTransparency=1,BorderSizePixel=0,ZIndex=2})
Panel.Parent=Window

local PHead=New("Frame",{Size=UDim2.new(1,0,0,HEAD_H),BackgroundTransparency=1,BorderSizePixel=0,ZIndex=3})
PHead.Parent=Panel

local PanelTitle=New("TextLabel",{Text="Webhook Logger",Font=Enum.Font.GothamBold,TextSize=14,
    TextColor3=T.TextWhite,BackgroundTransparency=1,Size=UDim2.new(1,-48,1,0),
    Position=UDim2.fromOffset(14,0),TextXAlignment=Enum.TextXAlignment.Left,ZIndex=4})
PanelTitle.Parent=PHead

-- X BUTTON
local XBtn=New("TextButton",{Text="✕",Font=Enum.Font.GothamBold,TextSize=11,TextColor3=T.TextMuted,
    BackgroundColor3=Color3.fromRGB(155,32,32),BackgroundTransparency=0.78,
    Size=UDim2.fromOffset(22,22),Position=UDim2.new(1,-28,0.5,-11),BorderSizePixel=0,ZIndex=5})
XBtn.Parent=PHead
C(XBtn,6); S(XBtn,Color3.fromRGB(255,80,80),0.75,1)

New("Frame",{Size=UDim2.new(1,-12,0,1),Position=UDim2.fromOffset(6,HEAD_H-1),
    BackgroundColor3=T.GlowBlue,BackgroundTransparency=0.68,BorderSizePixel=0,ZIndex=3}).Parent=Panel

-- Content ScrollFrame
local Content=New("ScrollingFrame",{Size=UDim2.new(1,-8,1,-HEAD_H-6),Position=UDim2.fromOffset(4,HEAD_H+3),
    BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=2,
    ScrollBarImageColor3=T.GlowBlue,ScrollBarImageTransparency=0.40,
    CanvasSize=UDim2.fromScale(0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y,ZIndex=3})
Content.Parent=Panel
LL(Content,6); Pad(Content,2,10,0,4)

-- COMPONENTS
local function Section(title, parent)
    local f=New("Frame",{Size=UDim2.new(1,0,0,20),BackgroundTransparency=1,BorderSizePixel=0,ZIndex=4})
    f.Parent=parent or Content
    New("TextLabel",{Text=string.upper(title),Font=Enum.Font.GothamBold,TextSize=9,TextColor3=T.TextAccent,
        BackgroundTransparency=1,Size=UDim2.new(1,0,1,0),TextXAlignment=Enum.TextXAlignment.Left,ZIndex=5}).Parent=f
    New("Frame",{Size=UDim2.new(1,0,0,1),Position=UDim2.new(0,0,1,-1),BackgroundColor3=T.GlowBlue,
        BackgroundTransparency=0.64,BorderSizePixel=0,ZIndex=4}).Parent=f
    return f
end

local function Input(label, placeholder, cb, parent)
    local card=New("Frame",{Size=UDim2.new(1,0,0,54),BackgroundColor3=T.CardBg,
        BackgroundTransparency=T.CardAlpha,BorderSizePixel=0,ZIndex=4})
    card.Parent=parent or Content; C(card,8); S(card,T.GlowBlue,0.68,1)
    New("TextLabel",{Text=label,Font=Enum.Font.GothamMedium,TextSize=11,TextColor3=T.TextSub,
        BackgroundTransparency=1,Size=UDim2.new(1,-14,0,14),Position=UDim2.fromOffset(10,6),
        TextXAlignment=Enum.TextXAlignment.Left,ZIndex=5}).Parent=card
    local box=New("TextBox",{PlaceholderText=placeholder or "",PlaceholderColor3=T.TextMuted,
        Text="",Font=Enum.Font.RobotoMono,TextSize=10,TextColor3=T.TextWhite,
        BackgroundColor3=T.InputBg,BackgroundTransparency=T.InputAlpha,
        Size=UDim2.new(1,-20,0,22),Position=UDim2.fromOffset(10,22),
        TextXAlignment=Enum.TextXAlignment.Left,ClearTextOnFocus=false,BorderSizePixel=0,ZIndex=5})
    box.Parent=card; C(box,5); S(box,T.GlowBlue,0.75,1); Pad(box,0,0,5,5)
    box.Focused:Connect(function() Tw(box,{BackgroundTransparency=0.18},0.15) end)
    box.FocusLost:Connect(function() Tw(box,{BackgroundTransparency=T.InputAlpha},0.15); if cb then cb(box.Text) end end)
    return card, box
end

local function Toggle(label, desc, default, cb, parent)
    local val=default or false
    local card=New("Frame",{Size=UDim2.new(1,0,0,desc and 46 or 36),BackgroundColor3=T.CardBg,
        BackgroundTransparency=T.CardAlpha,BorderSizePixel=0,ZIndex=4})
    card.Parent=parent or Content; C(card,8); S(card,T.GlowBlue,0.74,1)
    New("TextLabel",{Text=label,Font=Enum.Font.GothamSemibold,TextSize=12,TextColor3=T.TextWhite,
        BackgroundTransparency=1,Size=UDim2.new(1,-52,0,16),Position=UDim2.fromOffset(10,desc and 6 or 10),
        TextXAlignment=Enum.TextXAlignment.Left,ZIndex=5}).Parent=card
    if desc then New("TextLabel",{Text=desc,Font=Enum.Font.Gotham,TextSize=9,TextColor3=T.TextMuted,
        BackgroundTransparency=1,Size=UDim2.new(1,-52,0,12),Position=UDim2.fromOffset(10,25),
        TextXAlignment=Enum.TextXAlignment.Left,ZIndex=5}).Parent=card end
    local track=New("Frame",{Size=UDim2.fromOffset(34,18),Position=UDim2.new(1,-40,0.5,-9),
        BackgroundColor3=val and T.ToggleOn or T.ToggleOff,BorderSizePixel=0,ZIndex=5})
    track.Parent=card; C(track,UDim.new(1,0))
    local knob=New("Frame",{Size=UDim2.fromOffset(12,12),Position=val and UDim2.fromOffset(19,3) or UDim2.fromOffset(3,3),
        BackgroundColor3=Color3.fromRGB(255,255,255),BorderSizePixel=0,ZIndex=6})
    knob.Parent=track; C(knob,UDim.new(1,0))
    local hit=New("TextButton",{Text="",BackgroundTransparency=1,Size=UDim2.fromScale(1,1),ZIndex=7})
    hit.Parent=card
    hit.MouseButton1Click:Connect(function()
        val=not val
        Tw(track,{BackgroundColor3=val and T.ToggleOn or T.ToggleOff},0.2)
        Tw(knob,{Position=val and UDim2.fromOffset(19,3) or UDim2.fromOffset(3,3)},0.2,Enum.EasingStyle.Back)
        if cb then cb(val) end
    end)
    return card, function() return val end, function(v) val=v
        Tw(track,{BackgroundColor3=val and T.ToggleOn or T.ToggleOff},0.2)
        Tw(knob,{Position=val and UDim2.fromOffset(19,3) or UDim2.fromOffset(3,3)},0.2,Enum.EasingStyle.Back)
    end
end

local function Button(label, desc, cb, parent)
    local card=New("Frame",{Size=UDim2.new(1,0,0,desc and 46 or 34),BackgroundColor3=T.BtnBg,
        BackgroundTransparency=T.BtnAlpha,BorderSizePixel=0,ZIndex=4})
    card.Parent=parent or Content; C(card,8); S(card,T.GlowBlue,0.55,1)
    New("TextLabel",{Text=label,Font=Enum.Font.GothamSemibold,TextSize=12,TextColor3=T.TextWhite,
        BackgroundTransparency=1,Size=UDim2.new(1,-26,0,16),Position=UDim2.fromOffset(10,desc and 6 or 9),
        TextXAlignment=Enum.TextXAlignment.Left,ZIndex=5}).Parent=card
    if desc then New("TextLabel",{Text=desc,Font=Enum.Font.Gotham,TextSize=9,
        TextColor3=Color3.fromRGB(175,208,255),BackgroundTransparency=1,
        Size=UDim2.new(1,-26,0,11),Position=UDim2.fromOffset(10,25),
        TextXAlignment=Enum.TextXAlignment.Left,ZIndex=5}).Parent=card end
    New("TextLabel",{Text="›",Font=Enum.Font.GothamBold,TextSize=15,TextColor3=Color3.fromRGB(160,200,255),
        BackgroundTransparency=1,Size=UDim2.fromOffset(14,14),Position=UDim2.new(1,-18,0.5,-7),
        TextXAlignment=Enum.TextXAlignment.Center,ZIndex=5}).Parent=card
    local hit=New("TextButton",{Text="",BackgroundTransparency=1,Size=UDim2.fromScale(1,1),ZIndex=6})
    hit.Parent=card
    hit.MouseEnter:Connect(function() Tw(card,{BackgroundColor3=T.BtnHover,BackgroundTransparency=0.32},0.15) end)
    hit.MouseLeave:Connect(function() Tw(card,{BackgroundColor3=T.BtnBg,BackgroundTransparency=T.BtnAlpha},0.15) end)
    hit.MouseButton1Click:Connect(function()
        Tw(card,{BackgroundTransparency=0.12},0.07)
        task.delay(0.12,function() Tw(card,{BackgroundTransparency=0.32},0.10) end)
        if cb then cb() end
    end)
    return card
end

local function Paragraph(title, body, parent)
    local card=New("Frame",{AutomaticSize=Enum.AutomaticSize.Y,Size=UDim2.new(1,0,0,0),
        BackgroundColor3=T.CardBg,BackgroundTransparency=0.46,BorderSizePixel=0,ZIndex=4})
    card.Parent=parent or Content; C(card,8); S(card,T.GlowBlue,0.76,1); Pad(card,8,8,10,10)
    New("TextLabel",{Text=title,Font=Enum.Font.GothamBold,TextSize=11,TextColor3=T.TextAccent,
        BackgroundTransparency=1,Size=UDim2.new(1,0,0,14),TextXAlignment=Enum.TextXAlignment.Left,ZIndex=5}).Parent=card
    local bl=New("TextLabel",{Text=body,Font=Enum.Font.Gotham,TextSize=10,TextColor3=T.TextSub,
        BackgroundTransparency=1,Size=UDim2.new(1,0,0,0),Position=UDim2.fromOffset(0,17),
        AutomaticSize=Enum.AutomaticSize.Y,TextXAlignment=Enum.TextXAlignment.Left,
        TextWrapped=true,RichText=true,ZIndex=5})
    bl.Parent=card
    return card, function(_,nb) bl.Text=nb or "" end
end

local function Dropdown(label, options, multi, cb, parent)
    local selected={};local isOpen=false
    local listH=math.min(#options*28+8,148)
    local wrap=New("Frame",{Size=UDim2.new(1,0,0,48),BackgroundTransparency=1,BorderSizePixel=0,ZIndex=8})
    wrap.Parent=parent or Content
    local hdr=New("Frame",{Size=UDim2.new(1,0,0,48),BackgroundColor3=T.CardBg,
        BackgroundTransparency=T.CardAlpha,BorderSizePixel=0,ZIndex=9})
    hdr.Parent=wrap; C(hdr,8); S(hdr,T.GlowBlue,0.68,1)
    New("TextLabel",{Text=label,Font=Enum.Font.GothamMedium,TextSize=10,TextColor3=T.TextSub,
        BackgroundTransparency=1,Size=UDim2.new(1,-34,0,13),Position=UDim2.fromOffset(10,5),
        TextXAlignment=Enum.TextXAlignment.Left,ZIndex=10}).Parent=hdr
    local selLbl=New("TextLabel",{Text="Semua rarity",Font=Enum.Font.Gotham,TextSize=11,
        TextColor3=T.TextWhite,BackgroundTransparency=1,Size=UDim2.new(1,-34,0,15),
        Position=UDim2.fromOffset(10,26),TextXAlignment=Enum.TextXAlignment.Left,
        TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=10}); selLbl.Parent=hdr
    local arrow=New("TextLabel",{Text="⌄",Font=Enum.Font.GothamBold,TextSize=12,TextColor3=T.TextAccent,
        BackgroundTransparency=1,Size=UDim2.fromOffset(18,18),Position=UDim2.new(1,-22,0.5,-9),
        TextXAlignment=Enum.TextXAlignment.Center,ZIndex=10}); arrow.Parent=hdr
    local lst=New("ScrollingFrame",{Size=UDim2.new(1,0,0,0),Position=UDim2.fromOffset(0,50),
        BackgroundColor3=Color3.fromRGB(5,12,38),BackgroundTransparency=0.06,BorderSizePixel=0,
        ClipsDescendants=true,ScrollBarThickness=2,ScrollBarImageColor3=T.GlowBlue,
        CanvasSize=UDim2.fromScale(0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y,ZIndex=18,Visible=false})
    lst.Parent=wrap; C(lst,8); S(lst,T.GlowBlue,0.60,1); LL(lst,2); Pad(lst,3,3,5,5)
    for _,opt in ipairs(options) do
        local ob=New("TextButton",{Text="  "..opt,Font=Enum.Font.Gotham,TextSize=11,TextColor3=T.TextWhite,
            BackgroundColor3=Color3.fromRGB(28,62,165),BackgroundTransparency=1,
            Size=UDim2.new(1,0,0,26),TextXAlignment=Enum.TextXAlignment.Left,BorderSizePixel=0,ZIndex=19})
        ob.Parent=lst; C(ob,5)
        ob.MouseEnter:Connect(function() Tw(ob,{BackgroundTransparency=0.52},0.12) end)
        ob.MouseLeave:Connect(function() Tw(ob,{BackgroundTransparency=selected[opt] and 0.32 or 1},0.12) end)
        ob.MouseButton1Click:Connect(function()
            if multi then selected[opt]=not selected[opt]
            else for k in pairs(selected) do selected[k]=nil end; selected[opt]=true end
            Tw(ob,{BackgroundTransparency=selected[opt] and 0.32 or 1},0.15)
            local s={}; for k,v in pairs(selected) do if v then table.insert(s,k) end end
            selLbl.Text=#s==0 and "Semua rarity" or table.concat(s,", ")
            if cb then cb(s) end
        end)
    end
    local hb=New("TextButton",{Text="",BackgroundTransparency=1,Size=UDim2.fromScale(1,1),ZIndex=11}); hb.Parent=hdr
    hb.MouseButton1Click:Connect(function()
        isOpen=not isOpen
        if isOpen then
            lst.Visible=true; Tw(lst,{Size=UDim2.new(1,0,0,listH)},0.20,Enum.EasingStyle.Back)
            Tw(arrow,{Rotation=180},0.20); wrap.Size=UDim2.new(1,0,0,48+listH+4)
        else
            Tw(lst,{Size=UDim2.new(1,0,0,0)},0.15); Tw(arrow,{Rotation=0},0.15)
            task.delay(0.16,function() lst.Visible=false end); wrap.Size=UDim2.new(1,0,0,48)
        end
    end)
    return wrap
end

-- =====================================================
-- TAB SYSTEM (3D modern style)
-- =====================================================
local Tabs={}; local ActiveTab=nil

local function CreateTab(name, iconTxt)
    local btn=New("Frame",{Size=UDim2.new(1,0,0,TAB_H),BackgroundColor3=Color3.fromRGB(12,24,62),
        BackgroundTransparency=0.60,BorderSizePixel=0,ZIndex=4})
    btn.Parent=TabList; C(btn,7)
    Grad(btn,Color3.fromRGB(22,45,110),Color3.fromRGB(6,12,38),180)

    -- 3D highlight top line
    New("Frame",{Size=UDim2.new(1,-14,0,1),Position=UDim2.fromOffset(7,1),
        BackgroundColor3=Color3.fromRGB(180,215,255),BackgroundTransparency=0.72,
        BorderSizePixel=0,ZIndex=6}).Parent=btn
    -- shadow bottom line
    New("Frame",{Size=UDim2.new(1,-14,0,1),Position=UDim2.new(0,7,1,-1),
        BackgroundColor3=Color3.fromRGB(0,0,0),BackgroundTransparency=0.70,
        BorderSizePixel=0,ZIndex=6}).Parent=btn

    local bar=New("Frame",{Size=UDim2.fromOffset(3,18),Position=UDim2.new(0,-4,0.5,-9),
        BackgroundColor3=T.Indicator,BackgroundTransparency=1,BorderSizePixel=0,ZIndex=7})
    bar.Parent=btn; C(bar,UDim.new(1,0))

    local ico=New("TextLabel",{Text=iconTxt or "◆",Font=Enum.Font.GothamBold,TextSize=13,
        TextColor3=T.TextMuted,BackgroundTransparency=1,Size=UDim2.fromOffset(22,TAB_H),
        Position=UDim2.fromOffset(7,0),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=5})
    ico.Parent=btn

    local lbl=New("TextLabel",{Text=name,Font=Enum.Font.GothamSemibold,TextSize=11,
        TextColor3=T.TextMuted,BackgroundTransparency=1,Size=UDim2.new(1,-34,1,0),
        Position=UDim2.fromOffset(32,0),TextXAlignment=Enum.TextXAlignment.Left,ZIndex=5})
    lbl.Parent=btn

    local page=New("Frame",{Name="Page_"..name,Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,
        BackgroundTransparency=1,BorderSizePixel=0,Visible=false,ZIndex=4})
    page.Parent=Content; LL(page,6); Pad(page,0,4,0,0)

    local tabData={name=name,btn=btn,bar=bar,ico=ico,lbl=lbl,page=page}
    local hit=New("TextButton",{Text="",BackgroundTransparency=1,Size=UDim2.fromScale(1,1),ZIndex=8})
    hit.Parent=btn

    hit.MouseEnter:Connect(function()
        if ActiveTab~=tabData then
            Tw(btn,{BackgroundColor3=T.TabHover,BackgroundTransparency=T.TabHoverA},0.15)
            Tw(ico,{TextColor3=T.TextSub},0.15); Tw(lbl,{TextColor3=T.TextSub},0.15)
        end
    end)
    hit.MouseLeave:Connect(function()
        if ActiveTab~=tabData then
            Tw(btn,{BackgroundColor3=Color3.fromRGB(12,24,62),BackgroundTransparency=0.60},0.15)
            Tw(ico,{TextColor3=T.TextMuted},0.15); Tw(lbl,{TextColor3=T.TextMuted},0.15)
        end
    end)
    hit.MouseButton1Click:Connect(function()
        if ActiveTab==tabData then return end
        if ActiveTab then
            ActiveTab.page.Visible=false
            Tw(ActiveTab.btn,{BackgroundColor3=Color3.fromRGB(12,24,62),BackgroundTransparency=0.60},0.15)
            Tw(ActiveTab.bar,{BackgroundTransparency=1},0.15)
            Tw(ActiveTab.ico,{TextColor3=T.TextMuted},0.15)
            Tw(ActiveTab.lbl,{TextColor3=T.TextMuted},0.15)
        end
        ActiveTab=tabData; page.Visible=true
        Tw(btn,{BackgroundColor3=T.TabActive,BackgroundTransparency=T.TabActiveA},0.18)
        Tw(bar,{BackgroundTransparency=0},0.18)
        Tw(ico,{TextColor3=Color3.fromRGB(255,255,255)},0.18)
        Tw(lbl,{TextColor3=Color3.fromRGB(255,255,255)},0.18)
        PanelTitle.Text=name
    end)

    table.insert(Tabs,tabData)
    return page
end

-- BUAT TABS
local WebhookPage  = CreateTab("Webhook Logger","🔗")
local SettingsPage = CreateTab("Settings","⚙")

do
    local f=Tabs[1]; f.page.Visible=true; ActiveTab=f
    f.btn.BackgroundColor3=T.TabActive; f.btn.BackgroundTransparency=T.TabActiveA
    f.bar.BackgroundTransparency=0; f.ico.TextColor3=Color3.fromRGB(255,255,255)
    f.lbl.TextColor3=Color3.fromRGB(255,255,255); PanelTitle.Text=f.name
end

-- =====================================================
-- ISI TAB: WEBHOOK LOGGER
-- =====================================================
Section("Rarity Filter", WebhookPage)
Dropdown("Filter by Rarity", RarityList, true, function(opts)
    Settings.SelectedRarities = {}
    for _, v in ipairs(opts or {}) do
        local tier = RARITY_NAME_TO_TIER[v]
        if tier then Settings.SelectedRarities[tier]=true end
    end
end, WebhookPage)

Section("Setup Webhook", WebhookPage)
local WebhookUrlBuffer = ""
local _, UrlBox = Input("Discord Webhook URL","https://discord.com/api/webhooks/...",
    function(txt) WebhookUrlBuffer=tostring(txt) end, WebhookPage)

Button("Save Webhook URL","Validasi & simpan URL webhook", function()
    local url = WebhookUrlBuffer:gsub("%s+","")
    if not url:match("^https://discord.com/api/webhooks/")
    and not url:match("^https://canary.discord.com/api/webhooks/") then
        warn("[Vechnost] URL webhook tidak valid!")
        return
    end
    Settings.Url = url
    warn("[Vechnost] Webhook URL saved!")
end, WebhookPage)

Section("Logger Mode", WebhookPage)
Toggle("Server-Notifier Mode","Log ikan dari semua player di server",true,
    function(v) Settings.ServerWide=v end, WebhookPage)

Section("Control", WebhookPage)
local _, _, SetLoggerToggle = Toggle("Enable Webhook Logger","Aktifkan notifikasi ke Discord",false,
    function(v)
        if v then
            if Settings.Url=="" then
                warn("[Vechnost] Isi webhook URL dulu!")
                SetLoggerToggle(false)
                return
            end
            StartLogger()
        else
            StopLogger()
        end
    end, WebhookPage)

Section("Status", WebhookPage)
local _, UpdateStatus = Paragraph("Notifier Status","Status: Offline", WebhookPage)

-- Auto-update status setiap 2 detik
task.spawn(function()
    while true do
        task.wait(2)
        pcall(function()
            if Settings.Active then
                UpdateStatus(nil, string.format(
                    "Status: <font color='#40be69'>Aktif</font>\nMode: %s\nTotal Log: %d ikan",
                    Settings.ServerWide and "Server-Notifier" or "Local Only",
                    Settings.LogCount))
            else
                UpdateStatus(nil, "Status: <font color='#ff5555'>Offline</font>")
            end
        end)
    end
end)

-- =====================================================
-- ISI TAB: SETTINGS
-- =====================================================
Section("Tentang", SettingsPage)
Paragraph("Vechnost Webhook Notifier",
    "v2.4 Beta • Server-Notifier Fish Catch Logger\n"..
    "Log ikan dari semua player di server\n"..
    "Rarity: Common → Forgotten (tier 8)\n\n"..
    "<font color='#5aaeff'>by Vechnost • discord.gg/vechnost</font>",
    SettingsPage)

Section("Testing", SettingsPage)
Button("Test Webhook","Kirim pesan test ke Discord channel",function()
    if Settings.Url=="" then warn("[Vechnost] Isi webhook URL dulu!"); return end
    task.spawn(function() SendWebhook(BuildTestPayload(LocalPlayer.Name)) end)
    warn("[Vechnost] Test message terkirim!")
end, SettingsPage)

Button("Reset Log Counter","Reset counter dan hapus UUID cache",function()
    Settings.LogCount=0; Settings.SentUUID={}
    warn("[Vechnost] Counter di-reset!")
end, SettingsPage)

-- =====================================================
-- BAGIAN 14: VISIBILITY SYSTEM
-- =====================================================
local guiVisible = true

local function SetVisible(v)
    guiVisible = v
    if v then
        Screen.Enabled = true
        Window.Size = UDim2.fromOffset(0,0)
        Tw(Window,{Size=UDim2.fromOffset(WIN_W,WIN_H)},0.30,Enum.EasingStyle.Back,Enum.EasingDirection.Out)
    else
        Tw(Window,{Size=UDim2.fromOffset(0,0)},0.20,Enum.EasingStyle.Quad,Enum.EasingDirection.In)
        task.delay(0.22,function() Screen.Enabled=false end)
    end
end

XBtn.MouseEnter:Connect(function() Tw(XBtn,{BackgroundTransparency=0.30,TextColor3=Color3.fromRGB(255,85,85)},0.15) end)
XBtn.MouseLeave:Connect(function() Tw(XBtn,{BackgroundTransparency=0.78,TextColor3=T.TextMuted},0.15) end)
XBtn.MouseButton1Click:Connect(function() SetVisible(false) end)

UserInputService.InputBegan:Connect(function(inp,gp)
    if gp then return end
    if inp.KeyCode==Enum.KeyCode.V then SetVisible(not guiVisible) end
end)

-- =====================================================
-- BAGIAN 15: FLOATING ICON BUTTON
-- =====================================================
local FloatGui=New("ScreenGui",{Name=FLOAT_NAME,ResetOnSpawn=false,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling,DisplayOrder=101})
if syn and syn.protect_gui then pcall(syn.protect_gui,FloatGui) end
FloatGui.Parent=GetGuiParent()

local FloatBtn=New("ImageButton",{Image=ICON_ASSET,Size=UDim2.fromOffset(44,44),
    Position=UDim2.fromScale(0.05,0.5),BackgroundColor3=Color3.fromRGB(8,18,55),
    BackgroundTransparency=0.18,AutoButtonColor=false,BorderSizePixel=0,ZIndex=10,
    ScaleType=Enum.ScaleType.Fit,ImageColor3=Color3.fromRGB(255,255,255)})
FloatBtn.Parent=FloatGui
C(FloatBtn,UDim.new(1,0)); S(FloatBtn,T.GlowBlue,0.35,2)

FloatBtn.MouseEnter:Connect(function() Tw(FloatBtn,{BackgroundTransparency=0.0},0.15) end)
FloatBtn.MouseLeave:Connect(function() Tw(FloatBtn,{BackgroundTransparency=0.18},0.15) end)
FloatBtn.MouseButton1Click:Connect(function() SetVisible(not guiVisible) end)

-- Drag FloatBtn
local _fd,_fdS,_fpS=false,nil,nil
FloatBtn.InputBegan:Connect(function(inp)
    if inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch then
        _fd=true; _fdS=UserInputService:GetMouseLocation(); _fpS=FloatBtn.Position
        inp.Changed:Connect(function()
            if inp.UserInputState==Enum.UserInputState.End then _fd=false end
        end)
    end
end)
RunService.RenderStepped:Connect(function()
    if not _fd then return end
    local m=UserInputService:GetMouseLocation(); local d=m-_fdS
    local vp=workspace.CurrentCamera.ViewportSize; local sz=FloatBtn.AbsoluteSize
    FloatBtn.Position=UDim2.fromOffset(
        math.clamp(_fpS.X.Offset+d.X,0,vp.X-sz.X),
        math.clamp(_fpS.Y.Offset+d.Y,0,vp.Y-sz.Y))
end)

-- =====================================================
-- OPEN ANIMATION
-- =====================================================
Window.Size=UDim2.fromOffset(0,0)
Tw(Window,{Size=UDim2.fromOffset(WIN_W,WIN_H)},0.32,Enum.EasingStyle.Back,Enum.EasingDirection.Out)

warn("[Vechnost v2.4] LOADED!")
warn("[Vechnost v2.4] Shortcut: V = toggle GUI | X = tutup | Float icon = toggle")
warn("[Vechnost v2.4] Rarity baru: FORGOTTEN (tier 8) sudah ditambahkan")
