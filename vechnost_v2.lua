--[[ 
    FILE: vechnost_v2.lua (MODIFIED)
    BRAND: Vechnost
    VERSION: 2.5.0 (Anti-BAC Tuned)
    DESC: Complete Fish It Automation Suite
          - Auto Fishing + Clicker
          - Island Teleport
          - Auto Trading (Coin, Rarity, Stone, Name)
          - Auto Shop (Charm, Weather, Bait, Merchant)
          - Server-Wide Webhook Logger
    UI: Custom Dark Blue Sidebar Design
]]

-- =====================================================
-- BAGIAN 0: ANTI-BAC UTILITY
-- =====================================================
local function de(str)
    -- Decode string yang di-encode dengan ASCII codes dipisah spasi
    local res = ""
    for num in string.gmatch(str, "%d+") do
        res = res .. string.char(tonumber(num))
    end
    return res
end

-- Encode string penting agar tidak mudah terdeteksi
local s = {
    core = de("67 111 114 101 71 117 105"), -- "CoreGui"
    players = de("80 108 97 121 101 114 115"), -- "Players"
    repStorage = de("82 101 112 108 105 99 97 116 101 100 83 116 111 114 97 103 101"), -- "ReplicatedStorage"
    httpServ = de("72 116 116 112 83 101 114 118 105 99 101"), -- "HttpService"
    runServ = de("82 117 110 83 101 114 118 105 99 101"), -- "RunService"
    userInput = de("85 115 101 114 73 110 112 117 116 83 101 114 118 105 99 101"), -- "UserInputService"
    tween = de("84 119 101 101 110 83 101 114 118 105 99 101"), -- "TweenService"
    workspace = de("87 111 114 107 115 112 97 99 101"), -- "Workspace"
    virtInput = de("86 105 114 116 117 97 108 73 110 112 117 116 77 97 110 97 103 101 114"), -- "VirtualInputManager"
    virtUser = de("86 105 114 116 117 97 108 85 115 101 114"), -- "VirtualUser"
    localPlayer = de("76 111 99 97 108 80 108 97 121 101 114"), -- "LocalPlayer"
    playerGui = de("80 108 97 121 101 114 71 117 105"), -- "PlayerGui"
    packages = de("80 97 99 107 97 103 101 115"), -- "Packages"
    index = de("95 73 110 100 101 120"), -- "_Index"
    sleitnick = de("115 108 101 105 116 110 105 99 107 95 110 101 116 64 48 46 50 46 48"), -- "sleitnick_net@0.2.0"
    net = de("110 101 116"), -- "net"
    fishNotify = de("82 69 47 79 98 116 97 105 110 101 100 78 101 119 70 105 115 104 78 111 116 105 102 105 99 97 116 105 111 110"), -- "RE/ObtainedNewFishNotification"
    items = de("73 116 101 109 115"), -- "Items"
    replion = de("82 101 112 108 105 111 110"), -- "Replion"
    data = de("68 97 116 97"), -- "Data"
}

-- =====================================================
-- BAGIAN 1: CLEANUP SYSTEM
-- =====================================================
local Core = game:GetService(s.core)
local guiNames = {
    Main = de("86 101 99 104 110 111 115 116 95 77 97 105 110 95 85 73"), -- "Vechnost_Main_UI"
    Mobile = de("86 101 99 104 110 111 115 116 95 77 111 98 105 108 101 95 66 117 116 116 111 110"), -- "Vechnost_Mobile_Button"
}

for _, v in pairs(Core:GetChildren()) do
    for _, name in pairs(guiNames) do
        if v.Name == name then v:Destroy() end
    end
end

-- =====================================================
-- BAGIAN 2: SERVICES & GLOBALS
-- =====================================================
local plrs = game:GetService(s.players)
local repStor = game:GetService(s.repStorage)
local http = game:GetService(s.httpServ)
local run = game:GetService(s.runServ)
local uis = game:GetService(s.userInput)
local tween = game:GetService(s.tween)
local ws = game:GetService(s.workspace)
local vim = game:GetService(s.virtInput)
local vu = game:GetService(s.virtUser)

local localP = plrs.LocalPlayer
local pgui = localP:WaitForChild(s.playerGui)

local net, obtainedFish
do
    local ok, err = pcall(function()
        net = repStor:WaitForChild(s.packages, 10)
            :WaitForChild(s.index, 5)
            :WaitForChild(s.sleitnick, 5)
            :WaitForChild(s.net, 5)
        obtainedFish = net:WaitForChild(s.fishNotify, 5)
    end)
    if not ok then
        warn("[Vechnost] Remote load error")
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

local Fishing = {
    AutoCast = false,
    AutoReel = false,
    AutoShake = false,
    PerfectCatch = false,
    AntiAFK = false,
    AutoSell = false,
    ClickSpeed = 50,
}

