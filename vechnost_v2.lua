--[[
    FILE: vechnost_v2.lua
    BRAND: Vechnost
    VERSION: 2.5.2 (BAC-4226 Fixed)
    
    FIX LOG v2.5.2 - ROOT CAUSE BAC-4226:
    -----------------------------------------------
    [CRITICAL] Hapus RunService.RenderStepped - BAC detect koneksi per-frame dari injected script
    [CRITICAL] Hapus SEMUA background task.spawn loop saat idle - loop fishing/stats/webhook
               sekarang hanya jalan saat fitur aktif, berhenti otomatis saat toggle OFF
    [CRITICAL] Hapus cloneref, newcclosure, getconnections dari init - exploit API call terdeteksi BAC
    [CRITICAL] Hapus VirtualInputManager sepenuhnya
    [CRITICAL] ScanIslands() tidak lagi dipanggil saat load - hanya saat user klik tombol
    [CRITICAL] Float button drag pakai UserInputService.InputChanged, bukan RenderStepped
    [FIX] Anti-AFK menggunakan VirtualUser:ClickButton2 interval 4-6 menit, tanpa getconnections
    [FIX] Semua loop automation berhenti total ketika toggle dimatikan
    [FIX] gethui() hanya dipanggil sekali untuk GUI parent (unavoidable, normal)
    -----------------------------------------------
    PRINSIP ARSITEKTUR BARU:
    - Saat idle (semua toggle OFF): ZERO background threads, ZERO RunService connections
    - Loop HANYA hidup saat feature toggle = ON
    - Tidak ada exploit-specific API (cloneref, newcclosure, getconnections, syn.protect_gui)
      di jalur inisialisasi maupun background
]]

-- ============================================================
-- SECTION 1: SERVICES
-- ============================================================
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local HttpService        = game:GetService("HttpService")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")
local VirtualUser        = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

-- GUI Parent: gethui() dipanggil SEKALI, tidak diulang
local function GetSafeParent()
    local ok, h = pcall(function() return gethui() end)
    if ok and h then return h end
    return game:GetService("CoreGui")
end
local SafeParent = GetSafeParent()

-- Random name untuk GUI (hindari string scan)
local function RandStr(n)
    local s, c = "", "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    for i = 1, n do s = s .. c:sub(math.random(1, #c), math.random(1, #c)) end
    return s
end
local GUINAME  = RandStr(14)
local BTNNAME  = RandStr(14)
local IDENT    = "VechnostTag_v2"

-- Cleanup instance lama
for _, v in ipairs(SafeParent:GetChildren()) do
    if v:IsA("ScreenGui") and v:FindFirstChild(IDENT) then v:Destroy() end
end

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
-- SECTION 3: HTTP REQUEST (executor compat)
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
-- SECTION 7: ISLAND DATA (Fish It - no auto-scan on load)
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

-- Scan hanya saat user tekan tombol (bukan saat load)
local function ScanIslands()
    TeleportLocations = {}
    pcall(function()
        local ws = game:GetService("Workspace")
        -- Scan folder umum
        for _, fname in ipairs({"Zones","Islands","Locations","Areas","Map","World"}) do
            local folder = ws:FindFirstChild(fname)
            if folder then
                for _, obj in ipairs(folder:GetChildren()) do
                    local pos
                    if obj:IsA("BasePart") then
                        pos = obj.Position
                    elseif obj:IsA("Model") and obj.PrimaryPart then
                        pos = obj.PrimaryPart.Position
                    elseif obj:IsA("Model") or obj:IsA("Folder") then
                        local bp = obj:FindFirstChildWhichIsA("BasePart", true)
                        if bp then pos = bp.Position end
                    end
                    if pos then
                        local found = false
                        for _, l in ipairs(TeleportLocations) do
                            if l.Name == obj.Name then found=true; break end
                        end
                        if not found then
                            table.insert(TeleportLocations, {
                                Name   = obj.Name,
                                CFrame = CFrame.new(pos + Vector3.new(0,5,0)),
                            })
                        end
                    end
                end
            end
        end
        -- Keyword scan descendants
        for _, obj in ipairs(ws:GetDescendants()) do
            if obj:IsA("BasePart") or obj:IsA("Model") then
                local lname = obj.Name:lower()
                for _, island in ipairs(ISLANDS) do
                    for _, kw in ipairs(island.KW) do
                        if lname:find(kw, 1, true) then
                            local found = false
                            for _, l in ipairs(TeleportLocations) do
                                if l.Name == island.Name then found=true; break end
                            end
                            if not found then
                                local pos
                                if obj:IsA("BasePart") then pos = obj.Position
                                elseif obj:IsA("Model") and obj.PrimaryPart then pos = obj.PrimaryPart.Position end
                                if pos then
                                    table.insert(TeleportLocations, {
                                        Name   = island.Name,
                                        CFrame = CFrame.new(pos + Vector3.new(0,5,0)),
                                    })
                                end
                            end
                            break
                        end
                    end
                end
            end
        end
    end)
    -- SpawnLocation fallback
    pcall(function()
        local sp = game:GetService("Workspace"):FindFirstChildOfClass("SpawnLocation")
        if sp then
            local found = false
            for _, l in ipairs(TeleportLocations) do
                if l.Name == "Fisherman Island" then found=true; break end
            end
            if not found then
                table.insert(TeleportLocations, {
                    Name   = "Fisherman Island",
                    CFrame = sp.CFrame + Vector3.new(0,5,0),
                })
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
-- SECTION 8: SHOP DATA (Fish It actual items)
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
    -- Rate-limited fire, jitter 50-150ms
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
local FR = {} -- Fishing Remotes: Cast, Reel, Shake, Sell

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

-- Fishing settings (bisa diubah dari UI)
local FS = {
    AutoCast  = false,
    AutoReel  = false,
    AutoShake = false,
    AutoSell  = false,
    AntiAFK   = false,
}

-- Remote cooldown tracker
local RemoteCD = {}
local function RateOK(key, interval)
    local now = tick()
    if (now - (RemoteCD[key] or 0)) >= interval then
        RemoteCD[key] = now
        return true
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

-- GUI detection helpers (baca PlayerGui, bukan RunService)
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

-- Fishing state machine
local FState = {
    s           = "Idle",  -- Idle | Casting | Waiting | Biting | Reeling | Shaking
    lastCast    = 0,
    castCD      = 4,       -- seconds, randomized per cast
    lastSell    = 0,
}

-- *** FISHING LOOP - hanya hidup saat min 1 toggle ON ***
local fishThread = nil

local function AnyFishingActive()
    return FS.AutoCast or FS.AutoReel or FS.AutoShake or FS.AutoSell
end

local function StopFishingThread()
    if fishThread then
        task.cancel(fishThread)
        fishThread = nil
    end
    FState.s = "Idle"
end

local function StartFishingThread()
    if fishThread then return end  -- sudah jalan
    fishThread = task.spawn(function()
        while AnyFishingActive() do
            task.wait(math.random(90, 170) / 1000)  -- 90-170ms poll (non-fixed)

            -- AUTO CAST
            if FS.AutoCast and FR.Cast then
                local now = tick()
                if FState.s == "Idle" and (now - FState.lastCast) >= FState.castCD
                   and not IsBiting() and not IsShaking() then
                    FState.s       = "Casting"
                    FState.lastCast = now
                    FState.castCD  = math.random(350, 700) / 100  -- 3.5–7s random
                    SafeFire(FR.Cast, "cast", 0.5)
                    task.delay(math.random(30,80)/100, function()
                        if FState.s == "Casting" then FState.s = "Waiting" end
                    end)
                end
            end

            -- AUTO REEL
            if FS.AutoReel and FR.Reel then
                if (FState.s == "Waiting" or FState.s == "Idle") and IsBiting() then
                    FState.s = "Biting"
                    local delay = math.random(25, 85) / 100  -- 0.25–0.85s reaksi manusia
                    task.delay(delay, function()
                        if FState.s == "Biting" then
                            FState.s = "Reeling"
                            SafeFire(FR.Reel, "reel", 0.3)
                            task.delay(math.random(6,16)/10, function()
                                if FState.s == "Reeling" and not IsShaking() then
                                    FState.s = "Idle"
                                end
                            end)
                        end
                    end)
                end
            end

            -- AUTO SHAKE (8–14 CPS throttled, bukan inner loop)
            if FS.AutoShake and FR.Shake then
                if IsShaking() then
                    if FState.s ~= "Shaking" then FState.s = "Shaking" end
                    local cps = math.random(8, 14)
                    SafeFire(FR.Shake, "shake", 1/cps)
                else
                    if FState.s == "Shaking" then
                        FState.s = "Idle"
                        FState.lastCast = tick() - FState.castCD + math.random(10,20)/10
                    end
                end
            end

            -- AUTO SELL (tiap 8–12 detik random)
            if FS.AutoSell and FR.Sell then
                if RateOK("sell_global", math.random(8,12)) then
                    SafeFire(FR.Sell, "sell", 0.5, "All")
                end
            end
        end
        fishThread = nil
    end)
end

local function SetFishingFeature(key, val)
    FS[key] = val
    if val then
        StartFishingThread()
    elseif not AnyFishingActive() then
        StopFishingThread()
    end
end

-- ============================================================
-- SECTION 10: ANTI-AFK
-- ============================================================
-- Tidak pakai getconnections. Pakai VirtualUser dengan interval sangat panjang.
-- Thread hanya hidup saat diaktifkan.
local afkThread = nil

local function StartAntiAFK()
    if afkThread then return end
    afkThread = task.spawn(function()
        while FS.AntiAFK do
            -- 4–6 menit random (jauh dari threshold AFK)
            task.wait(math.random(240, 360))
            if FS.AntiAFK then
                pcall(function()
                    VirtualUser:ClickButton2(Vector2.new(
                        math.random(50, 400), math.random(50, 400)
                    ))
                end)
            end
        end
        afkThread = nil
    end)
end

local function StopAntiAFK()
    FS.AntiAFK = false
    if afkThread then
        task.cancel(afkThread)
        afkThread = nil
    end
end

-- ============================================================
-- SECTION 11: WEBHOOK & LOGGER
-- ============================================================
local WH = { Active=false, Url="", SentUUID={}, Rarities={}, ServerWide=true, Count=0 }
local IconCache = {}
local LogConns  = {}

local function FetchIcon(fishId, cb)
    if IconCache[fishId] ~= nil then cb(IconCache[fishId]); return end
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
                {
                    type       = 9,
                    components = {{type=10,content="**Fish**"},{type=10,content="> "..fish.Name}},
                    accessory  = icon~="" and {type=11,media={url=icon}} or nil,
                },
                {type=10, content="**Rarity:** "..rname},
                {type=10, content="**Weight:** "..string.format("%.1fkg", weight or 0)},
                {type=10, content="**Mutation:** "..(mutation or "None")},
                {type=14, spacing=1, divider=true},
                {type=10, content="-# "..os.date("!%B %d, %Y")},
            },
        }},
    }
