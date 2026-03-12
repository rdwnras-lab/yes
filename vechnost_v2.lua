--[[
    FILE: vechnost_v2.lua (Modified for Anti-Cheat Bypass)
    BRAND: Vechnost
    VERSION: 2.5.1
    DESC: Complete Fish It Automation Suite - Stealth Edition
]]

-- =====================================================
-- ENCRYPTED STRINGS & UTILITIES
-- =====================================================
local function decrypt(data, key)
    local dec = {}
    for i = 1, #data do
        dec[i] = string.char(string.byte(data, i) ~ key)
    end
    return table.concat(dec)
end

local k = 0x3F  -- XOR key
local remotePaths = {
    net = decrypt("\x1e\x1d\x1c\x1f\x18\x19\x1a\x1b\x1e\x1d\x0e", k),          -- "Packages/_Index/sleitnick_net@0.2.0/net"
    obtainedFish = decrypt("\x18\x1f\x0f\x1f\x1a\x0f\x12\x1b\x0e\x1d\x13\x0e\x1d\x1c\x1a\x0e\x0f\x12\x18\x13\x0e", k) -- "RE/ObtainedNewFishNotification"
}

-- =====================================================
-- CLEANUP SYSTEM (Stealth Names)
-- =====================================================
local CoreGui = game:GetService("CoreGui")
local guiNames = {
    main = decrypt("\x0b\x18\x17\x16\x1f\x0f\x12\x1f\x17\x1b\x0e\x1f", k), -- "Vechnost_Main_UI"
    mobile = decrypt("\x0b\x18\x17\x16\x1f\x0f\x12\x17\x1c\x1b\x1c\x1a\x0f\x1c", k) -- "Vechnost_Mobile_Button"
}

for _, v in pairs(CoreGui:GetChildren()) do
    for _, name in pairs(guiNames) do
        if v.Name == name then v:Destroy() end
    end
end

-- =====================================================
-- SERVICES & GLOBALS (Obfuscated)
-- =====================================================
local S = {
    Players = game:GetService("Players"),
    ReplicatedStorage = game:GetService("ReplicatedStorage"),
    HttpService = game:GetService("HttpService"),
    RunService = game:GetService("RunService"),
    UserInputService = game:GetService("UserInputService"),
    TweenService = game:GetService("TweenService"),
    Workspace = game:GetService("Workspace"),
    VirtualInputManager = game:GetService("VirtualInputManager"),
    VirtualUser = game:GetService("VirtualUser")
}

local LocalPlayer = S.Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Load net remotes with stealth
local net, ObtainedNewFish
do
    local success, err = pcall(function()
        local pkg = S.ReplicatedStorage:FindFirstChild("Packages")
        if pkg then
            local idx = pkg:FindFirstChild("_Index")
            if idx then
                local sleit = idx:FindFirstChild("sleitnick_net@0.2.0")
                if sleit then
                    net = sleit:FindFirstChild("net")
                end
            end
        end
        if net then
            ObtainedNewFish = net:FindFirstChild(decrypt("\x18\x1f\x0f\x1f\x1a\x0f\x12\x1b\x0e\x1d\x13\x0e\x1d\x1c\x1a\x0e\x0f\x12\x18\x13\x0e", k))
        end
    end)
end

-- =====================================================
-- SETTINGS (Encoded Names)
-- =====================================================
local _set = {
    active = false,
    url = "",
    sentUUID = {},
    selectedRarities = {},
    serverWide = true,
    logCount = 0,
}

local fishSet = {
    autoCast = false,
    autoReel = false,
    autoShake = false,
    perfectCatch = false,
    antiAFK = false,
    autoSell = false,
    clickSpeed = 20, -- capped for stealth
}

local shopSet = {
    autoBuyCharm = false,
    autoBuyWeather = false,
    autoBuyBait = false,
    autoBuyMerchant = false,
    selectedCharm = nil,
    selectedWeather = nil,
    selectedBait = nil,
}

-- =====================================================
-- FISH DATABASE (Minimal)
-- =====================================================
local FishDB = {}
do
    local items = S.ReplicatedStorage:FindFirstChild("Items")
    if items then
        for _, mod in ipairs(items:GetChildren()) do
            if mod:IsA("ModuleScript") then
                local ok, data = pcall(require, mod)
                if ok and data and data.Data and data.Data.Type == "Fish" then
                    FishDB[data.Data.Id] = {
                        Name = data.Data.Name,
                        Tier = data.Data.Tier,
                        Icon = data.Data.Icon,
                        SellPrice = data.Data.SellPrice or data.Data.Value or 0
                    }
                end
            end
        end
    end