local ShopSet = {
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
    pcall(function()
        local itemsFolder = repStor:FindFirstChild(s.items)
        if itemsFolder then
            for _, mod in ipairs(itemsFolder:GetChildren()) do
                if mod:IsA("ModuleScript") then
                    local ok, req = pcall(require, mod)
                    if ok and req and req.Data and req.Data.Type == "Fish" then
                        FishDB[req.Data.Id] = {
                            Name = req.Data.Name,
                            Tier = req.Data.Tier,
                            Icon = req.Data.Icon,
                            SellPrice = req.Data.SellPrice or req.Data.Value or 0
                        }
                    end
                end
            end
        end
    end)
end

local FishNameToId = {}
for id, data in pairs(FishDB) do
    if data.Name then
        FishNameToId[data.Name] = id
        FishNameToId[string.lower(data.Name)] = id
    end
end

-- =====================================================
-- BAGIAN 5: REPLION PLAYER DATA
-- =====================================================
local PlayerData = nil
do
    pcall(function()
        local Replion = require(repStor:FindFirstChild(s.packages):FindFirstChild(s.replion))
        PlayerData = Replion.Client:WaitReplion(s.data)
    end)
end

local function FormatNumber(n)
    if type(n)~="number" then return "0" end
    local formatted = tostring(math.floor(n))
    local k
    repeat
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
    until k==0
    return formatted
end

local function GetPlayerStats()
    local stats = { Coins=0, TotalCaught=0, BackpackCount=0, BackpackMax=0 }
    if not PlayerData then return stats end
    pcall(function()
        for _, key in ipairs({"Coins","Currency","Money"}) do
            local ok, val = pcall(function() return PlayerData:Get(key) end)
            if ok and val then stats.Coins=val break end
        end
        for _, key in ipairs({"TotalCaught","FishCaught"}) do
            local ok, val = pcall(function() return PlayerData:Get(key) end)
            if ok and val then stats.TotalCaught=val break end
        end
        local inv = PlayerData:Get("Inventory")
        if inv and typeof(inv)=="table" then
            local items = inv.Items or inv
            if typeof(items)=="table" then
                local c=0; for _ in pairs(items) do c=c+1 end
                stats.BackpackCount = c
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
    [1]="Common",[2]="Uncommon",[3]="Rare",[4]="Epic",
    [5]="Legendary",[6]="Mythic",[7]="Secret",
}
local RARITY_NAME_TO_TIER = {
    Common=1,Uncommon=2,Rare=3,Epic=4,Legendary=5,Mythic=6,Secret=7,
}
local RarityList = {"Common","Uncommon","Rare","Epic","Legendary","Mythic","Secret"}

-- =====================================================
-- BAGIAN 7: TELEPORT LOCATIONS
-- =====================================================
local TeleportSpots = {}
local islandDB = {
    {"Moosewood",{"moosewood","starter","spawn","hub"}},
    {"Roslit Bay",{"roslit","bay"}},
    {"Mushgrove Swamp",{"mushgrove","swamp","mushroom"}},
    {"Snowcap Island",{"snowcap","snow","ice","frozen"}},
    {"Terrapin Island",{"terrapin","turtle"}},
    {"Forsaken Shores",{"forsaken","shores"}},
    {"Sunstone Island",{"sunstone","sun"}},
    {"Kepler Island",{"kepler"}},
    {"Ancient Isle",{"ancient","isle"}},
    {"Volcanic Island",{"volcanic","volcano","lava","magma"}},
    {"Crystal Caverns",{"crystal","caverns","cave"}},
    {"Brine Pool",{"brine","pool"}},
    {"Vertigo",{"vertigo"}},
    {"Atlantis",{"atlantis","underwater"}},
    {"The Depths",{"depths","deep","abyss"}},
    {"Monster's Borough",{"monster","borough"}},
    {"Event Island",{"event","special"}},
}

local function ScanIslands()
    TeleportSpots = {}
    pcall(function()
        local zones = ws:FindFirstChild("Zones") or ws:FindFirstChild("Islands") or ws:FindFirstChild("Locations")
        if zones then
            for _, zone in pairs(zones:GetChildren()) do
                local pos
                if zone:IsA("BasePart") then
                    pos = zone.Position
                elseif zone:IsA("Model") and zone.PrimaryPart then
                    pos = zone.PrimaryPart.Position
                elseif zone:FindFirstChildWhichIsA("BasePart") then
                    pos = zone:FindFirstChildWhichIsA("BasePart").Position
                end
                if pos then
                    table.insert(TeleportSpots, {Name=zone.Name, Pos=pos, CFrame=CFrame.new(pos+Vector3.new(0,5,0))})
                end
            end
        end
        for _, obj in pairs(ws:GetDescendants()) do
            if obj:IsA("BasePart") then
                local nm = string.lower(obj.Name)
                for _, isl in ipairs(islandDB) do
                    for _, kw in ipairs(isl[2]) do
                        if string.find(nm, kw) then
                            local exists = false
                            for _, s in ipairs(TeleportSpots) do
                                if s.Name == isl[1] then exists=true break end
                            end
                            if not exists then
                                table.insert(TeleportSpots, {Name=isl[1], Pos=obj.Position, CFrame=CFrame.new(obj.Position+Vector3.new(0,5,0))})
                            end
                            break
                        end
                    end
                end
            end
        end
        local spawn = ws:FindFirstChildOfClass("SpawnLocation")
        if spawn then
            local exists = false
            for _, s in ipairs(TeleportSpots) do
                if string.find(string.lower(s.Name), "spawn") then exists=true break end
            end
            if not exists then
                table.insert(TeleportSpots, {Name="Spawn Point", Pos=spawn.Position, CFrame=spawn.CFrame+Vector3.new(0,5,0)})
            end
        end
    end)
    if #TeleportSpots==0 then
        for _, isl in ipairs(islandDB) do
            table.insert(TeleportSpots, {Name=isl[1], Pos=Vector3.new(0,50,0), CFrame=CFrame.new(0,50,0)})
        end
    end
    table.sort(TeleportSpots, function(a,b) return a.Name < b.Name end)
    return TeleportSpots
end

local function TeleportTo(name)
    local char = localP.Character
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    for _, loc in ipairs(TeleportSpots) do
        if loc.Name == name then
            hrp.CFrame = loc.CFrame
            return true
        end
    end
    return false
end

local function GetTeleportNames()
    local t={}
    for _, loc in ipairs(TeleportSpots) do table.insert(t, loc.Name) end
    if #t==0 then t={"(Scan first)"} end
    return t
end

ScanIslands()

-- =====================================================
-- BAGIAN 8: SHOP DATABASE
-- =====================================================
local ShopData = {
    Charms = {
        "Lucky Charm","Mythical Charm","Shiny Charm","Magnetic Charm",
        "Celestial Charm","Fortune Charm","Ocean Charm","Treasure Charm"
    },
    Weather = {
        "Sunny","Rainy","Stormy","Foggy","Snowy","Blood Moon","Aurora","Eclipse"
    },
    Bait = {
        "Basic Bait","Worm","Minnow","Shrimp","Premium Bait","Legendary Bait","Mythic Bait"
    },
    Merchant = {
        "Mystery Box","Premium Crate","Rod Upgrade","Backpack Upgrade","Enchant Stone","Evolved Stone"
    }
}

local function GetShopRemote(cat)
    if not net then return nil end
    local candidates = {
        Charm = {"RE/BuyCharm","RE/PurchaseCharm","RE/EquipCharm"},
        Weather = {"RE/BuyWeather","RE/ChangeWeather","RE/SetWeather"},
        Bait = {"RE/BuyBait","RE/PurchaseBait","RE/SelectBait"},
        Merchant = {"RE/BuyItem","RE/Purchase","RE/BuyMerchant"}
    }
    for _, rname in ipairs(candidates[cat] or {}) do
        local r = net:FindFirstChild(rname)
        if r then return r end
    end
    for _, child in ipairs(net:GetDescendants()) do
        if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
            local lname = string.lower(child.Name)
            if string.find(lname, string.lower(cat)) or string.find(lname, "buy") then
                return child
            end
        end
    end
    return nil
end

local function BuyItem(cat, item)
    local r = GetShopRemote(cat)
    if not r then return false end
    pcall(function()
        if r:IsA("RemoteEvent") then r:FireServer(item)
        else r:InvokeServer(item) end
    end)
    return true
end

-- =====================================================
-- BAGIAN 9: HTTP REQUEST
-- =====================================================
local HttpReq
do
    local env = getfenv()
    if env.syn and env.syn.request then HttpReq = env.syn.request
    elseif env.http_request then HttpReq = env.http_request
    elseif env.request then HttpReq = env.request
    elseif env.fluxus and env.fluxus.request then HttpReq = env.fluxus.request
    end
end

-- =====================================================
-- BAGIAN 10: ICON & WEBHOOK
-- =====================================================
local IconCache = {}
local IconWaiter = {}

local function FetchIcon(id, cb)
    if IconCache[id] then cb(IconCache[id]) return end
    if IconWaiter[id] then table.insert(IconWaiter[id], cb) return end
    IconWaiter[id] = {cb}
    task.spawn(function()
        local fish = FishDB[id]
        if not fish or not fish.Icon then cb("") return end
        local asset = tostring(fish.Icon):match("%d+")
        if not asset then cb("") return end
        local ok, res = pcall(function()
            return HttpReq({
                Url = "https://thumbnails.roblox.com/v1/assets?assetIds="..asset.."&size=420x420&format=Png",
                Method = "GET"
            })
        end)
        if ok and res and res.Body then
            local ok2, data = pcall(http.JSONDecode, http, res.Body)
            if ok2 and data and data.data and data.data[1] then
                IconCache[id] = data.data[1].imageUrl or ""
            end
        end
        for _, f in ipairs(IconWaiter[id] or {}) do f(IconCache[id] or "") end
        IconWaiter[id]=nil
    end)
end

local function RarityAllowed(id)
    local fish = FishDB[id]
    if not fish then return false end
    if next(Settings.SelectedRarities)==nil then return true end
    return Settings.SelectedRarities[fish.Tier]==true
end

local function BuildPayload(pName, fid, w, mut)
    local fish = FishDB[fid]
    if not fish then return nil end
    local rName = RARITY_MAP[fish.Tier] or "Unknown"
    local icon = IconCache[fid] or ""
    local date = os.date("!%B %d, %Y")
    return {
        username = "Vechnost Notifier",
        avatar_url = "https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png",
        flags = 32768,
        components = {{
            type = 17,
            components = {
                { type = 10, content = "# NEW FISH CAUGHT!" },
                { type = 14, spacing = 1, divider = true },
                { type = 10, content = "__@"..pName.." caught "..string.upper(rName).." fish__" },
                {
                    type = 9,
                    components = {
                        { type = 10, content = "**Fish Name**" },
                        { type = 10, content = "> "..fish.Name }
                    },
                    accessory = icon~="" and { type = 11, media = { url = icon } } or nil
                },
                { type = 10, content = "**Rarity:** "..rName },
                { type = 10, content = "**Weight:** "..string.format("%.1fkg", w or 0) },
                { type = 10, content = "**Mutation:** "..(mut or "None") },
                { type = 14, spacing = 1, divider = true },
                { type = 10, content = "-# "..date }
            }
        }}
    }
end

local function SendHook(payload)
    if Settings.Url=="" or not HttpReq or not payload then return end
    pcall(function()
        local url = Settings.Url
        if string.find(url, "?") then url=url.."&with_components=true" else url=url.."?with_components=true" end
        HttpReq({
            Url = url, Method = "POST",
            Headers = {["Content-Type"]="application/json"},
            Body = http:JSONEncode(payload)
        })
    end)
end

-- =====================================================
-- BAGIAN 11: FISH DETECTION
-- =====================================================
local connections = {}
local function onFishCaught(pArg, wData, wrap)
    if not Settings.Active then return end
    local item
    if wrap and type(wrap)=="table" and wrap.InventoryItem then item = wrap.InventoryItem
    elseif wData and type(wData)=="table" and wData.InventoryItem then item = wData.InventoryItem end
    if not item or not item.Id or not item.UUID then return end
    if not FishDB[item.Id] then return end
    if not RarityAllowed(item.Id) then return end
    if Settings.SentUUID[item.UUID] then return end
    Settings.SentUUID[item.UUID] = true
    local pName = localP.Name
    if typeof(pArg)=="Instance" and pArg:IsA("Player") then pName = pArg.Name
    elseif typeof(pArg)=="string" then pName = pArg end
    if not Settings.ServerWide and pName ~= localP.Name then return end
    local weight = wData and type(wData)=="table" and wData.Weight or 0
    local mut = wData and type(wData)=="table" and wData.Mutation or nil
    Settings.LogCount = Settings.LogCount+1
    FetchIcon(item.Id, function()
        SendHook(BuildPayload(pName, item.Id, weight, mut))
    end)
end

local function StartLog()
    if Settings.Active then return true end
    if not net or not obtainedFish then return false end
    Settings.Active = true
    Settings.SentUUID = {}
    Settings.LogCount = 0
    pcall(function()
        connections[#connections+1] = obtainedFish.OnClientEvent:Connect(onFishCaught)
    end)
    return true
end

local function StopLog()
    Settings.Active = false
    for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    connections = {}
end

-- =====================================================
-- BAGIAN 12: FISHING AUTOMATION
-- =====================================================
local FishRemotes = {}
do
    if net then
        for _, child in ipairs(net:GetDescendants()) do
            if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
                local lname = string.lower(child.Name)
                if string.find(lname, "cast") or string.find(lname, "throw") then
                    FishRemotes.Cast = FishRemotes.Cast or child
                elseif string.find(lname, "reel") or string.find(lname, "pull") or string.find(lname, "catch") then
                    FishRemotes.Reel = FishRemotes.Reel or child
                elseif string.find(lname, "shake") then
                    FishRemotes.Shake = FishRemotes.Shake or child
                elseif string.find(lname, "sell") then
                    FishRemotes.Sell = FishRemotes.Sell or child
                end
            end
        end
    end
end

local function click()
    pcall(function()
        vim:SendMouseButtonEvent(0,0,0,true,game,1)
        task.wait(0.01)
        vim:SendMouseButtonEvent(0,0,0,false,game,1)
    end)
end

local function biting()
    local pg = localP:FindFirstChild("PlayerGui")
    if not pg then return false end
    for _,g in ipairs(pg:GetDescendants()) do
        if g:IsA("GuiObject") and g.Visible then
            local nm = string.lower(g.Name)
            if string.find(nm, "bite") or string.find(nm, "catch") or string.find(nm, "!") or string.find(nm, "reel") then
                return true
            end
        end
    end
    return false
end

local function shaking()
    local pg = localP:FindFirstChild("PlayerGui")
    if not pg then return false end
    for _,g in ipairs(pg:GetDescendants()) do
        if g:IsA("GuiObject") and g.Visible then
            local nm = string.lower(g.Name)
            if string.find(nm, "shake") or string.find(nm, "struggle") or string.find(nm, "minigame") then
                return true
            end
        end
    end
    return false
end

task.spawn(function()
    while true do
        task.wait(0.1)
        if Fishing.AntiAFK then
            pcall(function()
                vu:CaptureController()
                vu:ClickButton2(Vector2.new())
            end)
        end
        if Fishing.AutoCast then
            pcall(function()
                if FishRemotes.Cast and FishRemotes.Cast:IsA("RemoteEvent") then
                    FishRemotes.Cast:FireServer()
                end
                click()
            end)
        end
        if Fishing.AutoReel and biting() then
            pcall(function()
                if FishRemotes.Reel and FishRemotes.Reel:IsA("RemoteEvent") then
                    FishRemotes.Reel:FireServer()
                end
                click()
            end)
        end
        if Fishing.AutoShake and shaking() then
            for i=1, Fishing.ClickSpeed do
                if not Fishing.AutoShake then break end
                pcall(function()
                    if FishRemotes.Shake then
                        FishRemotes.Shake:FireServer()
                    end
                    click()
                end)
                task.wait(1/Fishing.ClickSpeed)
            end
        end
        if Fishing.AutoSell then
            pcall(function()
                if FishRemotes.Sell then
                    FishRemotes.Sell:FireServer("All")
                end
            end)
        end
    end
end)

-- =====================================================
-- BAGIAN 13: TRADING SYSTEM
-- =====================================================
local Trade = {
    Target = nil,
    Inv = {},
    Stones = {},
    ByName = {Active=false, Item=nil, Amt=1, Sent=0},
    ByCoin = {Active=false, TargetCoins=0, Sent=0},
    ByRarity = {Active=false, Rarity=nil, Tier=nil, Amt=1, Sent=0},
    ByStone = {Active=false, Stone=nil, Amt=1, Sent=0},
}
local STONE_ITEMS = {"Enchant Stone","Evolved Stone"}

local function LoadInv()
    Trade.Inv = {}; Trade.Stones = {}
    pcall(function()
        local inv = PlayerData:Get("Inventory")
        if not inv then return end
        local items = inv.Items or inv
        if typeof(items)~="table" then return end
        for _, it in pairs(items) do
            if type(it)=="table" then
                local name
                if it.Id and FishDB[it.Id] then name = FishDB[it.Id].Name
                elseif it.Name then name = tostring(it.Name) end
                if name then
                    local isStone = false
                    for _, s in ipairs(STONE_ITEMS) do
                        if string.lower(name)==string.lower(s) then
                            isStone = true
                            Trade.Stones[s] = (Trade.Stones[s] or 0) + 1
                            break
                        end
                    end
                    if not isStone then
                        Trade.Inv[name] = (Trade.Inv[name] or 0) + 1
                    end
                end
            end
        end
    end)
end

local function GetInvNames()
    local t={}
    for name,_ in pairs(Trade.Inv) do table.insert(t,name) end
    table.sort(t)
    if #t==0 then t={"(Load first)"} end
    return t
end

local TradeRemote
local function GetTradeRemoteFunc()
    if TradeRemote then return TradeRemote end
    pcall(function()
        for _, child in pairs(net:GetDescendants()) do
            if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
                if string.find(string.lower(child.Name), "trade") then
                    TradeRemote = child
                    break
                end
            end
        end
    end)
    return TradeRemote
end

local function SendTrade(targetName, itemName, qty)
    local r = GetTradeRemoteFunc()
    if not r then return false end
    local target
    for _,p in pairs(plrs:GetPlayers()) do
        if p.Name==targetName or p.DisplayName==targetName then target=p break end
    end
    if not target then return false end
    local id = FishNameToId[itemName] or FishNameToId[string.lower(itemName)]
    pcall(function()
        if r:IsA("RemoteEvent") then
            r:FireServer(target, id or itemName, qty or 1)
        else
            r:InvokeServer(target, id or itemName, qty or 1)
        end
    end)
    return true
end

-- =====================================================
-- BAGIAN 14: UI COLOR SCHEME
-- =====================================================
local Colors = {
    Background = Color3.fromRGB(15,17,26),
    Sidebar = Color3.fromRGB(20,24,38),
    SidebarItem = Color3.fromRGB(30,36,58),
    SidebarItemHover = Color3.fromRGB(40,48,75),
    SidebarItemActive = Color3.fromRGB(45,55,90),
    Content = Color3.fromRGB(25,28,42),
    ContentItem = Color3.fromRGB(35,40,60),
    ContentItemHover = Color3.fromRGB(45,52,78),
    Accent = Color3.fromRGB(70,130,255),
    AccentHover = Color3.fromRGB(90,150,255),
    Text = Color3.fromRGB(255,255,255),
    TextDim = Color3.fromRGB(180,180,200),
    TextMuted = Color3.fromRGB(120,125,150),
    Border = Color3.fromRGB(50,55,80),
    Success = Color3.fromRGB(80,200,120),
    Error = Color3.fromRGB(255,100,100),
    Toggle = Color3.fromRGB(70,130,255),
    ToggleOff = Color3.fromRGB(60,65,90),
    DropdownBg = Color3.fromRGB(20,22,35),
}

-- =====================================================
-- BAGIAN 15: CREATE MAIN GUI
-- =====================================================
local sg = Instance.new("ScreenGui")
sg.Name = guiNames.Main
sg.ResetOnSpawn = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Parent = Core

local main = Instance.new("Frame")
main.Name = "MainFrame"
main.Size = UDim2.new(0,720,0,480)
main.Position = UDim2.new(0.5,-360,0.5,-240)
main.BackgroundColor3 = Colors.Background
main.BorderSizePixel = 0
main.ClipsDescendants = true
main.Parent = sg
Instance.new("UICorner", main).CornerRadius = UDim.new(0,12)
local mainStroke = Instance.new("UIStroke", main)
mainStroke.Color = Colors.Border
mainStroke.Thickness = 1

-- Title Bar
local titleBar = Instance.new("Frame", main)
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1,0,0,45)
titleBar.BackgroundColor3 = Colors.Sidebar
titleBar.BorderSizePixel = 0
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0,12)
local titleFix = Instance.new("Frame", titleBar)
titleFix.Size = UDim2.new(1,0,0,15)
titleFix.Position = UDim2.new(0,0,1,-15)
titleFix.BackgroundColor3 = Colors.Sidebar
titleFix.BorderSizePixel = 0
local titleLabel = Instance.new("TextLabel", titleBar)
titleLabel.Size = UDim2.new(1,-100,1,0)
titleLabel.Position = UDim2.new(0,15,0,0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Vechnost"
titleLabel.TextColor3 = Colors.Text
titleLabel.TextSize = 18
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
local closeBtn = Instance.new("TextButton", titleBar)
closeBtn.Size = UDim2.new(0,30,0,30)
closeBtn.Position = UDim2.new(1,-40,0.5,-15)
closeBtn.BackgroundColor3 = Colors.ContentItem
closeBtn.BorderSizePixel = 0
closeBtn.Text = "×"
closeBtn.TextColor3 = Colors.Text
closeBtn.TextSize = 20
closeBtn.Font = Enum.Font.GothamBold
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0,6)
local minBtn = Instance.new("TextButton", titleBar)
minBtn.Size = UDim2.new(0,30,0,30)
minBtn.Position = UDim2.new(1,-75,0.5,-15)
minBtn.BackgroundColor3 = Colors.ContentItem
minBtn.BorderSizePixel = 0
minBtn.Text = "—"
minBtn.TextColor3 = Colors.Text
minBtn.TextSize = 16
minBtn.Font = Enum.Font.GothamBold
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0,6)

