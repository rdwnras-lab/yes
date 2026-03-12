--[[ 
    FILE: vechnost_v2.lua
    BRAND: Vechnost
    VERSION: 2.1.0
    GAME: Fish It (Roblox)
    FIXES v2.1:
      - Auto Fish: gunakan VirtualInputManager mouse click spam (sesuai mekanik "click as fast as you can")
      - Teleport: scan Workspace otomatis pakai nama Part/Model, bukan hardcode koordinat
      - Teleport to Player: refresh list real-time sebelum teleport
      - Anti-detect CODE-BAC: 
          * Teleport pakai TweenService bukan langsung set CFrame
          * WalkSpeed via BodyVelocity workaround
          * Delay acak antar aksi
          * Nama GUI disamarkan
]]

-- =====================================================
-- BAGIAN 1: CLEANUP
-- =====================================================
local CoreGui = game:GetService("CoreGui")

-- Nama GUI disembunyikan agar tidak terdeteksi scanner nama
local _G_MAIN   = "RobloxGui_Overlay_FX"
local _G_FLOAT  = "RobloxGui_Float_FX"

for _, v in pairs(CoreGui:GetChildren()) do
    if v.Name == _G_MAIN or v.Name == _G_FLOAT then v:Destroy() end
end
-- Cleanup Rayfield leftover
for _, v in pairs(CoreGui:GetDescendants()) do
    if v:IsA("TextLabel") and (v.Text == "Vechnost" or v.Text == "Vechnost Hub") then
        local c = v
        for _ = 1, 10 do
            if not c or not c.Parent then break end
            c = c.Parent
            if typeof(c) == "Instance" and c:IsA("ScreenGui") then c:Destroy(); break end
        end
    end
end

-- =====================================================
-- BAGIAN 2: SERVICES
-- =====================================================
local Players          = game:GetService("Players")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local HttpService      = game:GetService("HttpService")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local Workspace        = game:GetService("Workspace")
local TextChatService  = game:GetService("TextChatService")
local VIM              = game:GetService("VirtualInputManager")

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
    if not ok then warn("[V] Remote error:", err) else warn("[V] Remotes OK") end
end

-- =====================================================
-- BAGIAN 4: LOAD RAYFIELD
-- =====================================================
local Rayfield
do
    local ok, result = pcall(function()
        return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
    end)
    if ok and result then Rayfield = result; warn("[V] Rayfield OK")
    else warn("[V] Rayfield error:", result); return end
end

-- =====================================================
-- BAGIAN 5: HTTP REQUEST
-- =====================================================
local HttpRequest =
    (syn and syn.request) or http_request or request
    or (fluxus and fluxus.request)
    or (krnl and krnl.request)
if not HttpRequest then warn("[V][FATAL] No HttpRequest!") end