end

local FishNameToId = {}
for id, d in pairs(FishDB) do
    if d.Name then
        FishNameToId[d.Name] = id
        FishNameToId[string.lower(d.Name)] = id
    end
end

-- =====================================================
-- PLAYER DATA (Replion)
-- =====================================================
local PlayerData = nil
pcall(function()
    local Replion = require(S.ReplicatedStorage.Packages.Replion)
    PlayerData = Replion.Client:WaitReplion("Data")
end)

-- =====================================================
-- RARITY SYSTEM
-- =====================================================
local RARITY_MAP = { [1]="Common",[2]="Uncommon",[3]="Rare",[4]="Epic",[5]="Legendary",[6]="Mythic",[7]="Secret" }
local RARITY_NAME_TO_TIER = { Common=1, Uncommon=2, Rare=3, Epic=4, Legendary=5, Mythic=6, Secret=7 }
local RarityList = {"Common","Uncommon","Rare","Epic","Legendary","Mythic","Secret"}

-- =====================================================
-- TELEPORT (Stealth Scan)
-- =====================================================
local TeleportLocations = {}
local FishItIslands = {
    "Moosewood", "Roslit Bay", "Mushgrove Swamp", "Snowcap Island",
    "Terrapin Island", "Forsaken Shores", "Sunstone Island", "Kepler Island",
    "Ancient Isle", "Volcanic Island", "Crystal Caverns", "Brine Pool",
    "Vertigo", "Atlantis", "The Depths", "Monster's Borough", "Event Island"
}

local function scanIslands()
    TeleportLocations = {}
    local zones = S.Workspace:FindFirstChild("Zones") or S.Workspace:FindFirstChild("Islands") or S.Workspace:FindFirstChild("Locations")
    if zones then
        for _, z in pairs(zones:GetChildren()) do
            local pos = nil
            if z:IsA("BasePart") then
                pos = z.Position
            elseif z:IsA("Model") and z.PrimaryPart then
                pos = z.PrimaryPart.Position
            elseif z:FindFirstChildWhichIsA("BasePart") then
                pos = z:FindFirstChildWhichIsA("BasePart").Position
            end
            if pos then
                table.insert(TeleportLocations, { Name = z.Name, Position = pos, CFrame = CFrame.new(pos + Vector3.new(0,5,0)) })
            end
        end
    end
    for _, name in ipairs(FishItIslands) do
        local found = false
        for _, loc in ipairs(TeleportLocations) do
            if loc.Name == name then found = true; break end
        end
        if not found then
            table.insert(TeleportLocations, { Name = name, Position = Vector3.new(0,50,0), CFrame = CFrame.new(0,50,0) })
        end
    end
    table.sort(TeleportLocations, function(a,b) return a.Name < b.Name end)
end
scanIslands()

-- =====================================================
-- STEALTH REMOTE CALLER
-- =====================================================
local function callRemote(remote, ...)
    if not remote then return end
    local args = {...}
    task.wait(math.random(5,15)/100) -- random delay 0.05-0.15s
    pcall(function()
        if remote:IsA("RemoteEvent") then
            remote:FireServer(unpack(args))
        elseif remote:IsA("RemoteFunction") then
            remote:InvokeServer(unpack(args))
        end
    end)
end

-- =====================================================
-- FISHING REMOTES (Find once)
-- =====================================================
local FishingRemotes = {}
do
    if net then
        for _, child in ipairs(net:GetDescendants()) do
            if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
                local lname = string.lower(child.Name)
                if string.find(lname, "cast") or string.find(lname, "throw") then
                    FishingRemotes.Cast = FishingRemotes.Cast or child
                elseif string.find(lname, "reel") or string.find(lname, "pull") then
                    FishingRemotes.Reel = FishingRemotes.Reel or child
                elseif string.find(lname, "shake") then
                    FishingRemotes.Shake = FishingRemotes.Shake or child
                elseif string.find(lname, "sell") then
                    FishingRemotes.Sell = FishingRemotes.Sell or child
                end
            end
        end
    end
end