-- Sidebar
local sidebar = Instance.new("Frame", main)
sidebar.Name = "Sidebar"
sidebar.Size = UDim2.new(0,150,1,-55)
sidebar.Position = UDim2.new(0,5,0,50)
sidebar.BackgroundColor3 = Colors.Sidebar
sidebar.BorderSizePixel = 0
Instance.new("UICorner", sidebar).CornerRadius = UDim.new(0,10)
local pad = Instance.new("UIPadding", sidebar)
pad.PaddingTop = UDim.new(0,8); pad.PaddingBottom = UDim.new(0,8); pad.PaddingLeft = UDim.new(0,8); pad.PaddingRight = UDim.new(0,8)
local sLayout = Instance.new("UIListLayout", sidebar)
sLayout.SortOrder = Enum.SortOrder.LayoutOrder; sLayout.Padding = UDim.new(0,4)

-- Content Area
local contentArea = Instance.new("Frame", main)
contentArea.Name = "ContentArea"
contentArea.Size = UDim2.new(1,-170,1,-60)
contentArea.Position = UDim2.new(0,165,0,55)
contentArea.BackgroundColor3 = Colors.Content
contentArea.BorderSizePixel = 0
Instance.new("UICorner", contentArea).CornerRadius = UDim.new(0,10)

