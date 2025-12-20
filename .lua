-- UFO • Position Saver UI (Standalone) v4 - PIVOT ANCHOR + Copy Numbers
do
    local Players = game:GetService("Players")
    local Workspace = game:GetService("Workspace")
    local UIS = game:GetService("UserInputService")
    local StarterGui = game:GetService("StarterGui")

    local LP = Players.LocalPlayer
    if not LP then return end

    local function notify(msg)
        msg = tostring(msg)
        print("[UFO_PosSaver]", msg)
        pcall(function()
            StarterGui:SetCore("SendNotification", { Title="Position Saver", Text=msg, Duration=4 })
        end)
    end

    local function trySetClipboard(text)
        if setclipboard then
            local ok = pcall(function() setclipboard(tostring(text)) end)
            return ok
        end
        return false
    end

    -- ===== choose parent safely =====
    local function getBestGuiParent()
        if typeof(gethui) == "function" then
            local ok, hui = pcall(gethui)
            if ok and hui then return hui, "gethui()" end
        end
        local core = game:GetService("CoreGui")
        if core then return core, "CoreGui" end
        local pg = LP:FindFirstChildOfClass("PlayerGui") or LP:WaitForChild("PlayerGui", 5)
        return pg, "PlayerGui"
    end

    -- ===== cleanup old gui =====
    local function cleanupOld()
        local core = game:GetService("CoreGui")
        local pg = LP:FindFirstChildOfClass("PlayerGui")

        for _, parent in ipairs({core, pg}) do
            if parent then
                local old = parent:FindFirstChild("UFO_PosSaver_UI")
                if old then old:Destroy() end
            end
        end

        if typeof(gethui) == "function" then
            local ok, hui = pcall(gethui)
            if ok and hui then
                local old = hui:FindFirstChild("UFO_PosSaver_UI")
                if old then old:Destroy() end
            end
        end
    end

    cleanupOld()

    -- ===== character helpers =====
    local function getChar() return LP.Character end
    local function getHRP()
        local ch = getChar()
        return ch and ch:FindFirstChild("HumanoidRootPart") or nil
    end

    local function raycastDown(fromPos)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Blacklist
        local ch = getChar()
        params.FilterDescendantsInstances = ch and { ch } or {}
        params.IgnoreWater = true
        return Workspace:Raycast(fromPos, Vector3.new(0, -350, 0), params)
    end

    local function getStandingPart()
        local hrp = getHRP()
        if not hrp then return nil end
        local r = raycastDown(hrp.Position)
        if r and r.Instance and r.Instance:IsA("BasePart") then
            return r.Instance
        end
        return nil
    end

    local function dist(a, b)
        local dx = a.X - b.X
        local dy = a.Y - b.Y
        local dz = a.Z - b.Z
        return math.sqrt(dx*dx + dy*dy + dz*dz)
    end

    -- ===== Pivot Anchor logic =====
    local function getModelPivot(m)
        local ok, pv = pcall(function() return m:GetPivot() end)
        if ok and typeof(pv) == "CFrame" then return pv end
        return nil
    end

    local function pickBestAnchorModel()
        local hrp = getHRP()
        if not hrp then return nil end

        local under = getStandingPart()
        if not under then return nil end

        -- Prefer nearest ancestor Model
        local model = under:FindFirstAncestorOfClass("Model")
        if model and getModelPivot(model) then
            return model
        end

        -- Fallback: find any model nearby by pivot
        local best, bestD = nil, math.huge
        local p = hrp.Position
        for _, d in ipairs(Workspace:GetDescendants()) do
            if d:IsA("Model") then
                local pv = getModelPivot(d)
                if pv then
                    local dd = dist(pv.Position, p)
                    if dd < bestD then
                        bestD = dd
                        best = d
                    end
                end
            end
        end
        return best
    end

    local function findModelByNameNearest(name, preferPos)
        local best, bestD = nil, math.huge
        preferPos = preferPos or (getHRP() and getHRP().Position) or Vector3.new(0,0,0)

        for _, d in ipairs(Workspace:GetDescendants()) do
            if d:IsA("Model") and d.Name == name then
                local pv = getModelPivot(d)
                if pv then
                    local dd = dist(pv.Position, preferPos)
                    if dd < bestD then
                        bestD = dd
                        best = d
                    end
                end
            end
        end
        return best
    end

    local function cframeToLua(cf)
        local comps = { cf:GetComponents() }
        local out = {}
        for i = 1, #comps do out[i] = string.format("%.6f", comps[i]) end
        return ("CFrame.new(%s)"):format(table.concat(out, ","))
    end

    -- ===== stored state =====
    local state = {
        hasData = false,
        anchorModelName = "",
        relative = nil,
        builtScript = "",
    }

    local function buildScriptFromState()
        if not state.hasData or not state.relative then return "" end
        local rel = cframeToLua(state.relative)

        return ([[
-- Position Warp Script (Relative to Model Pivot)
do
    local Players = game:GetService("Players")
    local Workspace = game:GetService("Workspace")
    local LP = Players.LocalPlayer

    local ANCHOR_MODEL_NAME = %q
    local RELATIVE = %s

    local function getHRP()
        local ch = LP.Character
        return ch and ch:FindFirstChild("HumanoidRootPart") or nil
    end

    local function dist(a, b)
        local dx = a.X - b.X
        local dy = a.Y - b.Y
        local dz = a.Z - b.Z
        return math.sqrt(dx*dx + dy*dy + dz*dz)
    end

    local function getPivot(m)
        local ok, pv = pcall(function() return m:GetPivot() end)
        if ok and typeof(pv) == "CFrame" then return pv end
        return nil
    end

    local function findModelNearest(name, preferPos)
        local best, bestD = nil, math.huge
        preferPos = preferPos or Vector3.new(0,0,0)
        for _, d in ipairs(Workspace:GetDescendants()) do
            if d:IsA("Model") and d.Name == name then
                local pv = getPivot(d)
                if pv then
                    local dd = dist(pv.Position, preferPos)
                    if dd < bestD then bestD = dd; best = d end
                end
            end
        end
        return best
    end

    local function warp()
        local hrp = getHRP()
        if not hrp then return end
        local m = findModelNearest(ANCHOR_MODEL_NAME, hrp.Position)
        if not m then
            warn("[PositionWarp] Model not found:", ANCHOR_MODEL_NAME)
            return
        end
        local pv = getPivot(m)
        if not pv then return end
        hrp.CFrame = pv:ToWorldSpace(RELATIVE)
    end

    warp()
end
]]):format(state.anchorModelName, rel)
    end

    local function saveNow()
        local hrp = getHRP()
        if not hrp then notify("Character/HRP not ready"); return end

        local model = pickBestAnchorModel()
        if not model then
            notify("No anchor model found (stand on house/plot floor)")
            return
        end

        local pv = getModelPivot(model)
        if not pv then
            notify("Anchor model has no pivot")
            return
        end

        state.anchorModelName = model.Name
        state.relative = pv:ToObjectSpace(hrp.CFrame)
        state.hasData = true
        state.builtScript = buildScriptFromState()

        notify("Saved ✅ AnchorModel = "..state.anchorModelName.." (Pivot)")
    end

    local function copyScript()
        if not state.builtScript or state.builtScript == "" then
            notify("No script yet → press Button 1")
            return
        end
        if trySetClipboard(state.builtScript) then
            notify("Copied Script ✅")
        else
            print("===== POSITION WARP SCRIPT =====\n"..state.builtScript.."\n===== END =====")
            notify("Clipboard not available → printed in console")
        end
    end

    local function testWarp()
        if not state.hasData or not state.relative then notify("No saved position yet"); return end
        local hrp = getHRP()
        if not hrp then notify("Character/HRP not ready"); return end

        local model = findModelByNameNearest(state.anchorModelName, hrp.Position)
        if not model then notify("Model not found: "..state.anchorModelName); return end
        local pv = getModelPivot(model)
        if not pv then notify("Model has no pivot"); return end

        hrp.CFrame = pv:ToWorldSpace(state.relative)
        notify("Warped ✅")
    end

    local function fmt3(n) return string.format("%.3f", tonumber(n) or 0) end

    local function showNumbersAndCopy()
        local hrp = getHRP()
        if not hrp then notify("Character/HRP not ready"); return end

        local p = hrp.Position
        local under = getStandingPart()
        local model = pickBestAnchorModel()
        local pv = model and getModelPivot(model) or nil

        local text = ""
        text = text .. ("HRP Position:\nX=%s\nY=%s\nZ=%s\n\n"):format(fmt3(p.X), fmt3(p.Y), fmt3(p.Z))

        if under then
            local up = under.Position
            text = text .. ("Standing Part:\n%s\nX=%s Y=%s Z=%s\n\n"):format(under.Name, fmt3(up.X), fmt3(up.Y), fmt3(up.Z))
        else
            text = text .. "Standing Part:\nNone\n\n"
        end

        if model and pv then
            local rel = pv:ToObjectSpace(hrp.CFrame).Position
            text = text .. ("Anchor Model (Pivot):\n%s\nPivot X=%s Y=%s Z=%s\nRel X=%s Y=%s Z=%s"):format(
                model.Name,
                fmt3(pv.Position.X), fmt3(pv.Position.Y), fmt3(pv.Position.Z),
                fmt3(rel.X), fmt3(rel.Y), fmt3(rel.Z)
            )
        else
            text = text .. "Anchor Model (Pivot):\nNone"
        end

        print("=== Position Numbers (Copy this) ===\n"..text.."\n==============================")
        local copied = trySetClipboard(text)
        notify(copied and "Numbers copied ✅ (see console too)" or "Numbers shown (console) ✅")
    end

    -- ===== build UI =====
    local parent, where = getBestGuiParent()

    local sg = Instance.new("ScreenGui")
    sg.Name = "UFO_PosSaver_UI"
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true
    sg.Parent = parent
    if syn and syn.protect_gui then pcall(function() syn.protect_gui(sg) end) end

    local main = Instance.new("Frame")
    main.Parent = sg
    main.Size = UDim2.fromOffset(380, 224)
    main.Position = UDim2.new(0, 24, 0, 160)
    main.BackgroundColor3 = Color3.fromRGB(0,0,0)
    main.BorderSizePixel = 0
    local uic = Instance.new("UICorner", main); uic.CornerRadius = UDim.new(0, 14)
    local st = Instance.new("UIStroke", main); st.Thickness = 2; st.Color = Color3.fromRGB(25,255,125)

    local title = Instance.new("TextLabel")
    title.Parent = main
    title.BackgroundTransparency = 1
    title.Size = UDim2.new(1, -20, 0, 34)
    title.Position = UDim2.new(0, 12, 0, 6)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.TextColor3 = Color3.fromRGB(255,255,255)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "Position Saver 📍 (Pivot Anchor)"

    local sub = Instance.new("TextLabel")
    sub.Parent = main
    sub.BackgroundTransparency = 1
    sub.Size = UDim2.new(1, -20, 0, 22)
    sub.Position = UDim2.new(0, 12, 0, 36)
    sub.Font = Enum.Font.Gotham
    sub.TextSize = 12
    sub.TextColor3 = Color3.fromRGB(200,200,200)
    sub.TextXAlignment = Enum.TextXAlignment.Left
    sub.Text = "Fix: multiple saves stay correct even if house/plot shifts."

    local function mkBtn(text, y, onClick)
        local b = Instance.new("TextButton")
        b.Parent = main
        b.Size = UDim2.new(1, -24, 0, 32)
        b.Position = UDim2.new(0, 12, 0, y)
        b.BackgroundColor3 = Color3.fromRGB(0,0,0)
        b.TextColor3 = Color3.fromRGB(255,255,255)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 13
        b.Text = text
        b.AutoButtonColor = false
        b.BorderSizePixel = 0
        local c = Instance.new("UICorner", b); c.CornerRadius = UDim.new(0, 12)
        local s = Instance.new("UIStroke", b); s.Thickness = 1.8; s.Color = Color3.fromRGB(25,255,125)
        b.MouseButton1Click:Connect(function() pcall(onClick) end)
        return b
    end

    mkBtn("1) Save Position Script (Pivot)", 66, saveNow)
    mkBtn("2) Copy Script", 102, copyScript)
    mkBtn("3) Test Warp", 138, testWarp)
    mkBtn("4) Show + Copy Numbers", 174, showNumbersAndCopy)

    -- drag
    local dragging, dragStart, startPos
    main.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)

    UIS.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    notify("UI Created ✅ Parent = "..where.." | v4 Pivot Anchor")
end
