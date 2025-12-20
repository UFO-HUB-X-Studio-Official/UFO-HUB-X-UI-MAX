--[[ 
UFO • Position Saver UI (Standalone) v2
Buttons:
1) Save Position Script (relative to anchor under your feet)
2) Copy Script
3) Test Warp
4) Show Position Numbers (XYZ + Anchor + Relative)
]]

do
    local Players = game:GetService("Players")
    local Workspace = game:GetService("Workspace")
    local UIS = game:GetService("UserInputService")
    local LP = Players.LocalPlayer

    local function getChar() return LP.Character end
    local function getHRP()
        local ch = getChar()
        return ch and ch:FindFirstChild("HumanoidRootPart") or nil
    end

    local function notify(msg)
        pcall(function()
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title = "Position Saver",
                Text = tostring(msg),
                Duration = 4
            })
        end)
    end

    --========================
    -- Anchor Finder (Save)
    --========================
    local function raycastDown(fromPos)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Blacklist
        local ch = getChar()
        params.FilterDescendantsInstances = ch and { ch } or {}
        params.IgnoreWater = true

        return Workspace:Raycast(fromPos, Vector3.new(0, -200, 0), params)
    end

    local function getStandingAnchor()
        local hrp = getHRP()
        if not hrp then return nil end

        local result = raycastDown(hrp.Position)
        if not result or not result.Instance then return nil end

        local inst = result.Instance
        if not inst:IsA("BasePart") then return nil end
        return inst
    end

    --========================
    -- Anchor Finder (Warp)
    --========================
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

    --========================
    -- Stored State
    --========================
    local state = {
        hasData = false,
        anchorName = "",
        modelNameHint = "",
        relative = nil, -- CFrame
        builtScript = "",
        lastSaveAt = 0,
    }

    local function fmt3(n)
        n = tonumber(n) or 0
        return string.format("%.3f", n)
    end

    local function cframeToLua(cf)
        local comps = { cf:GetComponents() }
        local out = {}
        for i = 1, #comps do
            out[i] = string.format("%.6f", comps[i])
        end
        return ("CFrame.new(%s)"):format(table.concat(out, ","))
    end

    local function buildScriptFromState()
        if not state.hasData or not state.relative then return "" end
        local rel = cframeToLua(state.relative)

        local scriptText = ([[
--[[ Position Warp Script (Relative to Anchor)
Saved Anchor Part Name: %s
Model Hint: %s
Relative CFrame: %s
]]

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
]]):format(
            state.anchorName,
            state.modelNameHint,
            rel,
            state.anchorName,
            state.modelNameHint,
            rel
        )

        return scriptText
    end

    local function saveNow()
        local hrp = getHRP()
        if not hrp then
            notify("Character/HRP not ready")
            return
        end

        local anchor = getStandingAnchor()
        if not anchor then
            notify("No anchor found (stand on a part/floor)")
            return
        end

        local model = anchor:FindFirstAncestorOfClass("Model")
        state.anchorName = anchor.Name
        state.modelNameHint = model and model.Name or ""
        state.relative = anchor.CFrame:ToObjectSpace(hrp.CFrame)
        state.hasData = true
        state.lastSaveAt = os.clock()

        state.builtScript = buildScriptFromState()
        notify("Saved! Anchor = "..state.anchorName)
    end

    local function testWarp()
        if not state.hasData or not state.relative then
            notify("No saved position yet")
            return
        end

        local hrp = getHRP()
        if not hrp then
            notify("Character/HRP not ready")
            return
        end

        local anchor = findAnchorInCurrentMap(state.anchorName, hrp.Position, state.modelNameHint)
        if not anchor then
            notify("Anchor not found in this map: "..state.anchorName)
            return
        end

        hrp.CFrame = anchor.CFrame:ToWorldSpace(state.relative)
        notify("Warped ✅ (Anchor: "..anchor.Name..")")
    end

    local function copyScript()
        if not state.builtScript or state.builtScript == "" then
            notify("No script built yet (press Button 1)")
            return
        end

        local ok = false
        if setclipboard then
            ok = pcall(function() setclipboard(state.builtScript) end)
        end

        if ok then
            notify("Copied to clipboard ✅")
        else
            print("===== POSITION WARP SCRIPT =====")
            print(state.builtScript)
            print("===== END =====")
            notify("Clipboard not available → printed in console")
        end
    end

    --========================
    -- Button 4: Show numbers
    --========================
    local function showNumbers()
        local hrp = getHRP()
        if not hrp then
            notify("Character/HRP not ready")
            return
        end

        local anchor = getStandingAnchor()
        local ax = anchor and anchor.Position.X or 0
        local ay = anchor and anchor.Position.Y or 0
        local az = anchor and anchor.Position.Z or 0

        local relTxt = "nil"
        if anchor then
            local rel = anchor.CFrame:ToObjectSpace(hrp.CFrame)
            local p = rel.Position
            relTxt = ("Rel XYZ: %s, %s, %s"):format(fmt3(p.X), fmt3(p.Y), fmt3(p.Z))
        end

        local p = hrp.Position
        local msg =
            ("HRP XYZ: %s, %s, %s\nAnchor: %s\nAnchor XYZ: %s, %s, %s\n%s"):format(
                fmt3(p.X), fmt3(p.Y), fmt3(p.Z),
                anchor and anchor.Name or "None",
                fmt3(ax), fmt3(ay), fmt3(az),
                relTxt
            )

        notify(msg)

        -- extra: print full for copy/manual debug
        print("=== Position Numbers ===")
        print(msg)
        if anchor then
            print("Anchor FullName:", anchor:GetFullName())
        end
        print("========================")
    end

    --========================
    -- Minimal Standalone UI
    --========================
    local function makeGui()
        local sg = Instance.new("ScreenGui")
        sg.Name = "UFO_PosSaver_UI"
        sg.ResetOnSpawn = false
        sg.IgnoreGuiInset = true
        pcall(function()
            sg.Parent = game:GetService("CoreGui")
        end)
        if not sg.Parent then
            sg.Parent = LP:WaitForChild("PlayerGui")
        end

        local main = Instance.new("Frame")
        main.Parent = sg
        main.Size = UDim2.fromOffset(360, 210) -- ✅ taller for button 4
        main.Position = UDim2.new(0, 24, 0, 160)
        main.BackgroundColor3 = Color3.fromRGB(0,0,0)
        main.BorderSizePixel = 0

        local uic = Instance.new("UICorner", main)
        uic.CornerRadius = UDim.new(0, 14)

        local stroke = Instance.new("UIStroke", main)
        stroke.Thickness = 2
        stroke.Color = Color3.fromRGB(25,255,125)

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
        sub.Text = "Uses anchor-under-feet → same house but shifted still matches."

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

            local c = Instance.new("UICorner", b)
            c.CornerRadius = UDim.new(0, 12)

            local s = Instance.new("UIStroke", b)
            s.Thickness = 1.8
            s.Color = Color3.fromRGB(25,255,125)

            b.MouseButton1Click:Connect(function()
                pcall(onClick)
            end)
            return b
        end

        mkBtn("1) Save Position Script", 66, saveNow)
        mkBtn("2) Copy Script", 102, copyScript)
        mkBtn("3) Test Warp", 138, testWarp)
        mkBtn("4) Show Position Numbers", 174, showNumbers) -- ✅ new

        -- drag
        local dragging, dragStart, startPos
        main.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos = main.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dragging = false
                    end
                end)
            end
        end)

        UIS.InputChanged:Connect(function(input)
            if not dragging then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                local delta = input.Position - dragStart
                main.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + delta.X,
                    startPos.Y.Scale, startPos.Y.Offset + delta.Y
                )
            end
        end)

        return sg
    end

    makeGui()
    notify("Loaded Position Saver UI (4 buttons)")
end