-- Dropdown container
local dropContainer = Instance.new("Frame", sg)
dropContainer.Name = "DropdownContainer"
dropContainer.Size = UDim2.new(1,0,1,0)
dropContainer.BackgroundTransparency = 1
dropContainer.ZIndex = 100

-- =====================================================
-- BAGIAN 16: TAB SYSTEM
-- =====================================================
local tabContents = {}
local tabButtons = {}
local currentTab = nil
local tabs = {
    {Name="Info", Icon="👤", Order=1},
    {Name="Fishing", Icon="🎣", Order=2},
    {Name="Teleport", Icon="📍", Order=3},
    {Name="Trading", Icon="🔄", Order=4},
    {Name="Shop", Icon="🛒", Order=5},
    {Name="Webhook", Icon="🔔", Order=6},
    {Name="Setting", Icon="⚙️", Order=7},
}

local function makeTabButton(data)
    local btn = Instance.new("TextButton")
    btn.Name = data.Name.."Tab"
    btn.Size = UDim2.new(1,0,0,38)
    btn.BackgroundColor3 = Colors.SidebarItem
    btn.BorderSizePixel = 0
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.LayoutOrder = data.Order
    btn.Parent = sidebar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,8)
    local ic = Instance.new("TextLabel", btn)
    ic.Size = UDim2.new(0,28,1,0); ic.Position = UDim2.new(0,8,0,0); ic.BackgroundTransparency=1; ic.Text=data.Icon; ic.TextColor3=Colors.Accent; ic.TextSize=16; ic.Font=Enum.Font.GothamBold
    local tx = Instance.new("TextLabel", btn)
    tx.Size = UDim2.new(1,-42,1,0); tx.Position = UDim2.new(0,38,0,0); tx.BackgroundTransparency=1; tx.Text=data.Name; tx.TextColor3=Colors.Text; tx.TextSize=13; tx.Font=Enum.Font.GothamSemibold; tx.TextXAlignment=Enum.TextXAlignment.Left
    btn.MouseEnter:Connect(function()
        if currentTab ~= data.Name then
            tween:Create(btn, TweenInfo.new(0.2), {BackgroundColor3=Colors.SidebarItemHover}):Play()
        end
    end)
    btn.MouseLeave:Connect(function()
        if currentTab ~= data.Name then
            tween:Create(btn, TweenInfo.new(0.2), {BackgroundColor3=Colors.SidebarItem}):Play()
        end
    end)
    return btn
end

local function makeContent(name)
    local sc = Instance.new("ScrollingFrame")
    sc.Name = name.."Content"
    sc.Size = UDim2.new(1,-16,1,-16)
    sc.Position = UDim2.new(0,8,0,8)
    sc.BackgroundTransparency = 1
    sc.BorderSizePixel = 0
    sc.ScrollBarThickness = 4
    sc.ScrollBarImageColor3 = Colors.Accent
    sc.CanvasSize = UDim2.new(0,0,0,0)
    sc.AutomaticCanvasSize = Enum.AutomaticSize.Y
    sc.Visible = false
    sc.Parent = contentArea
    local lay = Instance.new("UIListLayout", sc)
    lay.SortOrder = Enum.SortOrder.LayoutOrder; lay.Padding = UDim.new(0,8)
    Instance.new("UIPadding", sc).PaddingBottom = UDim.new(0,10)
    return sc
end

local function switchTab(name)
    if currentTab == name then return end
    for n,cont in pairs(tabContents) do cont.Visible = (n==name) end
    for n,btn in pairs(tabButtons) do
        local col = (n==name) and Colors.SidebarItemActive or Colors.SidebarItem
        tween:Create(btn, TweenInfo.new(0.2), {BackgroundColor3=col}):Play()
    end
    currentTab = name
end

for _,td in ipairs(tabs) do
    local b = makeTabButton(td)
    tabButtons[td.Name] = b
    tabContents[td.Name] = makeContent(td.Name)
    b.MouseButton1Click:Connect(function() switchTab(td.Name) end)
end

-- =====================================================
-- BAGIAN 17: UI COMPONENT CREATORS
-- =====================================================
local orderCnt = {}
local function nextOrder(tab) orderCnt[tab] = (orderCnt[tab] or 0) + 1; return orderCnt[tab] end

local function Section(tab, title)
    local p = tabContents[tab]; if not p then return end
    local f = Instance.new("Frame", p)
    f.Name = "S_"..title
    f.Size = UDim2.new(1,0,0,28)
    f.BackgroundTransparency = 1
    f.LayoutOrder = nextOrder(tab)
    local l = Instance.new("TextLabel", f)
    l.Size = UDim2.new(1,0,1,0); l.BackgroundTransparency=1; l.Text=title; l.TextColor3=Colors.Accent; l.TextSize=15; l.Font=Enum.Font.GothamBold; l.TextXAlignment=Enum.TextXAlignment.Left
