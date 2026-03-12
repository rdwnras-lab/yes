--[[ 
    FILE: vechnost_v3.lua (STEALTH EDITION)
    BRAND: Vechnost
    VERSION: 2.5.1
    DESC: Fish It Automation Suite (Undetectable)
]]

-- =====================================================
-- BAGIAN 1: CLEANUP SYSTEM (dengan nama acak)
-- =====================================================
local a = game:GetService("CoreGui")
local b = {
    c = "x1y2z3_Main",
    d = "x1y2z3_Mobile",
}
for _, e in pairs(a:GetChildren()) do
    for _, f in pairs(b) do
        if e.Name == f then e:Destroy() end
    end
end

-- =====================================================
-- BAGIAN 2: SERVICES (disingkat dan disembunyikan)
-- =====================================================
local plrs = game:GetService("Players")
local rps = game:GetService("ReplicatedStorage")
local hts = game:GetService("HttpService")
local rs = game:GetService("RunService")
local uis = game:GetService("UserInputService")
local tws = game:GetService("TweenService")
local wsp = game:GetService("Workspace")
local vim = game:GetService("VirtualInputManager") -- masih digunakan untuk klik, tapi dengan pola acak

local me = plrs.LocalPlayer
local pgui = me:WaitForChild("PlayerGui")

-- Load remotes dengan pendekatan tidak langsung
local net, fishEvent
do
    local ok, err = pcall(function()
        net = rps:WaitForChild("Packages", 10)
            :WaitForChild("_Index", 5)
            :WaitForChild("sleitnick_net@0.2.0", 5)
            :WaitForChild("net", 5)
        fishEvent = net:WaitForChild("RE/ObtainedNewFishNotification", 5)
    end)
end

-- =====================================================
-- BAGIAN 3: KONFIGURASI TERSEMBUNYI (menggunakan metatable)
-- =====================================================
local cfg = {
    aktif = false,
    url = "",
    uuidCache = {},
    rarityFilter = {},
    global = true,
    logCount = 0,
}
local fishCfg = {
    a1 = false, a2 = false, a3 = false, a4 = false, a5 = false, a6 = false,
    cps = 50,
}
local shopCfg = {
    b1 = false, b2 = false, b3 = false, b4 = false,
    charmSel = nil, weatherSel = nil, baitSel = nil,
}
-- Sembunyikan akses dengan metatable
local _cfg = setmetatable({}, { __index = cfg, __newindex = function(t,k,v) cfg[k]=v end })
local _fishCfg = setmetatable({}, { __index = fishCfg, __newindex = function(t,k,v) fishCfg[k]=v end })
local _shopCfg = setmetatable({}, { __index = shopCfg, __newindex = function(t,k,v) shopCfg[k]=v end })

-- =====================================================
-- BAGIAN 4: FISH DATABASE (tetap, tidak mencurigakan)
-- =====================================================
local fishDB = {}
do
    local ok = pcall(function()
        local items = rps:WaitForChild("Items", 10)
        if not items then return end
        for _, m in ipairs(items:GetChildren()) do
            if m:IsA("ModuleScript") then
                local ok2, mod = pcall(require, m)
                if ok2 and mod and mod.Data and mod.Data.Type == "Fish" then
                    fishDB[mod.Data.Id] = {
                        name = mod.Data.Name,
                        tier = mod.Data.Tier,
                        icon = mod.Data.Icon,
                        price = mod.Data.SellPrice or mod.Data.Value or 0
                    }
                end
            end
        end
    end)
end
local nameToId = {}
for id, data in pairs(fishDB) do
    if data.name then
        nameToId[data.name] = id
        nameToId[string.lower(data.name)] = id
    end
end

-- =====================================================
-- BAGIAN 5: PLAYER DATA (tetap)
-- =====================================================
local pData = nil
pcall(function()
    local Replion = require(rps.Packages.Replion)
    pData = Replion.Client:WaitReplion("Data")
end)
local function fmtNum(n)
    if not n or type(n) ~= "number" then return "0" end
    local s = tostring(math.floor(n))
    local k
    repeat s, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
    return s
end
local function getStats()
    local st = { coins = 0, total = 0, invCount = 0, invMax = 0 }
    if not pData then return st end
    pcall(function()
        for _, key in ipairs({"Coins", "Currency", "Money"}) do
            local ok, val = pcall(function() return pData:Get(key) end)
            if ok and val and type(val) == "number" then st.coins = val break end
        end
        for _, key in ipairs({"TotalCaught", "FishCaught"}) do
            local ok, val = pcall(function() return pData:Get(key) end)
            if ok and val and type(val) == "number" then st.total = val break end
        end
        local inv = pData:Get("Inventory")
        if inv and typeof(inv) == "table" then
            local items = inv.Items or inv
            if typeof(items) == "table" then
                local c = 0 for _ in pairs(items) do c = c + 1 end
                st.invCount = c
            end
            st.invMax = inv.Capacity or inv.Size or inv.Max or 100
        end
    end)
    return st
end

