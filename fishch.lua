-- Craft A World Script v2.0 — WORKING
-- Remote: ReplicatedStorage.Remotes.PlayerMovementPackets.[playerName]:FireServer(Vector2)
-- WARNING: Educational purposes only. Use at your own risk.

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

local player    = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local hrp       = character:WaitForChild("HumanoidRootPart")

player.CharacterAdded:Connect(function(char)
    character = char
    hrp = char:WaitForChild("HumanoidRootPart")
end)

-- ============================================================
-- REMOTE — path yang benar dari hasil spy
-- ============================================================
local function getRemote()
    -- Remotes > PlayerMovementPackets > [nama player kamu]
    local ok, remote = pcall(function()
        return ReplicatedStorage
            :WaitForChild("Remotes", 5)
            :WaitForChild("PlayerMovementPackets", 5)
            :WaitForChild(player.Name, 5)
    end)
    if ok and remote then return remote end
    return nil
end

-- Fire posisi ke server (inilah cara game handle punch & collect)
local function firePosition(vec2)
    local remote = getRemote()
    if remote then
        pcall(function()
            remote:FireServer(vec2)
        end)
    end
end

-- ============================================================
-- HELPER
-- ============================================================
local function isCharPart(obj)
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
    scannedBlocks   = {},   -- list obj block anchored
    breakDelay      = 0.08,
    collectSpeed    = 30,
}

