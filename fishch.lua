-- Craft A World Script v3.0 — FINAL CORRECT
-- Struktur: Workspace.Tiles (blocks), Workspace.Drops (items), Workspace.Gems
-- Remote: ReplicatedStorage.Remotes.PlayerMovementPackets.[player] :FireServer(Vector2)
-- WARNING: Educational purposes only. Use at your own risk.

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local hrp       = character:WaitForChild("HumanoidRootPart")

player.CharacterAdded:Connect(function(char)
    character = char
    hrp = char:WaitForChild("HumanoidRootPart")
end)

-- ============================================================
-- REMOTE — satu remote untuk semua aksi
-- Path: Remotes > PlayerMovementPackets > [namamu]
-- Kirim: Vector2(X, Y) = posisi tile di dunia
-- ============================================================
local Remote = nil

local function getRemote()
    if Remote and Remote.Parent then return Remote end
    local ok, r = pcall(function()
        return ReplicatedStorage
            :WaitForChild("Remotes", 5)
            :WaitForChild("PlayerMovementPackets", 5)
            :WaitForChild(player.Name, 5)
    end)
    if ok and r then Remote = r end
    return Remote
end

local function firePos(x, y)
    local r = getRemote()
    if r then
        pcall(function()
            r:FireServer(Vector2.new(x, y))
        end)
    end
end

-- ============================================================
-- REFERENSI FOLDER DARI DEX
-- ============================================================
local TilesFolder = Workspace:WaitForChild("Tiles", 10)     -- block dunia
local DropsFolder = Workspace:WaitForChild("Drops", 10)     -- item drop
local GemsFolder  = Workspace:FindFirstChild("Gems")        -- gem (optional)

-- ============================================================
-- STATE
-- ============================================================
local state = {
    autoClear   = false,
    autoCollect = false,  -- collect Drops + Gems
    breakDelay  = 0.05,
    flySpeed    = 40,
}

-- ============================================================
-- FLY SYSTEM
-- ============================================================
local bv, bg = nil, nil

local function startFly()
    if not hrp then return end
    if bv then bv:Destroy() end
    if bg then bg:Destroy() end
    bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    bv.Velocity  = Vector3.zero
    bv.Parent    = hrp
    bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
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
    bv.Velocity = dir.Unit * math.min(state.flySpeed, dist * 6)
    bg.CFrame   = CFrame.lookAt(hrp.Position, targetPos)
    return false
end