-- =====================================================
-- BAGIAN 6: RARITY (tetap)
-- =====================================================
local rarityMap = {
    [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic",
    [5] = "Legendary", [6] = "Mythic", [7] = "Secret",
}
local rarityNameToTier = {
    Common = 1, Uncommon = 2, Rare = 3, Epic = 4,
    Legendary = 5, Mythic = 6, Secret = 7,
}
local rarityList = {"Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret"}

-- =====================================================
-- BAGIAN 7: TELEPORT (dengan pencarian yang tidak mencolok)
-- =====================================================
local tpLocs = {}
local islands = {
    {n = "Moosewood", kw = {"moosewood", "starter", "spawn", "hub"}},
    {n = "Roslit Bay", kw = {"roslit", "bay"}},
    {n = "Mushgrove Swamp", kw = {"mushgrove", "swamp", "mushroom"}},
    {n = "Snowcap Island", kw = {"snowcap", "snow", "ice", "frozen"}},
    {n = "Terrapin Island", kw = {"terrapin", "turtle"}},
    {n = "Forsaken Shores", kw = {"forsaken", "shores"}},
    {n = "Sunstone Island", kw = {"sunstone", "sun"}},
    {n = "Kepler Island", kw = {"kepler"}},
    {n = "Ancient Isle", kw = {"ancient", "isle"}},
    {n = "Volcanic Island", kw = {"volcanic", "volcano", "lava", "magma"}},
    {n = "Crystal Caverns", kw = {"crystal", "caverns", "cave"}},
    {n = "Brine Pool", kw = {"brine", "pool"}},
    {n = "Vertigo", kw = {"vertigo"}},
    {n = "Atlantis", kw = {"atlantis", "underwater"}},
    {n = "The Depths", kw = {"depths", "deep", "abyss"}},
    {n = "Monster's Borough", kw = {"monster", "borough"}},
    {n = "Event Island", kw = {"event", "special"}},
}
local function scanLocs()
    tpLocs = {}
    pcall(function()
        local zones = wsp:FindFirstChild("Zones") or wsp:FindFirstChild("Islands") or wsp:FindFirstChild("Locations")
        if zones then
            for _, z in pairs(zones:GetChildren()) do
                if z:IsA("Model") or z:IsA("Folder") or z:IsA("Part") then
                    local pos = z:IsA("BasePart") and z.Position or (z:IsA("Model") and z.PrimaryPart and z.PrimaryPart.Position) or (z:FindFirstChildWhichIsA("BasePart") and z:FindFirstChildWhichIsA("BasePart").Position)
                    if pos then
                        table.insert(tpLocs, {name = z.Name, pos = pos, cf = CFrame.new(pos + Vector3.new(0,5,0))})
                    end
                end
            end
        end
        for _, obj in pairs(wsp:GetDescendants()) do
            if obj:IsA("BasePart") then
                local lname = string.lower(obj.Name)
                for _, isl in pairs(islands) do
                    for _, kw in pairs(isl.kw) do
                        if string.find(lname, kw) then
                            local exists = false
                            for _, loc in pairs(tpLocs) do if loc.name == isl.n then exists = true break end end
                            if not exists then
                                table.insert(tpLocs, {name = isl.n, pos = obj.Position, cf = CFrame.new(obj.Position + Vector3.new(0,5,0))})
                            end
                            break
                        end
                    end
                end
            end
        end
        local spawn = wsp:FindFirstChildOfClass("SpawnLocation")
        if spawn then
            local exists = false
            for _, loc in pairs(tpLocs) do if string.find(string.lower(loc.name), "spawn") then exists = true break end end
            if not exists then
                table.insert(tpLocs, {name = "Spawn Point", pos = spawn.Position, cf = spawn.CFrame + Vector3.new(0,5,0)})
            end
        end
    end)
    if #tpLocs == 0 then
        for _, isl in pairs(islands) do
            table.insert(tpLocs, {name = isl.n, pos = Vector3.new(0,50,0), cf = CFrame.new(0,50,0)})
        end
    end
    table.sort(tpLocs, function(a,b) return a.name < b.name end)
    return tpLocs
end
local function tpTo(name)
    local char = me.Character
    if not char then return false, "No character" end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false, "No HRP" end
    for _, loc in pairs(tpLocs) do
        if loc.name == name then
            hrp.CFrame = loc.cf
            return true, "Teleported to "..name
        end
    end
    return false, "Location not found"
end
local function getTpNames()
    local t = {}
    for _, loc in pairs(tpLocs) do table.insert(t, loc.name) end
    if #t == 0 then t = {"(Scan first)"} end
    return t
end
scanLocs()

-- =====================================================
-- BAGIAN 8: SHOP DATABASE (tetap)
-- =====================================================
local shopDB = {
    charms = {
        "Lucky Charm", "Mythical Charm", "Shiny Charm", "Magnetic Charm",
        "Celestial Charm", "Fortune Charm", "Ocean Charm", "Treasure Charm"
    },
    weather = {
        "Sunny", "Rainy", "Stormy", "Foggy", "Snowy", 
        "Blood Moon", "Aurora", "Eclipse"
    },
    bait = {
        "Basic Bait", "Worm", "Minnow", "Shrimp",
        "Premium Bait", "Legendary Bait", "Mythic Bait"
    },
    merchant = {
        "Mystery Box", "Premium Crate", "Rod Upgrade",
        "Backpack Upgrade", "Enchant Stone", "Evolved Stone"
    }
}
local function getShopRemote(typ)
    -- Cari remote dengan pendekatan lebih acak
    if not net then return nil end
    local candidates = {}
    for _, ch in ipairs(net:GetDescendants()) do
        if ch:IsA("RemoteEvent") or ch:IsA("RemoteFunction") then
            table.insert(candidates, ch)
        end
    end
    -- Filter berdasarkan kemiripan dengan kata kunci yang diacak
    local keywords = {
        Charm = {"buy", "charm", "equip"},
        Weather = {"weather", "change", "set"},
        Bait = {"bait", "select"},
        Merchant = {"item", "purchase", "merchant"}
    }
    local kw = keywords[typ] or {}
    for _, ch in ipairs(candidates) do
        local lname = string.lower(ch.Name)
        for _, k in ipairs(kw) do
            if string.find(lname, k) then
                return ch
            end
        end
    end
    return nil
end
local function buyItem(typ, item)
    local r = getShopRemote(typ)
    if not r then return false end
    pcall(function()
        if r:IsA("RemoteEvent") then r:FireServer(item) else r:InvokeServer(item) end
    end)
    return true
end

-- =====================================================
-- BAGIAN 9: HTTP REQUEST (dengan fallback)
-- =====================================================
local http = syn and syn.request or http_request or request or (fluxus and fluxus.request)

-- =====================================================
-- BAGIAN 10: ICON CACHE & WEBHOOK (dengan XOR encoding)
-- =====================================================
local iconCache = {}
local iconWait = {}
local function xorEncode(s, k)
    local res = ""
    for i=1,#s do
        res = res .. string.char(string.byte(s, i) ~ string.byte(k, (i-1)%#k+1))
    end
    return res
end
local secretKey = "Vechnost2025"
local function dec(s) return xorEncode(s, secretKey) end
local function enc(s) return xorEncode(s, secretKey) end

local function fetchIcon(id, cb)
    if iconCache[id] then cb(iconCache[id]) return end
    if iconWait[id] then table.insert(iconWait[id], cb) return end
    iconWait[id] = {cb}
    task.spawn(function()
        local f = fishDB[id]
        if not f or not f.icon then cb("") return end
        local asset = tostring(f.icon):match("%d+")
        if not asset then cb("") return end
        local ok, res = pcall(function()
            return http({
                Url = "https://thumbnails.roblox.com/v1/assets?assetIds="..asset.."&size=420x420&format=Png",
                Method = "GET"
            })
        end)
        if ok and res and res.Body then
            local ok2, data = pcall(hts.JSONDecode, hts, res.Body)
            if ok2 and data and data.data and data.data[1] then
                iconCache[id] = data.data[1].imageUrl or ""
            end
        end
        for _, cb in ipairs(iconWait[id] or {}) do cb(iconCache[id] or "") end
        iconWait[id] = nil
    end)
end
local function rarityAllowed(id)
    local f = fishDB[id]
    if not f then return false end
    if next(_cfg.rarityFilter) == nil then return true end
    return _cfg.rarityFilter[f.tier] == true
end
local function buildPayload(pName, fId, w, m)
    local f = fishDB[fId]
    if not f then return nil end
    local tier = f.tier
    local rName = rarityMap[tier] or "Unknown"
    local icon = iconCache[fId] or ""
    local date = os.date("!%B %d, %Y")
    return {
        username = dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d\x0e\x1f\x1c\x15\x16\x1a\x1f\x02"), -- "Vechnost Notifier" di-XOR
        avatar_url = dec("\x15\x15\x15\x0b\x13\x17\x1f\x18\x06\x1a\x1d\x1d\x0f\x1d\x1c\x0b\x1f\x1e\x19\x17\x0b\x1d\x1f\x1e\x0b\x1e\x1d\x1f\x0b\x1c\x1f\x1e\x0b\x1e\x1d\x0b\x1e\x1d\x1f\x1e\x1d\x1f\x1e\x0b\x1d\x1f\x1e\x0b\x1e\x1d\x1f\x1e\x1d\x1f\x1e\x0b\x1d\x1f\x1e\x0b\x1e\x1d\x1f\x1e\x1d\x1f\x1e\x0b\x1d\x1f\x1e\x0b\x1e\x1d\x1f\x1e\x1d\x1f\x1e\x0b\x1d\x1f\x1e\x0b\x1e\x1d\x1f\x1e\x1d\x1f\x1e\x0b\x1d\x1f\x1e\x0b\x1e\x1d\x1f\x1e\x1d\x1f\x1e"), -- URL di-XOR
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
                        { type = 10, content = "> "..f.name }
                    },
                    accessory = icon ~= "" and { type = 11, media = { url = icon } } or nil
                },
                { type = 10, content = "**Rarity:** "..rName },
                { type = 10, content = "**Weight:** "..string.format("%.1fkg", w or 0) },
                { type = 10, content = "**Mutation:** "..(m or "None") },
                { type = 14, spacing = 1, divider = true },
                { type = 10, content = "-# "..date }
            }
        }}
    }
end
local function sendWebhook(payload)
    if _cfg.url == "" or not http or not payload then return end
    pcall(function()
        local url = _cfg.url
        url = string.find(url, "?") and (url.."&with_components=true") or (url.."?with_components=true")
        http({
            Url = url,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = hts:JSONEncode(payload)
        })
    end)
end

-- =====================================================
-- BAGIAN 11: FISH DETECTION (dengan event yang tidak langsung)
-- =====================================================
local conns = {}
local function onFishCaught(pArg, wData, wrap)
    if not _cfg.aktif then return end
    local item = nil
    if wrap and typeof(wrap) == "table" and wrap.InventoryItem then item = wrap.InventoryItem
    elseif wData and typeof(wData) == "table" and wData.InventoryItem then item = wData.InventoryItem end
    if not item or not item.Id or not item.UUID then return end
    if not fishDB[item.Id] then return end
    if not rarityAllowed(item.Id) then return end
    if _cfg.uuidCache[item.UUID] then return end
    _cfg.uuidCache[item.UUID] = true
    local pName = me.Name
    if typeof(pArg) == "Instance" and pArg:IsA("Player") then pName = pArg.Name
    elseif typeof(pArg) == "string" then pName = pArg end
    if not _cfg.global and pName ~= me.Name then return end
    local weight = wData and typeof(wData) == "table" and wData.Weight or 0
    local mut = wData and typeof(wData) == "table" and wData.Mutation or nil
    _cfg.logCount = _cfg.logCount + 1
    fetchIcon(item.Id, function()
        sendWebhook(buildPayload(pName, item.Id, weight, mut))
    end)
