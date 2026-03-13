-- Craft A World Script v1.2
-- WARNING: Educational purposes only. Use at your own risk.

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")

local player    = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local hrp       = character:WaitForChild("HumanoidRootPart")

player.CharacterAdded:Connect(function(char)
    character = char
    hrp = char:WaitForChild("HumanoidRootPart")
end)

-- ============================================================
-- BAGIAN TUBUH KARAKTER (diblacklist dari scan)
-- ============================================================
local BODY_PARTS = {
    Head=1, Torso=1, ["Left Arm"]=1, ["Right Arm"]=1,
    ["Left Leg"]=1, ["Right Leg"]=1, HumanoidRootPart=1,
    UpperTorso=1, LowerTorso=1, LeftUpperArm=1, RightUpperArm=1,
    LeftLowerArm=1, RightLowerArm=1, LeftHand=1, RightHand=1,
    LeftUpperLeg=1, RightUpperLeg=1, LeftLowerLeg=1, RightLowerLeg=1,
    LeftFoot=1, RightFoot=1,
    -- UI / visual bawaan game
    Baseplate=1, ParallaxPlane=1, tileHighlight=1, TileHighlight=1,
    Highlight=1, SelectionBox=1, Cursor=1, Sky=1, Terrain=1,
    Camera=1, ["."]=1,
}

-- Cek apakah object adalah bagian karakter salah satu player
local function isCharacterPart(obj)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Character and obj:IsDescendantOf(plr.Character) then
            return true
        end
    end
    return false
end

-- ============================================================
-- STATE
-- ============================================================
local state = {
    autoClearWorld  = false,
    autoCollect     = false,
    scannedBlocks   = {},   -- {name, obj ref sample}
    targetNames     = {},   -- lookup table
    flySpeed        = 25,   -- stud/s untuk collect
}