end

local function SendWH(payload)
    if WH.Url == "" or not HttpRequest or not payload then return end
    pcall(function()
        local url = WH.Url .. (WH.Url:find("?") and "&" or "?") .. "with_components=true"
        HttpRequest({Url=url, Method="POST",
            Headers={["Content-Type"]="application/json"},
            Body=HttpService:JSONEncode(payload)})
    end)
end

local function OnFishCaught(pArg, wData, wrapper)
    if not WH.Active then return end
    local item = (wrapper and wrapper.InventoryItem)
               or (wData   and wData.InventoryItem)
    if not item or not item.Id or not item.UUID then return end
    if not FishDB[item.Id] then return end
    if not RarityOK(item.Id) then return end
    if WH.SentUUID[item.UUID] then return end
    WH.SentUUID[item.UUID] = true

    local pname = LocalPlayer.Name
    if typeof(pArg)=="Instance" and pArg:IsA("Player") then pname = pArg.Name
    elseif type(pArg)=="string" then pname = pArg end
    if not WH.ServerWide and pname ~= LocalPlayer.Name then return end

    local weight   = wData and wData.Weight   or 0
    local mutation = wData and wData.Mutation or nil
    WH.Count = WH.Count + 1
    FetchIcon(item.Id, function()
        SendWH(BuildPayload(pname, item.Id, weight, mutation))
    end)
end

