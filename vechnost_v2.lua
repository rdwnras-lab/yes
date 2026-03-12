--[[
    FILE: vechnost_rayfield.lua
    BRAND: Vechnost
    VERSION: 2.5.2 (Rayfield Edition)
    UI: Rayfield Library
    BAC: Zero background loops saat idle, No RunService connections
]]

-- ============================================================
-- SECTION 1: LOAD RAYFIELD
-- ============================================================
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

-- ============================================================
-- SECTION 2: SERVICES
-- ============================================================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")
local VirtualUser       = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- SECTION 3: HTTP REQUEST (executor compat)
-- ============================================================
local HttpRequest = syn and syn.request
    or (typeof(http_request) == "function" and http_request)
    or (typeof(request) == "function" and request)
    or (fluxus and fluxus.request)
    or nil

-- ============================================================
-- SECTION 4: GAME REMOTES
-- ============================================================
local net, ObtainedNewFish
pcall(function()
    net = ReplicatedStorage
        :WaitForChild("Packages", 10)
        :WaitForChild("_Index", 5)
        :WaitForChild("sleitnick_net@0.2.0", 5)
        :WaitForChild("net", 5)
    ObtainedNewFish = net:WaitForChild("RE/ObtainedNewFishNotification", 5)
end)

-- ============================================================
-- SECTION 5: FISH DATABASE
-- ============================================================
local FishDB = {}
pcall(function()
    local Items = ReplicatedStorage:WaitForChild("Items", 10)
    if not Items then return end
    for _, mod in ipairs(Items:GetChildren()) do
        if mod:IsA("ModuleScript") then
            local ok, m = pcall(require, mod)
            if ok and m and m.Data and m.Data.Type == "Fish" then
                FishDB[m.Data.Id] = {
                    Name      = m.Data.Name,
                    Tier      = m.Data.Tier,
                    Icon      = m.Data.Icon,
                    SellPrice = m.Data.SellPrice or m.Data.Value or 0,
                }
            end
        end
    end
end)

local FishNameToId = {}
for id, d in pairs(FishDB) do
    if d.Name then
        FishNameToId[d.Name] = id
        FishNameToId[d.Name:lower()] = id
    end
end

-- ============================================================
-- SECTION 6: PLAYER DATA (Replion)
-- ============================================================
local PlayerData
pcall(function()
    local Replion = require(ReplicatedStorage.Packages.Replion)
    PlayerData = Replion.Client:WaitReplion("Data")
end)

local function FmtNum(n)
    if type(n) ~= "number" then return "0" end
    local s = tostring(math.floor(n))
    local k
    repeat s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
    return s
end

local function GetStats()
    local r = {Coins=0, TotalCaught=0, BPCount=0, BPMax=100}
    if not PlayerData then return r end
    pcall(function()
        for _, k in ipairs({"Coins","Currency","Money","Gold"}) do
            local ok, v = pcall(function() return PlayerData:Get(k) end)
            if ok and type(v)=="number" then r.Coins = v; break end
        end
        for _, k in ipairs({"TotalCaught","FishCaught"}) do
            local ok, v = pcall(function() return PlayerData:Get(k) end)
            if ok and type(v)=="number" then r.TotalCaught = v; break end
        end
        local inv = PlayerData:Get("Inventory")
        if inv and type(inv)=="table" then
            local items = inv.Items or inv
            if type(items)=="table" then
                local cnt = 0; for _ in pairs(items) do cnt=cnt+1 end
                r.BPCount = cnt
            end
            r.BPMax = inv.Capacity or inv.Size or inv.Max or 100
        end
    end)
    return r
end

-- ============================================================
-- SECTION 7: RARITY & CONSTANTS
-- ============================================================
local RARITY_MAP  = {[1]="Common",[2]="Uncommon",[3]="Rare",[4]="Epic",[5]="Legendary",[6]="Mythic",[7]="Secret"}
local RARITY_TIER = {Common=1,Uncommon=2,Rare=3,Epic=4,Legendary=5,Mythic=6,Secret=7}
local RARITY_LIST = {"Common","Uncommon","Rare","Epic","Legendary","Mythic","Secret"}

-- ============================================================
-- SECTION 8: ISLAND DATA
-- ============================================================
local ISLANDS = {
    {Name="Fisherman Island",   KW={"fisherman","starter","spawn","hub","main"}},
    {Name="Kohana Island",      KW={"kohana"}},
    {Name="Kohana Volcano",     KW={"volcano","lava","magma"}},
    {Name="Coral Reef Island",  KW={"coral","reef"}},
    {Name="Esoteric Depths",    KW={"esoteric","depths","elevator"}},
    {Name="Tropical Grove",     KW={"tropical","grove"}},
    {Name="Crater Island",      KW={"crater","weather"}},
    {Name="Lost Isle",          KW={"lost","isle","sisyphus"}},
    {Name="Ancient Jungle",     KW={"ancient","jungle"}},
    {Name="Classic Island",     KW={"classic"}},
    {Name="Pirate Cove",        KW={"pirate","cove"}},
    {Name="Iron Cavern",        KW={"iron","cavern"}},
    {Name="Ancient Ruins",      KW={"ruins"}},
    {Name="Underground Cellar", KW={"underground","cellar"}},
}

local TeleportLocations = {}