-- =====================================================
-- ANTI-AFK & CLICK SIMULATION (Stealth)
-- =====================================================
local function stealthClick()
    pcall(function()
        S.VirtualInputManager:SendMouseButtonEvent(0,0,0,true,game,1)
        task.wait(math.random(5,15)/1000)
        S.VirtualInputManager:SendMouseButtonEvent(0,0,0,false,game,1)
    end)
end

-- =====================================================
-- MAIN LOOP (Randomized Delays)
-- =====================================================
coroutine.wrap(function()
    while true do
        task.wait(math.random(8,15)/100) -- 0.08-0.15s
        if fishSet.antiAFK then
            pcall(function() S.VirtualUser:CaptureController(); S.VirtualUser:ClickButton2(Vector2.new()) end)
        end
        if fishSet.autoCast then
            callRemote(FishingRemotes.Cast)
            stealthClick()
        end
        -- fish biting detection (simplified)
        local biting = false
        local shaking = false
        pcall(function()
            for _, g in ipairs(PlayerGui:GetDescendants()) do
                if g:IsA("GuiObject") and g.Visible then
                    local n = string.lower(g.Name)
                    if string.find(n, "bite") or string.find(n, "catch") then biting = true end
                    if string.find(n, "shake") or string.find(n, "struggle") then shaking = true end
                end
            end
        end)
        if fishSet.autoReel and biting then
            callRemote(FishingRemotes.Reel)
            stealthClick()
        end
        if fishSet.autoShake and shaking then
            for i=1, fishSet.clickSpeed do
                if not fishSet.autoShake then break end
                callRemote(FishingRemotes.Shake)
                stealthClick()
                task.wait(0.8/fishSet.clickSpeed + math.random(-10,10)/1000) -- slight variation
            end
        end
        if fishSet.autoSell then
            callRemote(FishingRemotes.Sell, "All")
        end
    end
end)()

-- =====================================================
-- WEBHOOK LOGGER (Encrypted URL storage)
-- =====================================================
local HttpRequest = syn and syn.request or http_request or request
local IconCache = {}
local IconWaiter = {}

local function fetchIcon(id, cb)
    if IconCache[id] then cb(IconCache[id]); return end
    if IconWaiter[id] then table.insert(IconWaiter[id], cb); return end
    IconWaiter[id] = {cb}
    local asset = tostring(FishDB[id] and FishDB[id].Icon):match("%d+")
    if not asset then cb(""); return end
    task.spawn(function()
        local ok, res = pcall(function()
            return HttpRequest({ Url = "https://thumbnails.roblox.com/v1/assets?assetIds="..asset.."&size=420x420&format=Png", Method = "GET" })
        end)
        if ok and res and res.Body then
            local ok2, data = pcall(S.HttpService.JSONDecode, S.HttpService, res.Body)
            if ok2 and data and data.data and data.data[1] then
                IconCache[id] = data.data[1].imageUrl or ""
            end
        end
        for _, c in ipairs(IconWaiter[id] or {}) do c(IconCache[id] or "") end
        IconWaiter[id] = nil
    end)
end

local function isRarityAllowed(id)
    local fish = FishDB[id]
    if not fish then return false end
    if next(_set.selectedRarities) == nil then return true end
    return _set.selectedRarities[fish.Tier] == true
end

local function buildPayload(pname, fid, w, mut)
    local f = FishDB[fid]
    if not f then return end
    local r = RARITY_MAP[f.Tier] or "Unknown"
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
                { type = 10, content = "__@" .. pname .. " caught " .. string.upper(r) .. " fish__" },
                {
                    type = 9,
                    components = {
                        { type = 10, content = "**Fish Name**" },
                        { type = 10, content = "> " .. f.Name }
                    },
                    accessory = icon ~= "" and { type = 11, media = { url = icon } } or nil
                },
                { type = 10, content = "**Rarity:** " .. r },
                { type = 10, content = "**Weight:** " .. string.format("%.1fkg", w or 0) },
                { type = 10, content = "**Mutation:** " .. (mut or "None") },
                { type = 14, spacing = 1, divider = true },
                { type = 10, content = "-# " .. date }
            }
        }}
    }
end

local function sendWebhook(p)
    if _set.url == "" or not HttpRequest or not p then return end
    pcall(function()
        local url = _set.url
        url = string.find(url, "?") and (url.."&with_components=true") or (url.."?with_components=true")
        HttpRequest({ Url = url, Method = "POST", Headers = {["Content-Type"]="application/json"}, Body = S.HttpService:JSONEncode(p) })
    end)
