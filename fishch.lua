-- Craft A World Script - Minimal Edition
-- WARNING: Educational purposes only. Use at your own risk.

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

-- Services
local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local Workspace           = game:GetService("Workspace")

local player    = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local hrp       = character:WaitForChild("HumanoidRootPart")

player.CharacterAdded:Connect(function(char)
    character = char
    hrp = char:WaitForChild("HumanoidRootPart")
end)

-- State
local state = {
    autoClearWorld  = false,
    autoCollect     = false,
    scannedBlocks   = {},
}

-- ============================================================
-- WINDOW
-- ============================================================
local Window = Fluent:CreateWindow({
    Title        = "Craft A World",
    SubTitle     = "Script v1.0",
    TabWidth     = 160,
    Size         = UDim2.fromOffset(500, 420),
    Acrylic      = true,
    Theme        = "Darker",
    MinimizeKey  = Enum.KeyCode.RightControl
})

-- ============================================================
-- HOME TAB (satu-satunya tab)
-- ============================================================
local HomeTab = Window:AddTab({ Title = "Home", Icon = "home" })

-- ── Header ───────────────────────────────────────────────────
local HeaderSection = HomeTab:AddSection("Craft A World - Main")
HeaderSection:AddParagraph({
    Title   = "Welcome!",
    Content = "Script aktif. Minimize: Right Ctrl\nScan dulu sebelum aktifkan Auto Clear World."
})

-- ── Auto Clear World ──────────────────────────────────────────
local ClearSection = HomeTab:AddSection("Auto Clear World")

-- Paragraf hasil scan — akan di-update setelah scan
local ScanResultParagraph = ClearSection:AddParagraph({
    Title   = "Hasil Scan",
    Content = "Belum ada scan. Tekan tombol Scan World dulu."
})

-- Helper: scan semua BasePart di Workspace yang bukan milik karakter
local function scanBlocks()
    local found = {}
    local seen  = {}

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if (obj:IsA("BasePart") or obj:IsA("MeshPart") or obj:IsA("UnionOperation"))
            and not obj:IsDescendantOf(character)
            and obj.Name ~= "Baseplate"
            and obj.Name ~= "HumanoidRootPart"
            and obj.Name ~= "Head"
            and not obj.Locked
        then
            if not seen[obj.Name] then
                seen[obj.Name] = true
                table.insert(found, obj.Name)
            end
        end
    end

    return found
end