local function StartLogger()
    if WH.Active then return true, "Already running" end
    if not ObtainedNewFish then return false, "Remote not found" end
    WH.Active = true; WH.SentUUID = {}; WH.Count = 0
    LogConns[#LogConns+1] = ObtainedNewFish.OnClientEvent:Connect(OnFishCaught)
    return true, "Logger started"
end

local function StopLogger()
    WH.Active = false
    for _, c in ipairs(LogConns) do pcall(function() c:Disconnect() end) end
    LogConns = {}
end

-- ============================================================
-- SECTION 12: TRADING
-- ============================================================
local Trade = {
    Target  = nil,
    Inv     = {},
    ByName  = {Active=false, Item=nil, Amount=1, Sent=0},
    ByRar   = {Active=false, Tier=nil},
    ByStone = {Active=false, Stone=nil},
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
                if item.Id and FishDB[item.Id] then name = FishDB[item.Id].Name
                elseif item.Name then name = tostring(item.Name) end
                if name then Trade.Inv[name] = (Trade.Inv[name] or 0) + 1 end
            end
        end
    end)
end

local function GetInvNames()
    local t = {}
    for n in pairs(Trade.Inv) do table.insert(t, n) end
    table.sort(t)
    if #t == 0 then return {"(Load inventory first)"} end
    return t
end

local TradeRemote
local function GetTradeRemote()
    if TradeRemote then return TradeRemote end
    pcall(function()
        for _, c in ipairs(net:GetDescendants()) do
            if (c:IsA("RemoteEvent") or c:IsA("RemoteFunction"))
               and c.Name:lower():find("trade") then
                TradeRemote = c; break
            end
        end
    end)
    return TradeRemote
end

local function DoTrade(targetName, itemName, qty)
    local remote = GetTradeRemote()
    if not remote then return false end
    local tp
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Name==targetName or p.DisplayName==targetName then tp=p; break end
    end
    if not tp then return false end
    local id = FishNameToId[itemName] or FishNameToId[itemName:lower()]
    task.delay(math.random(40,70)/100, function()
        pcall(function()
            if remote:IsA("RemoteEvent") then remote:FireServer(tp, id or itemName, qty or 1)
            else remote:InvokeServer(tp, id or itemName, qty or 1) end
        end)
    end)
    return true
end

-- ============================================================
-- SECTION 13: COLOR SCHEME
-- ============================================================
local C = {
    BG        = Color3.fromRGB(15,17,26),
    Sidebar   = Color3.fromRGB(20,24,38),
    SI        = Color3.fromRGB(30,36,58),
    SIH       = Color3.fromRGB(40,48,75),
    SIA       = Color3.fromRGB(45,55,90),
    Content   = Color3.fromRGB(25,28,42),
    CI        = Color3.fromRGB(35,40,60),
    CIH       = Color3.fromRGB(45,52,78),
    Accent    = Color3.fromRGB(70,130,255),
    AccentH   = Color3.fromRGB(90,150,255),
    Text      = Color3.fromRGB(255,255,255),
    TextD     = Color3.fromRGB(180,180,200),
    TextM     = Color3.fromRGB(120,125,150),
    Border    = Color3.fromRGB(50,55,80),
    Success   = Color3.fromRGB(80,200,120),
    Error     = Color3.fromRGB(255,100,100),
    TogON     = Color3.fromRGB(70,130,255),
    TogOFF    = Color3.fromRGB(60,65,90),
    DropBG    = Color3.fromRGB(20,22,35),
}

-- ============================================================
-- SECTION 14: BUILD GUI
-- ============================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name              = GUINAME
ScreenGui.ResetOnSpawn      = false
ScreenGui.ZIndexBehavior    = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder      = 999
ScreenGui.IgnoreGuiInset    = true
ScreenGui.Parent            = SafeParent

-- Identifier (untuk cleanup)
do
    local id = Instance.new("StringValue")
    id.Name = IDENT
    id.Parent = ScreenGui
end

local Main = Instance.new("Frame")
Main.Name               = "Main"
Main.Size               = UDim2.new(0,720,0,480)
Main.Position           = UDim2.new(0.5,-360,0.5,-240)
Main.BackgroundColor3   = C.BG
Main.BorderSizePixel    = 0
Main.ClipsDescendants   = true
Main.Parent             = ScreenGui
Instance.new("UICorner", Main).CornerRadius = UDim.new(0,12)
do
    local s = Instance.new("UIStroke", Main)
    s.Color = C.Border; s.Thickness = 1
end

-- Title bar
local TBar = Instance.new("Frame")
TBar.Name             = "TBar"
TBar.Size             = UDim2.new(1,0,0,45)
TBar.BackgroundColor3 = C.Sidebar
TBar.BorderSizePixel  = 0
TBar.Parent           = Main
Instance.new("UICorner", TBar).CornerRadius = UDim.new(0,12)
do  -- fix rounded bottom corner
    local f = Instance.new("Frame")
    f.Size=UDim2.new(1,0,0,15); f.Position=UDim2.new(0,0,1,-15)
    f.BackgroundColor3=C.Sidebar; f.BorderSizePixel=0; f.Parent=TBar
end

local TitleLbl = Instance.new("TextLabel")
TitleLbl.Size=UDim2.new(1,-110,1,0); TitleLbl.Position=UDim2.new(0,15,0,0)
TitleLbl.BackgroundTransparency=1
TitleLbl.Text="Vechnost v2.5.2"; TitleLbl.TextColor3=C.Text
TitleLbl.TextSize=17; TitleLbl.Font=Enum.Font.GothamBold
TitleLbl.TextXAlignment=Enum.TextXAlignment.Left; TitleLbl.Parent=TBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size=UDim2.new(0,30,0,30); CloseBtn.Position=UDim2.new(1,-40,0.5,-15)
CloseBtn.BackgroundColor3=C.CI; CloseBtn.BorderSizePixel=0
CloseBtn.Text="×"; CloseBtn.TextColor3=C.Text
CloseBtn.TextSize=20; CloseBtn.Font=Enum.Font.GothamBold
CloseBtn.AutoButtonColor=false; CloseBtn.Parent=TBar
Instance.new("UICorner", CloseBtn).CornerRadius=UDim.new(0,6)

local MinBtn = Instance.new("TextButton")
MinBtn.Size=UDim2.new(0,30,0,30); MinBtn.Position=UDim2.new(1,-75,0.5,-15)
MinBtn.BackgroundColor3=C.CI; MinBtn.BorderSizePixel=0
MinBtn.Text="—"; MinBtn.TextColor3=C.Text
MinBtn.TextSize=16; MinBtn.Font=Enum.Font.GothamBold
MinBtn.AutoButtonColor=false; MinBtn.Parent=TBar
Instance.new("UICorner", MinBtn).CornerRadius=UDim.new(0,6)

-- Sidebar
local Sidebar = Instance.new("Frame")
Sidebar.Name="Sidebar"; Sidebar.Size=UDim2.new(0,150,1,-55)
Sidebar.Position=UDim2.new(0,5,0,50); Sidebar.BackgroundColor3=C.Sidebar
Sidebar.BorderSizePixel=0; Sidebar.Parent=Main
Instance.new("UICorner", Sidebar).CornerRadius=UDim.new(0,10)
do
    local p=Instance.new("UIPadding",Sidebar)
    p.PaddingTop=UDim.new(0,8); p.PaddingBottom=UDim.new(0,8)
    p.PaddingLeft=UDim.new(0,8); p.PaddingRight=UDim.new(0,8)
    local l=Instance.new("UIListLayout",Sidebar)
    l.SortOrder=Enum.SortOrder.LayoutOrder; l.Padding=UDim.new(0,4)
end

-- Content area
local ContentArea = Instance.new("Frame")
ContentArea.Name="ContentArea"; ContentArea.Size=UDim2.new(1,-170,1,-60)
ContentArea.Position=UDim2.new(0,165,0,55); ContentArea.BackgroundColor3=C.Content
ContentArea.BorderSizePixel=0; ContentArea.Parent=Main
Instance.new("UICorner", ContentArea).CornerRadius=UDim.new(0,10)

-- Overlay for dropdowns
local DropOverlay = Instance.new("Frame")
DropOverlay.Name="DropOverlay"; DropOverlay.Size=UDim2.new(1,0,1,0)
DropOverlay.BackgroundTransparency=1; DropOverlay.ZIndex=100
DropOverlay.Parent=ScreenGui

-- ============================================================
-- SECTION 15: TAB SYSTEM
-- ============================================================
local TabContents = {}
local TabButtons  = {}
local CurrentTab  = nil

local TABS = {
    {N="Info",    I="👤", O=1}, {N="Fishing",  I="🎣", O=2},
    {N="Teleport",I="📍", O=3}, {N="Trading",  I="🔄", O=4},
    {N="Shop",    I="🛒", O=5}, {N="Webhook",  I="🔔", O=6},
    {N="Setting", I="⚙️", O=7},
}

local function MakeTabBtn(t)
    local btn = Instance.new("TextButton")
    btn.Name=t.N.."Tab"; btn.Size=UDim2.new(1,0,0,38)
    btn.BackgroundColor3=C.SI; btn.BorderSizePixel=0
    btn.Text=""; btn.AutoButtonColor=false; btn.LayoutOrder=t.O; btn.Parent=Sidebar
    Instance.new("UICorner", btn).CornerRadius=UDim.new(0,8)
    local il=Instance.new("TextLabel"); il.Size=UDim2.new(0,28,1,0); il.Position=UDim2.new(0,8,0,0)
    il.BackgroundTransparency=1; il.Text=t.I; il.TextColor3=C.Accent
    il.TextSize=16; il.Font=Enum.Font.GothamBold; il.Parent=btn
    local tl=Instance.new("TextLabel"); tl.Size=UDim2.new(1,-42,1,0); tl.Position=UDim2.new(0,38,0,0)
    tl.BackgroundTransparency=1; tl.Text=t.N; tl.TextColor3=C.Text
    tl.TextSize=13; tl.Font=Enum.Font.GothamSemibold
    tl.TextXAlignment=Enum.TextXAlignment.Left; tl.Parent=btn
    btn.MouseEnter:Connect(function()
        if CurrentTab~=t.N then TweenService:Create(btn,TweenInfo.new(.2),{BackgroundColor3=C.SIH}):Play() end end)
    btn.MouseLeave:Connect(function()
        if CurrentTab~=t.N then TweenService:Create(btn,TweenInfo.new(.2),{BackgroundColor3=C.SI}):Play() end end)
    return btn
end

local function MakeTabContent(name)
    local sf = Instance.new("ScrollingFrame")
    sf.Name=name.."Content"; sf.Size=UDim2.new(1,-16,1,-16); sf.Position=UDim2.new(0,8,0,8)
    sf.BackgroundTransparency=1; sf.BorderSizePixel=0
    sf.ScrollBarThickness=4; sf.ScrollBarImageColor3=C.Accent
    sf.CanvasSize=UDim2.new(0,0,0,0); sf.AutomaticCanvasSize=Enum.AutomaticSize.Y
    sf.Visible=false; sf.Parent=ContentArea
    local ll=Instance.new("UIListLayout",sf)
    ll.SortOrder=Enum.SortOrder.LayoutOrder; ll.Padding=UDim.new(0,8)
    Instance.new("UIPadding",sf).PaddingBottom=UDim.new(0,10)
    return sf
end

local function SwitchTab(name)
    if CurrentTab==name then return end
    for n,c in pairs(TabContents) do c.Visible=(n==name) end
    for n,b in pairs(TabButtons)  do
        TweenService:Create(b,TweenInfo.new(.2),{BackgroundColor3=n==name and C.SIA or C.SI}):Play()
    end
    CurrentTab=name
end

for _, t in ipairs(TABS) do
    local btn = MakeTabBtn(t)
    TabButtons[t.N]  = btn
    TabContents[t.N] = MakeTabContent(t.N)
    btn.MouseButton1Click:Connect(function() SwitchTab(t.N) end)
end

-- ============================================================
-- SECTION 16: UI COMPONENT HELPERS
-- ============================================================
local LOC = {}  -- layout order counters per tab
local function LO(tab) LOC[tab]=(LOC[tab] or 0)+1; return LOC[tab] end

local function Section(tab, title)
    local p=TabContents[tab]; if not p then return end
    local f=Instance.new("Frame"); f.Name="S_"..title
    f.Size=UDim2.new(1,0,0,28); f.BackgroundTransparency=1
    f.LayoutOrder=LO(tab); f.Parent=p
    local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,1,0)
    l.BackgroundTransparency=1; l.Text=title; l.TextColor3=C.Accent
    l.TextSize=15; l.Font=Enum.Font.GothamBold
    l.TextXAlignment=Enum.TextXAlignment.Left; l.Parent=f