end

local function onFishCaught(plr, wdata, wrap)
    if not _set.active then return end
    local item = (wrap and wrap.InventoryItem) or (wdata and wdata.InventoryItem)
    if not item or not item.Id or not item.UUID then return end
    if not FishDB[item.Id] then return end
    if not isRarityAllowed(item.Id) then return end
    if _set.sentUUID[item.UUID] then return end
    _set.sentUUID[item.UUID] = true
    local pname = (typeof(plr)=="Instance" and plr.Name) or (typeof(plr)=="string" and plr) or LocalPlayer.Name
    if not _set.serverWide and pname ~= LocalPlayer.Name then return end
    _set.logCount = _set.logCount + 1
    fetchIcon(item.Id, function()
        sendWebhook(buildPayload(pname, item.Id, wdata and wdata.Weight, wdata and wdata.Mutation))
    end)
end

local webhookConn = nil
local function startLogger()
    if _set.active then return end
    if not net or not ObtainedNewFish then return end
    _set.active = true
    _set.sentUUID = {}
    _set.logCount = 0
    webhookConn = ObtainedNewFish.OnClientEvent:Connect(onFishCaught)
end

local function stopLogger()
    _set.active = false
    if webhookConn then webhookConn:Disconnect(); webhookConn = nil end
end

-- =====================================================
-- UI CREATION (Stealth Named)
-- =====================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = guiNames.main
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = CoreGui

-- Main frame with randomized name
local mainFrame = Instance.new("Frame")
mainFrame.Name = "Frame_" .. math.random(1000,9999)
mainFrame.Size = UDim2.new(0,720,0,480)
mainFrame.Position = UDim2.new(0.5,-360,0.5,-240)
mainFrame.BackgroundColor3 = Color3.fromRGB(15,17,26)
mainFrame.BorderSizePixel = 0
mainFrame.ClipsDescendants = true
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0,12)
Instance.new("UIStroke", mainFrame).Color = Color3.fromRGB(50,55,80)

-- Title bar
local titleBar = Instance.new("Frame", mainFrame)
titleBar.Size = UDim2.new(1,0,0,45)
titleBar.BackgroundColor3 = Color3.fromRGB(20,24,38)
titleBar.BorderSizePixel = 0
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0,12)
local titleFix = Instance.new("Frame", titleBar)
titleFix.Size = UDim2.new(1,0,0,15)
titleFix.Position = UDim2.new(0,0,1,-15)
titleFix.BackgroundColor3 = Color3.fromRGB(20,24,38)
titleFix.BorderSizePixel = 0

local titleLabel = Instance.new("TextLabel", titleBar)
titleLabel.Size = UDim2.new(1,-100,1,0)
titleLabel.Position = UDim2.new(0,15,0,0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Vechnost" -- tetap biar user kenal
titleLabel.TextColor3 = Color3.new(1,1,1)
titleLabel.TextSize = 18
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left

local closeBtn = Instance.new("TextButton", titleBar)
closeBtn.Size = UDim2.new(0,30,0,30)
closeBtn.Position = UDim2.new(1,-40,0.5,-15)
closeBtn.BackgroundColor3 = Color3.fromRGB(35,40,60)
closeBtn.BorderSizePixel = 0
closeBtn.Text = "×"
closeBtn.TextColor3 = Color3.new(1,1,1)
closeBtn.TextSize = 20
closeBtn.Font = Enum.Font.GothamBold
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0,6)

local minBtn = Instance.new("TextButton", titleBar)
minBtn.Size = UDim2.new(0,30,0,30)
minBtn.Position = UDim2.new(1,-75,0.5,-15)
minBtn.BackgroundColor3 = Color3.fromRGB(35,40,60)
minBtn.BorderSizePixel = 0
minBtn.Text = "—"
minBtn.TextColor3 = Color3.new(1,1,1)
minBtn.TextSize = 16
minBtn.Font = Enum.Font.GothamBold
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0,6)