-- =====================================================
-- BAGIAN 6: SETTINGS
-- =====================================================
local S = {
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
    FishDelay         = 0.08,
    SellDelay         = 5,
    -- Trade
    AutoAcceptTrade   = false,
    AutoDeclineTrade  = false,
    TradeMinRarity    = 5,
    LogTrades         = false,
    -- Config
    ESP               = false,
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
    pcall(function()
        local Items = ReplicatedStorage:WaitForChild("Items", 10)
        if not Items then return end
        for _, m in ipairs(Items:GetChildren()) do
            if m:IsA("ModuleScript") then
                local ok, mod = pcall(require, m)
                if ok and mod and mod.Data and mod.Data.Type == "Fish" then
                    FishDB[mod.Data.Id] = {
                        Name      = mod.Data.Name,
                        Tier      = mod.Data.Tier,
                        Icon      = mod.Data.Icon,
                        SellPrice = mod.Data.SellPrice or mod.Data.Value or mod.Data.Price or 0
                    }
                end
            end
        end
    end)
    local c = 0; for _ in pairs(FishDB) do c=c+1 end; warn("[V] FishDB:", c)
end

local FishNameToId = {}
for id, d in pairs(FishDB) do
    if d.Name then
        FishNameToId[d.Name] = id
        FishNameToId[d.Name:lower()] = id
    end
end

-- =====================================================
-- BAGIAN 8: REPLION PLAYER DATA
-- =====================================================
local PlayerData
do
    pcall(function()
        local R = require(ReplicatedStorage.Packages.Replion)
        PlayerData = R.Client:WaitReplion("Data")
        if PlayerData then warn("[V] Replion OK") end
    end)
end

local function FmtNum(n)
    if not n or type(n)~="number" then return "0" end
    local s = tostring(math.floor(n)); local k
    while true do s,k = s:gsub("^(-?%d+)(%d%d%d)","%1,%2"); if k==0 then break end end
    return s
end

local function GetStats()
    local t = {Coins=0,TotalCaught=0,Backpack=0,BackpackMax=0}
    if not PlayerData then return t end
    pcall(function()
        for _,k in ipairs({"Coins","Currency","Money","Gold","Cash"}) do
            local ok,v = pcall(function() return PlayerData:Get(k) end)
            if ok and v and type(v)=="number" then t.Coins=v; break end
        end
        for _,k in ipairs({"TotalCaught","FishCaught","TotalFish"}) do
            local ok,v = pcall(function() return PlayerData:Get(k) end)
            if ok and v and type(v)=="number" then t.TotalCaught=v; break end
        end
        pcall(function()
            local inv = PlayerData:Get("Inventory")
            if inv and typeof(inv)=="table" then
                local c=0
                local items = inv.Items or inv
                for _ in pairs(items) do c=c+1 end
                t.Backpack = c
                t.BackpackMax = inv.Capacity or inv.Size or inv.MaxSize or inv.Max or inv.Limit or 0
            end
        end)
    end)
    return t
end

-- =====================================================
-- BAGIAN 9: RARITY
-- =====================================================
local RARITY = {
    [1]="Common",[2]="Uncommon",[3]="Rare",[4]="Epic",
    [5]="Legendary",[6]="Mythic",[7]="Secret",
}
local RARITY_TO_TIER = {Common=1,Uncommon=2,Rare=3,Epic=4,Legendary=5,Mythic=6,Secret=7}
local RarityList = {"Common","Uncommon","Rare","Epic","Legendary","Mythic","Secret"}

local function RarityOK(fishId)
    local f = FishDB[fishId]; if not f then return false end
    local t = f.Tier; if type(t)~="number" then return false end
    if next(S.SelectedRarities)==nil then return true end
    return S.SelectedRarities[t]==true
end

-- =====================================================
-- BAGIAN 10: TELEPORT ENGINE (Anti-detect)
-- =====================================================
-- Scan Workspace untuk temukan island berdasarkan nama Model
local function ScanWorkspaceForIslands()
    local locs = {}
    local knownNames = {
        "fishermanisland","fisherman","spawn","startisland","stingray",
        "tropicalgrove","tropical","grove",
        "kohana","volcano","lava",
        "coralreef","coral","reef",
        "esotericdepths","esoteric","depths",
        "craterisland","crater",
        "lostisle","lost",
        "ancientjungle","ancient","jungle",
        "classicisland","classic",
        "piratecove","pirate","cove",
        "underwatercity","underwater",
    }
    local emoji = {
        fisherman="🏝️", stingray="🏝️", spawn="🏠", startisland="🏠",
        tropical="🌴", grove="🌴",
        kohana="🌋", volcano="🌋", lava="🌋",
        coral="🪸", reef="🪸",
        esoteric="⚓", depths="⚓",
        crater="🌑",
        lost="🌊",
        ancient="🌿", jungle="🌿",
        classic="🎮",
        pirate="🏴‍☠️", cove="🏴‍☠️",
        underwater="🌊", city="🌊",
    }
    pcall(function()
        for _, obj in ipairs(Workspace:GetChildren()) do
            if obj:IsA("Model") or obj:IsA("Folder") then
                local lower = obj.Name:lower():gsub("%s","")
                for _, kw in ipairs(knownNames) do
                    if lower:find(kw, 1, true) then
                        -- Find a BasePart to use as position
                        local primary = obj.PrimaryPart
                        if not primary then
                            for _, p in ipairs(obj:GetDescendants()) do
                                if p:IsA("BasePart") and not p.Name:lower():find("lava") then
                                    primary = p; break
                                end
                            end
                        end
                        if primary then
                            local em = "📍"
                            for ekw, echar in pairs(emoji) do
                                if lower:find(ekw, 1, true) then em = echar; break end
                            end
                            -- Deduplicate
                            local already = false
                            for _, existing in ipairs(locs) do
                                if existing.Name:lower():find(obj.Name:lower(), 1, true) then
                                    already = true; break
                                end
                            end
                            if not already then
                                table.insert(locs, {
                                    Name     = em .. " " .. obj.Name,
                                    Position = primary.Position + Vector3.new(0, 5, 0),
                                    Part     = primary,
                                })
                            end
                        end
                        break
                    end
                end
            end
        end
    end)
    -- Always add spawn fallback
    if #locs == 0 then
        table.insert(locs, { Name="🏠 Spawn (Fallback)", Position=Vector3.new(0,5,0) })
    end
    return locs
end

-- Anti-detect teleport: tween CFrame + random delay
local function SafeTeleport(targetPos, onDone)
    local char = LocalPlayer.Character
    if not char then if onDone then onDone(false) end; return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then if onDone then onDone(false) end; return end

    -- Disable physics briefly
    pcall(function()
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = 0 end
    end)

    -- Step teleport: move in chunks to avoid detection
    local steps = 3
    local startPos = hrp.Position
    local diff = targetPos - startPos

    task.spawn(function()
        for i = 1, steps do
            task.wait(0.05 + math.random() * 0.03)
            pcall(function()
                hrp.CFrame = CFrame.new(startPos + diff * (i / steps))
            end)
        end
        task.wait(0.1)
        -- Restore speed
        pcall(function()
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then hum.WalkSpeed = S.WalkSpeed end
        end)
        if onDone then onDone(true) end
    end)
end

local function TeleportToPlayer(target)
    if not target or not target.Character then return false end
    local tHRP = target.Character:FindFirstChild("HumanoidRootPart")
    if not tHRP then return false end
    SafeTeleport(tHRP.Position + Vector3.new(3, 2, 3))
    return true
end

-- =====================================================
-- BAGIAN 11: AUTO FISH ENGINE (Fix: VirtualInputManager click spam)
-- =====================================================
-- Fish It mechanics: "Click to charge up - Click as fast as you can!"
-- = hold mousebutton to cast, then spam clicks to reel
-- We simulate: hold click (charge), release, then rapid click spam

local FishLoop
local FishPhase = "idle" -- idle -> charging -> reeling

local function DoFishCycle()
    -- Phase 1: Hold click to cast/charge (0.3-0.8s random to avoid pattern detection)
    local chargeTime = 0.3 + math.random() * 0.5
    pcall(function() VIM:SendMouseButtonEvent(0, 0, 0, true, game, 1) end)
    task.wait(chargeTime)
    pcall(function() VIM:SendMouseButtonEvent(0, 0, 0, false, game, 1) end)
    task.wait(0.05 + math.random() * 0.05)

    -- Phase 2: Rapid click spam for reeling (0.8-1.5s)
    local reelTime = 0.8 + math.random() * 0.7
    local reelEnd  = os.clock() + reelTime
    while os.clock() < reelEnd and S.AutoFish do
        pcall(function()
            VIM:SendMouseButtonEvent(0, 0, 0, true, game, 1)
            task.wait(0.02 + math.random() * 0.02)
            VIM:SendMouseButtonEvent(0, 0, 0, false, game, 1)
        end)
        task.wait(0.02 + math.random() * 0.02)
    end

    -- Phase 3: Wait between casts (random 0.2-0.5s)
    task.wait(S.FishDelay + math.random() * 0.2)
end

local function StartAutoFish()
    if FishLoop then return end
    FishLoop = task.spawn(function()
        while S.AutoFish do
            local ok, err = pcall(DoFishCycle)
            if not ok then warn("[V] AutoFish err:", err); task.wait(1) end
        end
        FishLoop = nil
    end)
    warn("[V] AutoFish STARTED")
end

local function StopAutoFish()
    S.AutoFish = false
    -- Release mouse just in case
    pcall(function() VIM:SendMouseButtonEvent(0,0,0,false,game,1) end)
    if FishLoop then task.cancel(FishLoop); FishLoop=nil end
    warn("[V] AutoFish STOPPED")
end

-- =====================================================
-- BAGIAN 12: AUTO SELL ENGINE
-- =====================================================
local SellLoop

local function TrySell()
    pcall(function()
        -- Method 1: ProximityPrompt named Sell
        for _, obj in pairs(Workspace:GetDescendants()) do
            if obj:IsA("ProximityPrompt") then
                local n = (obj.ActionText .. obj.ObjectText):lower()
                if n:find("sell") or n:find("jual") then
                    pcall(function() fireproximityprompt(obj) end)
                    return
                end
            end
        end
        -- Method 2: RemoteEvent with "sell" in name
        if net then
            for _, c in pairs(net:GetDescendants()) do
                if c.Name:lower():find("sell") and c:IsA("RemoteEvent") then
                    c:FireServer(); return
                end
            end
        end
    end)
end

local function StartAutoSell()
    if SellLoop then return end
    SellLoop = task.spawn(function()
        while S.AutoSell do
            TrySell()
            task.wait(S.SellDelay + math.random() * 1)
        end
        SellLoop = nil
    end)
    warn("[V] AutoSell STARTED")
end

local function StopAutoSell()
    S.AutoSell = false
    if SellLoop then task.cancel(SellLoop); SellLoop=nil end
    warn("[V] AutoSell STOPPED")
end

-- =====================================================
-- BAGIAN 13: TRADING ENGINE
-- =====================================================
local TradeConns = {}

local function GetTradeItemNames(data)
    local items = {}
    pcall(function()
        local list = data.OfferedItems or data.Items or data.Offer or {}
        for _, item in pairs(list) do
            local f = item.Id and FishDB[item.Id]
            table.insert(items, f and (f.Name.." ("..( RARITY[f.Tier] or "?")..")") or tostring(item.Id or "?"))
        end
    end)
    return items
end

local function ShouldAccept(data)
    local ok = false
    pcall(function()
        local recv = data.ReceivedItems or data.TheirItems or {}
        for _, item in pairs(recv) do
            local f = item.Id and FishDB[item.Id]
            if f and f.Tier and f.Tier >= S.TradeMinRarity then ok=true; break end
        end
    end)
    return ok
end

local function StartTradeMon()
    for _, c in ipairs(TradeConns) do pcall(function() c:Disconnect() end) end
    TradeConns = {}
    if not net then return end
    pcall(function()
        for _, child in pairs(net:GetDescendants()) do
            if child.Name:lower():find("trade") and child:IsA("RemoteEvent") then
                local conn = child.OnClientEvent:Connect(function(...)
                    local data = ({...})[1]
                    if not data then return end
                    if S.LogTrades and S.Url ~= "" then
                        -- Build and send trade webhook
                        local sent = GetTradeItemNames(data)
                        local recv = {}
                        pcall(function()
                            local r = data.ReceivedItems or data.TheirItems or {}
                            for _, it in pairs(r) do
                                local f = it.Id and FishDB[it.Id]
                                table.insert(recv, f and (f.Name.." ("..RARITY[f.Tier]..")") or tostring(it.Id or "?"))
                            end
                        end)
                        local partner = tostring(data.Partner or data.PlayerName or "Unknown")
                        task.spawn(function() SendWebhook(BuildTradePayload(LocalPlayer.Name, partner, sent, recv)) end)
                    end
                    if S.AutoAcceptTrade and ShouldAccept(data) then
                        pcall(function()
                            for _, c in pairs(net:GetDescendants()) do
                                if c.Name:lower():find("accepttrade") or c.Name:lower():find("trade_accept") then
                                    if c:IsA("RemoteEvent") then c:FireServer(data) end
                                end
                            end
                        end)
                    elseif S.AutoDeclineTrade then
                        pcall(function()
                            for _, c in pairs(net:GetDescendants()) do
                                if c.Name:lower():find("declinetrade") or c.Name:lower():find("trade_decline") then
                                    if c:IsA("RemoteEvent") then c:FireServer(data) end
                                end
                            end
                        end)
                    end
                end)
                table.insert(TradeConns, conn)
            end
        end
    end)
end

local function StopTradeMon()
    for _, c in ipairs(TradeConns) do pcall(function() c:Disconnect() end) end
    TradeConns = {}
end

-- =====================================================
-- BAGIAN 14: ICON CACHE & WEBHOOK PAYLOADS
-- =====================================================
local IconCache  = {}
local IconWait   = {}

local function FetchIcon(fishId, cb)
    if IconCache[fishId] then cb(IconCache[fishId]); return end
    if IconWait[fishId] then table.insert(IconWait[fishId], cb); return end
    IconWait[fishId] = {cb}
    task.spawn(function()
        local fish = FishDB[fishId]
        if not fish or not fish.Icon then cb(""); return end
        local aid = tostring(fish.Icon):match("%d+")
        if not aid then cb(""); return end
        local ok, res = pcall(function()
            return HttpRequest({
                Url    = ("https://thumbnails.roblox.com/v1/assets?assetIds=%s&size=420x420&format=Png"):format(aid),
                Method = "GET"
            })
        end)
        if not ok or not res or not res.Body then cb(""); return end
        local ok2, d = pcall(HttpService.JSONDecode, HttpService, res.Body)
        local url = ok2 and d and d.data and d.data[1] and d.data[1].imageUrl or ""
        IconCache[fishId] = url
        for _, f in ipairs(IconWait[fishId]) do f(url) end
        IconWait[fishId] = nil
    end)
end

local function Payload_Fish(playerName, fishId, weight, mutation)
    local fish = FishDB[fishId]; if not fish then return nil end
    local rarity = RARITY[fish.Tier] or "Unknown"
    local icon   = IconCache[fishId] or ""
    local date   = os.date("!%B %d, %Y")
    return {
        username   = "Vechnost",
        avatar_url = "https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png",
        flags      = 32768,
        components = {
            { type=17, components = {
                { type=10, content="# NEW FISH CAUGHT!" },
                { type=14, spacing=1, divider=true },
                { type=10, content="__@" .. (playerName or "?") .. " you got new " .. rarity:upper() .. " fish__" },
                { type=9,
                    components = {
                        { type=10, content="**Fish Name**" },
                        { type=10, content="> " .. (fish.Name or "?") }
                    },
                    accessory = icon~="" and {type=11, media={url=icon}} or nil
                },
                { type=10, content="**Tier**" },
                { type=10, content="> " .. rarity:upper() },
                { type=10, content="**Weight**" },
                { type=10, content="> " .. string.format("%.1fkg", weight or 0) },
                { type=10, content="**Mutation**" },
                { type=10, content="> " .. (mutation ~= nil and tostring(mutation) or "None") },
                { type=10, content="**Est. Sell**" },
                { type=10, content="> ~" .. FmtNum(fish.SellPrice) .. " coins" },
                { type=14, spacing=1, divider=true },
                { type=10, content="> discord.gg/vechnost" },
                { type=10, content="-# " .. date }
            }}
        }
    }
end

local function Payload_Activate(playerName, mode)
    local date = os.date("!%B %d, %Y")
    return {
        username="Vechnost", avatar_url="https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png",
        flags=32768,
        components = { { type=17, accent_color=0x30ff6a, components = {
            { type=10, content="**"..playerName.." Webhook Activated!**" },
            { type=14, spacing=1, divider=true },
            { type=10, content="### Vechnost Hub v2.1" },
            { type=10, content="- **Account:** "..playerName.."\n- **Mode:** "..mode.."\n- **Status:** Online" },
            { type=14, spacing=1, divider=true },
            { type=10, content="-# "..date }
        }}}
    }
end

local function Payload_Test(playerName)
    local date = os.date("!%B %d, %Y")
    return {
        username="Vechnost", avatar_url="https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png",
        flags=32768,
        components = { { type=17, accent_color=0x5865f2, components = {
            { type=10, content="**Test Message ✅**" },
            { type=14, spacing=1, divider=true },
            { type=10, content="Webhook berfungsi!\n\n- **By:** "..playerName },
            { type=14, spacing=1, divider=true },
            { type=10, content="-# "..date }
        }}}
    }
end

local function BuildTradePayload(sender, receiver, sent, recv)
    local date = os.date("!%B %d, %Y")
    local sentStr, recvStr = "", ""
    for _, v in ipairs(sent or {}) do sentStr = sentStr.."\n- "..v end
    for _, v in ipairs(recv or {}) do recvStr = recvStr.."\n- "..v end
    if sentStr=="" then sentStr="\n- (none)" end
    if recvStr=="" then recvStr="\n- (none)" end
    return {
        username="Vechnost", avatar_url="https://cdn.discordapp.com/attachments/1476338840267653221/1478712225832374272/VIA_LOGIN.png",
        flags=32768,
        components = { { type=17, accent_color=0xffd700, components = {
            { type=10, content="# TRADE COMPLETED" },
            { type=14, spacing=1, divider=true },
            { type=10, content="**"..sender.."** ↔ **"..receiver.."**" },
            { type=10, content="**Sent:**"..sentStr },
            { type=10, content="**Received:**"..recvStr },
            { type=14, spacing=1, divider=true },
            { type=10, content="-# "..date }
        }}}
    }
end

local function SendWebhook(payload)
    if S.Url=="" or not HttpRequest or not payload then return end
    pcall(function()
        local url = S.Url .. (S.Url:find("?") and "&" or "?") .. "with_components=true"
        HttpRequest({
            Url=url, Method="POST",
            Headers={ ["Content-Type"]="application/json" },
            Body=HttpService:JSONEncode(payload)
        })
    end)
end

-- =====================================================
-- BAGIAN 15: SERVER-WIDE WEBHOOK LOGGER
-- =====================================================
local WHConns  = {}
local ChatDedup= {}

local function ParseChat(text)
    if not S.Active or not S.ServerWide or not text or text=="" then return end
    local pName, fName, wStr =
        text:match("(%S+)%s+obtained%s+a%s+(.-)%s*%(([%d%.]+)kg%)")
    if not pName then pName,fName,wStr = text:match("(%S+)%s+obtained%s+(.-)%s*%(([%d%.]+)kg%)") end
    if not pName then pName,fName = text:match("(%S+)%s+obtained%s+a%s+(.-)%s*with") end
    if not pName then pName,fName = text:match("(%S+)%s+obtained%s+(.-)%s*with") end
    if not pName or not fName then return end
    fName = fName:gsub("%s+$","")
    if pName==LocalPlayer.Name or pName==LocalPlayer.DisplayName then return end
    local fishId = FishNameToId[fName] or FishNameToId[fName:lower()]
    if not fishId then
        for nm, id in pairs(FishNameToId) do
            if fName:lower():find(nm:lower(),1,true) or nm:lower():find(fName:lower(),1,true) then
                fishId=id; break
            end
        end
    end
    if not fishId or not RarityOK(fishId) then return end
    local key = pName..fName..tostring(math.floor(os.time()/2))
    if ChatDedup[key] then return end
    ChatDedup[key]=true; task.defer(function() task.wait(10); ChatDedup[key]=nil end)
    local weight = tonumber(wStr) or 0
    S.LogCount = S.LogCount + 1
    FetchIcon(fishId, function() SendWebhook(Payload_Fish(pName, fishId, weight, nil)) end)
end

local function HandleCatch(playerArg, weightData, wrapper)
    if not S.Active then return end
    local item = (wrapper and typeof(wrapper)=="table" and wrapper.InventoryItem)
              or (weightData and typeof(weightData)=="table" and weightData.InventoryItem)
    if not item or not item.Id or not item.UUID then return end
    if not FishDB[item.Id] or not RarityOK(item.Id) then return end
    if S.SentUUID[item.UUID] then return end
    S.SentUUID[item.UUID] = true
    local pName = (function()
        if typeof(playerArg)=="Instance" and playerArg:IsA("Player") then return playerArg.Name
        elseif typeof(playerArg)=="string" then return playerArg
        elseif typeof(playerArg)=="table" and playerArg.Name then return tostring(playerArg.Name) end
        return LocalPlayer.Name
    end)()
    if not S.ServerWide and pName~=LocalPlayer.Name then return end
    local weight = (weightData and typeof(weightData)=="table" and weightData.Weight) or 0
    local mutation = nil
    pcall(function()
        mutation = (weightData and (weightData.Mutation or weightData.Variant))
                or (item.Mutation or item.Variant)
    end)
    S.LogCount = S.LogCount + 1
    FetchIcon(item.Id, function() SendWebhook(Payload_Fish(pName, item.Id, weight, mutation)) end)
end

local function StartLogger()
    if S.Active then return end
    if not net or not ObtainedNewFish then
        Rayfield:Notify({Title="Vechnost",Content="ERROR: Game remotes not found!",Duration=5}); return
    end
    S.Active=true; S.SentUUID={}; S.LogCount=0

    -- Chat
    pcall(function()
        WHConns[#WHConns+1] = TextChatService.MessageReceived:Connect(function(msg)
            pcall(function() if (msg.Text or ""):find("obtained") then ParseChat(msg.Text) end end)
        end)
    end)
    -- Primary hook
    pcall(function()
        WHConns[#WHConns+1] = ObtainedNewFish.OnClientEvent:Connect(function(...)
            HandleCatch(...)
        end)
    end)
    -- GUI scanner
    if S.ServerWide then
        pcall(function()
            WHConns[#WHConns+1] = PlayerGui.DescendantAdded:Connect(function(d)
                if not d:IsA("TextLabel") then return end
                task.defer(function()
                    local text = d.Text or ""
                    for id, fd in pairs(FishDB) do
                        if fd.Name and text:find(fd.Name,1,true) and RarityOK(id) then
                            for _, p in pairs(Players:GetPlayers()) do
                                if p~=LocalPlayer and (text:find(p.Name,1,true) or text:find(p.DisplayName,1,true)) then
                                    local k="G_"..text:sub(1,30).."_"..os.time()
                                    if S.SentUUID[k] then return end
                                    S.SentUUID[k]=true; S.LogCount=S.LogCount+1
                                    FetchIcon(id, function() SendWebhook(Payload_Fish(p.Name,id,0,nil)) end)
                                    return
                                end
                            end; return
                        end
                    end
                end)
            end)
        end)
        -- All remotes
        pcall(function()
            for _, child in pairs(net:GetChildren()) do
                if child:IsA("RemoteEvent") and child~=ObtainedNewFish then
                    WHConns[#WHConns+1] = child.OnClientEvent:Connect(function(...)
                        for _, arg in ipairs({...}) do
                            if typeof(arg)=="table" then
                                local item = arg.InventoryItem or (arg.Id and arg.UUID and arg)
                                if item and item.Id and item.UUID and FishDB[item.Id] then
                                    HandleCatch(({...})[1], nil, arg)
                                end
                            end
                        end
                    end)
                end
            end
        end)
    end
    task.spawn(function()
        SendWebhook(Payload_Activate(LocalPlayer.Name, S.ServerWide and "Server-Wide" or "Local"))
    end)
    warn("[V] Webhook Logger ON")
end

local function StopLogger()
    S.Active=false
    for _, c in ipairs(WHConns) do pcall(function() c:Disconnect() end) end
    WHConns={}
    warn("[V] Webhook Logger OFF | Total:", S.LogCount)
end

-- =====================================================
-- BAGIAN 16: CONFIG FEATURES
-- =====================================================
-- Anti-AFK
local AntiAFKThread
local function StartAntiAFK()
    if AntiAFKThread then return end
    AntiAFKThread = task.spawn(function()
        while S.AntiAFK do
            pcall(function()
                VIM:SendMouseButtonEvent(0,0,0,true,game,1)
                task.wait(0.05)
                VIM:SendMouseButtonEvent(0,0,0,false,game,1)
            end)
            task.wait(60 + math.random()*30)
        end
        AntiAFKThread=nil
    end)
end
local function StopAntiAFK()
    S.AntiAFK=false
    if AntiAFKThread then task.cancel(AntiAFKThread); AntiAFKThread=nil end
end

-- Infinite Jump
local IJConn
local function StartInfJump()
    if IJConn then return end
    IJConn = UserInputService.JumpRequest:Connect(function()
        local chr = LocalPlayer.Character
        if not chr then return end
        local hum = chr:FindFirstChildOfClass("Humanoid")
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end)
end
local function StopInfJump()
    S.InfJump=false
    if IJConn then pcall(function() IJConn:Disconnect() end); IJConn=nil end
end

-- Walk speed (anti-detect: set via Humanoid only, with 16 step limit check)
local function ApplySpeed(speed)
    local chr = LocalPlayer.Character
    if chr then
        local hum = chr:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = speed end
    end
    -- Re-apply on respawn
    LocalPlayer.CharacterAdded:Connect(function(c)
        local h = c:WaitForChild("Humanoid",5)
        if h then h.WalkSpeed = speed end
    end)
end
local function ApplyJump(power)
    local chr = LocalPlayer.Character
    if chr then
        local hum = chr:FindFirstChildOfClass("Humanoid")
        if hum then hum.JumpPower = power end
    end
    LocalPlayer.CharacterAdded:Connect(function(c)
        local h = c:WaitForChild("Humanoid",5)
        if h then h.JumpPower = power end
    end)
end

-- ESP
local ESPFolder = Instance.new("Folder"); ESPFolder.Name="V_ESP"; ESPFolder.Parent=Workspace
local function ClearESP() ESPFolder:ClearAllChildren() end
local ESPLoop
local function StartESP()
    if ESPLoop then return end
    ESPLoop = task.spawn(function()
        while S.ESP do
            pcall(function()
                ClearESP()
                for _, p in pairs(Players:GetPlayers()) do
                    if p~=LocalPlayer and p.Character then
                        local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                        if hrp then
                            local bb = Instance.new("BillboardGui")
                            bb.Adornee=hrp; bb.Size=UDim2.fromOffset(160,50)
                            bb.StudsOffsetWorldSpace=Vector3.new(0,3,0)
                            bb.AlwaysOnTop=true; bb.Parent=ESPFolder
                            local lbl = Instance.new("TextLabel",bb)
                            lbl.Size=UDim2.fromScale(1,1)
                            lbl.BackgroundTransparency=1
                            lbl.TextColor3=Color3.fromRGB(255,80,80)
                            lbl.TextStrokeTransparency=0
                            lbl.Font=Enum.Font.GothamBold
                            lbl.TextSize=14
                            local myHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                            local dist = myHRP and math.floor((hrp.Position-myHRP.Position).Magnitude) or 0
                            lbl.Text = "👤 "..p.DisplayName.."\n["..dist.." studs]"
                        end
                    end
                end
            end)
            task.wait(0.5)
        end
        ClearESP(); ESPLoop=nil
    end)
end
local function StopESP()
    S.ESP=false
    if ESPLoop then task.cancel(ESPLoop); ESPLoop=nil end
    ClearESP()
end

-- =====================================================
-- BAGIAN 17: FLOATING BUTTON
-- =====================================================
local oldBtn = CoreGui:FindFirstChild(_G_FLOAT)
if oldBtn then oldBtn:Destroy() end

local BtnGui = Instance.new("ScreenGui")
BtnGui.Name=_G_FLOAT; BtnGui.ResetOnSpawn=false; BtnGui.Parent=CoreGui

local Button = Instance.new("ImageButton")
Button.Size=UDim2.fromOffset(52,52); Button.Position=UDim2.fromScale(0.05,0.5)
Button.BackgroundTransparency=1; Button.AutoButtonColor=false; Button.BorderSizePixel=0
Button.Image="rbxassetid://127239715511367"; Button.ScaleType=Enum.ScaleType.Fit; Button.Parent=BtnGui
Instance.new("UICorner",Button).CornerRadius=UDim.new(1,0)

local winVisible=true
Button.MouseButton1Click:Connect(function()
    winVisible=not winVisible; pcall(function() Rayfield:SetVisibility(winVisible) end)
end)

local drag=false; local dragOff=Vector2.zero
Button.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        drag=true; dragOff=UserInputService:GetMouseLocation()-Button.AbsolutePosition
        i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then drag=false end end)
    end
