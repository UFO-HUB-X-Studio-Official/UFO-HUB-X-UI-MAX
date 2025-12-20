-- UFO • Position Saver UI (Standalone) v3 - FIX "not showing"
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

    -- ===== choose parent safely =====
    local function getBestGuiParent()
        -- 1) executor UI container (if exists)
        if typeof(gethui) == "function" then
            local ok, hui = pcall(gethui)
            if ok and hui then return hui, "gethui()" end
        end

        -- 2) CoreGui (sometimes blocked)
        local core = game:GetService("CoreGui")
        if core then return core, "CoreGui" end

        -- 3) PlayerGui fallback
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
        return Workspace:Raycast(fromPos, Vector3.new(0, -250, 0), params)
    end

    local function getStandingAnchor()
        local hrp = getHRP()
        if not hrp then return nil end
        local r = raycastDown(hrp.Position)
        if not r or not r.Instance then return nil end
        local inst = r.Instance
        if inst:IsA("BasePart") then return inst end
        return nil
    end

    local function dist(a, b)
        local dx = a.X - b.X
        local dy = a.Y - b.Y
        local dz = a.Z - b.Z
        return math.sqrt(dx*dx + dy*dy + dz*dz)
    end

    local function findAnchorInCurrentMap(anchorName, preferPos, modelNameHint)
        local best, bestD = nil, math.huge
        preferPos = preferPos or (getHRP() and getHRP().Position) or Vector3.new(0,0,0)

        for _, d in ipairs(Workspace:GetDescendants()) do
            if d:IsA("BasePart") and d.Name == anchorName then
                if modelNameHint and modelNameHint ~= "" then
                    local m = d:FindFirstAncestorOfClass("Model")
                    if m and m.Name ~= modelNameHint then
                        local dd = dist(d.Position, preferPos) + 999
                        if dd < bestD then bestD = dd; best = d end
                        continue
                    end
                end
                local dd = dist(d.Position, preferPos)
                if dd < bestD then bestD = dd; best = d end
            end
        end
        return best
    end

    -- ===== stored state =====
    local state = {
        hasData = false,
        anchorName = "",
        modelNameHint = "",
        relative = nil,
        builtScript = "",
    }

    local function fmt3(n)
        n = tonumber(n) or 0
        return string.format("%.3f", n)
    end

    local function cframeToLua(cf)
        local comps = { cf:GetComponents() }
        local out = {}
        for i = 1, #comps do out[i] = string.format("%.6f", comps[i]) end
        return ("CFrame.new(%s)"):format(table.concat(out, ","))
    end

    local function buildScriptFromState()
        if not state.hasData or not state.relative then return "" end
        local rel = cframeToLua(state.relative)

        local scriptText = ([[
-- Position Warp Script (Relative to Anchor)
do
    local Players = game:GetService("Players")
    local Workspace = game:GetService("Workspace")
    local LP = Players.LocalPlayer

    local ANCHOR_NAME = %q
    local MODEL_HINT  = %q
    local RELATIVE    = %s

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

    local function findAnchor(preferPos)
        local best, bestD = nil, math.huge
        preferPos = preferPos or Vector3.new(0,0,0)

        for _, d in ipairs(Workspace:GetDescendants()) do
            if d:IsA("BasePart") and d.Name == ANCHOR_NAME then
                if MODEL_HINT and MODEL_HINT ~= "" then
                    local m = d:FindFirstAncestorOfClass("Model")
                    if m and m.Name ~= MODEL_HINT then
                        local dd = dist(d.Position, preferPos) + 999
                        if dd < bestD then bestD = dd; best = d end
                        continue
                    end
                end
                local dd = dist(d.Position, preferPos)
                if dd < bestD then bestD = dd; best = d end
            end
        end
        return best
    end

    local function warp()
        local hrp = getHRP()
        if not hrp then return end
        local anchor = findAnchor(hrp.Position)
        if not anchor then
            warn("[PositionWarp] Anchor not found:", ANCHOR_NAME)
            return
        end
        hrp.CFrame = anchor.CFrame:ToWorldSpace(RELATIVE)
    end

    warp()
end
]]):format(state.anchorName, state.modelNameHint, rel)

        return scriptText
    end

    local function saveNow()
        local hrp = getHRP()
        if not hrp then notify("Character/HRP not ready"); return end

        local anchor = getStandingAnchor()
        if not anchor then notify("No anchor found (stand on a part/floor)"); return end

        local model = anchor:FindFirstAncestorOfClass("Model")
        state.anchorName = anchor.Name
        state.modelNameHint = model and model.Name or ""
        state.relative = anchor.CFrame:ToObjectSpace(hrp.CFrame)
        state.hasData = true
        state.builtScript = buildScriptFromState()
        notify("Saved ✅ Anchor = "..state.anchorName)
    end

    local function copyScript()
        if not state.builtScript or state.builtScript == "" then
            notify("No script yet → press Button 1")
            return
        end
        local ok = false
        if setclipboard then ok = pcall(function() setclipboard(state.builtScript) end) end
        if ok then
            notify("Copied ✅")
        else
            print("===== POSITION WARP SCRIPT =====\n"..state.builtScript.."\n===== END =====")
            notify("Clipboard not available → printed in console")
        end
    end

    local function testWarp()
        if not state.hasData or not state.relative then notify("No saved position yet"); return end
        local hrp = getHRP()
        if not hrp then notify("Character/HRP not ready"); return end

        local anchor = findAnchorInCurrentMap(state.anchorName, hrp.Position, state.modelNameHint)
        if not anchor then notify("Anchor not found in this map: "..state.anchorName); return end

        hrp.CFrame = anchor.CFrame:ToWorldSpace(state.relative)
        notify("Warped ✅")
    end

    local function showNumbers()
        local hrp = getHRP()
        if not hrp then notify("Character/HRP not ready"); return end

        local anchor = getStandingAnchor()
        local p = hrp.Position

        local msg = ("HRP XYZ: %s, %s, %s"):format(fmt3(p.X), fmt3(p.Y), fmt3(p.Z))
        if anchor then
            local ap = anchor.Position
            local rel = anchor.CFrame:ToObjectSpace(hrp.CFrame).Position
            msg = msg .. ("\nAnchor: %s\nAnchor XYZ: %s, %s, %s\nRel XYZ: %s, %s, %s"):format(
                anchor.Name,
                fmt3(ap.X), fmt3(ap.Y), fmt3(ap.Z),
                fmt3(rel.X), fmt3(rel.Y), fmt3(rel.Z)
            )
            print("Anchor FullName:", anchor:GetFullName())
        else
            msg = msg .. "\nAnchor: None"
        end

        notify(msg)
        print("=== Position Numbers ===\n"..msg.."\n========================")
    end

    -- ===== build UI =====
    local parent, where = getBestGuiParent()

    local sg = Instance.new("ScreenGui")
    sg.Name = "UFO_PosSaver_UI"
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true
    sg.Parent = parent

    -- (optional) protect gui if executor supports it
    if syn and syn.protect_gui then pcall(function() syn.protect_gui(sg) end) end

    local main = Instance.new("Frame")
    main.Parent = sg
    main.Size = UDim2.fromOffset(360, 212)
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
    title.Text = "Position Saver 📍 (Standalone)"

    local sub = Instance.new("TextLabel")
    sub.Parent = main
    sub.BackgroundTransparency = 1
    sub.Size = UDim2.new(1, -20, 0, 22)
    sub.Position = UDim2.new(0, 12, 0, 36)
    sub.Font = Enum.Font.Gotham
    sub.TextSize = 12
    sub.TextColor3 = Color3.fromRGB(200,200,200)
    sub.TextXAlignment = Enum.TextXAlignment.Left
    sub.Text = "Anchor-under-feet → keep same spot even if house shifted."

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

    mkBtn("1) Save Position Script", 66, saveNow)
    mkBtn("2) Copy Script", 102, copyScript)
    mkBtn("3) Test Warp", 138, testWarp)
    mkBtn("4) Show Position Numbers", 174, showNumbers)

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

    notify("UI Created ✅ Parent = "..where.." | Name = UFO_PosSaver_UI")
end