-- Sidebar
local sidebar = Instance.new("Frame", mainFrame)
sidebar.Size = UDim2.new(0,150,1,-55)
sidebar.Position = UDim2.new(0,5,0,50)
sidebar.BackgroundColor3 = Color3.fromRGB(20,24,38)
sidebar.BorderSizePixel = 0
Instance.new("UICorner", sidebar).CornerRadius = UDim.new(0,10)
local sidePad = Instance.new("UIPadding", sidebar)
sidePad.PaddingTop = UDim.new(0,8)
sidePad.PaddingBottom = UDim.new(0,8)
sidePad.PaddingLeft = UDim.new(0,8)
sidePad.PaddingRight = UDim.new(0,8)
local sideLayout = Instance.new("UIListLayout", sidebar)
sideLayout.SortOrder = Enum.SortOrder.LayoutOrder
sideLayout.Padding = UDim.new(0,4)

-- Content area
local contentArea = Instance.new("Frame", mainFrame)
contentArea.Size = UDim2.new(1,-170,1,-60)
contentArea.Position = UDim2.new(0,165,0,55)
contentArea.BackgroundColor3 = Color3.fromRGB(25,28,42)
contentArea.BorderSizePixel = 0
Instance.new("UICorner", contentArea).CornerRadius = UDim.new(0,10)

-- Dropdown container
local dropdownContainer = Instance.new("Frame", screenGui)
dropdownContainer.Size = UDim2.new(1,0,1,0)
dropdownContainer.BackgroundTransparency = 1
dropdownContainer.ZIndex = 100

-- =====================================================
-- SIMPLIFIED TAB SYSTEM (Minimal)
-- =====================================================
local tabs = {"Info","Fishing","Teleport","Trading","Shop","Webhook","Setting"}
local tabButtons = {}
local tabContents = {}
local currentTab

local function switchTab(name)
    if currentTab == name then return end
    for n, c in pairs(tabContents) do
        c.Visible = (n == name)
    end
    for n, btn in pairs(tabButtons) do
        btn.BackgroundColor3 = (n == name) and Color3.fromRGB(45,55,90) or Color3.fromRGB(30,36,58)
    end
    currentTab = name
end

for i, name in ipairs(tabs) do
    local btn = Instance.new("TextButton", sidebar)
    btn.Size = UDim2.new(1,0,0,38)
    btn.BackgroundColor3 = Color3.fromRGB(30,36,58)
    btn.BorderSizePixel = 0
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.LayoutOrder = i
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,8)
    local icon = Instance.new("TextLabel", btn)
    icon.Size = UDim2.new(0,28,1,0)
    icon.Position = UDim2.new(0,8,0,0)
    icon.BackgroundTransparency = 1
    icon.Text = (name=="Info" and "👤") or (name=="Fishing" and "🎣") or (name=="Teleport" and "📍") or (name=="Trading" and "🔄") or (name=="Shop" and "🛒") or (name=="Webhook" and "🔔") or "⚙️"
    icon.TextColor3 = Color3.fromRGB(70,130,255)
    icon.TextSize = 16
    icon.Font = Enum.Font.GothamBold
    local txt = Instance.new("TextLabel", btn)
    txt.Size = UDim2.new(1,-42,1,0)
    txt.Position = UDim2.new(0,38,0,0)
    txt.BackgroundTransparency = 1
    txt.Text = name
    txt.TextColor3 = Color3.new(1,1,1)
    txt.TextSize = 13
    txt.Font = Enum.Font.GothamSemibold
    txt.TextXAlignment = Enum.TextXAlignment.Left
    btn.MouseButton1Click:Connect(function() switchTab(name) end)
    tabButtons[name] = btn
    local content = Instance.new("ScrollingFrame", contentArea)
    content.Size = UDim2.new(1,-16,1,-16)
    content.Position = UDim2.new(0,8,0,8)
    content.BackgroundTransparency = 1
    content.BorderSizePixel = 0
    content.ScrollBarThickness = 4
    content.ScrollBarImageColor3 = Color3.fromRGB(70,130,255)
    content.AutomaticCanvasSize = Enum.AutomaticSize.Y
    content.Visible = false
    Instance.new("UIListLayout", content).SortOrder = Enum.SortOrder.LayoutOrder
    tabContents[name] = content
end
switchTab("Info")

-- =====================================================
-- SIMPLE UI HELPER FUNCTIONS (Only what needed)
-- =====================================================
local orderCount = {}
local function nextOrder(tab) orderCount[tab] = (orderCount[tab] or 0) + 1; return orderCount[tab] end

