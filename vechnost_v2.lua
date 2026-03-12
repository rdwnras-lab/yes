--[[
    FILE: vechnost_v2_rayfield.lua
    BRAND: Vechnost
    VERSION: 2.5.2 (BAC-4226 Fixed) - RAYFIELD EDITION
    
    FIX LOG v2.5.2 - ROOT CAUSE BAC-4226:
    -----------------------------------------------
    [CRITICAL] Hapus RunService.RenderStepped - BAC detect koneksi per-frame dari injected script
    [CRITICAL] Hapus SEMUA background task.spawn loop saat idle - loop fishing/stats/webhook
               sekarang hanya jalan saat fitur aktif, berhenti otomatis saat toggle OFF
    [FIX] Anti-AFK menggunakan VirtualUser:ClickButton2 interval 4-6 menit, tanpa getconnections
    [FIX] Semua loop automation berhenti total ketika toggle dimatikan
    -----------------------------------------------
]]

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- ============================================================
-- SECTION 1: SERVICES
-- ============================================================
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local HttpService        = game:GetService("HttpService")
local UserInputService   = game:GetService("UserInputService")
local VirtualUser        = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- SECTION 2: GAME REMOTES
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
-- SECTION 3: HTTP REQUEST
-- ============================================================
local HttpRequest = syn and syn.request
    or (typeof(http_request) == "function" and http_request)
    or (typeof(request) == "function" and request)
    or (fluxus and fluxus.request)
    or nil

-- ============================================================
-- SECTION 4: FISH DATABASE
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
-- SECTION 5: PLAYER DATA (Replion)
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
                local cnt=0; for _ in pairs(items) do cnt=cnt+1 end
                r.BPCount = cnt
            end
            r.BPMax = inv.Capacity or inv.Size or inv.Max or 100
        end
    end)
    return r
end

-- ============================================================
-- SECTION 6: RARITY & CONSTANTS
-- ============================================================
local RARITY_MAP = {[1]="Common",[2]="Uncommon",[3]="Rare",[4]="Epic",
                    [5]="Legendary",[6]="Mythic",[7]="Secret"}
local RARITY_TIER = {Common=1,Uncommon=2,Rare=3,Epic=4,Legendary=5,Mythic=6,Secret=7}
local RARITY_LIST = {"Common","Uncommon","Rare","Epic","Legendary","Mythic","Secret"}

-- ============================================================
-- SECTION 7: ISLAND DATA
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
                        for _, l in ipairs(TeleportLocations) do if l.Name == obj.Name then found=true; break end end
                        if not found then table.insert(TeleportLocations, {Name = obj.Name, CFrame = CFrame.new(pos + Vector3.new(0,5,0))}) end
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
                            for _, l in ipairs(TeleportLocations) do if l.Name == island.Name then found=true; break end end
                            if not found then
                                local pos
                                if obj:IsA("BasePart") then pos = obj.Position
                                elseif obj:IsA("Model") and obj.PrimaryPart then pos = obj.PrimaryPart.Position end
                                if pos then table.insert(TeleportLocations, {Name = island.Name, CFrame = CFrame.new(pos + Vector3.new(0,5,0))}) end
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
            for _, l in ipairs(TeleportLocations) do if l.Name == "Fisherman Island" then found=true; break end end
            if not found then table.insert(TeleportLocations, {Name = "Fisherman Island", CFrame = sp.CFrame + Vector3.new(0,5,0)}) end
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
        if l.Name == name then
            hrp.CFrame = l.CFrame
            return true, "Teleported to " .. name
        end
    end
    return false, "Location not found"
end

local function GetLocNames()
    if #TeleportLocations == 0 then return {"(Klik Scan dulu)"} end
    local t = {}
    for _, l in ipairs(TeleportLocations) do table.insert(t, l.Name) end
    return t
end