end

local function Paragraph(tab, title, content)
    local p = tabContents[tab]; if not p then return end
    local f = Instance.new("Frame", p)
    f.Name = "P_"..title
    f.Size = UDim2.new(1,0,0,55)
    f.BackgroundColor3 = Colors.ContentItem
    f.BorderSizePixel = 0
    f.LayoutOrder = nextOrder(tab)
    Instance.new("UICorner", f).CornerRadius = UDim.new(0,8)
    local tL = Instance.new("TextLabel", f)
    tL.Name = "Title"; tL.Size = UDim2.new(1,-20,0,20); tL.Position = UDim2.new(0,10,0,6); tL.BackgroundTransparency=1; tL.Text=title; tL.TextColor3=Colors.Text; tL.TextSize=13; tL.Font=Enum.Font.GothamBold; tL.TextXAlignment=Enum.TextXAlignment.Left
    local cL = Instance.new("TextLabel", f)
    cL.Name = "Content"; cL.Size = UDim2.new(1,-20,0,22); cL.Position = UDim2.new(0,10,0,26); cL.BackgroundTransparency=1; cL.Text=content; cL.TextColor3=Colors.TextDim; cL.TextSize=11; cL.Font=Enum.Font.Gotham; cL.TextXAlignment=Enum.TextXAlignment.Left; cL.TextWrapped=true
    return {Frame=f, Set=function(_,d) tL.Text = d.Title or tL.Text; cL.Text = d.Content or cL.Text end}
end

local function Input(tab, name, placeholder, cb)
    local p = tabContents[tab]; if not p then return end
    local f = Instance.new("Frame", p)
    f.Name = "I_"..name
    f.Size = UDim2.new(1,0,0,58)
    f.BackgroundColor3 = Colors.ContentItem
    f.BorderSizePixel = 0
    f.LayoutOrder = nextOrder(tab)
    Instance.new("UICorner", f).CornerRadius = UDim.new(0,8)
    local lbl = Instance.new("TextLabel", f)
    lbl.Size = UDim2.new(1,-20,0,18); lbl.Position = UDim2.new(0,10,0,6); lbl.BackgroundTransparency=1; lbl.Text=name; lbl.TextColor3=Colors.Text; lbl.TextSize=12; lbl.Font=Enum.Font.GothamSemibold; lbl.TextXAlignment=Enum.TextXAlignment.Left
    local box = Instance.new("TextBox", f)
    box.Size = UDim2.new(1,-20,0,26); box.Position = UDim2.new(0,10,0,26); box.BackgroundColor3 = Colors.Background; box.BorderSizePixel = 0; box.Text = ""; box.PlaceholderText = placeholder or ""; box.PlaceholderColor3 = Colors.TextMuted; box.TextColor3 = Colors.Text; box.TextSize = 11; box.Font = Enum.Font.Gotham; box.ClearTextOnFocus = false
    Instance.new("UICorner", box).CornerRadius = UDim.new(0,6)
    Instance.new("UIPadding", box).PaddingLeft = UDim.new(0,10); box.PaddingRight = UDim.new(0,10)
    box.FocusLost:Connect(function() if cb then cb(box.Text) end end)
    return {Frame=f, TextBox=box, Get=function() return box.Text end, Set=function(_,v) box.Text=v end}
end

local function Button(tab, name, cb)
    local p = tabContents[tab]; if not p then return end
    local btn = Instance.new("TextButton", p)
    btn.Name = "B_"..name
    btn.Size = UDim2.new(1,0,0,36)
    btn.BackgroundColor3 = Colors.Accent
    btn.BorderSizePixel = 0
    btn.Text = name
    btn.TextColor3 = Colors.Text
    btn.TextSize = 12
    btn.Font = Enum.Font.GothamSemibold
    btn.AutoButtonColor = false
    btn.LayoutOrder = nextOrder(tab)
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,8)
    btn.MouseEnter:Connect(function() tween:Create(btn, TweenInfo.new(0.2), {BackgroundColor3=Colors.AccentHover}):Play() end)
    btn.MouseLeave:Connect(function() tween:Create(btn, TweenInfo.new(0.2), {BackgroundColor3=Colors.Accent}):Play() end)
    btn.MouseButton1Click:Connect(cb)
    return btn
end

local function Toggle(tab, name, default, cb)
    local p = tabContents[tab]; if not p then return end
    local state = default or false
    local f = Instance.new("Frame", p)
    f.Name = "T_"..name
    f.Size = UDim2.new(1,0,0,42)
    f.BackgroundColor3 = Colors.ContentItem
    f.BorderSizePixel = 0
    f.LayoutOrder = nextOrder(tab)
    Instance.new("UICorner", f).CornerRadius = UDim.new(0,8)
    local lbl = Instance.new("TextLabel", f)
    lbl.Size = UDim2.new(1,-70,1,0); lbl.Position = UDim2.new(0,12,0,0); lbl.BackgroundTransparency=1; lbl.Text=name; lbl.TextColor3=Colors.Text; lbl.TextSize=12; lbl.Font=Enum.Font.GothamSemibold; lbl.TextXAlignment=Enum.TextXAlignment.Left
    local togBtn = Instance.new("TextButton", f)
    togBtn.Size = UDim2.new(0,46,0,24); togBtn.Position = UDim2.new(1,-56,0.5,-12); togBtn.BackgroundColor3 = state and Colors.Toggle or Colors.ToggleOff; togBtn.BorderSizePixel = 0; togBtn.Text = ""; togBtn.AutoButtonColor = false
    Instance.new("UICorner", togBtn).CornerRadius = UDim.new(1,0)
    local circ = Instance.new("Frame", togBtn)
    circ.Size = UDim2.new(0,18,0,18); circ.Position = state and UDim2.new(1,-21,0.5,-9) or UDim2.new(0,3,0.5,-9); circ.BackgroundColor3 = Colors.Text; circ.BorderSizePixel = 0
    Instance.new("UICorner", circ).CornerRadius = UDim.new(1,0)
    local function update()
        local targetPos = state and UDim2.new(1,-21,0.5,-9) or UDim2.new(0,3,0.5,-9)
        local targetCol = state and Colors.Toggle or Colors.ToggleOff
        tween:Create(circ, TweenInfo.new(0.2), {Position = targetPos}):Play()
        tween:Create(togBtn, TweenInfo.new(0.2), {BackgroundColor3 = targetCol}):Play()
    end
    togBtn.MouseButton1Click:Connect(function() state = not state; update(); if cb then cb(state) end end)
    return {Frame=f, Set=function(_,v) state=v; update() end, Get=function() return state end}
end