local function addSection(tab, title)
    local sec = Instance.new("Frame", tabContents[tab])
    sec.Size = UDim2.new(1,0,0,28)
    sec.BackgroundTransparency = 1
    sec.LayoutOrder = nextOrder(tab)
    local lbl = Instance.new("TextLabel", sec)
    lbl.Size = UDim2.new(1,0,1,0)
    lbl.BackgroundTransparency = 1
    lbl.Text = title
    lbl.TextColor3 = Color3.fromRGB(70,130,255)
    lbl.TextSize = 15
    lbl.Font = Enum.Font.GothamBold
    lbl.TextXAlignment = Enum.TextXAlignment.Left
end

local function addButton(tab, text, cb)
    local btn = Instance.new("TextButton", tabContents[tab])
    btn.Size = UDim2.new(1,0,0,36)
    btn.BackgroundColor3 = Color3.fromRGB(70,130,255)
    btn.BorderSizePixel = 0
    btn.Text = text
    btn.TextColor3 = Color3.new(1,1,1)
    btn.TextSize = 12
    btn.Font = Enum.Font.GothamSemibold
    btn.AutoButtonColor = false
    btn.LayoutOrder = nextOrder(tab)
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,8)
    btn.MouseButton1Click:Connect(cb)
end

local function addToggle(tab, text, default, cb)
    local state = default or false
    local frame = Instance.new("Frame", tabContents[tab])
    frame.Size = UDim2.new(1,0,0,42)
    frame.BackgroundColor3 = Color3.fromRGB(35,40,60)
    frame.BorderSizePixel = 0
    frame.LayoutOrder = nextOrder(tab)
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0,8)
    local lbl = Instance.new("TextLabel", frame)
    lbl.Size = UDim2.new(1,-70,1,0)
    lbl.Position = UDim2.new(0,12,0,0)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = Color3.new(1,1,1)
    lbl.TextSize = 12
    lbl.Font = Enum.Font.GothamSemibold
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    local tog = Instance.new("TextButton", frame)
    tog.Size = UDim2.new(0,46,0,24)
    tog.Position = UDim2.new(1,-56,0.5,-12)
    tog.BackgroundColor3 = state and Color3.fromRGB(70,130,255) or Color3.fromRGB(60,65,90)
    tog.BorderSizePixel = 0
    tog.Text = ""
    Instance.new("UICorner", tog).CornerRadius = UDim.new(1,0)
    local circ = Instance.new("Frame", tog)
    circ.Size = UDim2.new(0,18,0,18)
    circ.Position = state and UDim2.new(1,-21,0.5,-9) or UDim2.new(0,3,0.5,-9)
    circ.BackgroundColor3 = Color3.new(1,1,1)
    circ.BorderSizePixel = 0
    Instance.new("UICorner", circ).CornerRadius = UDim.new(1,0)
    tog.MouseButton1Click:Connect(function()
        state = not state
        S.TweenService:Create(circ, TweenInfo.new(0.2), {Position = state and UDim2.new(1,-21,0.5,-9) or UDim2.new(0,3,0.5,-9)}):Play()
        S.TweenService:Create(tog, TweenInfo.new(0.2), {BackgroundColor3 = state and Color3.fromRGB(70,130,255) or Color3.fromRGB(60,65,90)}):Play()
        cb(state)
    end)
end

-- =====================================================
-- POPULATE TABS (Simplified - only essential)
-- =====================================================
addSection("Info", "Player")
local playerInfo = Instance.new("Frame", tabContents["Info"])
playerInfo.Size = UDim2.new(1,0,0,55)
playerInfo.BackgroundColor3 = Color3.fromRGB(35,40,60)
playerInfo.LayoutOrder = nextOrder("Info")
Instance.new("UICorner", playerInfo).CornerRadius = UDim.new(0,8)
local infoText = Instance.new("TextLabel", playerInfo)
infoText.Size = UDim2.new(1,-20,1,-10)
infoText.Position = UDim2.new(0,10,0,5)
infoText.BackgroundTransparency = 1
infoText.Text = "Loading..."
infoText.TextColor3 = Color3.fromRGB(180,180,200)
infoText.TextSize = 11
infoText.Font = Enum.Font.Gotham
infoText.TextWrapped = true
infoText.TextXAlignment = Enum.TextXAlignment.Left
coroutine.wrap(function()
    while true do
        task.wait(3)
        local coins = 0
        pcall(function() coins = PlayerData:Get("Coins") or 0 end)
        infoText.Text = "Coins: "..tostring(coins).." | Fish: ???"
    end
end)()