-- ============================================================
-- WINDOW
-- ============================================================
local Window = Fluent:CreateWindow({
    Title       = "Craft A World",
    SubTitle    = "Script v1.2",
    TabWidth    = 160,
    Size        = UDim2.fromOffset(520, 460),
    Acrylic     = true,
    Theme       = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local HomeTab = Window:AddTab({ Title = "Home", Icon = "home" })

-- Header
local HeaderSection = HomeTab:AddSection("Craft A World - Main")
HeaderSection:AddParagraph({
    Title   = "Welcome!",
    Content = "Script v1.2 aktif. Minimize: Right Ctrl\nScan dulu agar Auto Clear tahu block mana yang dipukul."
})

-- ── AUTO CLEAR WORLD ─────────────────────────────────────────
local ClearSection = HomeTab:AddSection("Auto Clear World")

local ScanResultParagraph = ClearSection:AddParagraph({
    Title   = "Hasil Scan",
    Content = "Belum di-scan. Tekan Scan World terlebih dahulu."
})

-- ============================================================
-- FUNGSI SCAN — tanpa whitelist, scan SEMUA object nyata
-- Tampilkan nama asli supaya kita tahu nama block di game ini
-- ============================================================
local function scanWorldBlocks()
    local found = {}
    local seen  = {}

    -- Cari folder yang kemungkinan besar adalah container block
    -- (World, Map, Tiles, Blocks, Grid, dll)
    local function searchInside(folder)
        for _, obj in ipairs(folder:GetDescendants()) do
            if not (obj:IsA("BasePart") or obj:IsA("MeshPart")) then continue end
            if BODY_PARTS[obj.Name] then continue end
            if isCharacterPart(obj) then continue end

            local name = obj.Name
            if name == "" or name == "." then continue end

            if not seen[name] then
                seen[name] = true
                table.insert(found, name)
            end
        end
    end

    -- Cari folder khusus block di Workspace terlebih dulu
    local knownFolders = {
        "World", "Map", "Tiles", "Blocks", "Grid",
        "WorldMap", "TileMap", "Level", "Terrain",
        "WorldFolder", "BlockFolder", "TileFolder"
    }
    local foundFolder = false
    for _, fname in ipairs(knownFolders) do
        local f = Workspace:FindFirstChild(fname)
        if f then
            searchInside(f)
            foundFolder = true
        end
    end

    -- Jika tidak ada folder khusus, scan seluruh Workspace
    if not foundFolder then
        searchInside(Workspace)
    end

    table.sort(found)
    return found
end

-- Tombol Scan World
ClearSection:AddButton({
    Title       = "🔍 Scan World",
    Description = "Deteksi semua block nyata di world (tanpa filter nama)",
    Callback    = function()
        state.scannedBlocks = scanWorldBlocks()
        state.targetNames   = {}

        if #state.scannedBlocks == 0 then
            ScanResultParagraph:SetDesc(
                "❌ Tidak ada object ditemukan.\n"..
                "Pastikan sudah masuk ke dalam world dan ada block di sekitarmu."
            )
        else
            -- Bangun lookup table
            for _, n in ipairs(state.scannedBlocks) do
                state.targetNames[n] = true
            end

            local lines = {}
            for i, name in ipairs(state.scannedBlocks) do
                table.insert(lines, "• " .. name)
                if i >= 15 then
                    if #state.scannedBlocks > 15 then
                        table.insert(lines, "  ... +" .. (#state.scannedBlocks - 15) .. " lainnya")
                    end
                    break
                end
            end
            ScanResultParagraph:SetDesc(
                "✅ " .. #state.scannedBlocks .. " nama block terdeteksi:\n"
                .. table.concat(lines, "\n")
            )
        end

        Fluent:Notify({
            Title    = "Scan Selesai",
            Content  = #state.scannedBlocks .. " nama block ditemukan.",
            Duration = 3
        })
    end
})

-- Toggle Auto Clear World
local AutoClearToggle = ClearSection:AddToggle("AutoClearWorld", {
    Title       = "Auto Clear World",
    Description = "Otomatis break semua block hasil scan di world",
    Default     = false
})
AutoClearToggle:OnChanged(function(value)
    if value and #state.scannedBlocks == 0 then
        Fluent:Notify({
            Title    = "⚠️ Peringatan",
            Content  = "Scan World dulu sebelum aktifkan Auto Clear!",
            Duration = 4
        })
        state.autoClearWorld = false
        AutoClearToggle:SetValue(false)
        return
    end
    state.autoClearWorld = value
    Fluent:Notify({
        Title   = "Auto Clear World",
        Content = value and "✅ AKTIF — Breaking blocks..." or "❌ Dimatikan.",
        Duration = 2
    })
end)

-- ── AUTO COLLECT FLOATING ITEMS ───────────────────────────────
local CollectSection = HomeTab:AddSection("Auto Collect Floating Items")

CollectSection:AddParagraph({
    Title   = "Info",
    Content = "Karakter akan FLY/WALK mendekati item drop\n(tidak teleport instan)."
})

local AutoCollectToggle = CollectSection:AddToggle("AutoCollect", {
    Title       = "Auto Collect Floating Items",
    Description = "Karakter terbang mendekati lalu mengambil item drop",
    Default     = false
})
AutoCollectToggle:OnChanged(function(value)
    state.autoCollect = value
    Fluent:Notify({
        Title   = "Auto Collect",
        Content = value and "✅ AKTIF — Terbang ke item..." or "❌ Dimatikan.",
        Duration = 2
    })
end)

local FlySpeedSlider = CollectSection:AddSlider("FlySpeed", {
    Title       = "Kecepatan Terbang",
    Description = "Seberapa cepat karakter menuju item (stud/s)",
    Default     = 25,
    Min         = 5,
    Max         = 100,
    Rounding    = 1
})
FlySpeedSlider:OnChanged(function(v) state.flySpeed = v end)

-- ============================================================
-- HELPER: cari RemoteEvent
-- ============================================================
local function findRemote(...)
    local names = {...}
    local folders = {
        ReplicatedStorage:FindFirstChild("Events"),
        ReplicatedStorage:FindFirstChild("RemoteEvents"),
        ReplicatedStorage:FindFirstChild("Remotes"),
        ReplicatedStorage:FindFirstChild("RE"),
        ReplicatedStorage:FindFirstChild("events"),
        ReplicatedStorage,
    }
    for _, folder in ipairs(folders) do
        if folder then
            for _, rName in ipairs(names) do
                local r = folder:FindFirstChild(rName)
                if r then return r end
            end
        end
    end
    return nil
end

-- ============================================================
-- HELPER: fly / move karakter ke posisi target
-- pakai BodyVelocity agar halus (bukan teleport)
-- ============================================================
local flyBodyVel  = nil
local flyBodyGyro = nil

local function startFly()
    if not hrp then return end
    -- Hapus yang lama
    if flyBodyVel  then flyBodyVel:Destroy()  end
    if flyBodyGyro then flyBodyGyro:Destroy() end

    flyBodyVel = Instance.new("BodyVelocity")
    flyBodyVel.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    flyBodyVel.Velocity  = Vector3.zero
    flyBodyVel.Parent    = hrp

    flyBodyGyro = Instance.new("BodyGyro")
    flyBodyGyro.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
    flyBodyGyro.D         = 100
    flyBodyGyro.Parent    = hrp
end

local function stopFly()
    if flyBodyVel  then flyBodyVel:Destroy();  flyBodyVel  = nil end
    if flyBodyGyro then flyBodyGyro:Destroy(); flyBodyGyro = nil end
end

local function flyToward(targetPos)
    if not hrp or not flyBodyVel then return end
    local dir = (targetPos - hrp.Position)
    local dist = dir.Magnitude
    if dist < 2 then
        flyBodyVel.Velocity = Vector3.zero
        return true   -- sudah dekat
    end
    flyBodyVel.Velocity = dir.Unit * math.min(state.flySpeed, dist * 5)
    flyBodyGyro.CFrame  = CFrame.lookAt(hrp.Position, targetPos)
    return false
end

-- ============================================================
-- LOOP: Auto Clear World
-- ============================================================
spawn(function()
    while true do
        task.wait(0.15)
        if not state.autoClearWorld or #state.scannedBlocks == 0 then continue end
        if not character or not hrp then continue end

        local breakRemote = findRemote(
            "BreakBlock","breakBlock","Break","break",
            "HitBlock","hitBlock","PunchBlock","punchBlock",
            "Punch","punch","DamageBlock","Hit","Attack"
        )

        -- Kumpulkan target sekali
        local targets = {}
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if (obj:IsA("BasePart") or obj:IsA("MeshPart"))
                and state.targetNames[obj.Name]
                and not BODY_PARTS[obj.Name]
                and not isCharacterPart(obj)
            then
                table.insert(targets, obj)
            end
        end

        for _, obj in ipairs(targets) do
            if not state.autoClearWorld then break end
            if not obj or not obj.Parent then continue end

            -- Teleport ke dekat block (auto clear = cepat)
            pcall(function()
                hrp.CFrame = CFrame.new(obj.Position + Vector3.new(0, 0, 3))
            end)

            -- Coba semua metode break
            if breakRemote then
                pcall(function()
                    if breakRemote:IsA("RemoteEvent") then
                        breakRemote:FireServer(obj, obj.Position)
                    elseif breakRemote:IsA("RemoteFunction") then
                        breakRemote:InvokeServer(obj, obj.Position)
                    end
                end)
            end

            local cd = obj:FindFirstChildWhichIsA("ClickDetector")
            if cd then pcall(fireclickdetector, cd) end

            local ti = obj:FindFirstChild("TouchInterest")
            if ti then
                pcall(firetouchinterest, hrp, obj, 0)
                task.wait(0.02)
                pcall(firetouchinterest, hrp, obj, 1)
            end

            task.wait(0.08)
        end
    end
end)

-- ============================================================
-- LOOP: Auto Collect — FLY menuju item
-- ============================================================
local collectActive = false

spawn(function()
    while true do
        task.wait(0.1)
        if not state.autoCollect then
            if collectActive then
                stopFly()
                collectActive = false
            end
            continue
        end
        if not character or not hrp then continue end

        -- Aktifkan fly saat pertama kali
        if not collectActive then
            startFly()
            collectActive = true
        end

        -- Temukan item drop terdekat
        -- Di Craft A World, item drop biasanya:
        -- 1. Part kecil (size < 2.5 di semua axis)
        -- 2. Bukan milik karakter
        -- 3. Bergerak / melayang (Anchored = false)
        local nearest  = nil
        local nearDist = math.huge

        for _, obj in ipairs(Workspace:GetDescendants()) do
            if not obj:IsA("BasePart") then continue end
            if BODY_PARTS[obj.Name] then continue end
            if isCharacterPart(obj) then continue end
            if obj.Anchored then continue end          -- item drop tidak ter-anchor

            local sz = obj.Size
            -- Item drop biasanya kecil
            if sz.X > 3 or sz.Y > 3 or sz.Z > 3 then continue end

            -- Jangan ambil bagian tool / equip pemain sendiri
            if obj:IsDescendantOf(player.Character or game) and
               obj ~= hrp then continue end

            local dist = (obj.Position - hrp.Position).Magnitude
            if dist < nearDist then
                nearDist = dist
                nearest  = obj
            end
        end

        if nearest and nearDist < 300 then
            local arrived = flyToward(nearest.Position + Vector3.new(0, 1, 0))

            if arrived or nearDist < 3 then
                -- Sudah dekat — coba collect
                local collectRemote = findRemote(
                    "CollectItem","collectItem","PickupItem","pickupItem",
                    "Collect","collect","PickUp","pickup",
                    "GrabItem","grabItem","TouchDrop","collectDrop"
                )
                if collectRemote then
                    pcall(function() collectRemote:FireServer(nearest) end)
                end

                local ti = nearest:FindFirstChild("TouchInterest")
                if ti then
                    pcall(firetouchinterest, hrp, nearest, 0)
                    task.wait(0.04)
                    pcall(firetouchinterest, hrp, nearest, 1)
                end
            end
        else
            -- Tidak ada item — diam di tempat
            if flyBodyVel then
                flyBodyVel.Velocity = Vector3.zero
            end
        end
    end
end)

-- Bersihkan fly saat autoCollect dimatikan
AutoCollectToggle:OnChanged(function(value)
    if not value and collectActive then
        stopFly()
        collectActive = false
    end
end)

-- ============================================================
-- STARTUP
-- ============================================================
Window:SelectTab(1)

Fluent:Notify({
    Title    = "Craft A World Script v1.2",
    Content  = "Loaded! Masuk world, lalu tekan Scan World.",
    Duration = 5
})