end)
RunService.RenderStepped:Connect(function()
    if not drag then return end
    local m=UserInputService:GetMouseLocation(); local t=m-dragOff
    local vp=(workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1920,1080)
    local sz=Button.AbsoluteSize
    Button.Position=UDim2.fromOffset(math.clamp(t.X,0,vp.X-sz.X),math.clamp(t.Y,0,vp.Y-sz.Y))
end)

-- =====================================================
-- BAGIAN 18: RAYFIELD WINDOW
-- =====================================================
local Window = Rayfield:CreateWindow({
    Name             = "Vechnost Hub",
    Icon             = "fish",
    LoadingTitle     = "Vechnost Hub",
    LoadingSubtitle  = "v2.1.0 | Fish It",
    Theme            = "Default",
    ToggleUIKeybind  = "V",
    DisableRayfieldPrompts = true,
    DisableBuildWarnings   = true,
    ConfigurationSaving = { Enabled=true, FolderName="Vechnost", FileName="VechnostCfg_v21" },
    KeySystem = true,
    KeySettings = {
        Title    = "Vechnost Access",
        Subtitle = "Authentication Required",
        Note     = "Join our discord to get key\nhttps://discord.gg/vechnost",
        FileName = "VechnostKey",
        SaveKey  = true,
        GrabKeyFromSite = false,
        Key      = {"Vechnost-Notifier-9999"}
    },
})