local function ScanIslands()
    TeleportLocations = {}
    pcall(function()
        local ws = game:GetService("Workspace")
        for _, fname in ipairs({"Zones","Islands","Locations","Areas","Map","World"}) do
            local folder = ws:FindFirstChild(fname)
            if folder then
                for _, obj in ipairs(folder:GetChildren()) do
                    local pos
                    if obj:IsA("BasePart") then pos = obj.Position
                    elseif obj:IsA("Model") and obj.PrimaryPart then pos = obj.PrimaryPart.Position
                    elseif obj:IsA("Model") or obj:IsA("Folder") then
                        local bp = obj:FindFirstChildWhichIsA("BasePart", true)
                        if bp then pos = bp.Position end
                    end
                    if pos then
                        local found = false
                        for _, l in ipairs(TeleportLocations) do if l.Name==obj.Name then found=true; break end end
                        if not found then
                            table.insert(TeleportLocations, {Name=obj.Name, CFrame=CFrame.new(pos+Vector3.new(0,5,0))})
                        end
                    end
                end
            end
        end
        for _, obj in ipairs(ws:GetDescendants()) do
            if obj:IsA("BasePart") or obj:IsA("Model") then
                local lname = obj.Name:lower()
                for _, island in ipairs(ISLANDS) do
                    for _, kw in ipairs(island.KW) do
                        if lname:find(kw, 1, true) then
                            local found = false
                            for _, l in ipairs(TeleportLocations) do if l.Name==island.Name then found=true; break end end
                            if not found then
                                local pos
                                if obj:IsA("BasePart") then pos = obj.Position
                                elseif obj:IsA("Model") and obj.PrimaryPart then pos = obj.PrimaryPart.Position end
                                if pos then
                                    table.insert(TeleportLocations, {Name=island.Name, CFrame=CFrame.new(pos+Vector3.new(0,5,0))})
                                end
                            end
                            break
                        end
                    end
                end
            end
        end
    end)
    pcall(function()
        local sp = game:GetService("Workspace"):FindFirstChildOfClass("SpawnLocation")
        if sp then
            local found = false
            for _, l in ipairs(TeleportLocations) do if l.Name=="Fisherman Island" then found=true; break end end
            if not found then
                table.insert(TeleportLocations, {Name="Fisherman Island", CFrame=sp.CFrame+Vector3.new(0,5,0)})
            end
        end
    end)
    table.sort(TeleportLocations, function(a,b) return a.Name < b.Name end)
end

local function TeleportTo(name)
    local char = LocalPlayer.Character
    if not char then return false, "No character" end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false, "No HRP" end
    for _, l in ipairs(TeleportLocations) do
        if l.Name == name then hrp.CFrame = l.CFrame; return true, "Teleported to "..name end
    end
    return false, "Location not found"
end

local function GetLocNames()
    if #TeleportLocations == 0 then return {"(Scan dulu)"} end
    local t = {}
    for _, l in ipairs(TeleportLocations) do table.insert(t, l.Name) end
    return t
end

-- ============================================================
-- SECTION 9: SHOP DATA
-- ============================================================
local SHOP = {
    Bait     = {"Basic Bait","Worm","Minnow","Shrimp","Sandworm","Firefly","Glowbait","Premium Bait","Lava Bait","Deep Sea Bait","Ancient Bait","Mythic Bait"},
    Rod      = {"Basic Rod","Copper Rod","Iron Rod","Gold Rod","Crystal Rod","Lava Rod","Ocean Rod","Ancient Rod","Mythic Rod","Secret Rod"},
    Boat     = {"Basic Boat","Wooden Boat","Speed Boat","Ocean Vessel","Dive Boat"},
    Merchant = {"Enchant Stone","Evolved Stone","Luck Potion","Mutation Potion","XP Boost","Coin Boost"},
    Weather  = {"Sunny","Rainy","Stormy","Foggy","Snowy","Blood Moon","Aurora"},
}

local function FindRemoteByPatterns(patterns)
    if not net then return nil end
    for _, child in ipairs(net:GetDescendants()) do
        if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
            local ln = child.Name:lower()
            for _, p in ipairs(patterns) do
                if ln:find(p, 1, true) then return child end
            end
        end
    end
    return nil
end

local function BuyItem(category, itemName)
    local patterns = {
        Bait     = {"bait","buy","purchase"},
        Rod      = {"rod","buy","purchase"},
        Boat     = {"boat","buy","purchase"},
        Merchant = {"buy","item","purchase","merchant"},
        Weather  = {"weather","setweather","changeweather"},
    }
    local remote = FindRemoteByPatterns(patterns[category] or {})
    if not remote then return false end
    task.delay(math.random(50,150)/1000, function()
        pcall(function()
            if remote:IsA("RemoteEvent") then remote:FireServer(itemName)
            else remote:InvokeServer(itemName) end
        end)
    end)
    return true
end

-- ============================================================
-- SECTION 10: FISHING REMOTES & STATE MACHINE
-- ============================================================
local FR = {}

local function FindFishingRemotes()
    FR = {}
    if not net then return end
    for _, child in ipairs(net:GetDescendants()) do
        if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
            local ln = child.Name:lower()
            if not FR.Cast  and (ln:find("cast") or ln:find("throw"))                         then FR.Cast  = child
            elseif not FR.Reel  and (ln:find("reel") or ln:find("pull") or ln:find("catch"))  then FR.Reel  = child
            elseif not FR.Shake and (ln:find("shake") or ln:find("struggle") or ln:find("mash")) then FR.Shake = child
            elseif not FR.Sell  and  ln:find("sell")                                           then FR.Sell  = child end
        end
    end
end
FindFishingRemotes()

local FS = {AutoCast=false, AutoReel=false, AutoShake=false, AutoSell=false, AntiAFK=false}

local RemoteCD = {}
local function RateOK(key, interval)
    local now = tick()
    if (now - (RemoteCD[key] or 0)) >= interval then RemoteCD[key]=now; return true end
    return false
end