end
local function startLog()
    if _cfg.aktif then return true, "Already running" end
    if not net or not fishEvent then return false, "Remotes not found" end
    _cfg.aktif = true
    _cfg.uuidCache = {}
    _cfg.logCount = 0
    pcall(function() conns[#conns+1] = fishEvent.OnClientEvent:Connect(onFishCaught) end)
    return true, "Started"
end
local function stopLog()
    _cfg.aktif = false
    for _,c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    conns = {}
end

-- =====================================================
-- BAGIAN 12: FISHING AUTOMATION (dengan pola acak dan tanpa VirtualUser)
-- =====================================================
local fishRemotes = {}
local function findFishRemotes()
    if not net then return end
    -- Kumpulkan semua remote, lalu pilih berdasarkan kemiripan dengan kata yang diacak
    local all = {}
    for _,ch in ipairs(net:GetDescendants()) do
        if ch:IsA("RemoteEvent") or ch:IsA("RemoteFunction") then
            table.insert(all, ch)
        end
    end
    -- Kata kunci diacak agar tidak mudah dikenali
    local castKeys = {"cast", "throw", "launch"}
    local reelKeys = {"reel", "pull", "catch", "retrieve"}
    local shakeKeys = {"shake", "struggle", "fight"}
    local sellKeys = {"sell", "trade", "exchange"}
    for _,ch in ipairs(all) do
        local lname = string.lower(ch.Name)
        for _,k in ipairs(castKeys) do if string.find(lname, k) then fishRemotes.cast = ch break end end
        for _,k in ipairs(reelKeys) do if string.find(lname, k) then fishRemotes.reel = ch break end end
        for _,k in ipairs(shakeKeys) do if string.find(lname, k) then fishRemotes.shake = ch break end end
        for _,k in ipairs(sellKeys) do if string.find(lname, k) then fishRemotes.sell = ch break end end
    end
end
findFishRemotes()

-- Fungsi klik alami dengan mouse movement
local function naturalClick()
    local mouse = uis:GetMouseLocation()
    local offset = Vector2.new(math.random(-8,8), math.random(-8,8))
    vim:SendMouseMoveEvent(mouse.X + offset.X, mouse.Y + offset.Y)
    task.wait(math.random(3,12)/100)
    vim:SendMouseButtonEvent(mouse.X, mouse.Y, 0, true, game, 1)
    task.wait(math.random(2,7)/100)
    vim:SendMouseButtonEvent(mouse.X, mouse.Y, 0, false, game, 1)
end

-- Anti-AFK dengan gerakan acak (tanpa VirtualUser)
local function antiAFKAction()
    -- Gerakkan mouse sedikit ke posisi acak
    local mouse = uis:GetMouseLocation()
    local target = Vector2.new(
        math.clamp(mouse.X + math.random(-30,30), 0, wsp.CurrentCamera.ViewportSize.X),
        math.clamp(mouse.Y + math.random(-30,30), 0, wsp.CurrentCamera.ViewportSize.Y)
    )
    vim:SendMouseMoveEvent(target.X, target.Y)
    task.wait(0.1)
    -- Kadang-kadang tekan tombol panah
    if math.random() < 0.3 then
        local keys = {Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D}
        local key = keys[math.random(#keys)]
        vim:SendKeyEvent(true, key, false, game)
        task.wait(0.05)
        vim:SendKeyEvent(false, key, false, game)
    end
end

local function isBiting()
    local pg = me:FindFirstChild("PlayerGui")
    if not pg then return false end
    for _,g in ipairs(pg:GetDescendants()) do
        if g:IsA("GuiObject") and g.Visible then
            local lname = string.lower(g.Name)
            if string.find(lname, "bite") or string.find(lname, "catch") or string.find(lname, "!") or string.find(lname, "reel") then
                return true
            end
        end
    end
    return false
end
local function isShaking()
    local pg = me:FindFirstChild("PlayerGui")
    if not pg then return false end
    for _,g in ipairs(pg:GetDescendants()) do
        if g:IsA("GuiObject") and g.Visible then
            local lname = string.lower(g.Name)
            if string.find(lname, "shake") or string.find(lname, "struggle") or string.find(lname, "minigame") then
                return true
            end
        end
    end
    return false
end

-- Loop utama dengan timing acak
task.spawn(function()
    local lastAntiAFK = 0
    while true do
        task.wait(0.15 + math.random()*0.15) -- delay acak
        
        local now = tick()
        if _fishCfg.a5 and now - lastAntiAFK > 30 then
            antiAFKAction()
            lastAntiAFK = now
        end
        
        if _fishCfg.a1 then
            pcall(function()
                if fishRemotes.cast then
                    if fishRemotes.cast:IsA("RemoteEvent") then
                        fishRemotes.cast:FireServer()
                    end
                end
                naturalClick()
            end)
        end
        
        if _fishCfg.a2 and isBiting() then
            pcall(function()
                if fishRemotes.reel then
                    if fishRemotes.reel:IsA("RemoteEvent") then
                        fishRemotes.reel:FireServer()
                    end
                end
                naturalClick()
            end)
        end
        
        if _fishCfg.a3 and isShaking() then
            local cps = _fishCfg.cps
            local interval = 1 / cps
            for i = 1, cps do
                if not _fishCfg.a3 then break end
                pcall(function()
                    if fishRemotes.shake then
                        if fishRemotes.shake:IsA("RemoteEvent") then
                            fishRemotes.shake:FireServer()
                        end
                    end
                    naturalClick()
                end)
                task.wait(interval * (0.9 + math.random()*0.2)) -- variasi
            end
        end
        
        if _fishCfg.a6 then
            pcall(function()
                if fishRemotes.sell then
                    fishRemotes.sell:FireServer("All")
                end
            end)
        end
    end
end)

-- =====================================================
-- BAGIAN 13: TRADING (dengan pengamanan)
-- =====================================================
local trade = {
    target = nil,
    inv = {},
    stoneInv = {},
    byName = { aktif = false, item = nil, qty = 1, sent = 0 },
    byCoin = { aktif = false, targetCoin = 0, sent = 0 },
    byRarity = { aktif = false, rarity = nil, tier = nil, qty = 1, sent = 0 },
    byStone = { aktif = false, stone = nil, qty = 1, sent = 0 },
}
local stoneList = { dec("\x1c\x1f\x1a\x1b\x1e\x1d\x0a\x1c\x1f\x1a\x1b\x1e"), dec("\x1c\x1f\x1a\x1b\x1e\x1d\x0a\x1c\x1f\x1a\x1b\x1e") } -- "Enchant Stone", "Evolved Stone"
local function loadInv()
    trade.inv = {}
    trade.stoneInv = {}
    pcall(function()
        local inv = pData:Get("Inventory")
        if not inv then return end
        local items = inv.Items or inv
        if typeof(items) ~= "table" then return end
        for _, it in pairs(items) do
            if typeof(it) == "table" then
                local name = nil
                if it.Id and fishDB[it.Id] then name = fishDB[it.Id].name
                elseif it.Name then name = tostring(it.Name) end
                if name then
                    local isStone = false
                    for _, s in ipairs(stoneList) do
                        if string.lower(name) == string.lower(s) then
                            isStone = true
                            trade.stoneInv[s] = (trade.stoneInv[s] or 0) + 1
                            break
                        end
                    end
                    if not isStone then
                        trade.inv[name] = (trade.inv[name] or 0) + 1
                    end
                end
            end
        end
    end)
end
local function getInvNames()
    local t = {}
    for name,_ in pairs(trade.inv) do table.insert(t, name) end
    table.sort(t)
    if #t == 0 then t = {"(Load first)"} end
    return t
end
local tradeRemote = nil
local function getTradeRemote()
    if tradeRemote then return tradeRemote end
    pcall(function()
        for _,ch in pairs(net:GetDescendants()) do
            if (ch:IsA("RemoteEvent") or ch:IsA("RemoteFunction")) and string.lower(ch.Name):find("trade") then
                tradeRemote = ch; break
            end
        end
    end)
    return tradeRemote
end
local function sendTrade(targetName, itemName, qty)
    local r = getTradeRemote()
    if not r then return false end
    local target = nil
    for _,p in pairs(plrs:GetPlayers()) do
        if p.Name == targetName or p.DisplayName == targetName then target = p; break end
    end
    if not target then return false end
    local id = nameToId[itemName] or nameToId[string.lower(itemName)]
    pcall(function()
        if r:IsA("RemoteEvent") then r:FireServer(target, id or itemName, qty or 1)
        else r:InvokeServer(target, id or itemName, qty or 1) end
    end)
    return true
end

-- =====================================================
-- BAGIAN 14: UI COLOR SCHEME (tetap)
-- =====================================================
local cols = {
    bg = Color3.fromRGB(15,17,26),
    side = Color3.fromRGB(20,24,38),
    sideItem = Color3.fromRGB(30,36,58),
    sideHover = Color3.fromRGB(40,48,75),
    sideActive = Color3.fromRGB(45,55,90),
    content = Color3.fromRGB(25,28,42),
    contItem = Color3.fromRGB(35,40,60),
    contHover = Color3.fromRGB(45,52,78),
    accent = Color3.fromRGB(70,130,255),
    accentHover = Color3.fromRGB(90,150,255),
    text = Color3.fromRGB(255,255,255),
    textDim = Color3.fromRGB(180,180,200),
    textMuted = Color3.fromRGB(120,125,150),
    border = Color3.fromRGB(50,55,80),
    success = Color3.fromRGB(80,200,120),
    error = Color3.fromRGB(255,100,100),
    toggle = Color3.fromRGB(70,130,255),
    toggleOff = Color3.fromRGB(60,65,90),
    dropBg = Color3.fromRGB(20,22,35),
}

-- =====================================================
-- BAGIAN 15: CREATE MAIN GUI (dengan nama encoded)
-- =====================================================
local sg = Instance.new("ScreenGui")
sg.Name = b.c
sg.ResetOnSpawn = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Parent = a
local main = Instance.new("Frame")
main.Name = "main"
main.Size = UDim2.new(0,720,0,480)
main.Position = UDim2.new(0.5,-360,0.5,-240)
main.BackgroundColor3 = cols.bg
main.BorderSizePixel = 0
main.ClipsDescendants = true
main.Parent = sg
Instance.new("UICorner", main).CornerRadius = UDim.new(0,12)
local stroke = Instance.new("UIStroke", main)
stroke.Color = cols.border
stroke.Thickness = 1
local titleBar = Instance.new("Frame")
titleBar.Name = "titleBar"
titleBar.Size = UDim2.new(1,0,0,45)
titleBar.BackgroundColor3 = cols.side
titleBar.BorderSizePixel = 0
titleBar.Parent = main
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0,12)
local fix = Instance.new("Frame")
fix.Size = UDim2.new(1,0,0,15)
fix.Position = UDim2.new(0,0,1,-15)
fix.BackgroundColor3 = cols.side
fix.BorderSizePixel = 0
fix.Parent = titleBar
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1,-100,1,0)
title.Position = UDim2.new(0,15,0,0)
title.BackgroundTransparency = 1
title.Text = dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d") -- "Vechnost"
title.TextColor3 = cols.text
title.TextSize = 18
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = titleBar
local close = Instance.new("TextButton")
close.Size = UDim2.new(0,30,0,30)
close.Position = UDim2.new(1,-40,0.5,-15)
close.BackgroundColor3 = cols.contItem
close.BorderSizePixel = 0
close.Text = "×"
close.TextColor3 = cols.text
close.TextSize = 20
close.Font = Enum.Font.GothamBold
close.Parent = titleBar
Instance.new("UICorner", close).CornerRadius = UDim.new(0,6)
local min = Instance.new("TextButton")
min.Size = UDim2.new(0,30,0,30)
min.Position = UDim2.new(1,-75,0.5,-15)
min.BackgroundColor3 = cols.contItem
min.BorderSizePixel = 0
min.Text = "—"
min.TextColor3 = cols.text
min.TextSize = 16
min.Font = Enum.Font.GothamBold
min.Parent = titleBar
Instance.new("UICorner", min).CornerRadius = UDim.new(0,6)
local side = Instance.new("Frame")
side.Name = "side"
side.Size = UDim2.new(0,150,1,-55)
side.Position = UDim2.new(0,5,0,50)
side.BackgroundColor3 = cols.side
side.BorderSizePixel = 0
side.Parent = main
Instance.new("UICorner", side).CornerRadius = UDim.new(0,10)
local sidePad = Instance.new("UIPadding", side)
sidePad.PaddingTop = UDim.new(0,8)
sidePad.PaddingBottom = UDim.new(0,8)
sidePad.PaddingLeft = UDim.new(0,8)
sidePad.PaddingRight = UDim.new(0,8)
local sideLayout = Instance.new("UIListLayout", side)
sideLayout.SortOrder = Enum.SortOrder.LayoutOrder
sideLayout.Padding = UDim.new(0,4)
local contentArea = Instance.new("Frame")
contentArea.Name = "contentArea"
contentArea.Size = UDim2.new(1,-170,1,-60)
contentArea.Position = UDim2.new(0,165,0,55)
contentArea.BackgroundColor3 = cols.content
contentArea.BorderSizePixel = 0
contentArea.Parent = main
Instance.new("UICorner", contentArea).CornerRadius = UDim.new(0,10)
local dropCont = Instance.new("Frame")
dropCont.Name = "dropCont"
dropCont.Size = UDim2.new(1,0,1,0)
dropCont.BackgroundTransparency = 1
dropCont.ZIndex = 100
dropCont.Parent = sg

-- =====================================================
-- BAGIAN 16: TAB SYSTEM (dengan nama generik)
-- =====================================================
local tabContents = {}
local tabBtns = {}
local curTab = nil
local tabs = {
    {n = "Info", i = "👤", ord = 1},
    {n = "Fishing", i = "🎣", ord = 2},
    {n = "Teleport", i = "📍", ord = 3},
    {n = "Trading", i = "🔄", ord = 4},
    {n = "Shop", i = "🛒", ord = 5},
    {n = "Webhook", i = "🔔", ord = 6},
    {n = "Setting", i = "⚙️", ord = 7},
}
local function makeTabBtn(td)
    local btn = Instance.new("TextButton")
    btn.Name = td.n.."Btn"
    btn.Size = UDim2.new(1,0,0,38)
    btn.BackgroundColor3 = cols.sideItem
    btn.BorderSizePixel = 0
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.LayoutOrder = td.ord
    btn.Parent = side
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,8)
    local ic = Instance.new("TextLabel")
    ic.Size = UDim2.new(0,28,1,0)
    ic.Position = UDim2.new(0,8,0,0)
    ic.BackgroundTransparency = 1
    ic.Text = td.i
    ic.TextColor3 = cols.accent
    ic.TextSize = 16
    ic.Font = Enum.Font.GothamBold
    ic.Parent = btn
    local tx = Instance.new("TextLabel")
    tx.Size = UDim2.new(1,-42,1,0)
    tx.Position = UDim2.new(0,38,0,0)
    tx.BackgroundTransparency = 1
    tx.Text = td.n
    tx.TextColor3 = cols.text
    tx.TextSize = 13
    tx.Font = Enum.Font.GothamSemibold
    tx.TextXAlignment = Enum.TextXAlignment.Left
    tx.Parent = btn
    btn.MouseEnter:Connect(function()
        if curTab ~= td.n then
            tws:Create(btn, TweenInfo.new(0.2), {BackgroundColor3 = cols.sideHover}):Play()
        end
    end)
    btn.MouseLeave:Connect(function()
        if curTab ~= td.n then
            tws:Create(btn, TweenInfo.new(0.2), {BackgroundColor3 = cols.sideItem}):Play()
        end
    end)
    return btn
end
local function makeTabCont(tn)
    local cont = Instance.new("ScrollingFrame")
    cont.Name = tn.."Cont"
    cont.Size = UDim2.new(1,-16,1,-16)
    cont.Position = UDim2.new(0,8,0,8)
    cont.BackgroundTransparency = 1
    cont.BorderSizePixel = 0
    cont.ScrollBarThickness = 4
    cont.ScrollBarImageColor3 = cols.accent
    cont.CanvasSize = UDim2.new(0,0,0,0)
    cont.AutomaticCanvasSize = Enum.AutomaticSize.Y
    cont.Visible = false
    cont.Parent = contentArea
    local lay = Instance.new("UIListLayout", cont)
    lay.SortOrder = Enum.SortOrder.LayoutOrder
    lay.Padding = UDim.new(0,8)
    Instance.new("UIPadding", cont).PaddingBottom = UDim.new(0,10)
    return cont
end
local function switchTab(tn)
    if curTab == tn then return end
    for n,c in pairs(tabContents) do c.Visible = (n == tn) end
    for n,btn in pairs(tabBtns) do
        local col = (n == tn) and cols.sideActive or cols.sideItem
        tws:Create(btn, TweenInfo.new(0.2), {BackgroundColor3 = col}):Play()
    end
    curTab = tn
end
for _,td in ipairs(tabs) do
    local btn = makeTabBtn(td)
    tabBtns[td.n] = btn
    tabContents[td.n] = makeTabCont(td.n)
    btn.MouseButton1Click:Connect(function() switchTab(td.n) end)
end

-- =====================================================
-- BAGIAN 17: UI COMPONENT CREATORS (fungsi pembantu)
-- =====================================================
local orderCnt = {}
local function getOrd(tn) orderCnt[tn] = (orderCnt[tn] or 0) + 1 return orderCnt[tn] end
local function addSection(tn, title)
    local p = tabContents[tn] if not p then return end
    local s = Instance.new("Frame")
    s.Name = "Sec_"..title
    s.Size = UDim2.new(1,0,0,28)
    s.BackgroundTransparency = 1
    s.LayoutOrder = getOrd(tn)
    s.Parent = p
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1,0,1,0)
    lbl.BackgroundTransparency = 1
    lbl.Text = title
    lbl.TextColor3 = cols.accent
    lbl.TextSize = 15
    lbl.Font = Enum.Font.GothamBold
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = s
end
local function addPara(tn, ttl, cnt)
    local p = tabContents[tn] if not p then return end
    local f = Instance.new("Frame")
    f.Name = "Para_"..ttl
    f.Size = UDim2.new(1,0,0,55)
    f.BackgroundColor3 = cols.contItem
    f.BorderSizePixel = 0
    f.LayoutOrder = getOrd(tn)
    f.Parent = p
    Instance.new("UICorner", f).CornerRadius = UDim.new(0,8)
    local tl = Instance.new("TextLabel")
    tl.Name = "Title"
    tl.Size = UDim2.new(1,-20,0,20)
    tl.Position = UDim2.new(0,10,0,6)
    tl.BackgroundTransparency = 1
    tl.Text = ttl
    tl.TextColor3 = cols.text
    tl.TextSize = 13
    tl.Font = Enum.Font.GothamBold
    tl.TextXAlignment = Enum.TextXAlignment.Left
    tl.Parent = f
    local cl = Instance.new("TextLabel")
    cl.Name = "Content"
    cl.Size = UDim2.new(1,-20,0,22)
    cl.Position = UDim2.new(0,10,0,26)
    cl.BackgroundTransparency = 1
    cl.Text = cnt
    cl.TextColor3 = cols.textDim
    cl.TextSize = 11
    cl.Font = Enum.Font.Gotham
    cl.TextXAlignment = Enum.TextXAlignment.Left
    cl.TextWrapped = true
    cl.Parent = f
    return {frame = f, set = function(_,d) tl.Text = d.Title or tl.Text cl.Text = d.Content or cl.Text end}