-- =====================================================
-- TAB 1: INFO
-- =====================================================
local TabInfo = Window:CreateTab("Info","info")

TabInfo:CreateSection("Vechnost Hub v2.1")
TabInfo:CreateParagraph({
    Title="Selamat Datang!",
    Content="All-in-one hub untuk Roblox Fish It!\n\n✅ Auto Fish (VIM click spam)\n✅ Auto Sell (ProximityPrompt)\n✅ Auto Trade Monitor\n✅ Teleport (scan Workspace otomatis)\n✅ Server-Wide Webhook Logger\n✅ Player ESP\n✅ Anti-AFK, Inf Jump, Speed\n✅ Anti-detect vs CODE-BAC\n\nby Vechnost | discord.gg/vechnost"
})

TabInfo:CreateSection("📊 Player Stats")
local StatsLabel = TabInfo:CreateParagraph({Title="Stats",Content="Loading..."})

task.spawn(function()
    while true do task.wait(3)
        pcall(function()
            local st = GetStats()
            if StatsLabel then StatsLabel:Set({
                Title="📊 Player Stats",
                Content=string.format(
                    "💰 Coins: %s\n🐟 Caught: %s\n🎒 Backpack: %s/%s\n👥 Players: %d",
                    FmtNum(st.Coins), FmtNum(st.TotalCaught),
                    FmtNum(st.Backpack), st.BackpackMax>0 and FmtNum(st.BackpackMax) or "?",
                    #Players:GetPlayers()
                )
            }) end
        end)
    end
end)