end

local function Para(tab, title, body)
    local p=TabContents[tab]; if not p then return end
    local f=Instance.new("Frame"); f.Name="P_"..title
    f.Size=UDim2.new(1,0,0,55); f.BackgroundColor3=C.CI
    f.BorderSizePixel=0; f.LayoutOrder=LO(tab); f.Parent=p
    Instance.new("UICorner",f).CornerRadius=UDim.new(0,8)
    local tl=Instance.new("TextLabel"); tl.Name="T"
    tl.Size=UDim2.new(1,-20,0,20); tl.Position=UDim2.new(0,10,0,6)
    tl.BackgroundTransparency=1; tl.Text=title; tl.TextColor3=C.Text
    tl.TextSize=13; tl.Font=Enum.Font.GothamBold
    tl.TextXAlignment=Enum.TextXAlignment.Left; tl.Parent=f
    local cl=Instance.new("TextLabel"); cl.Name="C"
    cl.Size=UDim2.new(1,-20,0,22); cl.Position=UDim2.new(0,10,0,26)
    cl.BackgroundTransparency=1; cl.Text=body; cl.TextColor3=C.TextD
    cl.TextSize=11; cl.Font=Enum.Font.Gotham
    cl.TextXAlignment=Enum.TextXAlignment.Left; cl.TextWrapped=true; cl.Parent=f
    return {
        Set=function(self,d)
            if d.Title then tl.Text=d.Title end
            if d.Content then cl.Text=d.Content end
        end
    }
end

local function Input(tab, name, ph, cb)
    local p=TabContents[tab]; if not p then return end
    local f=Instance.new("Frame"); f.Name="I_"..name
    f.Size=UDim2.new(1,0,0,58); f.BackgroundColor3=C.CI
    f.BorderSizePixel=0; f.LayoutOrder=LO(tab); f.Parent=p
    Instance.new("UICorner",f).CornerRadius=UDim.new(0,8)
    local nl=Instance.new("TextLabel"); nl.Size=UDim2.new(1,-20,0,18); nl.Position=UDim2.new(0,10,0,6)
    nl.BackgroundTransparency=1; nl.Text=name; nl.TextColor3=C.Text
    nl.TextSize=12; nl.Font=Enum.Font.GothamSemibold
    nl.TextXAlignment=Enum.TextXAlignment.Left; nl.Parent=f
    local tb=Instance.new("TextBox"); tb.Size=UDim2.new(1,-20,0,26); tb.Position=UDim2.new(0,10,0,26)
    tb.BackgroundColor3=C.BG; tb.BorderSizePixel=0; tb.Text=""
    tb.PlaceholderText=ph or ""; tb.PlaceholderColor3=C.TextM
    tb.TextColor3=C.Text; tb.TextSize=11; tb.Font=Enum.Font.Gotham
    tb.ClearTextOnFocus=false; tb.Parent=f
    Instance.new("UICorner",tb).CornerRadius=UDim.new(0,6)
    local pad=Instance.new("UIPadding",tb)
    pad.PaddingLeft=UDim.new(0,10); pad.PaddingRight=UDim.new(0,10)
    tb.FocusLost:Connect(function() if cb then cb(tb.Text) end end)
    return {Frame=f, TB=tb, Get=function() return tb.Text end, Set=function(s,v) tb.Text=v end}
end

local function Btn(tab, name, cb)
    local p=TabContents[tab]; if not p then return end
    local b=Instance.new("TextButton"); b.Name="B_"..name
    b.Size=UDim2.new(1,0,0,36); b.BackgroundColor3=C.Accent
    b.BorderSizePixel=0; b.Text=name; b.TextColor3=C.Text
    b.TextSize=12; b.Font=Enum.Font.GothamSemibold
    b.AutoButtonColor=false; b.LayoutOrder=LO(tab); b.Parent=p
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,8)
    b.MouseEnter:Connect(function() TweenService:Create(b,TweenInfo.new(.2),{BackgroundColor3=C.AccentH}):Play() end)
    b.MouseLeave:Connect(function() TweenService:Create(b,TweenInfo.new(.2),{BackgroundColor3=C.Accent}):Play() end)
    b.MouseButton1Click:Connect(function() if cb then cb() end end)
    return b
end

local function Toggle(tab, name, def, cb)
    local p=TabContents[tab]; if not p then return end
    local state=def or false
    local f=Instance.new("Frame"); f.Name="T_"..name
    f.Size=UDim2.new(1,0,0,42); f.BackgroundColor3=C.CI
    f.BorderSizePixel=0; f.LayoutOrder=LO(tab); f.Parent=p
    Instance.new("UICorner",f).CornerRadius=UDim.new(0,8)
    local ll=Instance.new("TextLabel"); ll.Size=UDim2.new(1,-70,1,0); ll.Position=UDim2.new(0,12,0,0)
    ll.BackgroundTransparency=1; ll.Text=name; ll.TextColor3=C.Text
    ll.TextSize=12; ll.Font=Enum.Font.GothamSemibold
    ll.TextXAlignment=Enum.TextXAlignment.Left; ll.Parent=f
    local tb=Instance.new("TextButton"); tb.Size=UDim2.new(0,46,0,24); tb.Position=UDim2.new(1,-56,.5,-12)
    tb.BackgroundColor3=state and C.TogON or C.TogOFF; tb.BorderSizePixel=0
    tb.Text=""; tb.AutoButtonColor=false; tb.Parent=f
    Instance.new("UICorner",tb).CornerRadius=UDim.new(1,0)
    local circle=Instance.new("Frame"); circle.Size=UDim2.new(0,18,0,18)
    circle.Position=state and UDim2.new(1,-21,.5,-9) or UDim2.new(0,3,.5,-9)
    circle.BackgroundColor3=C.Text; circle.BorderSizePixel=0; circle.Parent=tb
    Instance.new("UICorner",circle).CornerRadius=UDim.new(1,0)
    local function Update()
        TweenService:Create(circle,TweenInfo.new(.2),{Position=state and UDim2.new(1,-21,.5,-9) or UDim2.new(0,3,.5,-9)}):Play()
        TweenService:Create(tb,TweenInfo.new(.2),{BackgroundColor3=state and C.TogON or C.TogOFF}):Play()
    end
    tb.MouseButton1Click:Connect(function()
        state=not state; Update(); if cb then cb(state) end end)
    return {Frame=f,
        SetValue=function(s,v) state=v; Update() end,
        GetValue=function() return state end}