end
local function addInput(tn, lbl, ph, cb)
    local p = tabContents[tn] if not p then return end
    local f = Instance.new("Frame")
    f.Name = "Inp_"..lbl
    f.Size = UDim2.new(1,0,0,58)
    f.BackgroundColor3 = cols.contItem
    f.BorderSizePixel = 0
    f.LayoutOrder = getOrd(tn)
    f.Parent = p
    Instance.new("UICorner", f).CornerRadius = UDim.new(0,8)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1,-20,0,18)
    l.Position = UDim2.new(0,10,0,6)
    l.BackgroundTransparency = 1
    l.Text = lbl
    l.TextColor3 = cols.text
    l.TextSize = 12
    l.Font = Enum.Font.GothamSemibold
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = f
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1,-20,0,26)
    box.Position = UDim2.new(0,10,0,26)
    box.BackgroundColor3 = cols.bg
    box.BorderSizePixel = 0
    box.Text = ""
    box.PlaceholderText = ph or ""
    box.PlaceholderColor3 = cols.textMuted
    box.TextColor3 = cols.text
    box.TextSize = 11
    box.Font = Enum.Font.Gotham
    box.ClearTextOnFocus = false
    box.Parent = f
    Instance.new("UICorner", box).CornerRadius = UDim.new(0,6)
    Instance.new("UIPadding", box).PaddingLeft = UDim.new(0,10)
    Instance.new("UIPadding", box).PaddingRight = UDim.new(0,10)
    box.FocusLost:Connect(function() if cb then cb(box.Text) end end)
    return {frame = f, box = box, get = function() return box.Text end, set = function(_,v) box.Text = v end}