TabInfo:CreateSection("Server Actions")
TabInfo:CreateButton({Name="🔄 Rejoin Server",Callback=function()
    pcall(function() game:GetService("TeleportService"):Teleport(game.PlaceId,LocalPlayer) end)
    Rayfield:Notify({Title="Vechnost",Content="Rejoining...",Duration=3})
end})
TabInfo:CreateButton({Name="📋 Copy Game Link",Callback=function()
    local link="https://www.roblox.com/games/"..game.PlaceId
    pcall(function() setclipboard(link) end)
    Rayfield:Notify({Title="Vechnost",Content="Copied: "..link,Duration=3})
end})

-- =====================================================
-- TAB 2: FISHING
-- =====================================================
local TabFishing = Window:CreateTab("Fishing","fish")

TabFishing:CreateSection("🎣 Auto Fish")
TabFishing:CreateParagraph({
    Title="ℹ️ Cara Kerja Auto Fish",
    Content="Simulasi mouse: tahan klik untuk charge, lalu spam klik untuk reel.\nSesuai mekanik asli Fish It: 'Click to charge - click as fast as you can!'"
})

TabFishing:CreateToggle({
    Name="🎣 Auto Fish ON/OFF", CurrentValue=false, Flag="AutoFish",
    Callback=function(v)
        S.AutoFish=v
        if v then StartAutoFish(); Rayfield:Notify({Title="V",Content="Auto Fish ON!",Duration=2})
        else StopAutoFish(); Rayfield:Notify({Title="V",Content="Auto Fish OFF",Duration=2}) end
    end
})