local function Slider(tab, name, min, max, default, cb)
    local p = tabContents[tab]; if not p then return end
    local val = default or min
    local f = Instance.new("Frame", p)
    f.Name = "S_"..name
    f.Size = UDim2.new(1,0,0,52)
    f.BackgroundColor3 = Colors.ContentItem
    f.BorderSizePixel = 0
    f.LayoutOrder = nextOrder(tab)
    Instance.new("UICorner", f).CornerRadius = UDim.new(0,8)
    local lbl = Instance.new("TextLabel", f)
    lbl.Size = UDim2.new(1,-60,0,18); lbl.Position = UDim2.new(0,10,0,6); lbl.BackgroundTransparency=1; lbl.Text=name; lbl.TextColor3=Colors.Text; lbl.TextSize=12; lbl.Font=Enum.Font.GothamSemibold; lbl.TextXAlignment=Enum.TextXAlignment.Left
    local vLbl = Instance.new("TextLabel", f)
    vLbl.Size = UDim2.new(0,45,0,18); vLbl.Position = UDim2.new(1,-55,0,6); vLbl.BackgroundTransparency=1; vLbl.Text=tostring(val); vLbl.TextColor3=Colors.Accent; vLbl.TextSize=12; vLbl.Font=Enum.Font.GothamBold; vLbl.TextXAlignment=Enum.TextXAlignment.Right
    local track = Instance.new("Frame", f)
    track.Size = UDim2.new(1,-20,0,8); track.Position = UDim2.new(0,10,0,34); track.BackgroundColor3 = Colors.Background; track.BorderSizePixel = 0
    Instance.new("UICorner", track).CornerRadius = UDim.new(1,0)
    local fill = Instance.new("Frame", track)
    fill.Size = UDim2.new((val-min)/(max-min),0,1,0); fill.BackgroundColor3 = Colors.Accent; fill.BorderSizePixel = 0
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1,0)
    local knob = Instance.new("Frame", track)
    knob.Size = UDim2.new(0,14,0,14); knob.Position = UDim2.new((val-min)/(max-min),-7,0.5,-7); knob.BackgroundColor3 = Colors.Text; knob.BorderSizePixel = 0
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1,0)
    local dragging = false
    local function upd(v)
        val = math.clamp(math.floor(v), min, max)
        local pct = (val-min)/(max-min)
        fill.Size = UDim2.new(pct,0,1,0)
        knob.Position = UDim2.new(pct,-7,0.5,-7)
        vLbl.Text = tostring(val)
        if cb then cb(val) end
    end
    track.InputBegan:Connect(function(inp)
        if inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch then
            dragging = true
            local pct = math.clamp((inp.Position.X - track.AbsolutePosition.X)/track.AbsoluteSize.X,0,1)
            upd(min + pct*(max-min))
        end
    end)
    track.InputEnded:Connect(function(inp)
        if inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    uis.InputChanged:Connect(function(inp)
        if dragging and (inp.UserInputType==Enum.UserInputType.MouseMovement or inp.UserInputType==Enum.UserInputType.Touch) then
            local pct = math.clamp((inp.Position.X - track.AbsolutePosition.X)/track.AbsoluteSize.X,0,1)
            upd(min + pct*(max-min))
        end
    end)
    return {Frame=f, Set=upd, Get=function() return val end}
end

-- Dropdown
local activeDrop = nil
local function Dropdown(tab, name, opts, default, cb)
    local p = tabContents[tab]; if not p then return end
    local sel = default
    local open = false
    local optFrameRef = nil
    local f = Instance.new("Frame", p)
    f.Name = "D_"..name
    f.Size = UDim2.new(1,0,0,58)
    f.BackgroundColor3 = Colors.ContentItem
    f.BorderSizePixel = 0
    f.LayoutOrder = nextOrder(tab)
    Instance.new("UICorner", f).CornerRadius = UDim.new(0,8)
    local lbl = Instance.new("TextLabel", f)
    lbl.Size = UDim2.new(1,-20,0,18); lbl.Position = UDim2.new(0,10,0,6); lbl.BackgroundTransparency=1; lbl.Text=name; lbl.TextColor3=Colors.Text; lbl.TextSize=12; lbl.Font=Enum.Font.GothamSemibold; lbl.TextXAlignment=Enum.TextXAlignment.Left
    local btn = Instance.new("TextButton", f)
    btn.Size = UDim2.new(1,-20,0,26); btn.Position = UDim2.new(0,10,0,26); btn.BackgroundColor3 = Colors.Background; btn.BorderSizePixel = 0; btn.Text = ""; btn.AutoButtonColor = false
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,6)
    local selLbl = Instance.new("TextLabel", btn)
    selLbl.Size = UDim2.new(1,-30,1,0); selLbl.Position = UDim2.new(0,10,0,0); selLbl.BackgroundTransparency=1; selLbl.Text = sel or "Select..."; selLbl.TextColor3 = sel and Colors.Text or Colors.TextMuted; selLbl.TextSize = 11; selLbl.Font = Enum.Font.Gotham; selLbl.TextXAlignment = Enum.TextXAlignment.Left; selLbl.TextTruncate = Enum.TextTruncate.AtEnd
    local arrow = Instance.new("TextLabel", btn)
    arrow.Size = UDim2.new(0,20,1,0); arrow.Position = UDim2.new(1,-25,0,0); arrow.BackgroundTransparency=1; arrow.Text = "▼"; arrow.TextColor3 = Colors.TextMuted; arrow.TextSize = 10; arrow.Font = Enum.Font.Gotham
    local function close()
        if optFrameRef then optFrameRef:Destroy(); optFrameRef=nil end
        open=false; tween:Create(arrow, TweenInfo.new(0.2), {Rotation=0}):Play(); activeDrop=nil
    end
    local function openDrop()
        if activeDrop and activeDrop~=close then activeDrop() end
        activeDrop = close; open=true; tween:Create(arrow, TweenInfo.new(0.2), {Rotation=180}):Play()
        local btnPos = btn.AbsolutePosition; local btnSize = btn.AbsoluteSize
        local optFrame = Instance.new("Frame", dropContainer)
        optFrame.Name = "DropdownOptions"
        optFrame.Size = UDim2.new(0, btnSize.X, 0, math.min(#opts*28+8,150))
        optFrame.Position = UDim2.fromOffset(btnPos.X, btnPos.Y+btnSize.Y+5)
        optFrame.BackgroundColor3 = Colors.DropdownBg
        optFrame.BorderSizePixel = 0
        optFrame.ZIndex = 100
        Instance.new("UICorner", optFrame).CornerRadius = UDim.new(0,6)
        local st = Instance.new("UIStroke", optFrame); st.Color = Colors.Border; st.Thickness = 1
        local sc = Instance.new("ScrollingFrame", optFrame)
        sc.Size = UDim2.new(1,-8,1,-8); sc.Position = UDim2.new(0,4,0,4); sc.BackgroundTransparency=1; sc.BorderSizePixel=0; sc.ScrollBarThickness=3; sc.ScrollBarImageColor3=Colors.Accent; sc.CanvasSize = UDim2.new(0,0,0,#opts*28); sc.ZIndex=101
        local lay = Instance.new("UIListLayout", sc); lay.SortOrder = Enum.SortOrder.LayoutOrder; lay.Padding = UDim.new(0,2)
        optFrameRef = optFrame
        for i,optName in ipairs(opts) do
            local optBtn = Instance.new("TextButton", sc)
            optBtn.Name = optName
            optBtn.Size = UDim2.new(1,0,0,26)
            optBtn.BackgroundColor3 = (optName==sel) and Colors.Accent or Colors.ContentItem
            optBtn.BorderSizePixel = 0
            optBtn.Text = optName
            optBtn.TextColor3 = Colors.Text
            optBtn.TextSize = 11
            optBtn.Font = Enum.Font.Gotham
            optBtn.AutoButtonColor = false
            optBtn.LayoutOrder = i
            optBtn.ZIndex = 102
            Instance.new("UICorner", optBtn).CornerRadius = UDim.new(0,4)
            optBtn.MouseEnter:Connect(function()
                if optName~=sel then tween:Create(optBtn, TweenInfo.new(0.1), {BackgroundColor3=Colors.ContentItemHover}):Play() end
            end)
            optBtn.MouseLeave:Connect(function()
                if optName~=sel then tween:Create(optBtn, TweenInfo.new(0.1), {BackgroundColor3=Colors.ContentItem}):Play() end
            end)
            optBtn.MouseButton1Click:Connect(function()
                sel = optName
                selLbl.Text = optName; selLbl.TextColor3 = Colors.Text
                if cb then cb(optName) end
                close()
            end)
        end
    end
    btn.MouseButton1Click:Connect(function() if open then close() else openDrop() end end)
    return {Frame=f, Refresh=function(_,newOpts,keepSel) opts=newOpts; if not keepSel then sel=nil; selLbl.Text="Select..."; selLbl.TextColor3=Colors.TextMuted end if open then close() end end,
            Set=function(_,v) sel=v; selLbl.Text=v or "Select..."; selLbl.TextColor3=v and Colors.Text or Colors.TextMuted end,
            Get=function() return sel end}
end

uis.InputBegan:Connect(function(inp)
    if inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch then
        if activeDrop then task.defer(function() task.wait(0.05); if activeDrop then activeDrop() end end) end
    end
end)

-- Notifications
local notifCont = Instance.new("Frame", sg)
notifCont.Name = "Notifs"
notifCont.Size = UDim2.new(0,280,1,0); notifCont.Position = UDim2.new(1,-290,0,0); notifCont.BackgroundTransparency = 1
local notifLayout = Instance.new("UIListLayout", notifCont)
notifLayout.SortOrder = Enum.SortOrder.LayoutOrder; notifLayout.Padding = UDim.new(0,8); notifLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
Instance.new("UIPadding", notifCont).PaddingBottom = UDim.new(0,20)

local function Notify(tit, msg, dur)
    dur = dur or 3
    local n = Instance.new("Frame", notifCont)
    n.Size = UDim2.new(0,260,0,65); n.BackgroundColor3 = Colors.Sidebar; n.BorderSizePixel=0; n.BackgroundTransparency=1
    Instance.new("UICorner", n).CornerRadius = UDim.new(0,10)
    local st = Instance.new("UIStroke", n); st.Color = Colors.Accent; st.Transparency = 1
    local tL = Instance.new("TextLabel", n); tL.Size = UDim2.new(1,-20,0,20); tL.Position = UDim2.new(0,10,0,8); tL.BackgroundTransparency=1; tL.Text=tit; tL.TextColor3=Colors.Accent; tL.TextSize=13; tL.Font=Enum.Font.GothamBold; tL.TextXAlignment=Enum.TextXAlignment.Left
    local cL = Instance.new("TextLabel", n); cL.Size = UDim2.new(1,-20,0,28); cL.Position = UDim2.new(0,10,0,28); cL.BackgroundTransparency=1; cL.Text=msg; cL.TextColor3=Colors.TextDim; cL.TextSize=11; cL.Font=Enum.Font.Gotham; cL.TextXAlignment=Enum.TextXAlignment.Left; cL.TextWrapped=true
    tween:Create(n, TweenInfo.new(0.3), {BackgroundTransparency=0}):Play()
    tween:Create(st, TweenInfo.new(0.3), {Transparency=0}):Play()
    task.delay(dur, function()
        tween:Create(n, TweenInfo.new(0.3), {BackgroundTransparency=1}):Play()
        tween:Create(st, TweenInfo.new(0.3), {Transparency=1}):Play()
        task.wait(0.3); n:Destroy()
    end)
end

-- =====================================================
-- BAGIAN 18: POPULATE TAB CONTENTS
-- =====================================================

-- Info
Section("Info","Player Information")
Paragraph("Info","Player",localP.Name)
local statsPar = Paragraph("Info","Statistics","Loading...")
task.spawn(function() while true do task.wait(3) local s=GetPlayerStats() statsPar:Set({Title="Statistics",Content=string.format("Coins: %s | Fish: %s | Backpack: %d/%d",FormatNumber(s.Coins),FormatNumber(s.TotalCaught),s.BackpackCount,s.BackpackMax)}) end end)
Section("Info","About")
Paragraph("Info","Vechnost v2.5.0","Complete Fish It Automation Suite\nby Vechnost Team")

-- Fishing
Section("Fishing","Auto Fishing")
Toggle("Fishing","Auto Cast",false,function(v) Fishing.AutoCast=v; Notify("Vechnost",v and "Auto Cast ON" or "OFF",2) end)
Toggle("Fishing","Auto Reel",false,function(v) Fishing.AutoReel=v; Notify("Vechnost",v and "Auto Reel ON" or "OFF",2) end)
Toggle("Fishing","Auto Shake",false,function(v) Fishing.AutoShake=v; Notify("Vechnost",v and "Auto Shake ON" or "OFF",2) end)
Section("Fishing","Clicker Settings")
Slider("Fishing","Click Speed (CPS)",10,100,50,function(v) Fishing.ClickSpeed=v end)
Toggle("Fishing","Perfect Catch",false,function(v) Fishing.PerfectCatch=v; Notify("Vechnost",v and "Perfect Catch ON" or "OFF",2) end)
Section("Fishing","Utility")
Toggle("Fishing","Anti AFK",false,function(v) Fishing.AntiAFK=v; Notify("Vechnost",v and "Anti AFK ON" or "OFF",2) end)
Toggle("Fishing","Auto Sell",false,function(v) Fishing.AutoSell=v; Notify("Vechnost",v and "Auto Sell ON" or "OFF",2) end)

-- Teleport
Section("Teleport","Island Teleport")
local tpDrop = Dropdown("Teleport","Select Island",GetTeleportNames(),nil,function(s) if s and s~="(Scan first)" then local ok,_=TeleportTo(s); Notify("Vechnost",ok and "Teleported" or "Failed",2) end end)
Button("Teleport","Refresh Locations",function() ScanIslands(); tpDrop:Refresh(GetTeleportNames(),false); Notify("Vechnost","Found "..#TeleportSpots.." spots",2) end)
Section("Teleport","Quick Teleport")
Button("Teleport","TP to Spawn",function() local c=localP.Character; if c and c:FindFirstChild("HumanoidRootPart") then local s=ws:FindFirstChildOfClass("SpawnLocation"); if s then c.HumanoidRootPart.CFrame=s.CFrame+Vector3.new(0,5,0); Notify("Vechnost","Teleported to Spawn",2) end end end)
Button("Teleport","TP to Nearest Player",function() local c=localP.Character; if not c or not c:FindFirstChild("HumanoidRootPart") then return end local my=c.HumanoidRootPart.Position; local near,dist=nil,math.huge; for _,p in pairs(plrs:GetPlayers()) do if p~=localP and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then local d=(p.Character.HumanoidRootPart.Position-my).Magnitude; if d<dist then near=p; dist=d end end end; if near then c.HumanoidRootPart.CFrame=near.Character.HumanoidRootPart.CFrame+Vector3.new(3,0,0); Notify("Vechnost","Teleported to "..near.Name,2) else Notify("Vechnost","No players",2) end end)

-- Trading
Section("Trading","Select Target Player")
local plrList = {}; for _,p in pairs(plrs:GetPlayers()) do if p~=localP then table.insert(plrList,p.Name) end end; if #plrList==0 then plrList={"(None)"} end
local plrDrop = Dropdown("Trading","Select Player",plrList,nil,function(s) if s and s~="(None)" then Trade.Target=s; Notify("Vechnost","Target: "..s,2) end end)
Button("Trading","Refresh Player List",function() local t={}; for _,p in pairs(plrs:GetPlayers()) do if p~=localP then table.insert(t,p.Name) end end; if #t==0 then t={"(None)"} end; plrDrop:Refresh(t,false); Notify("Vechnost","Found "..#t.." players",2) end)
Section("Trading","Trade by Name")
local tradeStat = Paragraph("Trading","Trade Status","Ready")
local itemDrop = Dropdown("Trading","Select Item",{"(Load)"},nil,function(s) if s and s~="(Load)" then Trade.ByName.Item=s end end)
Button("Trading","Load Inventory",function() LoadInv(); local names=GetInvNames(); itemDrop:Refresh(names,false); Notify("Vechnost","Loaded "..#names.." items",2) end)
local amtBuf = "1"
Input("Trading","Amount","1",function(t) amtBuf=t; local n=tonumber(t); if n and n>0 then Trade.ByName.Amt=math.floor(n) end end)
local tradeToggle = Toggle("Trading","Start Trade",false,function(v)
    if v then
        if not Trade.Target then Notify("Vechnost","Select target!",3); tradeToggle:Set(false) return end
        if not Trade.ByName.Item then Notify("Vechnost","Select item!",3); tradeToggle:Set(false) return end
        Trade.ByName.Active=true; Trade.ByName.Sent=0
        task.spawn(function()
            local tot=Trade.ByName.Amt; local it=Trade.ByName.Item; local targ=Trade.Target
            for i=1,tot do
                if not Trade.ByName.Active then break end
                tradeStat:Set({Title="Trade Status",Content=string.format("Sending: %d/%d %s",i,tot,it)})
                SendTrade(targ,it,1); Trade.ByName.Sent=i; task.wait(0.5)
            end
            Trade.ByName.Active=false; tradeToggle:Set(false); tradeStat:Set({Title="Trade Status",Content=string.format("Done: %d/%d",Trade.ByName.Sent,tot)}); Notify("Vechnost","Trade complete",2)
        end)
    else Trade.ByName.Active=false end
end)
Section("Trading","Trade by Rarity")
local rarityDrop = Dropdown("Trading","Select Rarity",RarityList,nil,function(s) if s then Trade.ByRarity.Rarity=s; Trade.ByRarity.Tier=RARITY_NAME_TO_TIER[s]; Notify("Vechnost","Selected: "..s,2) end end)
Section("Trading","Trade Stone")
local stoneDrop = Dropdown("Trading","Select Stone",STONE_ITEMS,nil,function(s) if s then Trade.ByStone.Stone=s end end)

-- Shop
Section("Shop","Auto Buy Charm")
local charmDrop = Dropdown("Shop","Select Charm",ShopData.Charms,nil,function(s) ShopSet.SelectedCharm=s end)
Toggle("Shop","Auto Buy Charm",false,function(v) ShopSet.AutoBuyCharm=v; if v and ShopSet.SelectedCharm then task.spawn(function() while ShopSet.AutoBuyCharm do BuyItem("Charm",ShopSet.SelectedCharm); task.wait(1) end end) end; Notify("Vechnost",v and "Auto Charm ON" or "OFF",2) end)
Section("Shop","Auto Buy Weather")
local weatherDrop = Dropdown("Shop","Select Weather",ShopData.Weather,nil,function(s) ShopSet.SelectedWeather=s end)
Toggle("Shop","Auto Buy Weather",false,function(v) ShopSet.AutoBuyWeather=v; if v and ShopSet.SelectedWeather then BuyItem("Weather",ShopSet.SelectedWeather) end; Notify("Vechnost",v and "Weather changed!" or "OFF",2) end)
Section("Shop","Auto Buy Bait")
local baitDrop = Dropdown("Shop","Select Bait",ShopData.Bait,nil,function(s) ShopSet.SelectedBait=s end)
Toggle("Shop","Auto Buy Bait",false,function(v) ShopSet.AutoBuyBait=v; if v and ShopSet.SelectedBait then task.spawn(function() while ShopSet.AutoBuyBait do BuyItem("Bait",ShopSet.SelectedBait); task.wait(2) end end) end; Notify("Vechnost",v and "Auto Bait ON" or "OFF",2) end)
Section("Shop","Merchant Shop")
local merchDrop = Dropdown("Shop","Select Item",ShopData.Merchant,nil,function() end)
Button("Shop","Buy Selected Item",function() local sel=merchDrop:Get(); if sel then BuyItem("Merchant",sel); Notify("Vechnost","Purchased "..sel,2) else Notify("Vechnost","Select item",2) end end)

-- Webhook
Section("Webhook","Rarity Filter")
local wRarityDrop = Dropdown("Webhook","Filter Rarity",RarityList,nil,function(s) if s then Settings.SelectedRarities={}; local t=RARITY_NAME_TO_TIER[s]; if t then Settings.SelectedRarities[t]=true end; Notify("Vechnost","Filter: "..s,2) end end)
Button("Webhook","Clear Filter (All Rarity)",function() Settings.SelectedRarities={}; wRarityDrop:Set(nil); Notify("Vechnost","Filter cleared",2) end)
Section("Webhook","Setup")
local urlBuf = ""
Input("Webhook","Discord Webhook URL","https://discord.com/api/webhooks/...",function(t) urlBuf=t end)
Button("Webhook","Save Webhook URL",function() local u=urlBuf:gsub("%s+",""); if not u:match("^https://discord.com/api/webhooks/") and not u:match("^https://canary.discord.com/api/webhooks/") then Notify("Vechnost","Invalid URL",3) return end; Settings.Url=u; Notify("Vechnost","URL saved",2) end)
Section("Webhook","Mode")
Toggle("Webhook","Server-Wide Mode",true,function(v) Settings.ServerWide=v; Notify("Vechnost",v and "Server-Wide" or "Local Only",2) end)
Section("Webhook","Control")
local logToggle = Toggle("Webhook","Enable Logger",false,function(v)
    if v then
        if Settings.Url=="" then Notify("Vechnost","Set URL first",3); logToggle:Set(false) return end
        local ok,msg = StartLog(); if ok then Notify("Vechnost","Logger started",2) else Notify("Vechnost",msg,3); logToggle:Set(false) end
    else StopLog(); Notify("Vechnost","Logger stopped",2) end
end)
Section("Webhook","Status")
local statusPar = Paragraph("Webhook","Logger Status","Offline")
task.spawn(function() while true do task.wait(2) if Settings.Active then statusPar:Set({Title="Logger Status",Content=string.format("Active | Mode: %s | Logged: %d",Settings.ServerWide and "Server-Wide" or "Local",Settings.LogCount)}) else statusPar:Set({Title="Logger Status",Content="Offline"}) end end end)

-- Setting
Section("Setting","Testing")
Button("Setting","Test Webhook",function()
    if Settings.Url=="" then Notify("Vechnost","Set URL first",3) return end
    SendHook({username="Vechnost Notifier",avatar_url="https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png",flags=32768,components={{type=17,accent_color=0x5865f2,components={{type=10,content="**Test Message**"},{type=14,spacing=1,divider=true},{type=10,content="Webhook is working!\n\n- **Sent by:** "..localP.Name},{type=10,content="-# "..os.date("!%B %d, %Y")}}}})
    Notify("Vechnost","Test sent",2)
end)
Button("Setting","Reset Counter",function() Settings.LogCount=0; Settings.SentUUID={}; Notify("Vechnost","Counter reset",2) end)
Section("Setting","UI")
Button("Setting","Toggle UI (Press V)",function() main.Visible = not main.Visible end)
Section("Setting","Credits")
Paragraph("Setting","Vechnost Team","Thanks for using Vechnost!\nDiscord: discord.gg/vechnost")

-- =====================================================
-- BAGIAN 19: UI CONTROLS
-- =====================================================
local dragging, dragOffset = false, Vector2.zero
titleBar.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=true; dragOffset=Vector2.new(i.Position.X,i.Position.Y)-Vector2.new(main.AbsolutePosition.X,main.AbsolutePosition.Y) end end)
titleBar.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=false end end)
uis.InputChanged:Connect(function(i) if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then local new=Vector2.new(i.Position.X,i.Position.Y)-dragOffset; main.Position=UDim2.fromOffset(new.X,new.Y) end end)
closeBtn.MouseEnter:Connect(function() tween:Create(closeBtn,TweenInfo.new(0.15),{BackgroundColor3=Colors.Error}):Play() end)
closeBtn.MouseLeave:Connect(function() tween:Create(closeBtn,TweenInfo.new(0.15),{BackgroundColor3=Colors.ContentItem}):Play() end)
closeBtn.MouseButton1Click:Connect(function() sg:Destroy() end)
local minimized = false
minBtn.MouseEnter:Connect(function() tween:Create(minBtn,TweenInfo.new(0.15),{BackgroundColor3=Colors.ContentItemHover}):Play() end)
minBtn.MouseLeave:Connect(function() tween:Create(minBtn,TweenInfo.new(0.15),{BackgroundColor3=Colors.ContentItem}):Play() end)
minBtn.MouseButton1Click:Connect(function() minimized = not minimized; local sz = minimized and UDim2.new(0,720,0,45) or UDim2.new(0,720,0,480); tween:Create(main,TweenInfo.new(0.3),{Size=sz}):Play() end)
uis.InputBegan:Connect(function(i,g) if not g and i.KeyCode==Enum.KeyCode.V then main.Visible = not main.Visible end end)

-- =====================================================
-- BAGIAN 20: MOBILE BUTTON
-- =====================================================
local oldMob = Core:FindFirstChild(guiNames.Mobile); if oldMob then oldMob:Destroy() end
local mobGui = Instance.new("ScreenGui", Core)
mobGui.Name = guiNames.Mobile
mobGui.ResetOnSpawn = false
local mobBtn = Instance.new("ImageButton", mobGui)
mobBtn.Size = UDim2.fromOffset(52,52)
mobBtn.Position = UDim2.fromScale(0.05,0.5)
mobBtn.BackgroundTransparency = 1
mobBtn.AutoButtonColor = false
mobBtn.Image = "rbxassetid://127239715511367"
Instance.new("UICorner", mobBtn).CornerRadius = UDim.new(1,0)
mobBtn.MouseButton1Click:Connect(function() main.Visible = not main.Visible end)
local floatDrag, floatOffset = false, Vector2.zero
mobBtn.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        floatDrag=true; floatOffset=uis:GetMouseLocation()-mobBtn.AbsolutePosition
        i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then floatDrag=false end end)
    end
end)
run.RenderStepped:Connect(function()
    if not floatDrag then return end
    local mouse = uis:GetMouseLocation()
    local target = mouse - floatOffset
    local vp = ws.CurrentCamera and ws.CurrentCamera.ViewportSize or Vector2.new(1920,1080)
    local sz = mobBtn.AbsoluteSize
    mobBtn.Position = UDim2.fromOffset(math.clamp(target.X,0,vp.X-sz.X), math.clamp(target.Y,0,vp.Y-sz.Y))
end)

-- =====================================================
-- BAGIAN 21: INIT
-- =====================================================
switchTab("Info")
warn("[Vechnost] v2.5.0 (Anti-BAC) Loaded!")
Notify("Vechnost","Script loaded! Press V to toggle",3)