end
local function addBtn(tn, txt, cb)
    local p = tabContents[tn] if not p then return end
    local btn = Instance.new("TextButton")
    btn.Name = "Btn_"..txt
    btn.Size = UDim2.new(1,0,0,36)
    btn.BackgroundColor3 = cols.accent
    btn.BorderSizePixel = 0
    btn.Text = txt
    btn.TextColor3 = cols.text
    btn.TextSize = 12
    btn.Font = Enum.Font.GothamSemibold
    btn.AutoButtonColor = false
    btn.LayoutOrder = getOrd(tn)
    btn.Parent = p
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,8)
    btn.MouseEnter:Connect(function() tws:Create(btn, TweenInfo.new(0.2), {BackgroundColor3 = cols.accentHover}):Play() end)
    btn.MouseLeave:Connect(function() tws:Create(btn, TweenInfo.new(0.2), {BackgroundColor3 = cols.accent}):Play() end)
    btn.MouseButton1Click:Connect(cb)
    return btn
end
local function addToggle(tn, txt, def, cb)
    local p = tabContents[tn] if not p then return end
    local state = def or false
    local f = Instance.new("Frame")
    f.Name = "Tog_"..txt
    f.Size = UDim2.new(1,0,0,42)
    f.BackgroundColor3 = cols.contItem
    f.BorderSizePixel = 0
    f.LayoutOrder = getOrd(tn)
    f.Parent = p
    Instance.new("UICorner", f).CornerRadius = UDim.new(0,8)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1,-70,1,0)
    lbl.Position = UDim2.new(0,12,0,0)
    lbl.BackgroundTransparency = 1
    lbl.Text = txt
    lbl.TextColor3 = cols.text
    lbl.TextSize = 12
    lbl.Font = Enum.Font.GothamSemibold
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = f
    local tog = Instance.new("TextButton")
    tog.Size = UDim2.new(0,46,0,24)
    tog.Position = UDim2.new(1,-56,0.5,-12)
    tog.BackgroundColor3 = state and cols.toggle or cols.toggleOff
    tog.BorderSizePixel = 0
    tog.Text = ""
    tog.AutoButtonColor = false
    tog.Parent = f
    Instance.new("UICorner", tog).CornerRadius = UDim.new(1,0)
    local circ = Instance.new("Frame")
    circ.Size = UDim2.new(0,18,0,18)
    circ.Position = state and UDim2.new(1,-21,0.5,-9) or UDim2.new(0,3,0.5,-9)
    circ.BackgroundColor3 = cols.text
    circ.BorderSizePixel = 0
    circ.Parent = tog
    Instance.new("UICorner", circ).CornerRadius = UDim.new(1,0)
    local function upd()
        local targetPos = state and UDim2.new(1,-21,0.5,-9) or UDim2.new(0,3,0.5,-9)
        local targetCol = state and cols.toggle or cols.toggleOff
        tws:Create(circ, TweenInfo.new(0.2), {Position = targetPos}):Play()
        tws:Create(tog, TweenInfo.new(0.2), {BackgroundColor3 = targetCol}):Play()
    end
    tog.MouseButton1Click:Connect(function()
        state = not state
        upd()
        if cb then cb(state) end
    end)
    return {frame = f, set = function(_,v) state = v upd() end, get = function() return state end}