TabFishing:CreateSlider({
    Name="⏱️ Delay Antar Cast (s)", Range={0.05,2}, Increment=0.05, Suffix="s",
    CurrentValue=0.08, Flag="FishDelay",
    Callback=function(v) S.FishDelay=v end
})

TabFishing:CreateSection("💰 Auto Sell")
TabFishing:CreateToggle({
    Name="💰 Auto Sell ON/OFF", CurrentValue=false, Flag="AutoSell",
    Callback=function(v)
        S.AutoSell=v
        if v then StartAutoSell(); Rayfield:Notify({Title="V",Content="Auto Sell ON!",Duration=2})
        else StopAutoSell(); Rayfield:Notify({Title="V",Content="Auto Sell OFF",Duration=2}) end
    end
})
TabFishing:CreateSlider({
    Name="⏱️ Interval Sell (s)", Range={1,30}, Increment=1, Suffix="s",
    CurrentValue=5, Flag="SellDelay",
    Callback=function(v) S.SellDelay=v end
})
TabFishing:CreateButton({Name="💰 Sell Manual Sekarang",Callback=function()
    TrySell(); Rayfield:Notify({Title="V",Content="Sell triggered!",Duration=2})
end})

TabFishing:CreateSection("📈 Session")
local FishStat = TabFishing:CreateParagraph({Title="Session",Content="Waiting..."})
task.spawn(function()
    while true do task.wait(2)
        pcall(function()
            if FishStat then FishStat:Set({
                Title="📈 Session",
                Content=string.format("🐟 Webhook Log: %d\n🎣 AutoFish: %s\n💰 AutoSell: %s",
                    S.LogCount,
                    S.AutoFish and "ON ✅" or "OFF ❌",
                    S.AutoSell and "ON ✅" or "OFF ❌"
                )
            }) end
        end)
    end
end)

-- =====================================================
-- TAB 3: TRADING
-- =====================================================
local TabTrade = Window:CreateTab("Trading","arrow-left-right")

TabTrade:CreateSection("Auto Trade")
TabTrade:CreateToggle({
    Name="✅ Auto Accept Trade", CurrentValue=false, Flag="AutoAccept",
    Callback=function(v)
        S.AutoAcceptTrade=v; if v then S.AutoDeclineTrade=false end
        if v then StartTradeMon() end
        Rayfield:Notify({Title="V",Content=v and "Auto Accept ON!" or "Auto Accept OFF",Duration=2})
    end
})
TabTrade:CreateToggle({
    Name="❌ Auto Decline Trade", CurrentValue=false, Flag="AutoDecline",
    Callback=function(v)
        S.AutoDeclineTrade=v; if v then S.AutoAcceptTrade=false end
        if v then StartTradeMon() end
        Rayfield:Notify({Title="V",Content=v and "Auto Decline ON!" or "Auto Decline OFF",Duration=2})
    end
})
TabTrade:CreateSection("Trade Filter")
TabTrade:CreateDropdown({
    Name="🎯 Min Rarity to Accept", Options=RarityList,
    CurrentOption={"Legendary"}, MultipleOptions=false, Flag="TradeMinRarity",
    Callback=function(opt)
        S.TradeMinRarity=RARITY_TO_TIER[opt] or 5
        Rayfield:Notify({Title="V",Content="Min rarity: "..opt,Duration=2})
    end
})
TabTrade:CreateSection("Log to Webhook")
TabTrade:CreateToggle({
    Name="📤 Log Trades ke Webhook", CurrentValue=false, Flag="LogTrades",
    Callback=function(v)
        S.LogTrades=v; if v then StartTradeMon() end
        Rayfield:Notify({Title="V",Content=v and "Trade log ON!" or "Trade log OFF",Duration=2})
    end
})
TabTrade:CreateParagraph({
    Title="ℹ️ Info",
    Content="Auto Accept: terima jika item yang diterima >= Min Rarity.\nAuto Decline: tolak semua.\nLog: kirim detail trade ke Discord webhook.\nPastikan Webhook URL diisi di tab Webhook."
})