local function SafeFire(remote, cdKey, cdSec, ...)
    if not remote then return end
    if not RateOK(cdKey, cdSec) then return end
    local args = {...}
    task.delay(math.random(20,80)/1000, function()
        pcall(function()
            if remote:IsA("RemoteEvent") then remote:FireServer(table.unpack(args))
            else remote:InvokeServer(table.unpack(args)) end
        end)
    end)
end

local function GuiHasName(patterns)
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return false end
    for _, d in ipairs(pg:GetDescendants()) do
        if d:IsA("GuiObject") and d.Visible then
            local ln = d.Name:lower()
            for _, p in ipairs(patterns) do if ln:find(p,1,true) then return true end end
        end
    end
    return false
end
local function IsBiting()  return GuiHasName({"bite","reel","catch","pull","!"}) end
local function IsShaking() return GuiHasName({"shake","struggle","mash","minigame","click"}) end

local FState = {s="Idle", lastCast=0, castCD=4}
local fishThread = nil

local function AnyFishingActive()
    return FS.AutoCast or FS.AutoReel or FS.AutoShake or FS.AutoSell
end
local function StopFishingThread()
    if fishThread then task.cancel(fishThread); fishThread=nil end
    FState.s = "Idle"
end
local function StartFishingThread()
    if fishThread then return end
    fishThread = task.spawn(function()
        while AnyFishingActive() do
            task.wait(math.random(90,170)/1000)

            if FS.AutoCast and FR.Cast then
                local now = tick()
                if FState.s=="Idle" and (now-FState.lastCast)>=FState.castCD and not IsBiting() and not IsShaking() then
                    FState.s="Casting"; FState.lastCast=now
                    FState.castCD=math.random(350,700)/100
                    SafeFire(FR.Cast,"cast",0.5)
                    task.delay(math.random(30,80)/100, function()
                        if FState.s=="Casting" then FState.s="Waiting" end
                    end)
                end
            end

            if FS.AutoReel and FR.Reel then
                if (FState.s=="Waiting" or FState.s=="Idle") and IsBiting() then
                    FState.s="Biting"
                    task.delay(math.random(25,85)/100, function()
                        if FState.s=="Biting" then
                            FState.s="Reeling"
                            SafeFire(FR.Reel,"reel",0.3)
                            task.delay(math.random(6,16)/10, function()
                                if FState.s=="Reeling" and not IsShaking() then FState.s="Idle" end
                            end)
                        end
                    end)
                end
            end

            if FS.AutoShake and FR.Shake then
                if IsShaking() then
                    if FState.s~="Shaking" then FState.s="Shaking" end
                    SafeFire(FR.Shake,"shake",1/math.random(8,14))
                else
                    if FState.s=="Shaking" then
                        FState.s="Idle"
                        FState.lastCast=tick()-FState.castCD+math.random(10,20)/10
                    end
                end
            end

            if FS.AutoSell and FR.Sell then
                if RateOK("sell_global", math.random(8,12)) then
                    SafeFire(FR.Sell,"sell",0.5,"All")
                end
            end
        end
        fishThread = nil
    end)
end

local function SetFishing(key, val)
    FS[key] = val
    if val then StartFishingThread()
    elseif not AnyFishingActive() then StopFishingThread() end
end

-- ============================================================
-- SECTION 11: ANTI-AFK
-- ============================================================
local afkThread = nil
local function StartAntiAFK()
    if afkThread then return end
    afkThread = task.spawn(function()
        while FS.AntiAFK do
            task.wait(math.random(240,360))
            if FS.AntiAFK then
                pcall(function()
                    VirtualUser:ClickButton2(Vector2.new(math.random(50,400),math.random(50,400)))
                end)
            end
        end
        afkThread = nil
    end)
end
local function StopAntiAFK()
    FS.AntiAFK=false
    if afkThread then task.cancel(afkThread); afkThread=nil end
end

-- ============================================================
-- SECTION 12: WEBHOOK & LOGGER
-- ============================================================
local WH = {Active=false, Url="", SentUUID={}, Rarities={}, ServerWide=true, Count=0}
local IconCache = {}
local LogConns  = {}

local function FetchIcon(fishId, cb)
    if IconCache[fishId]~=nil then cb(IconCache[fishId]); return end
    task.spawn(function()
        local fish = FishDB[fishId]
        if not fish or not fish.Icon then IconCache[fishId]=""; cb(""); return end
        local aid = tostring(fish.Icon):match("%d+")
        if not aid then IconCache[fishId]=""; cb(""); return end
        local ok, res = pcall(function()
            return HttpRequest({
                Url    = "https://thumbnails.roblox.com/v1/assets?assetIds="..aid.."&size=420x420&format=Png",
                Method = "GET",
            })
        end)
        if ok and res and res.Body then
            local ok2, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
            if ok2 and data and data.data and data.data[1] then
                IconCache[fishId] = data.data[1].imageUrl or ""
            end
        end
        IconCache[fishId] = IconCache[fishId] or ""
        cb(IconCache[fishId])
    end)
end

local function RarityOK(fishId)
    local fish = FishDB[fishId]
    if not fish then return false end
    if not next(WH.Rarities) then return true end
    return WH.Rarities[fish.Tier] == true
end