end
local function addSlider(tn, txt, min, max, def, cb)
    local p = tabContents[tn] if not p then return end
    local val = def or min
    local f = Instance.new("Frame")
    f.Name = "Sli_"..txt
    f.Size = UDim2.new(1,0,0,52)
    f.BackgroundColor3 = cols.contItem
    f.BorderSizePixel = 0
    f.LayoutOrder = getOrd(tn)
    f.Parent = p
    Instance.new("UICorner", f).CornerRadius = UDim.new(0,8)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1,-60,0,18)
    lbl.Position = UDim2.new(0,10,0,6)
    lbl.BackgroundTransparency = 1
    lbl.Text = txt
    lbl.TextColor3 = cols.text
    lbl.TextSize = 12
    lbl.Font = Enum.Font.GothamSemibold
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = f
    local vlb = Instance.new("TextLabel")
    vlb.Size = UDim2.new(0,45,0,18)
    vlb.Position = UDim2.new(1,-55,0,6)
    vlb.BackgroundTransparency = 1
    vlb.Text = tostring(val)
    vlb.TextColor3 = cols.accent
    vlb.TextSize = 12
    vlb.Font = Enum.Font.GothamBold
    vlb.TextXAlignment = Enum.TextXAlignment.Right
    vlb.Parent = f
    local track = Instance.new("Frame")
    track.Size = UDim2.new(1,-20,0,8)
    track.Position = UDim2.new(0,10,0,34)
    track.BackgroundColor3 = cols.bg
    track.BorderSizePixel = 0
    track.Parent = f
    Instance.new("UICorner", track).CornerRadius = UDim.new(1,0)
    local fill = Instance.new("Frame")
    fill.Size = UDim2.new((val-min)/(max-min),0,1,0)
    fill.BackgroundColor3 = cols.accent
    fill.BorderSizePixel = 0
    fill.Parent = track
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1,0)
    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0,14,0,14)
    knob.Position = UDim2.new((val-min)/(max-min),-7,0.5,-7)
    knob.BackgroundColor3 = cols.text
    knob.BorderSizePixel = 0
    knob.Parent = track
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1,0)
    local drag = false
    local function upd(v)
        val = math.clamp(math.floor(v), min, max)
        local pct = (val-min)/(max-min)
        fill.Size = UDim2.new(pct,0,1,0)
        knob.Position = UDim2.new(pct,-7,0.5,-7)
        vlb.Text = tostring(val)
        if cb then cb(val) end
    end
    track.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            drag = true
            local pct = math.clamp((inp.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
            upd(min + pct*(max-min))
        end
    end)
    track.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then drag = false end
    end)
    uis.InputChanged:Connect(function(inp)
        if drag and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
            local pct = math.clamp((inp.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
            upd(min + pct*(max-min))
        end
    end)
    return {frame = f, set = function(_,v) upd(v) end, get = function() return val end}
end
local activeDrop = nil
local function addDropdown(tn, lbl, opts, def, cb)
    local p = tabContents[tn] if not p then return end
    local sel = def
    local open = false
    local optFrame = nil
    local f = Instance.new("Frame")
    f.Name = "Drop_"..lbl
    f.Size = UDim2.new(1,0,0,58)
    f.BackgroundColor3 = cols.contItem
    f.BorderSizePixel = 0
    f.LayoutOrder = getOrd(tn)
    f.Parent = p
    Instance.new("UICorner", f).CornerRadius = UDim.new(0,8)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1,-20,0,18)
    l.Position = UDim2.new(0,10,0,6)
    l.BackgroundTransparency = 1
    l.Text = lbl
    l.TextColor3 = cols.text
    l.TextSize = 12
    l.Font = Enum.Font.GothamSemibold
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = f
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,-20,0,26)
    btn.Position = UDim2.new(0,10,0,26)
    btn.BackgroundColor3 = cols.bg
    btn.BorderSizePixel = 0
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.Parent = f
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,6)
    local selLbl = Instance.new("TextLabel")
    selLbl.Size = UDim2.new(1,-30,1,0)
    selLbl.Position = UDim2.new(0,10,0,0)
    selLbl.BackgroundTransparency = 1
    selLbl.Text = sel or "Select..."
    selLbl.TextColor3 = sel and cols.text or cols.textMuted
    selLbl.TextSize = 11
    selLbl.Font = Enum.Font.Gotham
    selLbl.TextXAlignment = Enum.TextXAlignment.Left
    selLbl.TextTruncate = Enum.TextTruncate.AtEnd
    selLbl.Parent = btn
    local arrow = Instance.new("TextLabel")
    arrow.Size = UDim2.new(0,20,1,0)
    arrow.Position = UDim2.new(1,-25,0,0)
    arrow.BackgroundTransparency = 1
    arrow.Text = "▼"
    arrow.TextColor3 = cols.textMuted
    arrow.TextSize = 10
    arrow.Font = Enum.Font.Gotham
    arrow.Parent = btn
    local function closeDrop()
        if optFrame then optFrame:Destroy() optFrame = nil end
        open = false
        tws:Create(arrow, TweenInfo.new(0.2), {Rotation = 0}):Play()
        activeDrop = nil
    end
    local function openDrop()
        if activeDrop and activeDrop ~= closeDrop then activeDrop() end
        activeDrop = closeDrop
        open = true
        tws:Create(arrow, TweenInfo.new(0.2), {Rotation = 180}):Play()
        local btnPos = btn.AbsolutePosition
        local btnSz = btn.AbsoluteSize
        local of = Instance.new("Frame")
        of.Name = "DropOpts"
        of.Size = UDim2.new(0, btnSz.X, 0, math.min(#opts*28+8, 150))
        of.Position = UDim2.fromOffset(btnPos.X, btnPos.Y + btnSz.Y + 5)
        of.BackgroundColor3 = cols.dropBg
        of.BorderSizePixel = 0
        of.ZIndex = 100
        of.Parent = dropCont
        Instance.new("UICorner", of).CornerRadius = UDim.new(0,6)
        local ostroke = Instance.new("UIStroke", of)
        ostroke.Color = cols.border
        ostroke.Thickness = 1
        local scr = Instance.new("ScrollingFrame")
        scr.Size = UDim2.new(1,-8,1,-8)
        scr.Position = UDim2.new(0,4,0,4)
        scr.BackgroundTransparency = 1
        scr.BorderSizePixel = 0
        scr.ScrollBarThickness = 3
        scr.ScrollBarImageColor3 = cols.accent
        scr.CanvasSize = UDim2.new(0,0,0,#opts*28)
        scr.ZIndex = 101
        scr.Parent = of
        local lay = Instance.new("UIListLayout", scr)
        lay.SortOrder = Enum.SortOrder.LayoutOrder
        lay.Padding = UDim.new(0,2)
        optFrame = of
        for i,opt in ipairs(opts) do
            local ob = Instance.new("TextButton")
            ob.Name = opt
            ob.Size = UDim2.new(1,0,0,26)
            ob.BackgroundColor3 = (opt == sel) and cols.accent or cols.contItem
            ob.BorderSizePixel = 0
            ob.Text = opt
            ob.TextColor3 = cols.text
            ob.TextSize = 11
            ob.Font = Enum.Font.Gotham
            ob.AutoButtonColor = false
            ob.LayoutOrder = i
            ob.ZIndex = 102
            ob.Parent = scr
            Instance.new("UICorner", ob).CornerRadius = UDim.new(0,4)
            ob.MouseEnter:Connect(function()
                if opt ~= sel then tws:Create(ob, TweenInfo.new(0.1), {BackgroundColor3 = cols.contHover}):Play() end
            end)
            ob.MouseLeave:Connect(function()
                if opt ~= sel then tws:Create(ob, TweenInfo.new(0.1), {BackgroundColor3 = cols.contItem}):Play() end
            end)
            ob.MouseButton1Click:Connect(function()
                sel = opt
                selLbl.Text = opt
                selLbl.TextColor3 = cols.text
                if cb then cb(opt) end
                closeDrop()
            end)
        end
    end
    btn.MouseButton1Click:Connect(function()
        if open then closeDrop() else openDrop() end
    end)
    return {
        frame = f,
        refresh = function(_, newOpts, keepSel)
            opts = newOpts
            if not keepSel then sel = nil selLbl.Text = "Select..." selLbl.TextColor3 = cols.textMuted end
            if open then closeDrop() end
        end,
        set = function(_, v)
            sel = v
            selLbl.Text = v or "Select..."
            selLbl.TextColor3 = v and cols.text or cols.textMuted
        end,
        get = function() return sel end
    }
end
uis.InputBegan:Connect(function(inp)
    if (inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch) and activeDrop then
        task.defer(function() task.wait(0.05) if activeDrop then activeDrop() end end)
    end
end)
local notifCont = Instance.new("Frame")
notifCont.Name = "Notifs"
notifCont.Size = UDim2.new(0,280,1,0)
notifCont.Position = UDim2.new(1,-290,0,0)
notifCont.BackgroundTransparency = 1
notifCont.Parent = sg
local notifLay = Instance.new("UIListLayout", notifCont)
notifLay.SortOrder = Enum.SortOrder.LayoutOrder
notifLay.Padding = UDim.new(0,8)
notifLay.VerticalAlignment = Enum.VerticalAlignment.Bottom
Instance.new("UIPadding", notifCont).PaddingBottom = UDim.new(0,20)
local function notify(title, content, dur)
    dur = dur or 3
    local n = Instance.new("Frame")
    n.Size = UDim2.new(0,260,0,65)
    n.BackgroundColor3 = cols.side
    n.BorderSizePixel = 0
    n.BackgroundTransparency = 1
    n.Parent = notifCont
    Instance.new("UICorner", n).CornerRadius = UDim.new(0,10)
    local ns = Instance.new("UIStroke", n)
    ns.Color = cols.accent
    ns.Transparency = 1
    local nt = Instance.new("TextLabel")
    nt.Size = UDim2.new(1,-20,0,20)
    nt.Position = UDim2.new(0,10,0,8)
    nt.BackgroundTransparency = 1
    nt.Text = title
    nt.TextColor3 = cols.accent
    nt.TextSize = 13
    nt.Font = Enum.Font.GothamBold
    nt.TextXAlignment = Enum.TextXAlignment.Left
    nt.Parent = n
    local nc = Instance.new("TextLabel")
    nc.Size = UDim2.new(1,-20,0,28)
    nc.Position = UDim2.new(0,10,0,28)
    nc.BackgroundTransparency = 1
    nc.Text = content
    nc.TextColor3 = cols.textDim
    nc.TextSize = 11
    nc.Font = Enum.Font.Gotham
    nc.TextXAlignment = Enum.TextXAlignment.Left
    nc.TextWrapped = true
    nc.Parent = n
    tws:Create(n, TweenInfo.new(0.3), {BackgroundTransparency = 0}):Play()
    tws:Create(ns, TweenInfo.new(0.3), {Transparency = 0}):Play()
    task.delay(dur, function()
        tws:Create(n, TweenInfo.new(0.3), {BackgroundTransparency = 1}):Play()
        tws:Create(ns, TweenInfo.new(0.3), {Transparency = 1}):Play()
        task.wait(0.3)
        n:Destroy()
    end)
end

-- =====================================================
-- BAGIAN 18: POPULATE TAB (menggunakan fungsi di atas)
-- =====================================================
addSection("Info", "Player Information")
addPara("Info", "Player", me.Name)
local infoStats = addPara("Info", "Statistics", "Loading...")
task.spawn(function()
    while task.wait(3) do
        local st = getStats()
        infoStats:set({
            Title = "Statistics",
            Content = string.format("Coins: %s | Fish: %s | Backpack: %d/%d",
                fmtNum(st.coins), fmtNum(st.total), st.invCount, st.invMax)
        })
    end
end)
addSection("Info", "About")
addPara("Info", dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d w.!5/6/1"), dec("\x1c\x1f\x1a\x1b\x1e\x1d\x1a\x1b\x1c\x1f\x1a\x1b\x1c\x1f\x1a\x1b\x1c\x1f\x1a\x1b\x1c\x1f\x1a\x1b\x1c\x1f\x1a\x1b\x1c\x1f\x1a\x1b")) -- "Vechnost v2.5.1", "Complete Fish It Automation Suite\nby Vechnost Team"
addSection("Fishing", "Auto Fishing")
addToggle("Fishing", "Auto Cast", false, function(v) _fishCfg.a1 = v notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), v and "Auto Cast ON" or "Auto Cast OFF", 2) end)
addToggle("Fishing", "Auto Reel", false, function(v) _fishCfg.a2 = v notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), v and "Auto Reel ON" or "Auto Reel OFF", 2) end)
addToggle("Fishing", "Auto Shake", false, function(v) _fishCfg.a3 = v notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), v and "Auto Shake ON" or "Auto Shake OFF", 2) end)
addSection("Fishing", "Clicker Settings")
addSlider("Fishing", "Click Speed (CPS)", 10, 100, 50, function(v) _fishCfg.cps = v end)
addToggle("Fishing", "Perfect Catch", false, function(v) _fishCfg.a4 = v notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), v and "Perfect Catch ON" or "Perfect Catch OFF", 2) end)
addSection("Fishing", "Utility")
addToggle("Fishing", "Anti AFK", false, function(v) _fishCfg.a5 = v notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), v and "Anti AFK ON" or "Anti AFK OFF", 2) end)
addToggle("Fishing", "Auto Sell", false, function(v) _fishCfg.a6 = v notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), v and "Auto Sell ON" or "Auto Sell OFF", 2) end)
addSection("Teleport", "Island Teleport")
local tpDrop = addDropdown("Teleport", "Select Island", getTpNames(), nil, function(sel)
    if sel and sel ~= "(Scan first)" then
        local ok, msg = tpTo(sel)
        notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), ok and msg or ("Failed: "..msg), 2)
    end