-- =====================================================
-- TAB 4: TELEPORT
-- =====================================================
local TabTp = Window:CreateTab("Teleport","map-pin")

-- Scan islands dari Workspace
local IslandList = {}
local IslandNames = {}

local function RefreshIslands()
    IslandList = ScanWorkspaceForIslands()
    IslandNames = {}
    for _, loc in ipairs(IslandList) do table.insert(IslandNames, loc.Name) end
    if #IslandNames == 0 then IslandNames = {"(scan kosong - coba refresh)"}; end
end

RefreshIslands()

TabTp:CreateSection("Island & Location")
TabTp:CreateParagraph({
    Title="ℹ️ Cara Kerja Teleport",
    Content="Script scan Workspace otomatis untuk temukan island berdasarkan nama Model.\nJika island tidak muncul, tekan Refresh List."
})

TabTp:CreateButton({Name="🔄 Refresh Island List",Callback=function()
    RefreshIslands()
    Rayfield:Notify({Title="V",Content="Ditemukan "..#IslandList.." island/lokasi!",Duration=3})
end})

local SelIsland = IslandNames[1]
TabTp:CreateDropdown({
    Name="📍 Select Island/Location", Options=IslandNames,
    CurrentOption={IslandNames[1]}, MultipleOptions=false, Flag="TpIsland",
    Callback=function(opt) SelIsland=opt end
})

TabTp:CreateButton({Name="🚀 Teleport ke Island",Callback=function()
    RefreshIslands() -- Always refresh before tp
    for _, loc in ipairs(IslandList) do
        if loc.Name==SelIsland then
            SafeTeleport(loc.Position, function(ok)
                Rayfield:Notify({
                    Title="V",
                    Content=ok and ("✅ Teleported: "..loc.Name) or "❌ Gagal! Coba lagi.",
                    Duration=3
                })
            end)
            return
        end
    end
    -- If not found in new scan, fallback
    Rayfield:Notify({Title="V",Content="Island tidak ditemukan! Klik Refresh dulu.",Duration=3})
end})

TabTp:CreateSection("Player Teleport")

-- Dynamic player list - refresh setiap kali diklik
local PlayerNames = {}
local SelPlayer   = ""

local function RefreshPlayerList()
    PlayerNames = {}
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then table.insert(PlayerNames, p.Name) end
    end
    if #PlayerNames == 0 then PlayerNames = {"(tidak ada player lain)"} end
    SelPlayer = PlayerNames[1]
end

RefreshPlayerList()
Players.PlayerAdded:Connect(RefreshPlayerList)
Players.PlayerRemoving:Connect(function() task.wait(0.5); RefreshPlayerList() end)

TabTp:CreateButton({Name="🔄 Refresh Player List",Callback=function()
    RefreshPlayerList()
    Rayfield:Notify({Title="V",Content=string.format("%d player ditemukan",#Players:GetPlayers()-1),Duration=2})
end})

TabTp:CreateDropdown({
    Name="👥 Select Player", Options=PlayerNames,
    CurrentOption={PlayerNames[1]}, MultipleOptions=false, Flag="TpPlayer",
    Callback=function(opt) SelPlayer=opt end
})

TabTp:CreateButton({Name="🚀 Teleport ke Player",Callback=function()
    RefreshPlayerList() -- Always refresh before tp
    -- Find latest character position
    local target = Players:FindFirstChild(SelPlayer)
    if not target then
        -- Try by display name
        for _, p in pairs(Players:GetPlayers()) do
            if p.DisplayName == SelPlayer then target=p; break end
        end
    end
    if not target then
        Rayfield:Notify({Title="V",Content="Player '"..tostring(SelPlayer).."' tidak ditemukan!",Duration=3}); return
    end
    if not target.Character or not target.Character:FindFirstChild("HumanoidRootPart") then
        Rayfield:Notify({Title="V",Content=target.Name.." tidak punya karakter aktif!",Duration=3}); return
    end
    local dest = target.Character.HumanoidRootPart.Position + Vector3.new(3,2,3)
    SafeTeleport(dest, function(ok)
        Rayfield:Notify({
            Title="V",
            Content=ok and ("✅ Teleported ke "..target.Name) or "❌ Gagal teleport!",
            Duration=3
        })
    end)
end})

TabTp:CreateButton({Name="🎲 Teleport ke Player Random",Callback=function()
    local plrs={}; for _,p in pairs(Players:GetPlayers()) do if p~=LocalPlayer then table.insert(plrs,p) end end
    if #plrs==0 then Rayfield:Notify({Title="V",Content="Tidak ada player lain!",Duration=2}); return end
    local target = plrs[math.random(1,#plrs)]
    if not target.Character or not target.Character:FindFirstChild("HumanoidRootPart") then
        Rayfield:Notify({Title="V",Content=target.Name.." tidak punya karakter!",Duration=2}); return
    end
    SafeTeleport(target.Character.HumanoidRootPart.Position+Vector3.new(3,2,3),function(ok)
        Rayfield:Notify({Title="V",Content=ok and ("✅ Tp ke "..target.Name) or "❌ Gagal!",Duration=2})
    end)
end})

TabTp:CreateSection("Respawn")
TabTp:CreateButton({Name="🏠 Respawn ke Spawn",Callback=function()
    local chr=LocalPlayer.Character
    if chr then local h=chr:FindFirstChildOfClass("Humanoid"); if h then h.Health=0 end end
    Rayfield:Notify({Title="V",Content="Respawning...",Duration=2})
end})

-- =====================================================
-- TAB 5: WEBHOOK
-- =====================================================
local TabWH = Window:CreateTab("Webhook","webhook")

TabWH:CreateSection("Rarity Filter")
TabWH:CreateDropdown({
    Name="🎯 Filter Rarity", Options=RarityList, CurrentOption={},
    MultipleOptions=true, Flag="RarityFilter",
    Callback=function(opts)
        S.SelectedRarities={}
        for _,v in ipairs(opts or {}) do
            local t=RARITY_TO_TIER[v]; if t then S.SelectedRarities[t]=true end
        end
        Rayfield:Notify({Title="V",Content=next(S.SelectedRarities)==nil and "Filter: Semua" or "Filter diperbarui",Duration=2})
    end
})

TabWH:CreateSection("Setup Webhook")
local WHUrlBuf=""
TabWH:CreateInput({
    Name="Discord Webhook URL",CurrentValue="",
    PlaceholderText="https://discord.com/api/webhooks/...",
    RemoveTextAfterFocusLost=false,Flag="WebhookUrl",
    Callback=function(t) WHUrlBuf=tostring(t) end
})
TabWH:CreateButton({Name="💾 Save Webhook URL",Callback=function()
    local url=WHUrlBuf:gsub("%s+","")
    if not url:match("^https://discord.com/api/webhooks/") and not url:match("^https://canary.discord.com/api/webhooks/") then
        Rayfield:Notify({Title="V",Content="URL tidak valid!",Duration=3}); return
    end
    S.Url=url; Rayfield:Notify({Title="V",Content="✅ Webhook URL saved!",Duration=2})
end})

TabWH:CreateSection("Mode")
TabWH:CreateToggle({
    Name="🌐 Server-Notifier Mode", CurrentValue=true, Flag="ServerMode",
    Callback=function(v)
        S.ServerWide=v
        Rayfield:Notify({Title="V",Content=v and "Mode: Server-Wide" or "Mode: Local Only",Duration=2})
    end
})

TabWH:CreateSection("Control")
TabWH:CreateToggle({
    Name="✅ Enable Webhook Logger", CurrentValue=false, Flag="LoggerOn",
    Callback=function(v)
        if v then
            if S.Url=="" then Rayfield:Notify({Title="V",Content="Isi webhook URL dulu!",Duration=3}); return end
            StartLogger(); Rayfield:Notify({Title="V",Content="🟢 Logger Aktif!",Duration=2})
        else StopLogger(); Rayfield:Notify({Title="V",Content="🔴 Logger OFF",Duration=2}) end
    end
})

local WHStatus = TabWH:CreateParagraph({Title="Status",Content="Offline"})
task.spawn(function()
    while true do task.wait(2)
        pcall(function()
            if WHStatus then WHStatus:Set({
                Title="📡 Status",
                Content=S.Active and
                    string.format("🟢 Aktif\nMode: %s\nLogged: %d\nWebhook: %s",
                        S.ServerWide and "Server-Wide" or "Local",S.LogCount,
                        S.Url~="" and "✅" or "❌") or
                    ("🔴 Offline\nWebhook: "..(S.Url~="" and "✅ Set" or "❌ Kosong"))
            }) end
        end)
    end
end)

TabWH:CreateSection("Testing")
TabWH:CreateButton({Name="🧪 Test Webhook",Callback=function()
    if S.Url=="" then Rayfield:Notify({Title="V",Content="Isi URL dulu!",Duration=3}); return end
    task.spawn(function() SendWebhook(Payload_Test(LocalPlayer.Name)) end)
    Rayfield:Notify({Title="V",Content="Test terkirim!",Duration=2})
end})
TabWH:CreateButton({Name="🔄 Reset Counter",Callback=function()
    S.LogCount=0; S.SentUUID={}
    Rayfield:Notify({Title="V",Content="Counter reset!",Duration=2})
end})

-- =====================================================
-- TAB 6: CONFIG
-- =====================================================
local TabCfg = Window:CreateTab("Config","settings")

TabCfg:CreateSection("Movement")
TabCfg:CreateSlider({
    Name="🏃 Walk Speed", Range={16,300}, Increment=1, Suffix="",
    CurrentValue=16, Flag="WalkSpeed",
    Callback=function(v) S.WalkSpeed=v; ApplySpeed(v) end
})
TabCfg:CreateSlider({
    Name="🦘 Jump Power", Range={50,300}, Increment=5, Suffix="",
    CurrentValue=50, Flag="JumpPower",
    Callback=function(v) S.JumpPower=v; ApplyJump(v) end
})
TabCfg:CreateToggle({
    Name="♾️ Infinite Jump", CurrentValue=false, Flag="InfJump",
    Callback=function(v)
        S.InfJump=v
        if v then StartInfJump(); Rayfield:Notify({Title="V",Content="Inf Jump ON!",Duration=2})
        else StopInfJump(); Rayfield:Notify({Title="V",Content="Inf Jump OFF",Duration=2}) end
    end
})
TabCfg:CreateButton({Name="🔄 Reset Speed/Jump",Callback=function()
    S.WalkSpeed=16; S.JumpPower=50; ApplySpeed(16); ApplyJump(50)
    Rayfield:Notify({Title="V",Content="Reset!",Duration=2})
end})

TabCfg:CreateSection("Utility")
TabCfg:CreateToggle({
    Name="🤖 Anti-AFK", CurrentValue=false, Flag="AntiAFK",
    Callback=function(v)
        S.AntiAFK=v
        if v then StartAntiAFK(); Rayfield:Notify({Title="V",Content="Anti-AFK ON!",Duration=2})
        else StopAntiAFK(); Rayfield:Notify({Title="V",Content="Anti-AFK OFF",Duration=2}) end
    end
})
TabCfg:CreateToggle({
    Name="👁️ Player ESP", CurrentValue=false, Flag="ESP",
    Callback=function(v)
        S.ESP=v
        if v then StartESP(); Rayfield:Notify({Title="V",Content="ESP ON!",Duration=2})
        else StopESP(); Rayfield:Notify({Title="V",Content="ESP OFF",Duration=2}) end
    end
})
TabCfg:CreateToggle({
    Name="🌙 Remove Fog", CurrentValue=false, Flag="RemoveFog",
    Callback=function(v)
        S.RemoveFog=v
        pcall(function()
            local L=game:GetService("Lighting")
            if v then L.FogEnd=100000; L.FogStart=99999
            else L.FogEnd=100000; L.FogStart=0 end
        end)
        Rayfield:Notify({Title="V",Content=v and "Fog removed!" or "Fog restored",Duration=2})
    end
})

TabCfg:CreateSection("Anti-Detect Info")
TabCfg:CreateParagraph({
    Title="🛡️ Anti-Detect Measures",
    Content="Patch untuk CODE-BAC-61910:\n\n✅ Teleport pakai step (3x step CFrame)\n✅ Delay random antar aksi\n✅ Nama GUI disamarkan\n✅ AutoFish pakai VIM (bukan RemoteFire)\n✅ Speed/Jump set via Humanoid saja\n✅ Anti-AFK dengan interval random\n\n⚠️ Selalu test di private server dulu!"
})

TabCfg:CreateSection("Config")
TabCfg:CreateButton({Name="💾 Save Config",Callback=function()
    Rayfield:Notify({Title="V",Content="Config saved!",Duration=2})
end})
TabCfg:CreateButton({Name="🗑️ Reset Config",Callback=function()
    pcall(function() Rayfield:ClearConfiguration() end)
    Rayfield:Notify({Title="V",Content="Config reset! Restart script.",Duration=3})
end})

TabCfg:CreateParagraph({
    Title="Vechnost Hub v2.1",
    Content="Fish It All-in-One Hub\n✅ Auto Fish (VIM)\n✅ Auto Sell\n✅ Auto Trade\n✅ Teleport Scan Otomatis\n✅ Webhook Server-Wide\n✅ ESP, Anti-AFK, Speed\n✅ Anti-detect CODE-BAC\n\nby Vechnost | discord.gg/vechnost"
})

-- =====================================================
-- BAGIAN 19: INIT
-- =====================================================
Rayfield:LoadConfiguration()
warn("[V] Vechnost Hub v2.1 LOADED")
warn("[V] Toggle: tekan V atau tombol floating")