local function BuildPayload(pname, fishId, weight, mutation)
    local fish = FishDB[fishId]
    if not fish then return nil end
    local rname = RARITY_MAP[fish.Tier] or "Unknown"
    local icon  = IconCache[fishId] or ""
    return {
        username   = "Vechnost Notifier",
        avatar_url = "https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png",
        flags      = 32768,
        components = {{
            type       = 17,
            components = {
                {type=10, content="# NEW FISH CAUGHT!"},
                {type=14, spacing=1, divider=true},
                {type=10, content="__@"..pname.." caught **"..rname:upper().."** fish__"},
                {type=9,  components={{type=10,content="**Fish**"},{type=10,content="> "..fish.Name}},
                          accessory=icon~="" and {type=11,media={url=icon}} or nil},
                {type=10, content="**Rarity:** "..rname},
                {type=10, content="**Weight:** "..string.format("%.1fkg",weight or 0)},
                {type=10, content="**Mutation:** "..(mutation or "None")},
                {type=14, spacing=1, divider=true},
                {type=10, content="-# "..os.date("!%B %d, %Y")},
            },
        }},
    }
end

local function SendWH(payload)
    if WH.Url=="" or not HttpRequest or not payload then return end
    pcall(function()
        local url = WH.Url..(WH.Url:find("?") and "&" or "?").."with_components=true"
        HttpRequest({Url=url, Method="POST",
            Headers={["Content-Type"]="application/json"},
            Body=HttpService:JSONEncode(payload)})
    end)
end

local function OnFishCaught(pArg, wData, wrapper)
    if not WH.Active then return end
    local item = (wrapper and wrapper.InventoryItem) or (wData and wData.InventoryItem)
    if not item or not item.Id or not item.UUID then return end
    if not FishDB[item.Id] then return end
    if not RarityOK(item.Id) then return end
    if WH.SentUUID[item.UUID] then return end
    WH.SentUUID[item.UUID] = true
    local pname = LocalPlayer.Name
    if typeof(pArg)=="Instance" and pArg:IsA("Player") then pname=pArg.Name
    elseif type(pArg)=="string" then pname=pArg end
    if not WH.ServerWide and pname~=LocalPlayer.Name then return end
    local weight   = wData and wData.Weight   or 0
    local mutation = wData and wData.Mutation or nil
    WH.Count = WH.Count+1
    FetchIcon(item.Id, function() SendWH(BuildPayload(pname,item.Id,weight,mutation)) end)
end