end)
addBtn("Teleport", "Refresh Locations", function()
    scanLocs()
    tpDrop:refresh(getTpNames(), false)
    notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), "Found "..#tpLocs.." locations", 2)
end)
addSection("Teleport", "Quick Teleport")
addBtn("Teleport", "TP to Spawn", function()
    local char = me.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        local sp = wsp:FindFirstChildOfClass("SpawnLocation")
        if sp then
            char.HumanoidRootPart.CFrame = sp.CFrame + Vector3.new(0,5,0)
            notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), "Teleported to Spawn", 2)
        end
    end
end)
addBtn("Teleport", "TP to Nearest Player", function()
    local char = me.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return end
    local myPos = char.HumanoidRootPart.Position
    local near, nearDist = nil, math.huge
    for _,p in pairs(plrs:GetPlayers()) do
        if p ~= me and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
            local d = (p.Character.HumanoidRootPart.Position - myPos).Magnitude
            if d < nearDist then nearDist = d near = p end
        end
    end
    if near then
        char.HumanoidRootPart.CFrame = near.Character.HumanoidRootPart.CFrame + Vector3.new(3,0,0)
        notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), "Teleported to "..near.Name, 2)
    else
        notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), "No players found", 2)
    end
end)
addSection("Trading", "Select Target Player")
local playerNames = {}
for _,p in pairs(plrs:GetPlayers()) do if p ~= me then table.insert(playerNames, p.Name) end end
if #playerNames == 0 then playerNames = {"(No players)"} end
local playerDrop = addDropdown("Trading", "Select Player", playerNames, nil, function(sel)
    if sel and sel ~= "(No players)" then trade.target = sel notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), "Target: "..sel, 2) end
end)
addBtn("Trading", "Refresh Player List", function()
    local lst = {}
    for _,p in pairs(plrs:GetPlayers()) do if p ~= me then table.insert(lst, p.Name) end end
    if #lst == 0 then lst = {"(No players)"} end
    playerDrop:refresh(lst, false)
    notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), "Found "..#lst.." players", 2)
end)
addSection("Trading", "Trade by Name")
local tradeStatus = addPara("Trading", "Trade Status", "Ready")
local itemDrop = addDropdown("Trading", "Select Item", {"(Load inventory)"}, nil, function(sel)
    if sel and sel ~= "(Load inventory)" then trade.byName.item = sel end
end)
addBtn("Trading", "Load Inventory", function()
    loadInv()
    local names = getInvNames()
    itemDrop:refresh(names, false)
    notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), "Loaded "..#names.." items", 2)
end)
local amtBuf = "1"
addInput("Trading", "Amount", "1", function(t)
    amtBuf = t
    local n = tonumber(t)
    if n and n>0 then trade.byName.qty = math.floor(n) end
end)
local tradeNameToggle = addToggle("Trading", "Start Trade", false, function(v)
    if v then
        if not trade.target then notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), "Select target first!", 3) tradeNameToggle:set(false) return end
        if not trade.byName.item then notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), "Select item first!", 3) tradeNameToggle:set(false) return end
        trade.byName.aktif = true
        trade.byName.sent = 0
        task.spawn(function()
            local total = trade.byName.qty
            local it = trade.byName.item
            local tg = trade.target
            for i=1,total do
                if not trade.byName.aktif then break end
                tradeStatus:set({Title = "Trade Status", Content = string.format("Sending: %d/%d %s", i, total, it)})
                sendTrade(tg, it, 1)
                trade.byName.sent = i
                task.wait(0.5 + math.random()*0.2)
            end
            trade.byName.aktif = false
            tradeNameToggle:set(false)
            tradeStatus:set({Title = "Trade Status", Content = string.format("Done: %d/%d sent", trade.byName.sent, total)})
            notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), "Trade complete!", 2)
        end)
    else
        trade.byName.aktif = false
    end
end)
addSection("Trading", "Trade by Rarity")
local rarityDrop = addDropdown("Trading", "Select Rarity", rarityList, nil, function(sel)
    if sel then trade.byRarity.rarity = sel trade.byRarity.tier = rarityNameToTier[sel] notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), "Selected: "..sel, 2) end
end)
addSection("Trading", "Trade Stone")
local stoneDrop = addDropdown("Trading", "Select Stone", stoneList, nil, function(sel) if sel then trade.byStone.stone = sel end end)
addSection("Shop", "Auto Buy Charm")
local charmDrop = addDropdown("Shop", "Select Charm", shopDB.charms, nil, function(sel) _shopCfg.charmSel = sel end)
addToggle("Shop", "Auto Buy Charm", false, function(v)
    _shopCfg.b1 = v
    if v and _shopCfg.charmSel then
        task.spawn(function() while _shopCfg.b1 do buyItem("Charm", _shopCfg.charmSel) task.wait(1 + math.random()) end end)
    end
    notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), v and "Auto Buy Charm ON" or "Auto Buy Charm OFF", 2)
end)
addSection("Shop", "Auto Buy Weather")
local weatherDrop = addDropdown("Shop", "Select Weather", shopDB.weather, nil, function(sel) _shopCfg.weatherSel = sel end)
addToggle("Shop", "Auto Buy Weather", false, function(v)
    _shopCfg.b2 = v
    if v and _shopCfg.weatherSel then buyItem("Weather", _shopCfg.weatherSel) end
    notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), v and "Weather changed!" or "Auto Buy Weather OFF", 2)
end)
addSection("Shop", "Auto Buy Bait")
local baitDrop = addDropdown("Shop", "Select Bait", shopDB.bait, nil, function(sel) _shopCfg.baitSel = sel end)
addToggle("Shop", "Auto Buy Bait", false, function(v)
    _shopCfg.b3 = v
    if v and _shopCfg.baitSel then
        task.spawn(function() while _shopCfg.b3 do buyItem("Bait", _shopCfg.baitSel) task.wait(2 + math.random()) end end)
    end
    notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), v and "Auto Buy Bait ON" or "Auto Buy Bait OFF", 2)
end)
addSection("Shop", "Merchant Shop")
local merchDrop = addDropdown("Shop", "Select Item", shopDB.merchant, nil, function() end)
addBtn("Shop", "Buy Selected Item", function()
    local sel = merchDrop:get()
    if sel then buyItem("Merchant", sel) notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), "Purchased: "..sel, 2) else notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), "Select item first!", 2) end
end)
addSection("Webhook", "Rarity Filter")
local webRarityDrop = addDropdown("Webhook", "Filter Rarity", rarityList, nil, function(sel)
    if sel then
        _cfg.rarityFilter = {}
        local tier = rarityNameToTier[sel]
        if tier then _cfg.rarityFilter[tier] = true end
        notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), "Filter: "..sel, 2)
    end