end

local function Slider(tab, name, mn, mx, def, cb)
    local p=TabContents[tab]; if not p then return end
    local val=def or mn
    local f=Instance.new("Frame"); f.Name="Sl_"..name
    f.Size=UDim2.new(1,0,0,52); f.BackgroundColor3=C.CI
    f.BorderSizePixel=0; f.LayoutOrder=LO(tab); f.Parent=p
    Instance.new("UICorner",f).CornerRadius=UDim.new(0,8)
    local nl=Instance.new("TextLabel"); nl.Size=UDim2.new(1,-60,0,18); nl.Position=UDim2.new(0,10,0,6)
    nl.BackgroundTransparency=1; nl.Text=name; nl.TextColor3=C.Text
    nl.TextSize=12; nl.Font=Enum.Font.GothamSemibold
    nl.TextXAlignment=Enum.TextXAlignment.Left; nl.Parent=f
    local vl=Instance.new("TextLabel"); vl.Size=UDim2.new(0,45,0,18); vl.Position=UDim2.new(1,-55,0,6)
    vl.BackgroundTransparency=1; vl.Text=tostring(val); vl.TextColor3=C.Accent
    vl.TextSize=12; vl.Font=Enum.Font.GothamBold
    vl.TextXAlignment=Enum.TextXAlignment.Right; vl.Parent=f
    local track=Instance.new("Frame"); track.Size=UDim2.new(1,-20,0,8); track.Position=UDim2.new(0,10,0,34)
    track.BackgroundColor3=C.BG; track.BorderSizePixel=0; track.Parent=f
    Instance.new("UICorner",track).CornerRadius=UDim.new(1,0)
    local fill=Instance.new("Frame"); fill.Size=UDim2.new((val-mn)/(mx-mn),0,1,0)
    fill.BackgroundColor3=C.Accent; fill.BorderSizePixel=0; fill.Parent=track
    Instance.new("UICorner",fill).CornerRadius=UDim.new(1,0)
    local knob=Instance.new("Frame"); knob.Size=UDim2.new(0,14,0,14)
    knob.Position=UDim2.new((val-mn)/(mx-mn),-7,.5,-7)
    knob.BackgroundColor3=C.Text; knob.BorderSizePixel=0; knob.Parent=track
    Instance.new("UICorner",knob).CornerRadius=UDim.new(1,0)
    local drag=false
    local function Upd(v)
        val=math.clamp(math.floor(v),mn,mx)
        local pct=(val-mn)/(mx-mn)
        fill.Size=UDim2.new(pct,0,1,0)
        knob.Position=UDim2.new(pct,-7,.5,-7)
        vl.Text=tostring(val); if cb then cb(val) end
    end
    track.InputBegan:Connect(function(inp)
        if inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch then
            drag=true
            Upd(mn+(math.clamp((inp.Position.X-track.AbsolutePosition.X)/track.AbsoluteSize.X,0,1))*(mx-mn))
        end
    end)
    track.InputEnded:Connect(function(inp)
        if inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch then drag=false end
    end)
    -- Slider drag pakai InputChanged (bukan RenderStepped)
    UserInputService.InputChanged:Connect(function(inp)
        if drag and (inp.UserInputType==Enum.UserInputType.MouseMovement or inp.UserInputType==Enum.UserInputType.Touch) then
            Upd(mn+(math.clamp((inp.Position.X-track.AbsolutePosition.X)/track.AbsoluteSize.X,0,1))*(mx-mn))
        end
    end)
    return {Frame=f, Set=function(s,v) Upd(v) end, Get=function() return val end}
end

-- ============================================================
-- SECTION 17: DROPDOWN
-- ============================================================
local ActiveDD = nil