-- ============================================================
-- WINDOW
-- ============================================================
local Window = Fluent:CreateWindow({
    Title       = "Craft A World",
    SubTitle    = "Script v2.0 — Working",
    TabWidth    = 160,
    Size        = UDim2.fromOffset(520, 460),
    Acrylic     = true,
    Theme       = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local HomeTab = Window:AddTab({ Title = "Home", Icon = "home" })

-- Header
HomeTab:AddSection("Craft A World - Main"):AddParagraph({
    Title   = "Welcome! v2.0",
    Content = "Remote: PlayerMovementPackets ✅\nMinimize: Right Ctrl\n\nScan → aktifkan fitur yang kamu mau."
})

-- ============================================================
-- SECTION: AUTO CLEAR WORLD
-- ============================================================
local ClearSection = HomeTab:AddSection("Auto Clear World")

local ScanResultPara = ClearSection:AddParagraph({
    Title   = "Hasil Scan",
    Content = "Belum scan. Tekan Scan World dulu."
})

-- Scan: cari semua BasePart yang ter-anchor (= block dunia)
-- bukan karakter, bukan UI
local SKIP_NAMES = {
    Baseplate=1, ParallaxPlane=1, tileHighlight=1, TileHighlight=1,
    Highlight=1, SelectionBox=1, Terrain=1,
    Head=1, Torso=1, ["Left Arm"]=1, ["Right Arm"]=1,
    ["Left Leg"]=1, ["Right Leg"]=1, HumanoidRootPart=1,
    UpperTorso=1, LowerTorso=1, LeftUpperArm=1, RightUpperArm=1,
    LeftLowerArm=1, RightLowerArm=1, LeftHand=1, RightHand=1,
    LeftUpperLeg=1, RightUpperLeg=1, LeftLowerLeg=1, RightLowerLeg=1,
    LeftFoot=1, RightFoot=1,
}

ClearSection:AddButton({
    Title       = "🔍 Scan World",
    Description = "Deteksi semua block (anchored) di world ini",
    Callback    = function()
        state.scannedBlocks = {}
        local nameCount = {}

        for _, obj in ipairs(Workspace:GetDescendants()) do
            if not (obj:IsA("BasePart") or obj:IsA("MeshPart")) then continue end
            if SKIP_NAMES[obj.Name] then continue end
            if not obj.Anchored then continue end          -- block dunia = anchored
            if isCharPart(obj) then continue end

            table.insert(state.scannedBlocks, obj)
            nameCount[obj.Name] = (nameCount[obj.Name] or 0) + 1
        end

        if #state.scannedBlocks == 0 then
            ScanResultPara:SetDesc("❌ Tidak ada block anchored ditemukan.")
        else
            -- Tampilkan ringkasan per nama
            local lines = {}
            for name, count in pairs(nameCount) do
                table.insert(lines, "• " .. name .. " ×" .. count)
            end
            table.sort(lines)
            local preview = {}
            for i = 1, math.min(12, #lines) do
                table.insert(preview, lines[i])
            end
            if #lines > 12 then
                table.insert(preview, "... +" .. (#lines-12) .. " jenis lainnya")
            end
            ScanResultPara:SetDesc(
                "✅ " .. #state.scannedBlocks .. " block ditemukan ("
                .. #lines .. " jenis):\n"
                .. table.concat(preview, "\n")
            )
        end

        Fluent:Notify({
            Title    = "Scan Selesai",
            Content  = #state.scannedBlocks .. " block siap di-break.",
            Duration = 3
        })
    end
})

local BreakDelaySlider = ClearSection:AddSlider("BreakDelay", {
    Title       = "Delay antar Break (detik)",
    Description = "Lebih kecil = lebih cepat (jangan terlalu cepat)",
    Default     = 0.08, Min = 0.05, Max = 1.0, Rounding = 2
})
BreakDelaySlider:OnChanged(function(v) state.breakDelay = v end)

local AutoClearToggle = ClearSection:AddToggle("AutoClearWorld", {
    Title       = "Auto Clear World",
    Description = "Otomatis break semua block hasil scan",
    Default     = false
})
AutoClearToggle:OnChanged(function(v)
    if v and #state.scannedBlocks == 0 then
        Fluent:Notify({Title="⚠️ Peringatan", Content="Scan World dulu!", Duration=3})
        state.autoClearWorld = false
        AutoClearToggle:SetValue(false)
        return
    end
    state.autoClearWorld = v
    Fluent:Notify({
        Title   = "Auto Clear World",
        Content = v and "✅ AKTIF — Breaking blocks..." or "❌ Dimatikan.",
        Duration = 2
    })
end)

-- ============================================================
-- SECTION: AUTO COLLECT FLOATING ITEMS
-- ============================================================
local CollectSection = HomeTab:AddSection("Auto Collect Floating Items")

CollectSection:AddParagraph({
    Title   = "Info",
    Content = "Karakter terbang smooth ke item drop lalu fire\nposisi item ke server untuk collect otomatis."
})

local AutoCollectToggle = CollectSection:AddToggle("AutoCollect", {
    Title       = "Auto Collect Floating Items",
    Description = "Terbang ke item drop & collect otomatis",
    Default     = false
})

local CollectSpeedSlider = CollectSection:AddSlider("CollectSpeed", {
    Title    = "Kecepatan Terbang",
    Default  = 30, Min = 5, Max = 100, Rounding = 1
})
CollectSpeedSlider:OnChanged(function(v) state.collectSpeed = v end)

AutoCollectToggle:OnChanged(function(v)
    state.autoCollect = v
    Fluent:Notify({
        Title   = "Auto Collect",
        Content = v and "✅ AKTIF — terbang ke item..." or "❌ Dimatikan.",
        Duration = 2
    })
end)

-- ============================================================
-- FLY SYSTEM (BodyVelocity)
-- ============================================================
local bv, bg = nil, nil

local function startFly()
    if not hrp then return end
    if bv then bv:Destroy() end
    if bg then bg:Destroy() end
    bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(1e5,1e5,1e5)
    bv.Velocity  = Vector3.zero
    bv.Parent    = hrp
    bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(1e5,1e5,1e5)
    bg.D = 100
    bg.Parent = hrp
end

local function stopFly()
    if bv then bv:Destroy(); bv = nil end
    if bg then bg:Destroy(); bg = nil end
end

local function flyToward(targetPos)
    if not hrp or not bv then return false end
    local dir  = targetPos - hrp.Position
    local dist = dir.Magnitude
    if dist < 2.5 then
        bv.Velocity = Vector3.zero
        return true
    end
    bv.Velocity = dir.Unit * math.min(state.collectSpeed, dist * 5)
    bg.CFrame   = CFrame.lookAt(hrp.Position, targetPos)
    return false
end

-- ============================================================
-- LOOP: Auto Clear World
-- ============================================================
spawn(function()
    while true do
        task.wait(0.1)
        if not state.autoClearWorld or #state.scannedBlocks == 0 then continue end
        if not character or not hrp then continue end

        -- Salin list (supaya aman saat list berubah)
        local targets = table.clone(state.scannedBlocks)

        for _, obj in ipairs(targets) do
            if not state.autoClearWorld then break end
            if not obj or not obj.Parent then continue end

            -- Kirim posisi block ke server via remote yang benar
            -- Game 2D: gunakan X dan Y dari Position
            local pos2D = Vector2.new(obj.Position.X, obj.Position.Y)
            firePosition(pos2D)

            task.wait(state.breakDelay)
        end

        -- Refresh list setelah satu putaran
        if state.autoClearWorld then
            local newList = {}
            for _, obj in ipairs(state.scannedBlocks) do
                if obj and obj.Parent then
                    table.insert(newList, obj)
                end
            end
            state.scannedBlocks = newList

            -- Update UI count
            ScanResultPara:SetDesc("🔄 Breaking... sisa " .. #state.scannedBlocks .. " block.")

            if #state.scannedBlocks == 0 then
                state.autoClearWorld = false
                AutoClearToggle:SetValue(false)
                ScanResultPara:SetDesc("✅ Semua block sudah di-break!")
                Fluent:Notify({Title="Auto Clear", Content="✅ World berhasil di-clear!", Duration=5})
            end
        end
    end
end)

-- ============================================================
-- LOOP: Auto Collect (fly + fire posisi item)
-- ============================================================
local flyActive = false

spawn(function()
    while true do
        task.wait(0.1)

        if state.autoCollect then
            if not flyActive then
                startFly()
                flyActive = true
            end
        else
            if flyActive then
                stopFly()
                flyActive = false
            end
            continue
        end

        if not character or not hrp then continue end

        -- Cari item drop terdekat:
        -- BasePart, TIDAK anchored, ukuran kecil, bukan karakter
        local nearest, nearDist = nil, math.huge

        for _, obj in ipairs(Workspace:GetDescendants()) do
            if not obj:IsA("BasePart") then continue end
            if obj.Anchored then continue end
            if SKIP_NAMES[obj.Name] then continue end
            if isCharPart(obj) then continue end

            -- Item drop biasanya sangat kecil
            local sz = obj.Size
            if sz.X > 3 or sz.Y > 3 or sz.Z > 3 then continue end

            local dist = (obj.Position - hrp.Position).Magnitude
            if dist < nearDist then
                nearDist = dist
                nearest  = obj
            end
        end

        if nearest and nearDist < 300 then
            -- Terbang ke item
            local arrived = flyToward(nearest.Position + Vector3.new(0, 1, 0))

            -- Saat sudah dekat, fire posisi item ke server
            if arrived or nearDist < 5 then
                local pos2D = Vector2.new(nearest.Position.X, nearest.Position.Y)
                firePosition(pos2D)
                task.wait(0.05)
            end
        else
            -- Tidak ada item — hover diam
            if bv then bv.Velocity = Vector3.zero end
        end
    end
end)

-- ============================================================
-- STARTUP
-- ============================================================
Window:SelectTab(1)

-- Cek apakah remote ditemukan
spawn(function()
    task.wait(2)
    local remote = getRemote()
    if remote then
        Fluent:Notify({
            Title    = "✅ Remote Ditemukan!",
            Content  = "PlayerMovementPackets/" .. player.Name .. " siap.",
            Duration = 4
        })
    else
        Fluent:Notify({
            Title    = "⚠️ Remote Tidak Ditemukan",
            Content  = "Pastikan sudah masuk ke dalam world!",
            Duration = 5
        })
    end
end)

Fluent:Notify({
    Title    = "Craft A World v2.0",
    Content  = "Script loaded! Masuk world dulu, lalu Scan.",
    Duration = 4
})