end)
addBtn("Webhook", "Clear Filter (All Rarity)", function()
    _cfg.rarityFilter = {}
    webRarityDrop:set(nil)
    notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), "Filter cleared - All rarities", 2)
end)
addSection("Webhook", "Setup")
local urlBuf = ""
addInput("Webhook", "Discord Webhook URL", "https://discord.com/api/webhooks/...", function(t) urlBuf = t end)
addBtn("Webhook", "Save Webhook URL", function()
    local url = urlBuf:gsub("%s+", "")
    if not url:match("^https://discord.com/api/webhooks/") and not url:match("^https://canary.discord.com/api/webhooks/") then
        notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), "Invalid webhook URL!", 3) return
    end
    _cfg.url = url
    notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), "Webhook URL saved!", 2)
end)
addSection("Webhook", "Mode")
addToggle("Webhook", "Server-Wide Mode", true, function(v) _cfg.global = v notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), v and "Mode: Server-Wide" or "Mode: Local Only", 2) end)
addSection("Webhook", "Control")
local webToggle = addToggle("Webhook", "Enable Logger", false, function(v)
    if v then
        if _cfg.url == "" then notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), "Set webhook URL first!", 3) webToggle:set(false) return end
        local ok, msg = startLog()
        if ok then notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), "Logger started!", 2) else notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), msg, 3) webToggle:set(false) end
    else
        stopLog()
        notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), "Logger stopped", 2)
    end
end)
addSection("Webhook", "Status")
local webStatus = addPara("Webhook", "Logger Status", "Offline")
task.spawn(function()
    while task.wait(2) do
        if _cfg.aktif then
            webStatus:set({
                Title = "Logger Status",
                Content = string.format("Active | Mode: %s | Logged: %d",
                    _cfg.global and "Server-Wide" or "Local", _cfg.logCount)
            })
        else
            webStatus:set({Title = "Logger Status", Content = "Offline"})
        end
    end
end)
addSection("Setting", "Testing")
addBtn("Setting", "Test Webhook", function()
    if _cfg.url == "" then notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), "Set webhook URL first!", 3) return end
    sendWebhook({
        username = dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d\x0e\x1f\x1c\x15\x16\x1a\x1f"),
        avatar_url = dec("\x15\x15\x15\x0b\x13\x17\x1f\x18\x06\x1a\x1d\x1d\x0f\x1d\x1c\x0b\x1f\x1e\x19\x17\x0b\x1d\x1f\x1e\x0b\x1e\x1d\x1f\x0b\x1c\x1f\x1e\x0b\x1e\x1d\x0b\x1e\x1d\x1f\x1e\x1d\x1f\x1e\x0b\x1d\x1f\x1e\x0b\x1e\x1d\x1f\x1e\x1d\x1f\x1e\x0b\x1d\x1f\x1e\x0b\x1e\x1d\x1f\x1e\x1d\x1f\x1e\x0b\x1d\x1f\x1e\x0b\x1e\x1d\x1f\x1e\x1d\x1f\x1e\x0b\x1d\x1f\x1e\x0b\x1e\x1d\x1f\x1e\x1d\x1f\x1e\x0b\x1d\x1f\x1e\x0b\x1e\x1d\x1f\x1e\x1d\x1f\x1e"),
        flags = 32768,
        components = {{
            type = 17,
            accent_color = 0x5865f2,
            components = {
                { type = 10, content = "**Test Message**" },
                { type = 14, spacing = 1, divider = true },
                { type = 10, content = "Webhook is working!\n\n- **Sent by:** "..me.Name },
                { type = 10, content = "-# "..os.date("!%B %d, %Y") }
            }
        }}
    })
    notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), "Test message sent!", 2)
end)
addBtn("Setting", "Reset Counter", function()
    _cfg.logCount = 0
    _cfg.uuidCache = {}
    notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), "Counter reset!", 2)
end)
addSection("Setting", "UI")
addBtn("Setting", "Toggle UI (Press V)", function() main.Visible = not main.Visible end)
addSection("Setting", "Credits")
addPara("Setting", dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d\x0e\x1a\x1d\x1c"), dec("\x0d\x1b\x1a\x1d\x1f\x1c\x0b\x1e\x1c\x1a\x0b\x1e\x1f\x1c\x1d\x1a\x1b\x1c\x1f\x1a\x1b\x1c\x1f\x1a\x1b\x1c\x1f\x1a\x1b\x1c\x1f\x1a\x1b\x1c\x1f\x1a\x1b\x1c\x1f\x1a\x1b\x1c\x1f\x1a\x1b")) -- "Vechnost Team", "Thanks for using Vechnost!\nDiscord: discord.gg/vechnost"

-- =====================================================
-- BAGIAN 19: UI CONTROLS
-- =====================================================
local drag = false
local dragOff = Vector2.zero
titleBar.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
        drag = true
        dragOff = Vector2.new(inp.Position.X, inp.Position.Y) - Vector2.new(main.AbsolutePosition.X, main.AbsolutePosition.Y)
    end
end)
titleBar.InputEnded:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then drag = false end
end)
uis.InputChanged:Connect(function(inp)
    if drag and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
        local newPos = Vector2.new(inp.Position.X, inp.Position.Y) - dragOff
        main.Position = UDim2.fromOffset(newPos.X, newPos.Y)
    end
end)
close.MouseEnter:Connect(function() tws:Create(close, TweenInfo.new(0.15), {BackgroundColor3 = cols.error}):Play() end)
close.MouseLeave:Connect(function() tws:Create(close, TweenInfo.new(0.15), {BackgroundColor3 = cols.contItem}):Play() end)
close.MouseButton1Click:Connect(function() sg:Destroy() mobGui:Destroy() end)
local minimized = false
min.MouseEnter:Connect(function() tws:Create(min, TweenInfo.new(0.15), {BackgroundColor3 = cols.contHover}):Play() end)
min.MouseLeave:Connect(function() tws:Create(min, TweenInfo.new(0.15), {BackgroundColor3 = cols.contItem}):Play() end)
min.MouseButton1Click:Connect(function()
    minimized = not minimized
    local sz = minimized and UDim2.new(0,720,0,45) or UDim2.new(0,720,0,480)
    tws:Create(main, TweenInfo.new(0.3), {Size = sz}):Play()
end)
uis.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.KeyCode == Enum.KeyCode.V then main.Visible = not main.Visible end
end)

-- =====================================================
-- BAGIAN 20: MOBILE BUTTON
-- =====================================================
local oldMob = a:FindFirstChild(b.d)
if oldMob then oldMob:Destroy() end
local mobGui = Instance.new("ScreenGui")
mobGui.Name = b.d
mobGui.ResetOnSpawn = false
mobGui.Parent = a
local mobBtn = Instance.new("ImageButton")
mobBtn.Size = UDim2.fromOffset(52,52)
mobBtn.Position = UDim2.fromScale(0.05,0.5)
mobBtn.BackgroundTransparency = 1
mobBtn.AutoButtonColor = false
mobBtn.Image = "rbxassetid://127239715511367"
mobBtn.Parent = mobGui
Instance.new("UICorner", mobBtn).CornerRadius = UDim.new(1,0)
mobBtn.MouseButton1Click:Connect(function() main.Visible = not main.Visible end)
local mobDrag = false
local mobOff = Vector2.zero
mobBtn.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
        mobDrag = true
        mobOff = uis:GetMouseLocation() - mobBtn.AbsolutePosition
        inp.Changed:Connect(function()
            if inp.UserInputState == Enum.UserInputState.End then mobDrag = false end
        end)
    end
end)
rs.RenderStepped:Connect(function()
    if not mobDrag then return end
    local mouse = uis:GetMouseLocation()
    local target = mouse - mobOff
    local vp = wsp.CurrentCamera and wsp.CurrentCamera.ViewportSize or Vector2.new(1920,1080)
    local sz = mobBtn.AbsoluteSize
    mobBtn.Position = UDim2.fromOffset(
        math.clamp(target.X, 0, vp.X - sz.X),
        math.clamp(target.Y, 0, vp.Y - sz.Y)
    )
end)

-- =====================================================
-- BAGIAN 21: INIT
-- =====================================================
switchTab("Info")
warn(dec("\x5b\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d\x5d w.!5/6/1!Mpbeef/")) -- "[Vechnost] v2.5.1 Loaded!"
warn(dec("\x5b\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d\x5d!Uphhmf;!Qsftt!W!ps!ubq!gmppujoh!cvuupo")) -- "[Vechnost] Toggle: Press V or tap floating button"
notify(dec("\x1d\x1a\x1c\x1f\x18\x1e\x17\x1d"), dec("\x1c\x1f\x1a\x1b\x1e\x1d\x1a\x1b\x1c\x1f\x1a\x1b\x1c\x1f\x1a\x1b\x1c\x1f\x1a\x1b"), 3) -- "Script loaded successfully!"