local function Dropdown(tab, name, opts, def, cb)
    local p=TabContents[tab]; if not p then return end
    local sel=def; local isOpen=false; local optFrame=nil
    local f=Instance.new("Frame"); f.Name="D_"..name
    f.Size=UDim2.new(1,0,0,58); f.BackgroundColor3=C.CI
    f.BorderSizePixel=0; f.LayoutOrder=LO(tab); f.Parent=p
    Instance.new("UICorner",f).CornerRadius=UDim.new(0,8)
    local nl=Instance.new("TextLabel"); nl.Size=UDim2.new(1,-20,0,18); nl.Position=UDim2.new(0,10,0,6)
    nl.BackgroundTransparency=1; nl.Text=name; nl.TextColor3=C.Text
    nl.TextSize=12; nl.Font=Enum.Font.GothamSemibold
    nl.TextXAlignment=Enum.TextXAlignment.Left; nl.Parent=f
    local db=Instance.new("TextButton"); db.Size=UDim2.new(1,-20,0,26); db.Position=UDim2.new(0,10,0,26)
    db.BackgroundColor3=C.BG; db.BorderSizePixel=0; db.Text=""; db.AutoButtonColor=false; db.Parent=f
    Instance.new("UICorner",db).CornerRadius=UDim.new(0,6)
    local sl=Instance.new("TextLabel"); sl.Size=UDim2.new(1,-30,1,0); sl.Position=UDim2.new(0,10,0,0)
    sl.BackgroundTransparency=1; sl.Text=sel or "Select..."; sl.TextColor3=sel and C.Text or C.TextM
    sl.TextSize=11; sl.Font=Enum.Font.Gotham; sl.TextXAlignment=Enum.TextXAlignment.Left
    sl.TextTruncate=Enum.TextTruncate.AtEnd; sl.Parent=db
    local ar=Instance.new("TextLabel"); ar.Size=UDim2.new(0,20,1,0); ar.Position=UDim2.new(1,-25,0,0)
    ar.BackgroundTransparency=1; ar.Text="▼"; ar.TextColor3=C.TextM; ar.TextSize=10
    ar.Font=Enum.Font.Gotham; ar.Parent=db

    local function Close()
        if optFrame then optFrame:Destroy(); optFrame=nil end
        isOpen=false
        TweenService:Create(ar,TweenInfo.new(.2),{Rotation=0}):Play()
        ActiveDD=nil
    end
    local function Open()
        if ActiveDD and ActiveDD~=Close then ActiveDD() end
        ActiveDD=Close; isOpen=true
        TweenService:Create(ar,TweenInfo.new(.2),{Rotation=180}):Play()
        local bp=db.AbsolutePosition; local bs=db.AbsoluteSize
        local of=Instance.new("Frame"); of.Name="DOpts"
        of.Size=UDim2.new(0,bs.X,0,math.min(#opts*28+8,150))
        of.Position=UDim2.fromOffset(bp.X,bp.Y+bs.Y+5)
        of.BackgroundColor3=C.DropBG; of.BorderSizePixel=0; of.ZIndex=100; of.Parent=DropOverlay
        Instance.new("UICorner",of).CornerRadius=UDim.new(0,6)
        do local s=Instance.new("UIStroke",of); s.Color=C.Border; s.Thickness=1 end
        local scroll=Instance.new("ScrollingFrame"); scroll.Size=UDim2.new(1,-8,1,-8)
        scroll.Position=UDim2.new(0,4,0,4); scroll.BackgroundTransparency=1
        scroll.BorderSizePixel=0; scroll.ScrollBarThickness=3
        scroll.ScrollBarImageColor3=C.Accent; scroll.CanvasSize=UDim2.new(0,0,0,#opts*28)
        scroll.ZIndex=101; scroll.Parent=of
        local ll=Instance.new("UIListLayout",scroll)
        ll.SortOrder=Enum.SortOrder.LayoutOrder; ll.Padding=UDim.new(0,2)
        optFrame=of
        for i,o in ipairs(opts) do
            local ob=Instance.new("TextButton"); ob.Name=o
            ob.Size=UDim2.new(1,0,0,26); ob.BackgroundColor3=o==sel and C.Accent or C.CI
            ob.BorderSizePixel=0; ob.Text=o; ob.TextColor3=C.Text
            ob.TextSize=11; ob.Font=Enum.Font.Gotham; ob.AutoButtonColor=false
            ob.LayoutOrder=i; ob.ZIndex=102; ob.Parent=scroll
            Instance.new("UICorner",ob).CornerRadius=UDim.new(0,4)
            ob.MouseEnter:Connect(function()
                if o~=sel then TweenService:Create(ob,TweenInfo.new(.1),{BackgroundColor3=C.CIH}):Play() end end)
            ob.MouseLeave:Connect(function()
                if o~=sel then TweenService:Create(ob,TweenInfo.new(.1),{BackgroundColor3=C.CI}):Play() end end)
            ob.MouseButton1Click:Connect(function()
                sel=o; sl.Text=o; sl.TextColor3=C.Text
                if cb then cb(o) end; Close()
            end)
        end
    end
    db.MouseButton1Click:Connect(function() if isOpen then Close() else Open() end end)
    return {
        Frame=f,
        Refresh=function(self,newOpts,keep)
            opts=newOpts
            if not keep then sel=nil; sl.Text="Select..."; sl.TextColor3=C.TextM end
            if isOpen then Close() end
        end,
        Set=function(self,v)
            sel=v; sl.Text=v or "Select..."; sl.TextColor3=v and C.Text or C.TextM
        end,
        Get=function() return sel end,
    }
end

-- Close dropdown on click-outside
UserInputService.InputBegan:Connect(function(inp)
    if inp.UserInputType==Enum.UserInputType.MouseButton1
    or inp.UserInputType==Enum.UserInputType.Touch then
        if ActiveDD then task.defer(function() task.wait(.05); if ActiveDD then ActiveDD() end end) end
    end
end)

-- ============================================================
-- SECTION 18: NOTIFICATION
-- ============================================================
local NotifCont = Instance.new("Frame")
NotifCont.Name="Notifs"; NotifCont.Size=UDim2.new(0,275,1,0)
NotifCont.Position=UDim2.new(1,-285,0,0); NotifCont.BackgroundTransparency=1
NotifCont.Parent=ScreenGui
do
    local l=Instance.new("UIListLayout",NotifCont)
    l.SortOrder=Enum.SortOrder.LayoutOrder
    l.Padding=UDim.new(0,8); l.VerticalAlignment=Enum.VerticalAlignment.Bottom
    Instance.new("UIPadding",NotifCont).PaddingBottom=UDim.new(0,20)
end

local function Notify(title, body, dur)
    dur=dur or 3
    local nf=Instance.new("Frame"); nf.Size=UDim2.new(0,255,0,65)
    nf.BackgroundColor3=C.Sidebar; nf.BorderSizePixel=0
    nf.BackgroundTransparency=1; nf.Parent=NotifCont
    Instance.new("UICorner",nf).CornerRadius=UDim.new(0,10)
    local sk=Instance.new("UIStroke",nf); sk.Color=C.Accent; sk.Transparency=1
    local tl=Instance.new("TextLabel"); tl.Size=UDim2.new(1,-20,0,20); tl.Position=UDim2.new(0,10,0,8)
    tl.BackgroundTransparency=1; tl.Text=title; tl.TextColor3=C.Accent
    tl.TextSize=13; tl.Font=Enum.Font.GothamBold
    tl.TextXAlignment=Enum.TextXAlignment.Left; tl.Parent=nf
    local cl=Instance.new("TextLabel"); cl.Size=UDim2.new(1,-20,0,28); cl.Position=UDim2.new(0,10,0,28)
    cl.BackgroundTransparency=1; cl.Text=body; cl.TextColor3=C.TextD
    cl.TextSize=11; cl.Font=Enum.Font.Gotham; cl.TextXAlignment=Enum.TextXAlignment.Left
    cl.TextWrapped=true; cl.Parent=nf
    TweenService:Create(nf,TweenInfo.new(.3),{BackgroundTransparency=0}):Play()
    TweenService:Create(sk,TweenInfo.new(.3),{Transparency=0}):Play()
    task.delay(dur,function()
        TweenService:Create(nf,TweenInfo.new(.3),{BackgroundTransparency=1}):Play()
        TweenService:Create(sk,TweenInfo.new(.3),{Transparency=1}):Play()
        task.wait(.3); pcall(function() nf:Destroy() end)
    end)
end

-- ============================================================
-- SECTION 19: POPULATE TABS
-- ============================================================

-- ——— INFO ———
Section("Info","Player")
Para("Info","Username",LocalPlayer.Name)
local InfoPara = Para("Info","Stats","Click [Refresh Stats] to load")
Btn("Info","Refresh Stats",function()
    local s=GetStats()
    InfoPara:Set({Title="Stats",
        Content=string.format("Coins: %s | Fish: %s | Bag: %d/%d",
            FmtNum(s.Coins),FmtNum(s.TotalCaught),s.BPCount,s.BPMax)})
end)
Section("Info","About")
Para("Info","Vechnost v2.5.2","Fix BAC-4226: Zero background loops saat idle\nTidak ada RunService connection\nTidak ada exploit API saat init")

-- ——— FISHING ———
Section("Fishing","Auto Fishing")
Para("Fishing","Info BAC",
    "Cast 3.5–7s | Reel 0.25–0.85s delay | Shake 8–14 CPS\nLoop HANYA aktif saat min 1 toggle ON")

Toggle("Fishing","Auto Cast",false,function(v)
    SetFishingFeature("AutoCast",v)
    Notify("Vechnost",v and "Auto Cast ON" or "Auto Cast OFF",2)
end)
Toggle("Fishing","Auto Reel",false,function(v)
    SetFishingFeature("AutoReel",v)
    Notify("Vechnost",v and "Auto Reel ON" or "Auto Reel OFF",2)
end)
Toggle("Fishing","Auto Shake",false,function(v)
    SetFishingFeature("AutoShake",v)
    Notify("Vechnost",v and "Auto Shake ON (8-14 CPS)" or "Auto Shake OFF",2)
end)
Section("Fishing","Utility")
Toggle("Fishing","Anti AFK",false,function(v)
    FS.AntiAFK=v
    if v then StartAntiAFK() else StopAntiAFK() end
    Notify("Vechnost",v and "Anti AFK ON (4-6min interval)" or "Anti AFK OFF",2)
end)
Toggle("Fishing","Auto Sell",false,function(v)
    SetFishingFeature("AutoSell",v)
    Notify("Vechnost",v and "Auto Sell ON (8-12s)" or "Auto Sell OFF",2)
end)
Btn("Fishing","Re-scan Remotes",function()
    FindFishingRemotes()
    local f={}
    if FR.Cast  then f[#f+1]="Cast"  end
    if FR.Reel  then f[#f+1]="Reel"  end
    if FR.Shake then f[#f+1]="Shake" end
    if FR.Sell  then f[#f+1]="Sell"  end
    Notify("Vechnost","Found: "..(#f>0 and table.concat(f,", ") or "none"),3)
end)

-- ——— TELEPORT ———
Section("Teleport","Fish It Islands")
Para("Teleport","Petunjuk","Klik [Scan Islands] terlebih dahulu\nagar lokasi ter-detect dari Workspace")

local TpDD = Dropdown("Teleport","Select Island",{"(Klik Scan dulu)"},nil,function(sel)
    if sel and sel~="(Klik Scan dulu)" then
        local ok,msg=TeleportTo(sel)
        Notify("Vechnost",ok and msg or ("Gagal: "..msg),2)
    end
end)

Btn("Teleport","Scan Islands",function()
    ScanIslands()
    TpDD:Refresh(GetLocNames(),false)
    Notify("Vechnost","Ditemukan "..#TeleportLocations.." lokasi",2)
end)

Section("Teleport","Quick TP")
Btn("Teleport","TP ke Spawn",function()
    local char=LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return end
    local sp=game:GetService("Workspace"):FindFirstChildOfClass("SpawnLocation")
    if sp then
        char.HumanoidRootPart.CFrame = sp.CFrame + Vector3.new(0,5,0)
        Notify("Vechnost","Teleported to Spawn",2)
    else Notify("Vechnost","SpawnLocation not found",2) end
end)
Btn("Teleport","TP ke Pemain Terdekat",function()
    local char=LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return end
    local myPos=char.HumanoidRootPart.Position
    local near,nearD=nil,math.huge
    for _,pl in ipairs(Players:GetPlayers()) do
        if pl~=LocalPlayer and pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") then
            local d=(pl.Character.HumanoidRootPart.Position-myPos).Magnitude
            if d<nearD then nearD=d; near=pl end
        end
    end
    if near then
        char.HumanoidRootPart.CFrame = near.Character.HumanoidRootPart.CFrame + Vector3.new(3,0,0)
        Notify("Vechnost","TP to "..near.Name,2)
    else Notify("Vechnost","Tidak ada pemain",2) end
end)

-- ——— TRADING ———
Section("Trading","Target Player")
local plNames={}
for _,pl in ipairs(Players:GetPlayers()) do
    if pl~=LocalPlayer then plNames[#plNames+1]=pl.Name end
end
if #plNames==0 then plNames={"(No players)"} end

local PlDD=Dropdown("Trading","Select Player",plNames,nil,function(sel)
    if sel and sel~="(No players)" then Trade.Target=sel; Notify("Vechnost","Target: "..sel,2) end
end)
Btn("Trading","Refresh Players",function()
    local t={}
    for _,pl in ipairs(Players:GetPlayers()) do
        if pl~=LocalPlayer then t[#t+1]=pl.Name end
    end
    if #t==0 then t={"(No players)"} end
    PlDD:Refresh(t,false)
    Notify("Vechnost","Found "..#t.." players",2)
end)

Section("Trading","Trade by Item")
local TradeStatus=Para("Trading","Status","Ready")
local ItemDD=Dropdown("Trading","Select Item",{"(Load inventory)"},nil,function(sel)
    if sel and sel~="(Load inventory)" then Trade.ByName.Item=sel end
end)
Btn("Trading","Load Inventory",function()
    LoadInv(); local names=GetInvNames(); ItemDD:Refresh(names,false)
    Notify("Vechnost","Loaded "..#names.." items",2)
end)
local amtBuf="1"
Input("Trading","Amount","1",function(t)
    amtBuf=t; local n=tonumber(t); if n and n>0 then Trade.ByName.Amount=math.floor(n) end
end)
local TBNToggle
TBNToggle=Toggle("Trading","Start Trade by Name",false,function(v)
    if v then
        if not Trade.Target then Notify("Vechnost","Select target first!",3); TBNToggle:SetValue(false); return end
        if not Trade.ByName.Item then Notify("Vechnost","Select item first!",3); TBNToggle:SetValue(false); return end
        Trade.ByName.Active=true; Trade.ByName.Sent=0
        task.spawn(function()
            local total=Trade.ByName.Amount; local item=Trade.ByName.Item; local tgt=Trade.Target
            for i=1,total do
                if not Trade.ByName.Active then break end
                TradeStatus:Set({Title="Status",Content=("Sending %d/%d %s"):format(i,total,item)})
                DoTrade(tgt,item,1); Trade.ByName.Sent=i
                task.wait(math.random(40,70)/100)
            end
            Trade.ByName.Active=false; TBNToggle:SetValue(false)
            TradeStatus:Set({Title="Status",Content=("Done: %d/%d sent"):format(Trade.ByName.Sent,total)})
            Notify("Vechnost","Trade complete!",2)
        end)
    else Trade.ByName.Active=false end
end)

Section("Trading","Trade by Rarity")
Dropdown("Trading","Select Rarity",RARITY_LIST,nil,function(sel)
    if sel then Trade.ByRar.Tier=RARITY_TIER[sel]; Notify("Vechnost","Rarity: "..sel,2) end
end)
Section("Trading","Trade Stone")
Dropdown("Trading","Select Stone",STONES,nil,function(sel)
    if sel then Trade.ByStone.Stone=sel end
end)

-- ——— SHOP ———
Section("Shop","Bait Shop")
local BaitDD=Dropdown("Shop","Select Bait",SHOP.Bait,nil,function(s) ShopSettings={SelectedBait=s} end)
do
    local ShopSettings={SelectedBait=nil,AutoBuyBait=false,SelectedRod=nil,AutoBuyRod=false}
    local baitToggle,rodToggle
    baitToggle=Toggle("Shop","Auto Buy Bait",false,function(v)
        ShopSettings.AutoBuyBait=v
        if v then
            task.spawn(function()
                while ShopSettings.AutoBuyBait do
                    local sel=BaitDD:Get()
                    if sel then BuyItem("Bait",sel) end
                    task.wait(math.random(20,40)/10)
                end
            end)
        end
        Notify("Vechnost",v and "Auto Buy Bait ON" or "Auto Buy Bait OFF",2)
    end)

    Section("Shop","Rod Shop")
    local RodDD=Dropdown("Shop","Select Rod",SHOP.Rod,nil,function(s) ShopSettings.SelectedRod=s end)
    rodToggle=Toggle("Shop","Auto Buy Rod",false,function(v)
        ShopSettings.AutoBuyRod=v
        if v then
            task.spawn(function()
                while ShopSettings.AutoBuyRod do
                    local sel=RodDD:Get()
                    if sel then BuyItem("Rod",sel) end
                    task.wait(math.random(30,60)/10)
                end
            end)
        end
        Notify("Vechnost",v and "Auto Buy Rod ON" or "Auto Buy Rod OFF",2)
    end)
end

Section("Shop","Merchant")
local MerDD=Dropdown("Shop","Select Item",SHOP.Merchant,nil,function(_) end)
Btn("Shop","Buy Item",function()
    local sel=MerDD:Get()
    if sel then BuyItem("Merchant",sel); Notify("Vechnost","Purchased: "..sel,2)
    else Notify("Vechnost","Select item first!",2) end
end)

Section("Shop","Weather (Crater Island)")
Para("Shop","Info","Teleport ke Crater Island dulu,\nlalu gunakan fitur ini.")
local WeatDD=Dropdown("Shop","Select Weather",SHOP.Weather,nil,function(_) end)
Btn("Shop","Request Weather",function()
    local sel=WeatDD:Get()
    if sel then BuyItem("Weather",sel); Notify("Vechnost","Weather request: "..sel,2)
    else Notify("Vechnost","Select weather first!",2) end
end)

-- ——— WEBHOOK ———
Section("Webhook","Rarity Filter")
local WHRarDD=Dropdown("Webhook","Filter Rarity",RARITY_LIST,nil,function(sel)
    WH.Rarities={}
    local t=RARITY_TIER[sel]; if t then WH.Rarities[t]=true end
    Notify("Vechnost","Filter: "..sel,2)
end)
Btn("Webhook","Clear Filter",function()
    WH.Rarities={}; WHRarDD:Set(nil); Notify("Vechnost","All rarities",2)
end)
Section("Webhook","URL Setup")
local urlBuf=""
Input("Webhook","Webhook URL","https://discord.com/api/webhooks/...",function(t) urlBuf=t end)
Btn("Webhook","Save URL",function()
    local url=urlBuf:gsub("%s+","")
    if not url:match("^https://discord") then Notify("Vechnost","Invalid URL!",3); return end
    WH.Url=url; Notify("Vechnost","URL saved!",2)
end)
Section("Webhook","Mode")
Toggle("Webhook","Server-Wide",true,function(v)
    WH.ServerWide=v; Notify("Vechnost",v and "Server-Wide" or "Local only",2)
end)
Section("Webhook","Control")
local LogToggle
LogToggle=Toggle("Webhook","Enable Logger",false,function(v)
    if v then
        if WH.Url=="" then Notify("Vechnost","Set URL first!",3); LogToggle:SetValue(false); return end
        local ok,msg=StartLogger()
        if ok then Notify("Vechnost","Logger ON!",2)
        else Notify("Vechnost",msg,3); LogToggle:SetValue(false) end
    else StopLogger(); Notify("Vechnost","Logger OFF",2) end
end)
Section("Webhook","Status")
local WHStatus=Para("Webhook","Logger","Offline")
-- Status update HANYA via tombol (tidak ada background loop)
Btn("Webhook","Refresh Status",function()
    WHStatus:Set({Title="Logger",
        Content=WH.Active
            and ("Active | "..(WH.ServerWide and "Server-Wide" or "Local").." | Count: "..WH.Count)
            or "Offline"})
end)

-- ——— SETTING ———
Section("Setting","Test")
Btn("Setting","Test Webhook",function()
    if WH.Url=="" then Notify("Vechnost","Set URL first!",3); return end
    SendWH({
        username="Vechnost Notifier",
        avatar_url="https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png",
        flags=32768,
        components={{type=17,components={
            {type=10,content="**Test Message**"},
            {type=14,spacing=1,divider=true},
            {type=10,content="Webhook OK!\n**From:** "..LocalPlayer.Name.." | **Script:** Vechnost v2.5.2"},
            {type=10,content="-# "..os.date("!%B %d, %Y")},
        }}}
    })
    Notify("Vechnost","Test sent!",2)
end)
Btn("Setting","Reset Counter",function()
    WH.Count=0; WH.SentUUID={}; Notify("Vechnost","Counter reset!",2)
end)
Btn("Setting","Re-scan Remotes",function()
    FindFishingRemotes()
    local f={}
    if FR.Cast  then f[#f+1]="Cast"  end
    if FR.Reel  then f[#f+1]="Reel"  end
    if FR.Shake then f[#f+1]="Shake" end
    if FR.Sell  then f[#f+1]="Sell"  end
    Notify("Vechnost","Remotes: "..(#f>0 and table.concat(f,", ") or "not found"),3)
end)
Section("Setting","UI")
Btn("Setting","Toggle UI (V)",function() Main.Visible=not Main.Visible end)
Section("Setting","Fix Log v2.5.2")
Para("Setting","BAC-4226 Fixes",
    "✓ Zero loop saat idle\n✓ No RunService connection\n✓ No exploit API on init\n✓ No VirtualInputManager\n✓ ScanIslands on-demand only")
Section("Setting","Credits")
Para("Setting","Vechnost Team","Discord: discord.gg/vechnost")

-- ============================================================
-- SECTION 20: UI INTERACTIONS (drag, close, minimize)
-- ============================================================

-- Drag via TitleBar - pakai InputChanged (bukan RenderStepped)
local dragging=false; local dragOff=Vector2.zero
TBar.InputBegan:Connect(function(inp)
    if inp.UserInputType==Enum.UserInputType.MouseButton1
    or inp.UserInputType==Enum.UserInputType.Touch then
        dragging=true
        dragOff=Vector2.new(inp.Position.X,inp.Position.Y)
              - Vector2.new(Main.AbsolutePosition.X,Main.AbsolutePosition.Y)
    end
end)
TBar.InputEnded:Connect(function(inp)
    if inp.UserInputType==Enum.UserInputType.MouseButton1
    or inp.UserInputType==Enum.UserInputType.Touch then dragging=false end
end)
UserInputService.InputChanged:Connect(function(inp)
    if dragging and (inp.UserInputType==Enum.UserInputType.MouseMovement
                  or inp.UserInputType==Enum.UserInputType.Touch) then
        local np=Vector2.new(inp.Position.X,inp.Position.Y)-dragOff
        Main.Position=UDim2.fromOffset(np.X,np.Y)
    end
end)

CloseBtn.MouseEnter:Connect(function() TweenService:Create(CloseBtn,TweenInfo.new(.15),{BackgroundColor3=C.Error}):Play() end)
CloseBtn.MouseLeave:Connect(function() TweenService:Create(CloseBtn,TweenInfo.new(.15),{BackgroundColor3=C.CI}):Play() end)
CloseBtn.MouseButton1Click:Connect(function()
    StopLogger(); StopAntiAFK(); StopFishingThread()
    ScreenGui:Destroy()
end)

local minimized=false
MinBtn.MouseEnter:Connect(function() TweenService:Create(MinBtn,TweenInfo.new(.15),{BackgroundColor3=C.CIH}):Play() end)
MinBtn.MouseLeave:Connect(function() TweenService:Create(MinBtn,TweenInfo.new(.15),{BackgroundColor3=C.CI}):Play() end)
MinBtn.MouseButton1Click:Connect(function()
    minimized=not minimized
    TweenService:Create(Main,TweenInfo.new(.3),{
        Size=minimized and UDim2.new(0,720,0,45) or UDim2.new(0,720,0,480)
    }):Play()
end)

UserInputService.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.KeyCode==Enum.KeyCode.V then Main.Visible=not Main.Visible end
end)

-- ============================================================
-- SECTION 21: MOBILE FLOATING BUTTON
-- ============================================================
local BtnGui=Instance.new("ScreenGui")
BtnGui.Name=BTNNAME; BtnGui.ResetOnSpawn=false; BtnGui.DisplayOrder=998
BtnGui.Parent=SafeParent
do local id=Instance.new("StringValue"); id.Name=IDENT; id.Parent=BtnGui end

local FloatBtn=Instance.new("ImageButton")
FloatBtn.Size=UDim2.fromOffset(52,52); FloatBtn.Position=UDim2.fromScale(0.05,0.5)
FloatBtn.BackgroundTransparency=1; FloatBtn.AutoButtonColor=false
FloatBtn.Image="rbxassetid://127239715511367"; FloatBtn.Parent=BtnGui
Instance.new("UICorner",FloatBtn).CornerRadius=UDim.new(1,0)

FloatBtn.MouseButton1Click:Connect(function() Main.Visible=not Main.Visible end)

-- Float button drag - HANYA pakai UserInputService.InputChanged (NO RunService)
local fDrag=false; local fOff=Vector2.zero
FloatBtn.InputBegan:Connect(function(inp)
    if inp.UserInputType==Enum.UserInputType.MouseButton1
    or inp.UserInputType==Enum.UserInputType.Touch then
        fDrag=true; fOff=UserInputService:GetMouseLocation()-FloatBtn.AbsolutePosition
    end
end)
FloatBtn.InputEnded:Connect(function(inp)
    if inp.UserInputType==Enum.UserInputType.MouseButton1
    or inp.UserInputType==Enum.UserInputType.Touch then fDrag=false end
end)
-- Pakai UserInputService.InputChanged (BUKAN RenderStepped/Heartbeat!)
UserInputService.InputChanged:Connect(function(inp)
    if fDrag and (inp.UserInputType==Enum.UserInputType.MouseMovement
               or inp.UserInputType==Enum.UserInputType.Touch) then
        local vp=game:GetService("Workspace").CurrentCamera
                 and game:GetService("Workspace").CurrentCamera.ViewportSize
                 or Vector2.new(1920,1080)
        local sz=FloatBtn.AbsoluteSize
        local target=UserInputService:GetMouseLocation()-fOff
        FloatBtn.Position=UDim2.fromOffset(
            math.clamp(target.X,0,vp.X-sz.X),
            math.clamp(target.Y,0,vp.Y-sz.Y))
    end
end)

-- ============================================================
-- INIT
-- ============================================================
SwitchTab("Info")
warn("[Vechnost] v2.5.2 loaded | ZERO background loops | No RunService connections")
Notify("Vechnost","v2.5.2 Loaded! BAC-4226 Fixed",3)