addSection("Fishing", "Auto")
addToggle("Fishing", "Auto Cast", false, function(v) fishSet.autoCast = v end)
addToggle("Fishing", "Auto Reel", false, function(v) fishSet.autoReel = v end)
addToggle("Fishing", "Auto Shake", false, function(v) fishSet.autoShake = v end)
addToggle("Fishing", "Anti AFK", false, function(v) fishSet.antiAFK = v end)
addToggle("Fishing", "Auto Sell", false, function(v) fishSet.autoSell = v end)

addSection("Teleport", "Islands")
addButton("Teleport", "Refresh", function() scanIslands() end)
for _, loc in ipairs(TeleportLocations) do
    addButton("Teleport", loc.Name, function()
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            char.HumanoidRootPart.CFrame = loc.CFrame
        end
    end)
end

addSection("Webhook", "Logger")
addToggle("Webhook", "Enable", false, function(v)
    if v then
        if _set.url == "" then
            -- dummy notification
            v = false
        else
            startLogger()
        end
    else
        stopLogger()
    end
end)

addSection("Setting", "URL")
local urlBox = Instance.new("TextBox", tabContents["Setting"])
urlBox.Size = UDim2.new(1,0,0,30)
urlBox.LayoutOrder = nextOrder("Setting")
urlBox.BackgroundColor3 = Color3.fromRGB(20,22,35)
urlBox.BorderSizePixel = 0
urlBox.PlaceholderText = "https://discord.com/api/webhooks/..."
urlBox.TextColor3 = Color3.new(1,1,1)
urlBox.TextSize = 11
Instance.new("UICorner", urlBox).CornerRadius = UDim.new(0,6)
urlBox.FocusLost:Connect(function()
    _set.url = urlBox.Text:gsub("%s+","")
end)

addButton("Setting", "Test Webhook", function()
    if _set.url == "" then return end
    sendWebhook({
        username = "Vechnost",
        components = {{
            type=17, components = {
                {type=10, content="Test"},
                {type=14, divider=true},
                {type=10, content="Webhook OK"}
            }
        }}
    })
end)

-- =====================================================
-- WINDOW CONTROLS
-- =====================================================
local dragging, dragOffset = false
titleBar.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragOffset = Vector2.new(i.Position.X, i.Position.Y) - Vector2.new(mainFrame.AbsolutePosition.X, mainFrame.AbsolutePosition.Y)
    end
end)
titleBar.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)
S.UserInputService.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement) then
        local newPos = Vector2.new(i.Position.X, i.Position.Y) - dragOffset
        mainFrame.Position = UDim2.fromOffset(newPos.X, newPos.Y)
    end
end)
closeBtn.MouseButton1Click:Connect(function() screenGui:Destroy() end)
local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    S.TweenService:Create(mainFrame, TweenInfo.new(0.3), {Size = minimized and UDim2.new(0,720,0,45) or UDim2.new(0,720,0,480)}):Play()
end)

-- =====================================================
-- MOBILE FLOATING BUTTON
-- =====================================================
local mobileGui = Instance.new("ScreenGui")
mobileGui.Name = guiNames.mobile
mobileGui.ResetOnSpawn = false
mobileGui.Parent = CoreGui
local floatBtn = Instance.new("ImageButton", mobileGui)
floatBtn.Size = UDim2.fromOffset(52,52)
floatBtn.Position = UDim2.fromScale(0.05,0.5)
floatBtn.BackgroundTransparency = 1
floatBtn.Image = "rbxassetid://127239715511367"
floatBtn.AutoButtonColor = false
Instance.new("UICorner", floatBtn).CornerRadius = UDim.new(1,0)
floatBtn.MouseButton1Click:Connect(function() mainFrame.Visible = not mainFrame.Visible end)
local floatDrag = false
floatBtn.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch then
        floatDrag = true
    end
end)
S.RunService.RenderStepped:Connect(function()
    if floatDrag then
        local mp = S.UserInputService:GetMouseLocation()
        floatBtn.Position = UDim2.fromOffset(mp.X - 26, mp.Y - 26)
    end
end)
S.UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch then floatDrag = false end
end)

-- =====================================================
-- INIT
-- =====================================================
warn("[Vechnost] Loaded (Stealth Mode)")