local function StartLogger()
    if WH.Active then return true, "Already running" end
    if not ObtainedNewFish then return false, "Remote not found" end
    WH.Active=true; WH.SentUUID={}; WH.Count=0
    LogConns[#LogConns+1] = ObtainedNewFish.OnClientEvent:Connect(OnFishCaught)
    return true, "Logger started"
end

local function StopLogger()
    WH.Active=false
    for _,c in ipairs(LogConns) do pcall(function() c:Disconnect() end) end
    LogConns={}
end

-- ============================================================
-- SECTION 13: TRADING
-- ============================================================
local Trade = {
    Target  = nil,
    Inv     = {},
    ByName  = {Active=false, Item=nil, Amount=1, Sent=0},
}
local STONES = {"Enchant Stone","Evolved Stone"}

local function LoadInv()
    Trade.Inv = {}
    pcall(function()
        local inv = PlayerData:Get("Inventory")
        if not inv then return end
        local items = inv.Items or inv
        if type(items)~="table" then return end
        for _, item in pairs(items) do
            if type(item)=="table" then
                local name
                if item.Id and FishDB[item.Id] then name=FishDB[item.Id].Name
                elseif item.Name then name=tostring(item.Name) end
                if name then Trade.Inv[name]=(Trade.Inv[name] or 0)+1 end
            end
        end
    end)
end

local function GetInvNames()
    local t={}
    for n in pairs(Trade.Inv) do table.insert(t,n) end
    table.sort(t)
    if #t==0 then return {"(No items)"} end
    return t
end

local TradeRemote
local function GetTradeRemote()
    if TradeRemote then return TradeRemote end
    pcall(function()
        for _,c in ipairs(net:GetDescendants()) do
            if (c:IsA("RemoteEvent") or c:IsA("RemoteFunction")) and c.Name:lower():find("trade") then
                TradeRemote=c; break
            end
        end
    end)
    return TradeRemote
end

local function DoTrade(targetName, itemName, qty)
    local remote = GetTradeRemote()
    if not remote then return false end
    local tp
    for _,p in ipairs(Players:GetPlayers()) do
        if p.Name==targetName or p.DisplayName==targetName then tp=p; break end
    end
    if not tp then return false end
    local id = FishNameToId[itemName] or FishNameToId[itemName:lower()]
    task.delay(math.random(40,70)/100, function()
        pcall(function()
            if remote:IsA("RemoteEvent") then remote:FireServer(tp,id or itemName,qty or 1)
            else remote:InvokeServer(tp,id or itemName,qty or 1) end
        end)
    end)
    return true
end

-- ============================================================
-- SECTION 14: RAYFIELD WINDOW
-- ============================================================
local Window = Rayfield:CreateWindow({
    Name             = "Vechnost v2.5.2",
    LoadingTitle     = "Vechnost",
    LoadingSubtitle  = "Fish It Automation Suite",
    Theme            = "DarkBlue",
    DisableRayfieldPrompts  = true,
    DisableBuildWarnings    = false,
    ConfigurationSaving     = {Enabled = false},
    Discord                 = {Enabled = false},
    KeySystem               = false,
})

-- ============================================================
-- SECTION 15: TAB — INFO
-- ============================================================
local TabInfo = Window:CreateTab("Info", 4483362458)

TabInfo:CreateParagraph({
    Title   = "Player",
    Content = LocalPlayer.Name .. " | " .. LocalPlayer.DisplayName,
})

local StatsPara = TabInfo:CreateParagraph({
    Title   = "Stats",
    Content = "Klik tombol Refresh di bawah untuk memuat statistik",
})

TabInfo:CreateButton({
    Title       = "Refresh Stats",
    Description = "Muat ulang statistik karakter",
    Callback    = function()
        local s = GetStats()
        StatsPara:Set(string.format("Coins: %s | Fish: %s | Bag: %d/%d",
            FmtNum(s.Coins), FmtNum(s.TotalCaught), s.BPCount, s.BPMax))
        Rayfield:Notify({Title="Stats",Content="Stats dimuat!",Duration=2})
    end,
})

TabInfo:CreateParagraph({
    Title   = "BAC Bypass v2.5.2",
    Content = "✓ Zero loop saat idle\n✓ No RunService connection\n✓ No exploit API on init\n✓ State Machine fishing\n✓ Rate-limited semua remote",
})

TabInfo:CreateParagraph({
    Title   = "About",
    Content = "Fish It Automation Suite\nDiscord: discord.gg/vechnost",
})

-- ============================================================
-- SECTION 16: TAB — FISHING
-- ============================================================
local TabFish = Window:CreateTab("Fishing", 4483362458)

TabFish:CreateParagraph({
    Title   = "Info BAC Bypass",
    Content = "Cast: 3.5–7s interval\nReel: 0.25–0.85s delay reaksi\nShake: 8–14 CPS throttled\nLoop HANYA aktif saat toggle ON",
})

TabFish:CreateSection("Auto Fishing")

TabFish:CreateToggle({
    Title         = "Auto Cast",
    Description   = "Otomatis lempar kail dengan interval random",
    CurrentValue  = false,
    Callback      = function(v)
        SetFishing("AutoCast", v)
        Rayfield:Notify({Title="Auto Cast", Content=v and "ON (3.5-7s interval)" or "OFF", Duration=2})
    end,
})

TabFish:CreateToggle({
    Title         = "Auto Reel",
    Description   = "Otomatis tarik saat ikan menggigit",
    CurrentValue  = false,
    Callback      = function(v)
        SetFishing("AutoReel", v)
        Rayfield:Notify({Title="Auto Reel", Content=v and "ON (human delay 0.25-0.85s)" or "OFF", Duration=2})
    end,
})

TabFish:CreateToggle({
    Title         = "Auto Shake",
    Description   = "Otomatis klik saat minigame shake (8-14 CPS)",
    CurrentValue  = false,
    Callback      = function(v)
        SetFishing("AutoShake", v)
        Rayfield:Notify({Title="Auto Shake", Content=v and "ON (8-14 CPS)" or "OFF", Duration=2})
    end,
})

TabFish:CreateSection("Utility")

TabFish:CreateToggle({
    Title         = "Anti AFK",
    Description   = "Mencegah kick AFK (VirtualUser 4-6 menit interval)",
    CurrentValue  = false,
    Callback      = function(v)
        FS.AntiAFK = v
        if v then StartAntiAFK() else StopAntiAFK() end
        Rayfield:Notify({Title="Anti AFK", Content=v and "ON (4-6 min interval)" or "OFF", Duration=2})
    end,
})

TabFish:CreateToggle({
    Title         = "Auto Sell",
    Description   = "Jual semua ikan otomatis tiap 8-12 detik",
    CurrentValue  = false,
    Callback      = function(v)
        SetFishing("AutoSell", v)
        Rayfield:Notify({Title="Auto Sell", Content=v and "ON (8-12s)" or "OFF", Duration=2})
    end,
})

TabFish:CreateButton({
    Title       = "Re-scan Remotes",
    Description = "Cari ulang remote fishing dari game",
    Callback    = function()
        FindFishingRemotes()
        local f={}
        if FR.Cast  then f[#f+1]="Cast"  end
        if FR.Reel  then f[#f+1]="Reel"  end
        if FR.Shake then f[#f+1]="Shake" end
        if FR.Sell  then f[#f+1]="Sell"  end
        Rayfield:Notify({
            Title   = "Remotes",
            Content = "Found: "..(#f>0 and table.concat(f,", ") or "tidak ada"),
            Duration = 3,
        })
    end,
})

-- ============================================================
-- SECTION 17: TAB — TELEPORT
-- ============================================================
local TabTP = Window:CreateTab("Teleport", 4483362458)

TabTP:CreateParagraph({
    Title   = "Petunjuk",
    Content = "1. Klik [Scan Islands] untuk mendeteksi lokasi dari Workspace\n2. Pilih island di dropdown lalu klik [Teleport]",
})

local tpSelected = nil
local tpDropdown = TabTP:CreateDropdown({
    Title          = "Select Island",
    Description    = "Klik Scan Islands dulu",
    Values         = {"(Scan dulu)"},
    CurrentOption  = {"(Scan dulu)"},
    MultiSelection = false,
    Callback       = function(v)
        tpSelected = type(v)=="table" and v[1] or v
    end,
})

TabTP:CreateButton({
    Title       = "Scan Islands",
    Description = "Deteksi semua lokasi dari Workspace game",
    Callback    = function()
        ScanIslands()
        local names = GetLocNames()
        tpDropdown:Set(names)
        Rayfield:Notify({
            Title   = "Scan Selesai",
            Content = "Ditemukan "..#TeleportLocations.." lokasi",
            Duration = 3,
        })
    end,
})

TabTP:CreateButton({
    Title       = "Teleport ke Lokasi",
    Description = "TP ke island yang dipilih di dropdown",
    Callback    = function()
        if not tpSelected or tpSelected=="(Scan dulu)" then
            Rayfield:Notify({Title="Error",Content="Pilih island dulu!",Duration=2}); return
        end
        local ok, msg = TeleportTo(tpSelected)
        Rayfield:Notify({Title=ok and "Teleport" or "Gagal", Content=msg, Duration=2})
    end,
})

TabTP:CreateSection("Quick Teleport")

TabTP:CreateButton({
    Title       = "TP ke Spawn",
    Description = "Teleport ke Fisherman Island (SpawnLocation)",
    Callback    = function()
        local char = LocalPlayer.Character
        if not char or not char:FindFirstChild("HumanoidRootPart") then return end
        local sp = game:GetService("Workspace"):FindFirstChildOfClass("SpawnLocation")
        if sp then
            char.HumanoidRootPart.CFrame = sp.CFrame + Vector3.new(0,5,0)
            Rayfield:Notify({Title="Teleport",Content="Teleported to Spawn",Duration=2})
        else
            Rayfield:Notify({Title="Error",Content="SpawnLocation not found",Duration=2})
        end
    end,
})

TabTP:CreateButton({
    Title       = "TP ke Pemain Terdekat",
    Description = "Teleport ke karakter pemain terdekat",
    Callback    = function()
        local char = LocalPlayer.Character
        if not char or not char:FindFirstChild("HumanoidRootPart") then return end
        local myPos = char.HumanoidRootPart.Position
        local near, nearD = nil, math.huge
        for _,pl in ipairs(Players:GetPlayers()) do
            if pl~=LocalPlayer and pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") then
                local d = (pl.Character.HumanoidRootPart.Position-myPos).Magnitude
                if d < nearD then nearD=d; near=pl end
            end
        end
        if near then
            char.HumanoidRootPart.CFrame = near.Character.HumanoidRootPart.CFrame + Vector3.new(3,0,0)
            Rayfield:Notify({Title="Teleport",Content="TP to "..near.Name,Duration=2})
        else
            Rayfield:Notify({Title="Error",Content="Tidak ada pemain",Duration=2})
        end
    end,
})

-- ============================================================
-- SECTION 18: TAB — TRADING
-- ============================================================
local TabTrade = Window:CreateTab("Trading", 4483362458)

TabTrade:CreateSection("Target Player")

local tradeTargetSel = nil
local playerListDD = TabTrade:CreateDropdown({
    Title          = "Select Player",
    Description    = "Pilih target trade",
    Values         = (function()
        local t={}
        for _,pl in ipairs(Players:GetPlayers()) do
            if pl~=LocalPlayer then t[#t+1]=pl.Name end
        end
        if #t==0 then t={"(No players)"} end
        return t
    end)(),
    CurrentOption  = {""},
    MultiSelection = false,
    Callback       = function(v)
        tradeTargetSel = type(v)=="table" and v[1] or v
        Trade.Target = tradeTargetSel
        Rayfield:Notify({Title="Trading",Content="Target: "..(tradeTargetSel or "-"),Duration=2})
    end,
})

TabTrade:CreateButton({
    Title       = "Refresh Player List",
    Description = "Perbarui daftar pemain di server",
    Callback    = function()
        local t={}
        for _,pl in ipairs(Players:GetPlayers()) do
            if pl~=LocalPlayer then t[#t+1]=pl.Name end
        end
        if #t==0 then t={"(No players)"} end
        playerListDD:Set(t)
        Rayfield:Notify({Title="Players",Content="Found "..#t.." players",Duration=2})
    end,
})

TabTrade:CreateSection("Trade by Item")

local invItemSel = nil
local invItemDD = TabTrade:CreateDropdown({
    Title          = "Select Item",
    Description    = "Load inventory dulu",
    Values         = {"(Load inventory)"},
    CurrentOption  = {"(Load inventory)"},
    MultiSelection = false,
    Callback       = function(v)
        invItemSel = type(v)=="table" and v[1] or v
        Trade.ByName.Item = invItemSel
    end,
})

TabTrade:CreateButton({
    Title       = "Load Inventory",
    Description = "Muat item dari backpack karakter",
    Callback    = function()
        LoadInv()
        local names = GetInvNames()
        invItemDD:Set(names)
        Rayfield:Notify({Title="Inventory",Content="Loaded "..#names.." items",Duration=2})
    end,
})

TabTrade:CreateInput({
    Title         = "Amount",
    Description   = "Jumlah item yang akan di-trade",
    CurrentValue  = "1",
    PlaceholderText = "Masukkan angka",
    Numeric       = true,
    Finished      = false,
    Callback      = function(v)
        local n = tonumber(v)
        if n and n>0 then Trade.ByName.Amount=math.floor(n) end
    end,
})

local tradeByNameActive = false
TabTrade:CreateToggle({
    Title         = "Start Trade by Name",
    Description   = "Mulai trade otomatis ke target",
    CurrentValue  = false,
    Callback      = function(v)
        if v then
            if not Trade.Target then
                Rayfield:Notify({Title="Error",Content="Pilih target dulu!",Duration=3}); return end
            if not Trade.ByName.Item then
                Rayfield:Notify({Title="Error",Content="Pilih item dulu!",Duration=3}); return end
            Trade.ByName.Active=true; Trade.ByName.Sent=0; tradeByNameActive=true
            task.spawn(function()
                local total=Trade.ByName.Amount; local item=Trade.ByName.Item; local tgt=Trade.Target
                for i=1,total do
                    if not Trade.ByName.Active then break end
                    DoTrade(tgt,item,1); Trade.ByName.Sent=i
                    task.wait(math.random(40,70)/100)
                end
                Trade.ByName.Active=false; tradeByNameActive=false
                Rayfield:Notify({
                    Title   = "Trade Selesai",
                    Content = string.format("Terkirim: %d/%d %s", Trade.ByName.Sent, total, item),
                    Duration = 3,
                })
            end)
        else
            Trade.ByName.Active=false; tradeByNameActive=false
        end
    end,
})

TabTrade:CreateSection("Trade by Rarity")

TabTrade:CreateDropdown({
    Title          = "Select Rarity",
    Description    = "Pilih rarity untuk trade",
    Values         = RARITY_LIST,
    CurrentOption  = {"Common"},
    MultiSelection = false,
    Callback       = function(v)
        local sel = type(v)=="table" and v[1] or v
        if sel then
            Rayfield:Notify({Title="Rarity",Content="Selected: "..sel,Duration=2})
        end
    end,
})

TabTrade:CreateSection("Trade Stone")

TabTrade:CreateDropdown({
    Title          = "Select Stone",
    Description    = "Pilih jenis stone",
    Values         = STONES,
    CurrentOption  = {STONES[1]},
    MultiSelection = false,
    Callback       = function(_) end,
})

-- ============================================================
-- SECTION 19: TAB — SHOP
-- ============================================================
local TabShop = Window:CreateTab("Shop", 4483362458)

TabShop:CreateSection("Bait Shop")

local baitSel = nil
local baitDD = TabShop:CreateDropdown({
    Title          = "Select Bait",
    Description    = "Pilih jenis umpan",
    Values         = SHOP.Bait,
    CurrentOption  = {SHOP.Bait[1]},
    MultiSelection = false,
    Callback       = function(v) baitSel = type(v)=="table" and v[1] or v end,
})

local autoBaitActive = false
TabShop:CreateToggle({
    Title         = "Auto Buy Bait",
    Description   = "Beli bait otomatis setiap 2-4 detik",
    CurrentValue  = false,
    Callback      = function(v)
        autoBaitActive = v
        if v then
            task.spawn(function()
                while autoBaitActive do
                    if baitSel then BuyItem("Bait", baitSel) end
                    task.wait(math.random(20,40)/10)
                end
            end)
        end
        Rayfield:Notify({Title="Bait Shop",Content=v and "Auto Buy ON" or "Auto Buy OFF",Duration=2})
    end,
})

TabShop:CreateSection("Rod Shop")

local rodSel = nil
local rodDD = TabShop:CreateDropdown({
    Title          = "Select Rod",
    Description    = "Pilih jenis joran",
    Values         = SHOP.Rod,
    CurrentOption  = {SHOP.Rod[1]},
    MultiSelection = false,
    Callback       = function(v) rodSel = type(v)=="table" and v[1] or v end,
})

local autoRodActive = false
TabShop:CreateToggle({
    Title         = "Auto Buy Rod",
    Description   = "Beli rod otomatis setiap 3-5 detik",
    CurrentValue  = false,
    Callback      = function(v)
        autoRodActive = v
        if v then
            task.spawn(function()
                while autoRodActive do
                    if rodSel then BuyItem("Rod", rodSel) end
                    task.wait(math.random(30,50)/10)
                end
            end)
        end
        Rayfield:Notify({Title="Rod Shop",Content=v and "Auto Buy ON" or "Auto Buy OFF",Duration=2})
    end,
})

TabShop:CreateSection("Merchant")

local merchantSel = nil
TabShop:CreateDropdown({
    Title          = "Select Item",
    Description    = "Pilih item dari merchant",
    Values         = SHOP.Merchant,
    CurrentOption  = {SHOP.Merchant[1]},
    MultiSelection = false,
    Callback       = function(v) merchantSel = type(v)=="table" and v[1] or v end,
})

TabShop:CreateButton({
    Title       = "Buy Item",
    Description = "Beli item yang dipilih dari merchant",
    Callback    = function()
        if merchantSel then
            BuyItem("Merchant", merchantSel)
            Rayfield:Notify({Title="Merchant",Content="Purchased: "..merchantSel,Duration=2})
        else
            Rayfield:Notify({Title="Error",Content="Pilih item dulu!",Duration=2})
        end
    end,
})

TabShop:CreateSection("Weather Machine (Crater Island)")

TabShop:CreateParagraph({
    Title   = "Info",
    Content = "Teleport ke Crater Island dulu sebelum menggunakan fitur ini",
})

local weatherSel = nil
TabShop:CreateDropdown({
    Title          = "Select Weather",
    Description    = "Pilih cuaca",
    Values         = SHOP.Weather,
    CurrentOption  = {SHOP.Weather[1]},
    MultiSelection = false,
    Callback       = function(v) weatherSel = type(v)=="table" and v[1] or v end,
})

TabShop:CreateButton({
    Title       = "Request Weather",
    Description = "Kirim request perubahan cuaca",
    Callback    = function()
        if weatherSel then
            BuyItem("Weather", weatherSel)
            Rayfield:Notify({Title="Weather",Content="Request: "..weatherSel,Duration=2})
        else
            Rayfield:Notify({Title="Error",Content="Pilih weather dulu!",Duration=2})
        end
    end,
})

-- ============================================================
-- SECTION 20: TAB — WEBHOOK
-- ============================================================
local TabWH = Window:CreateTab("Webhook", 4483362458)

TabWH:CreateSection("Rarity Filter")

local whRaritySel = nil
TabWH:CreateDropdown({
    Title          = "Filter Rarity",
    Description    = "Hanya log rarity tertentu (kosong = semua)",
    Values         = RARITY_LIST,
    CurrentOption  = {""},
    MultiSelection = false,
    Callback       = function(v)
        whRaritySel = type(v)=="table" and v[1] or v
        WH.Rarities = {}
        local t = RARITY_TIER[whRaritySel]
        if t then WH.Rarities[t]=true end
        Rayfield:Notify({Title="Filter",Content="Filter: "..(whRaritySel or "All"),Duration=2})
    end,
})

TabWH:CreateButton({
    Title       = "Clear Filter (All Rarity)",
    Description = "Reset filter ke semua rarity",
    Callback    = function()
        WH.Rarities={}; whRaritySel=nil
        Rayfield:Notify({Title="Filter",Content="All rarities diaktifkan",Duration=2})
    end,
})

TabWH:CreateSection("URL Setup")

local webhookUrlBuf = ""
TabWH:CreateInput({
    Title         = "Discord Webhook URL",
    Description   = "Paste URL webhook Discord kamu",
    CurrentValue  = "",
    PlaceholderText = "https://discord.com/api/webhooks/...",
    Numeric       = false,
    Finished      = false,
    Callback      = function(v) webhookUrlBuf = v end,
})

TabWH:CreateButton({
    Title       = "Save Webhook URL",
    Description = "Simpan URL dan validasi format",
    Callback    = function()
        local url = webhookUrlBuf:gsub("%s+","")
        if not url:match("^https://discord") then
            Rayfield:Notify({Title="Error",Content="URL tidak valid!",Duration=3}); return
        end
        WH.Url = url
        Rayfield:Notify({Title="Webhook",Content="URL tersimpan!",Duration=2})
    end,
})

TabWH:CreateSection("Mode & Control")

TabWH:CreateToggle({
    Title         = "Server-Wide Mode",
    Description   = "Log tangkapan semua pemain di server",
    CurrentValue  = true,
    Callback      = function(v)
        WH.ServerWide = v
        Rayfield:Notify({Title="Mode",Content=v and "Server-Wide" or "Local Only",Duration=2})
    end,
})

local logToggleRef = nil
logToggleRef = TabWH:CreateToggle({
    Title         = "Enable Logger",
    Description   = "Aktifkan fish logger ke Discord",
    CurrentValue  = false,
    Callback      = function(v)
        if v then
            if WH.Url=="" then
                Rayfield:Notify({Title="Error",Content="Set URL dulu!",Duration=3})
                if logToggleRef then logToggleRef:Set(false) end
                return
            end
            local ok, msg = StartLogger()
            if ok then Rayfield:Notify({Title="Logger",Content="Logger ON!",Duration=2})
            else
                Rayfield:Notify({Title="Error",Content=msg,Duration=3})
                if logToggleRef then logToggleRef:Set(false) end
            end
        else
            StopLogger()
            Rayfield:Notify({Title="Logger",Content="Logger OFF",Duration=2})
        end
    end,
})

TabWH:CreateSection("Status")

TabWH:CreateButton({
    Title       = "Refresh Status",
    Description = "Cek status logger saat ini",
    Callback    = function()
        local status = WH.Active
            and string.format("AKTIF | %s | Logged: %d", WH.ServerWide and "Server-Wide" or "Local", WH.Count)
            or "OFFLINE"
        Rayfield:Notify({Title="Logger Status",Content=status,Duration=3})
    end,
})

-- ============================================================
-- SECTION 21: TAB — SETTING
-- ============================================================
local TabSetting = Window:CreateTab("Setting", 4483362458)

TabSetting:CreateSection("Test & Debug")

TabSetting:CreateButton({
    Title       = "Test Webhook",
    Description = "Kirim pesan test ke Discord webhook",
    Callback    = function()
        if WH.Url=="" then
            Rayfield:Notify({Title="Error",Content="Set URL dulu!",Duration=3}); return
        end
        SendWH({
            username   = "Vechnost Notifier",
            avatar_url = "https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png",
            flags      = 32768,
            components = {{type=17, components={
                {type=10, content="**Test Message**"},
                {type=14, spacing=1, divider=true},
                {type=10, content="Webhook OK!\n**From:** "..LocalPlayer.Name.."\n**Script:** Vechnost v2.5.2 Rayfield"},
                {type=10, content="-# "..os.date("!%B %d, %Y")},
            }}}
        })
        Rayfield:Notify({Title="Webhook",Content="Test message terkirim!",Duration=2})
    end,
})

TabSetting:CreateButton({
    Title       = "Reset Log Counter",
    Description = "Reset counter webhook ke 0",
    Callback    = function()
        WH.Count=0; WH.SentUUID={}
        Rayfield:Notify({Title="Reset",Content="Counter direset!",Duration=2})
    end,
})

TabSetting:CreateButton({
    Title       = "Re-scan All Remotes",
    Description = "Cari ulang semua remote fishing",
    Callback    = function()
        FindFishingRemotes()
        local f={}
        if FR.Cast  then f[#f+1]="Cast"  end
        if FR.Reel  then f[#f+1]="Reel"  end
        if FR.Shake then f[#f+1]="Shake" end
        if FR.Sell  then f[#f+1]="Sell"  end
        Rayfield:Notify({
            Title   = "Remotes",
            Content = #f>0 and table.concat(f,", ") or "Tidak ada remote ditemukan",
            Duration = 3,
        })
    end,
})

TabSetting:CreateSection("BAC Bypass Notes")

TabSetting:CreateParagraph({
    Title   = "Fix Log v2.5.2",
    Content = "• No RunService.RenderStepped\n• Zero background thread saat idle\n• State machine fishing\n• Rate limiter semua remote\n• VirtualInputManager dihapus total\n• Scan dilakukan on-demand",
})

TabSetting:CreateSection("Credits")

TabSetting:CreateParagraph({
    Title   = "Vechnost Team",
    Content = "Discord: discord.gg/vechnost\nUI: Rayfield by Sirius",
})

-- ============================================================
-- INIT
-- ============================================================
warn("[Vechnost] v2.5.2 Rayfield Edition loaded!")
Rayfield:Notify({
    Title    = "Vechnost v2.5.2",
    Content  = "Rayfield Edition loaded!\nBAC-4226 Bypassed",
    Duration = 4,
    Image    = 4483362458,
})