-- Tombol Scan World
ClearSection:AddButton({
    Title       = "🔍 Scan World",
    Description = "Deteksi block yang ada di world (Dirt, Background, dll)",
    Callback    = function()
        state.scannedBlocks = scanBlocks()

        if #state.scannedBlocks == 0 then
            ScanResultParagraph:SetDesc("Tidak ada block yang terdeteksi.")
        else
            local display = {}
            for i = 1, math.min(12, #state.scannedBlocks) do
                table.insert(display, "• " .. state.scannedBlocks[i])
            end
            if #state.scannedBlocks > 12 then
                table.insert(display, "... dan " .. (#state.scannedBlocks - 12) .. " block lainnya")
            end
            ScanResultParagraph:SetDesc(
                "✅ Ditemukan " .. #state.scannedBlocks .. " jenis block:\n"
                .. table.concat(display, "\n")
            )
        end

        Fluent:Notify({
            Title    = "Scan Selesai",
            Content  = "Terdeteksi " .. #state.scannedBlocks .. " jenis block.",
            Duration = 3
        })
    end
})

-- Toggle Auto Clear World
local AutoClearToggle = ClearSection:AddToggle("AutoClearWorld", {
    Title       = "Auto Clear World",
    Description = "Otomatis break semua block yang terdeteksi dari hasil scan",
    Default     = false
})

AutoClearToggle:OnChanged(function(value)
    if value and #state.scannedBlocks == 0 then
        Fluent:Notify({
            Title    = "Peringatan!",
            Content  = "Scan world dulu sebelum mengaktifkan Auto Clear!",
            Duration = 4
        })
        state.autoClearWorld = false
        AutoClearToggle:SetValue(false)
        return
    end
    state.autoClearWorld = value
    Fluent:Notify({
        Title    = "Auto Clear World",
        Content  = value and "✅ AKTIF — Breaking blocks..." or "❌ Dimatikan.",
        Duration = 2
    })
end)

-- ── Auto Collect Floating Items ───────────────────────────────
local CollectSection = HomeTab:AddSection("Auto Collect Floating Items")

CollectSection:AddParagraph({
    Title   = "Info",
    Content = "Otomatis mengambil semua item / drop yang melayang\ndi world agar langsung masuk ke inventory kamu."
})

local AutoCollectToggle = CollectSection:AddToggle("AutoCollect", {
    Title       = "Auto Collect Floating Items",
    Description = "Aktifkan untuk mengambil semua item drop secara otomatis",
    Default     = false
})

AutoCollectToggle:OnChanged(function(value)
    state.autoCollect = value
    Fluent:Notify({
        Title    = "Auto Collect",
        Content  = value and "✅ AKTIF — Mengambil item..." or "❌ Dimatikan.",
        Duration = 2
    })
end)

-- ============================================================
-- BACKGROUND LOOPS
-- ============================================================

-- ── Loop: Auto Clear World ────────────────────────────────────
spawn(function()
    while true do
        task.wait(0.15)

        if state.autoClearWorld and #state.scannedBlocks > 0 and character and hrp then
            -- Buat lookup table nama block yang di-scan
            local targetNames = {}
            for _, name in ipairs(state.scannedBlocks) do
                targetNames[name] = true
            end

            -- Cari remote break yang umum dipakai
            local function findRemote(remoteName)
                for _, folder in ipairs({ "Events", "RemoteEvents", "Remotes", "RE", "events" }) do
                    local f = ReplicatedStorage:FindFirstChild(folder)
                    if f then
                        local r = f:FindFirstChild(remoteName)
                        if r then return r end
                    end
                end
                return ReplicatedStorage:FindFirstChild(remoteName)
            end

            local breakRemote = findRemote("BreakBlock")
                or findRemote("breakBlock")
                or findRemote("Break")
                or findRemote("HitBlock")
                or findRemote("PunchBlock")
                or findRemote("Punch")

            for _, obj in ipairs(Workspace:GetDescendants()) do
                if not state.autoClearWorld then break end

                local isTarget = (obj:IsA("BasePart") or obj:IsA("MeshPart") or obj:IsA("UnionOperation"))
                    and targetNames[obj.Name]
                    and not obj:IsDescendantOf(character)
                    and not obj.Locked

                if isTarget then
                    -- Teleport dekat block
                    hrp.CFrame = CFrame.new(obj.Position + Vector3.new(0, 2, 0))

                    -- Fire remote jika ada
                    if breakRemote then
                        pcall(function()
                            if breakRemote:IsA("RemoteEvent") then
                                breakRemote:FireServer(obj, obj.Position)
                            elseif breakRemote:IsA("RemoteFunction") then
                                breakRemote:InvokeServer(obj, obj.Position)
                            end
                        end)
                    end

                    -- Fallback: ClickDetector
                    local cd = obj:FindFirstChildWhichIsA("ClickDetector")
                    if cd then
                        pcall(fireclickdetector, cd)
                    end

                    -- Fallback: TouchInterest (pukul via sentuhan)
                    local ti = obj:FindFirstChild("TouchInterest")
                    if ti then
                        pcall(firetouchinterest, hrp, obj, 0)
                        task.wait(0.02)
                        pcall(firetouchinterest, hrp, obj, 1)
                    end

                    task.wait(0.05)
                end
            end
        end
    end
end)

-- ── Loop: Auto Collect Floating Items ────────────────────────
spawn(function()
    while true do
        task.wait(0.2)

        if state.autoCollect and hrp and character then
            for _, obj in ipairs(Workspace:GetDescendants()) do
                if not state.autoCollect then break end

                -- Deteksi item drop berdasarkan nama umum
                local name = obj.Name:lower()
                local isItem = obj:IsA("BasePart")
                    and not obj:IsDescendantOf(character)
                    and (
                        name:find("drop")   or
                        name:find("item")   or
                        name:find("pickup") or
                        name:find("gem")    or
                        name:find("coin")   or
                        name:find("seed")   or
                        name:find("float")  or
                        name:find("reward") or
                        name:find("block")  or
                        name:find("loot")
                    )

                if isItem then
                    local dist = (obj.Position - hrp.Position).Magnitude
                    if dist < 300 then
                        -- Teleport ke posisi item
                        hrp.CFrame = CFrame.new(obj.Position + Vector3.new(0, 2, 0))
                        task.wait(0.08)

                        -- Coba fire remote collect
                        local function tryCollect(remoteName)
                            for _, folder in ipairs({ "Events", "RemoteEvents", "Remotes", "RE", "events" }) do
                                local f = ReplicatedStorage:FindFirstChild(folder)
                                if f then
                                    local r = f:FindFirstChild(remoteName)
                                    if r and r:IsA("RemoteEvent") then
                                        pcall(function() r:FireServer(obj) end)
                                        return true
                                    end
                                end
                            end
                            return false
                        end

                        tryCollect("CollectItem")
                        tryCollect("collectItem")
                        tryCollect("PickupItem")
                        tryCollect("Collect")
                        tryCollect("PickUp")

                        -- Fallback TouchInterest
                        local ti = obj:FindFirstChild("TouchInterest")
                        if ti then
                            pcall(firetouchinterest, hrp, obj, 0)
                            task.wait(0.05)
                            pcall(firetouchinterest, hrp, obj, 1)
                        end
                    end
                end
            end
        end
    end
end)

-- ============================================================
-- STARTUP
-- ============================================================
Window:SelectTab(1)

Fluent:Notify({
    Title    = "Craft A World Script",
    Content  = "Loaded! Scan world dulu sebelum auto clear.",
    Duration = 5
})