-- ============================================================
-- WINDOW
-- ============================================================
local Window = Fluent:CreateWindow({
    Title       = "Craft A World",
    SubTitle    = "Script v3.0",
    TabWidth    = 160,
    Size        = UDim2.fromOffset(520, 460),
    Acrylic     = true,
    Theme       = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local HomeTab = Window:AddTab({ Title = "Home", Icon = "home" })

-- ── Header ───────────────────────────────────────────────────
HomeTab:AddSection("Craft A World - Main"):AddParagraph({
    Title   = "Script v3.0 ✅",
    Content = "Remote: PlayerMovementPackets\n"
            .."Tiles: Workspace.Tiles\n"
            .."Drops: Workspace.Drops\n"
            .."Minimize: Right Ctrl"
})

-- ============================================================
-- SECTION: AUTO CLEAR WORLD (break semua tile)
-- ============================================================
local ClearSection = HomeTab:AddSection("Auto Clear World")

local ScanPara = ClearSection:AddParagraph({
    Title   = "Status",
    Content = "Idle. Aktifkan toggle untuk mulai break tiles."
})

ClearSection:AddSlider("BreakDelay", {
    Title    = "Delay antar Break (detik)",
    Default  = 0.05, Min = 0.02, Max = 1.0, Rounding = 2
}):OnChanged(function(v) state.breakDelay = v end)

local AutoClearToggle = ClearSection:AddToggle("AutoClear", {
    Title       = "Auto Clear World",
    Description = "Break semua block di Workspace.Tiles secara otomatis",
    Default     = false
})
AutoClearToggle:OnChanged(function(v)
    state.autoClear = v
    if v then
        -- Cek apakah folder Tiles ada
        if not TilesFolder then
            TilesFolder = Workspace:FindFirstChild("Tiles")
        end
        if not TilesFolder then
            Fluent:Notify({Title="❌ Error", Content="Folder Tiles tidak ditemukan!", Duration=4})
            state.autoClear = false
            AutoClearToggle:SetValue(false)
            return
        end
    end
    Fluent:Notify({
        Title   = "Auto Clear World",
        Content = v and "✅ AKTIF — Breaking tiles..." or "❌ Dimatikan.",
        Duration = 2
    })
end)

-- ============================================================
-- SECTION: AUTO COLLECT (Drops + Gems)
-- ============================================================
local CollectSection = HomeTab:AddSection("Auto Collect Floating Items")

CollectSection:AddParagraph({
    Title   = "Info",
    Content = "Ambil otomatis dari:\n• Workspace.Drops (item drop)\n• Workspace.Gems (gem)"
})

CollectSection:AddSlider("FlySpeed", {
    Title    = "Kecepatan Terbang",
    Default  = 40, Min = 5, Max = 150, Rounding = 1
}):OnChanged(function(v) state.flySpeed = v end)

local AutoCollectToggle = CollectSection:AddToggle("AutoCollect", {
    Title       = "Auto Collect Drops & Gems",
    Description = "Terbang ke item drop dan gem lalu collect otomatis",
    Default     = false
})

local flyActive = false
AutoCollectToggle:OnChanged(function(v)
    state.autoCollect = v
    if v and not flyActive then
        startFly()
        flyActive = true
    elseif not v and flyActive then
        stopFly()
        flyActive = false
    end
    Fluent:Notify({
        Title   = "Auto Collect",
        Content = v and "✅ AKTIF — terbang ke drops & gems..." or "❌ Dimatikan.",
        Duration = 2
    })
end)

-- ============================================================
-- LOOP: Auto Clear — iterate Workspace.Tiles descendants
-- Tiles > Shadow > [unnamed BaseParts] = block dunia
-- ============================================================
spawn(function()
    while true do
        task.wait(0.05)
        if not state.autoClear then continue end
        if not TilesFolder then
            TilesFolder = Workspace:FindFirstChild("Tiles")
            task.wait(1)
            continue
        end

        -- Kumpulkan semua BasePart di dalam Tiles
        local blocks = {}
        for _, obj in ipairs(TilesFolder:GetDescendants()) do
            if obj:IsA("BasePart") or obj:IsA("MeshPart") then
                table.insert(blocks, obj)
            end
        end

        local count = #blocks
        if count == 0 then
            ScanPara:SetDesc("✅ Semua tile sudah di-break!")
            state.autoClear = false
            AutoClearToggle:SetValue(false)
            Fluent:Notify({Title="Auto Clear", Content="✅ World cleared!", Duration=4})
            continue
        end

        ScanPara:SetDesc("🔨 Breaking... sisa ±" .. count .. " tile")

        for _, obj in ipairs(blocks) do
            if not state.autoClear then break end
            if not obj or not obj.Parent then continue end

            -- Fire posisi tile ke server (X, Y dari Position)
            firePos(obj.Position.X, obj.Position.Y)

            task.wait(state.breakDelay)
        end
    end
end)

-- ============================================================
-- LOOP: Auto Collect — ambil dari Drops dan Gems
-- ============================================================
spawn(function()
    while true do
        task.wait(0.1)

        if not state.autoCollect then
            if flyActive then stopFly(); flyActive = false end
            continue
        end
        if not flyActive then startFly(); flyActive = true end
        if not character or not hrp then continue end

        -- Refresh referensi folder kalau belum ada
        if not DropsFolder then DropsFolder = Workspace:FindFirstChild("Drops") end
        if not GemsFolder  then GemsFolder  = Workspace:FindFirstChild("Gems")  end

        -- Kumpulkan semua target (Drops + Gems)
        local targets = {}

        if DropsFolder then
            for _, obj in ipairs(DropsFolder:GetDescendants()) do
                if obj:IsA("BasePart") or obj:IsA("Model") then
                    -- Ambil posisi (BasePart langsung atau PrimaryPart model)
                    local pos = nil
                    if obj:IsA("BasePart") then
                        pos = obj.Position
                    elseif obj:IsA("Model") and obj.PrimaryPart then
                        pos = obj.PrimaryPart.Position
                    end
                    if pos then
                        table.insert(targets, {pos = pos, obj = obj})
                    end
                end
            end
        end

        if GemsFolder then
            for _, obj in ipairs(GemsFolder:GetDescendants()) do
                if obj:IsA("BasePart") or obj:IsA("Model") then
                    local pos = nil
                    if obj:IsA("BasePart") then
                        pos = obj.Position
                    elseif obj:IsA("Model") and obj.PrimaryPart then
                        pos = obj.PrimaryPart.Position
                    end
                    if pos then
                        table.insert(targets, {pos = pos, obj = obj})
                    end
                end
            end
        end

        if #targets == 0 then
            -- Tidak ada item — diam
            if bv then bv.Velocity = Vector3.zero end
            continue
        end

        -- Ambil yang terdekat
        local nearest, nearDist = nil, math.huge
        for _, t in ipairs(targets) do
            local dist = (t.pos - hrp.Position).Magnitude
            if dist < nearDist then
                nearDist = dist
                nearest  = t
            end
        end

        if nearest then
            -- Terbang ke item
            local arrived = flyToward(nearest.pos + Vector3.new(0, 1, 0))

            -- Saat dekat, fire posisi ke server untuk collect
            if arrived or nearDist < 5 then
                firePos(nearest.pos.X, nearest.pos.Y)
                task.wait(0.05)
            end
        end
    end
end)

-- ============================================================
-- STARTUP — cek remote
-- ============================================================
Window:SelectTab(1)

spawn(function()
    task.wait(2)
    local r = getRemote()
    if r then
        Fluent:Notify({
            Title    = "✅ Remote OK",
            Content  = "PlayerMovementPackets/" .. player.Name .. " terhubung!",
            Duration = 4
        })
    else
        Fluent:Notify({
            Title    = "⚠️ Remote Tidak Ditemukan",
            Content  = "Masuk ke dalam world dulu, baru jalankan script!",
            Duration = 5
        })
    end
end)

Fluent:Notify({
    Title    = "Craft A World v3.0",
    Content  = "Script loaded! Masuk world dulu.",
    Duration = 3
})