-- ============================================================
-- SECTION 8: SHOP DATA
-- ============================================================
local SHOP = {
    Bait     = {"Basic Bait","Worm","Minnow","Shrimp","Sandworm","Firefly",
                "Glowbait","Premium Bait","Lava Bait","Deep Sea Bait","Ancient Bait","Mythic Bait"},
    Rod      = {"Basic Rod","Copper Rod","Iron Rod","Gold Rod","Crystal Rod",
                "Lava Rod","Ocean Rod","Ancient Rod","Mythic Rod","Secret Rod"},
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
    local jitter = math.random(50,150)/1000
    task.delay(jitter, function()
        pcall(function()
            if remote:IsA("RemoteEvent") then remote:FireServer(itemName)
            else remote:InvokeServer(itemName) end
        end)
    end)
    return true
end

-- ============================================================
-- SECTION 9: FISHING REMOTES & STATE
-- ============================================================
local FR = {}
local function FindFishingRemotes()
    FR = {}
    if not net then return end
    for _, child in ipairs(net:GetDescendants()) do
        if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
            local ln = child.Name:lower()
            if not FR.Cast  and (ln:find("cast")  or ln:find("throw")) then FR.Cast  = child
            elseif not FR.Reel  and (ln:find("reel")  or ln:find("pull") or ln:find("catch")) then FR.Reel  = child
            elseif not FR.Shake and (ln:find("shake") or ln:find("struggle") or ln:find("mash"))  then FR.Shake = child
            elseif not FR.Sell  and  ln:find("sell")  then FR.Sell  = child end
        end
    end
end
FindFishingRemotes()

local FS = { AutoCast = false, AutoReel = false, AutoShake = false, AutoSell = false, AntiAFK = false }
local RemoteCD = {}
local function RateOK(key, interval)
    local now = tick()
    if (now - (RemoteCD[key] or 0)) >= interval then
        RemoteCD[key] = now; return true
    end
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
            for _, p in ipairs(patterns) do
                if ln:find(p, 1, true) then return true end
            end
        end
    end
    return false
end
local function IsBiting()  return GuiHasName({"bite","reel","catch","pull","!"}) end
local function IsShaking() return GuiHasName({"shake","struggle","mash","minigame","click"}) end

local FState = { s = "Idle", lastCast = 0, castCD = 4, lastSell = 0 }
local fishThread = nil

local function AnyFishingActive() return FS.AutoCast or FS.AutoReel or FS.AutoShake or FS.AutoSell end

local function StopFishingThread()
    if fishThread then task.cancel(fishThread); fishThread = nil end
    FState.s = "Idle"
end

local function StartFishingThread()
    if fishThread then return end
    fishThread = task.spawn(function()
        while AnyFishingActive() do
            task.wait(math.random(90, 170) / 1000)

            if FS.AutoCast and FR.Cast then
                local now = tick()
                if FState.s == "Idle" and (now - FState.lastCast) >= FState.castCD and not IsBiting() and not IsShaking() then
                    FState.s = "Casting"
                    FState.lastCast = now
                    FState.castCD  = math.random(350, 700) / 100
                    SafeFire(FR.Cast, "cast", 0.5)
                    task.delay(math.random(30,80)/100, function() if FState.s == "Casting" then FState.s = "Waiting" end end)
                end
            end

            if FS.AutoReel and FR.Reel then
                if (FState.s == "Waiting" or FState.s == "Idle") and IsBiting() then
                    FState.s = "Biting"
                    task.delay(math.random(25, 85) / 100, function()
                        if FState.s == "Biting" then
                            FState.s = "Reeling"
                            SafeFire(FR.Reel, "reel", 0.3)
                            task.delay(math.random(6,16)/10, function()
                                if FState.s == "Reeling" and not IsShaking() then FState.s = "Idle" end
                            end)
                        end
                    end)
                end
            end

            if FS.AutoShake and FR.Shake then
                if IsShaking() then
                    if FState.s ~= "Shaking" then FState.s = "Shaking" end
                    SafeFire(FR.Shake, "shake", 1/math.random(8, 14))
                else
                    if FState.s == "Shaking" then
                        FState.s = "Idle"
                        FState.lastCast = tick() - FState.castCD + math.random(10,20)/10
                    end
                end
            end

            if FS.AutoSell and FR.Sell then
                if RateOK("sell_global", math.random(8,12)) then SafeFire(FR.Sell, "sell", 0.5, "All") end
            end
        end
        fishThread = nil
    end)
end

local function SetFishingFeature(key, val)
    FS[key] = val
    if val then StartFishingThread() elseif not AnyFishingActive() then StopFishingThread() end
end

-- ============================================================
-- SECTION 10: ANTI-AFK
-- ============================================================
local afkThread = nil
local function StartAntiAFK()
    if afkThread then return end
    afkThread = task.spawn(function()
        while FS.AntiAFK do
            task.wait(math.random(240, 360))
            if FS.AntiAFK then pcall(function() VirtualUser:ClickButton2(Vector2.new(math.random(50, 400), math.random(50, 400))) end) end
        end
        afkThread = nil
    end)
end
local function StopAntiAFK() FS.AntiAFK = false; if afkThread then task.cancel(afkThread); afkThread = nil end end

-- ============================================================
-- SECTION 11: WEBHOOK & LOGGER
-- ============================================================
local WH = { Active=false, Url="", SentUUID={}, Rarities={}, ServerWide=true, Count=0 }
local IconCache, LogConns = {}, {}

local function FetchIcon(fishId, cb)
    if IconCache[fishId] ~= nil then cb(IconCache[fishId]); return end
    task.spawn(function()
        local fish = FishDB[fishId]
        if not fish or not fish.Icon then IconCache[fishId]=""; cb(""); return end
        local aid = tostring(fish.Icon):match("%d+")
        if not aid then IconCache[fishId]=""; cb(""); return end
        local ok, res = pcall(function() return HttpRequest({Url="https://thumbnails.roblox.com/v1/assets?assetIds="..aid.."&size=420x420&format=Png", Method="GET"}) end)
        if ok and res and res.Body then
            local ok2, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
            if ok2 and data and data.data and data.data[1] then IconCache[fishId] = data.data[1].imageUrl or "" end
        end
        IconCache[fishId] = IconCache[fishId] or ""
        cb(IconCache[fishId])
    end)
end

local function BuildPayload(pname, fishId, weight, mutation)
    local fish = FishDB[fishId]
    if not fish then return nil end
    local rname = RARITY_MAP[fish.Tier] or "Unknown"
    local icon = IconCache[fishId] or ""
    return {
        username="Vechnost Notifier", avatar_url="https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png", flags=32768,
        components={{type=17,components={
            {type=10, content="# NEW FISH CAUGHT!"},
            {type=14, spacing=1, divider=true},
            {type=10, content="__@"..pname.." caught **"..rname:upper().."** fish__"},
            {type=9, components={{type=10,content="**Fish**"},{type=10,content="> "..fish.Name}}, accessory=icon~="" and {type=11,media={url=icon}} or nil},
            {type=10, content="**Rarity:** "..rname}, {type=10, content="**Weight:** "..string.format("%.1fkg", weight or 0)}, {type=10, content="**Mutation:** "..(mutation or "None")},
            {type=14, spacing=1, divider=true}, {type=10, content="-# "..os.date("!%B %d, %Y")}
        }}},
    }
end

local function SendWH(payload)
    if WH.Url == "" or not HttpRequest or not payload then return end
    pcall(function() HttpRequest({Url=WH.Url.."?with_components=true", Method="POST", Headers={["Content-Type"]="application/json"}, Body=HttpService:JSONEncode(payload)}) end)
end

local function OnFishCaught(pArg, wData, wrapper)
    if not WH.Active then return end
    local item = (wrapper and wrapper.InventoryItem) or (wData and wData.InventoryItem)
    if not item or not item.Id or not item.UUID or not FishDB[item.Id] or not (not next(WH.Rarities) or WH.Rarities[FishDB[item.Id].Tier]) or WH.SentUUID[item.UUID] then return end
    WH.SentUUID[item.UUID] = true
    local pname = (typeof(pArg)=="Instance" and pArg.Name) or (type(pArg)=="string" and pArg) or LocalPlayer.Name
    if not WH.ServerWide and pname ~= LocalPlayer.Name then return end
    WH.Count = WH.Count + 1
    FetchIcon(item.Id, function() SendWH(BuildPayload(pname, item.Id, wData and wData.Weight or 0, wData and wData.Mutation or nil)) end)
end

local function StartLogger()
    if WH.Active then return true, "Already running" end
    if not ObtainedNewFish then return false, "Remote not found" end
    WH.Active = true; WH.SentUUID = {}; WH.Count = 0
    LogConns[#LogConns+1] = ObtainedNewFish.OnClientEvent:Connect(OnFishCaught)
    return true, "Logger started"
end
local function StopLogger() WH.Active = false; for _, c in ipairs(LogConns) do pcall(function() c:Disconnect() end) end; LogConns = {} end

-- ============================================================
-- SECTION 12: TRADING
-- ============================================================
local Trade = { Target=nil, Inv={}, ByName={Active=false, Item=nil, Amount=1, Sent=0}, ByRar={Active=false, Tier=nil}, ByStone={Active=false, Stone=nil} }
local STONES = {"Enchant Stone","Evolved Stone"}

local function LoadInv()
    Trade.Inv = {}
    pcall(function()
        local inv = PlayerData:Get("Inventory")
        if not inv then return end
        for _, item in pairs(type(inv.Items or inv)=="table" and (inv.Items or inv) or {}) do
            if type(item)=="table" then
                local name = (item.Id and FishDB[item.Id] and FishDB[item.Id].Name) or (item.Name and tostring(item.Name))
                if name then Trade.Inv[name] = (Trade.Inv[name] or 0) + 1 end
            end
        end
    end)
end

local function GetInvNames()
    local t = {}; for n in pairs(Trade.Inv) do table.insert(t, n) end
    table.sort(t); return #t == 0 and {"(Load inventory first)"} or t
end

local function DoTrade(targetName, itemName, qty)
    local remote = nil
    pcall(function() for _, c in ipairs(net:GetDescendants()) do if (c:IsA("RemoteEvent") or c:IsA("RemoteFunction")) and c.Name:lower():find("trade") then remote = c; break end end end)
    if not remote then return false end
    local tp
    for _, p in ipairs(Players:GetPlayers()) do if p.Name==targetName or p.DisplayName==targetName then tp=p; break end end
    if not tp then return false end
    local id = FishNameToId[itemName] or FishNameToId[itemName:lower()]
    task.delay(math.random(40,70)/100, function() pcall(function() if remote:IsA("RemoteEvent") then remote:FireServer(tp, id or itemName, qty or 1) else remote:InvokeServer(tp, id or itemName, qty or 1) end end) end)
    return true
end

-- ============================================================
-- SECTION 13: RAYFIELD UI INITIALIZATION
-- ============================================================

local Window = Rayfield:CreateWindow({
    Name = "Vechnost v2.5.2 | Rayfield Edition",
    LoadingTitle = "Vechnost Executor",
    LoadingSubtitle = "by Team Vechnost",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false
})

local TabInfo    = Window:CreateTab("Info", 4483362458)
local TabFish    = Window:CreateTab("Fishing", 4483362458)
local TabTele    = Window:CreateTab("Teleport", 4483345998)
local TabTrade   = Window:CreateTab("Trading", 4483362458)
local TabShop    = Window:CreateTab("Shop", 4483345998)
local TabHook    = Window:CreateTab("Webhook", 4483362458)
local TabSet     = Window:CreateTab("Settings", 4483345998)

-- ==================== INFO TAB ====================
TabInfo:CreateSection("Player Info")
TabInfo:CreateParagraph({Title = "Username", Content = LocalPlayer.Name})
local StatsPara = TabInfo:CreateParagraph({Title = "Stats", Content = "Click [Refresh Stats] to load"})

TabInfo:CreateButton({
    Name = "Refresh Stats",
    Callback = function()
        local s = GetStats()
        StatsPara:Set({Title = "Stats", Content = string.format("Coins: %s | Fish: %s | Bag: %d/%d", FmtNum(s.Coins), FmtNum(s.TotalCaught), s.BPCount, s.BPMax)})
    end,
})

TabInfo:CreateSection("About")
TabInfo:CreateParagraph({Title = "Vechnost v2.5.2", Content = "Fix BAC-4226: Zero background loops saat idle\nTidak ada RunService connection\nRayfield Edition"})

-- ==================== FISHING TAB ====================
TabFish:CreateSection("Auto Fishing")
TabFish:CreateParagraph({Title = "Info BAC", Content = "Cast 3.5-7s | Reel 0.25-0.85s delay | Shake 8-14 CPS\nLoop HANYA aktif saat min 1 toggle ON"})

TabFish:CreateToggle({
    Name = "Auto Cast", CurrentValue = false,
    Callback = function(Value) SetFishingFeature("AutoCast", Value); Rayfield:Notify({Title="Vechnost", Content=Value and "Auto Cast ON" or "Auto Cast OFF", Duration=2}) end
})
TabFish:CreateToggle({
    Name = "Auto Reel", CurrentValue = false,
    Callback = function(Value) SetFishingFeature("AutoReel", Value); Rayfield:Notify({Title="Vechnost", Content=Value and "Auto Reel ON" or "Auto Reel OFF", Duration=2}) end
})
TabFish:CreateToggle({
    Name = "Auto Shake", CurrentValue = false,
    Callback = function(Value) SetFishingFeature("AutoShake", Value); Rayfield:Notify({Title="Vechnost", Content=Value and "Auto Shake ON (8-14 CPS)" or "Auto Shake OFF", Duration=2}) end
})

TabFish:CreateSection("Utility")
TabFish:CreateToggle({
    Name = "Anti AFK", CurrentValue = false,
    Callback = function(Value) FS.AntiAFK = Value; if Value then StartAntiAFK() else StopAntiAFK() end; Rayfield:Notify({Title="Vechnost", Content=Value and "Anti AFK ON" or "Anti AFK OFF", Duration=2}) end
})
TabFish:CreateToggle({
    Name = "Auto Sell", CurrentValue = false,
    Callback = function(Value) SetFishingFeature("AutoSell", Value); Rayfield:Notify({Title="Vechnost", Content=Value and "Auto Sell ON" or "Auto Sell OFF", Duration=2}) end
})
TabFish:CreateButton({
    Name = "Re-scan Remotes",
    Callback = function() FindFishingRemotes(); Rayfield:Notify({Title="Vechnost", Content="Remotes scanned.", Duration=2}) end
})

-- ==================== TELEPORT TAB ====================
TabTele:CreateSection("Islands")
TabTele:CreateParagraph({Title = "Petunjuk", Content = "Klik [Scan Islands] terlebih dahulu"})

local TpDropdown = TabTele:CreateDropdown({
    Name = "Select Island", Options = {"(Klik Scan dulu)"}, CurrentOption = {"(Klik Scan dulu)"}, MultipleOptions = false,
    Callback = function(Option)
        if Option[1] and Option[1] ~= "(Klik Scan dulu)" then
            local ok, msg = TeleportTo(Option[1])
            Rayfield:Notify({Title="Vechnost", Content=ok and msg or ("Gagal: "..msg), Duration=2})
        end
    end,
})

TabTele:CreateButton({
    Name = "Scan Islands",
    Callback = function()
        ScanIslands()
        TpDropdown:Refresh(GetLocNames(), true)
        Rayfield:Notify({Title="Vechnost", Content="Ditemukan "..#TeleportLocations.." lokasi", Duration=2})
    end
})

TabTele:CreateSection("Quick TP")
TabTele:CreateButton({
    Name = "TP ke Spawn",
    Callback = function()
        local sp = game:GetService("Workspace"):FindFirstChildOfClass("SpawnLocation")
        if sp and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            LocalPlayer.Character.HumanoidRootPart.CFrame = sp.CFrame + Vector3.new(0,5,0)
        end
    end
})

-- ==================== TRADING TAB ====================
TabTrade:CreateSection("Target Player")
local plNames = {}; for _,pl in ipairs(Players:GetPlayers()) do if pl~=LocalPlayer then plNames[#plNames+1]=pl.Name end end
if #plNames==0 then plNames={"(No players)"} end

local PlDropdown = TabTrade:CreateDropdown({
    Name = "Select Player", Options = plNames, CurrentOption = {plNames[1]}, MultipleOptions = false,
    Callback = function(Option) Trade.Target = Option[1] end
})
TabTrade:CreateButton({
    Name = "Refresh Players",
    Callback = function()
        local t = {}; for _,pl in ipairs(Players:GetPlayers()) do if pl~=LocalPlayer then t[#t+1]=pl.Name end end
        if #t==0 then t={"(No players)"} end
        PlDropdown:Refresh(t, true)
    end
})

TabTrade:CreateSection("Trade by Item")
local TradeStatus = TabTrade:CreateParagraph({Title="Status", Content="Ready"})
local ItemDropdown = TabTrade:CreateDropdown({
    Name = "Select Item", Options = {"(Load inventory)"}, CurrentOption = {"(Load inventory)"}, MultipleOptions = false,
    Callback = function(Option) Trade.ByName.Item = Option[1] end
})
TabTrade:CreateButton({
    Name = "Load Inventory",
    Callback = function() LoadInv(); ItemDropdown:Refresh(GetInvNames(), true) end
})
TabTrade:CreateInput({
    Name = "Amount", PlaceholderText = "1", RemoveTextAfterFocusLost = false,
    Callback = function(Text) local n=tonumber(Text); if n and n>0 then Trade.ByName.Amount=math.floor(n) end end
})
TabTrade:CreateToggle({
    Name = "Start Trade by Name", CurrentValue = false,
    Callback = function(Value)
        if Value then
            if not Trade.Target or not Trade.ByName.Item then Rayfield:Notify({Title="Error", Content="Select Target and Item first!", Duration=3}); return end
            Trade.ByName.Active = true
            task.spawn(function()
                local total=Trade.ByName.Amount; local item=Trade.ByName.Item; local tgt=Trade.Target
                for i=1,total do
                    if not Trade.ByName.Active then break end
                    TradeStatus:Set({Title="Status", Content=("Sending %d/%d %s"):format(i,total,item)})
                    DoTrade(tgt,item,1)
                    task.wait(math.random(40,70)/100)
                end
                Trade.ByName.Active=false
                TradeStatus:Set({Title="Status", Content="Done"})
            end)
        else Trade.ByName.Active = false end
    end
})

-- ==================== SHOP TAB ====================
TabShop:CreateSection("Bait Shop")
local ShopSettings={SelectedBait=nil,AutoBuyBait=false,SelectedRod=nil,AutoBuyRod=false}
TabShop:CreateDropdown({
    Name="Select Bait", Options=SHOP.Bait, CurrentOption={SHOP.Bait[1]}, MultipleOptions=false,
    Callback=function(Option) ShopSettings.SelectedBait = Option[1] end
})
TabShop:CreateToggle({
    Name="Auto Buy Bait", CurrentValue=false,
    Callback=function(Value)
        ShopSettings.AutoBuyBait=Value
        if Value then
            task.spawn(function()
                while ShopSettings.AutoBuyBait do
                    if ShopSettings.SelectedBait then BuyItem("Bait", ShopSettings.SelectedBait) end
                    task.wait(math.random(20,40)/10)
                end
            end)
        end
    end
})

TabShop:CreateSection("Merchant")
local MerDropdown = TabShop:CreateDropdown({
    Name="Select Item", Options=SHOP.Merchant, CurrentOption={SHOP.Merchant[1]}, MultipleOptions=false,
    Callback=function() end
})
TabShop:CreateButton({
    Name="Buy Merchant Item",
    Callback=function() BuyItem("Merchant", MerDropdown.CurrentOption[1]) end
})

-- ==================== WEBHOOK TAB ====================
TabHook:CreateSection("Settings")
TabHook:CreateInput({
    Name = "Webhook URL", PlaceholderText = "https://discord.com/...", RemoveTextAfterFocusLost = false,
    Callback = function(Text) WH.Url = Text:gsub("%s+","") end
})
TabHook:CreateToggle({
    Name = "Server-Wide Notification", CurrentValue = true,
    Callback = function(Value) WH.ServerWide = Value end
})

TabHook:CreateSection("Control")
local HookStatus = TabHook:CreateParagraph({Title="Logger Status", Content="Offline"})
TabHook:CreateToggle({
    Name = "Enable Logger", CurrentValue = false,
    Callback = function(Value)
        if Value then
            if WH.Url=="" then Rayfield:Notify({Title="Error", Content="Set URL First!", Duration=3}); return end
            StartLogger()
            HookStatus:Set({Title="Logger Status", Content="Active"})
        else 
            StopLogger()
            HookStatus:Set({Title="Logger Status", Content="Offline"})
        end
    end
})

-- ==================== SETTING TAB ====================
TabSet:CreateSection("Controls")
TabSet:CreateButton({
    Name = "Unload/Destroy Script",
    Callback = function()
        StopLogger()
        StopAntiAFK()
        StopFishingThread()
        Rayfield:Destroy()
    end
})

Rayfield:Notify({Title = "Vechnost v2.5.2", Content = "Script Loaded Successfully", Duration = 3})
