--// ===== Exploit Remote Monitor + Admin UI (Roblox) =====
--// Paste as ONE script in ServerScriptService
--// What it does:
--// 1) Hooks RemoteEvents/RemoteFunctions callbacks to log who called + args
--// 2) Admin can open a live log UI (client) and filter/search
--// 3) Basic spam detection (rate) to highlight suspicious callers
--// Notes:
--// - You CANNOT see hacker "code", only the Remote name + arguments they sent.
--// - This helps you patch server-side validation on the specific remotes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

--========================
-- CONFIG
--========================
local ADMIN_USER_IDS = {
	-- ใส่ UserId ของคุณ/ทีมงาน
	-- ตัวอย่าง: [12345678] = true,
}
-- ถ้าไม่ใส่เลย จะให้เจ้าของเกม (Creator) ดูได้อัตโนมัติ
local ALLOW_CREATOR = true

local MAX_LOGS = 600          -- จำนวน log เก็บสูงสุด (ring buffer)
local MAX_ARG_CHARS = 1400    -- จำกัดความยาว args ที่ serialize (กัน UI หน่วง/โดนปั่น)
local RATE_WINDOW = 3         -- วินาที
local RATE_LIMIT = 18         -- เรียกเกินนี้ใน window = ติดธง suspicious

--========================
-- Remote for admin UI
--========================
local MON_FOLDER = ReplicatedStorage:FindFirstChild("_UFOX_MONITOR") or Instance.new("Folder")
MON_FOLDER.Name = "_UFOX_MONITOR"
MON_FOLDER.Parent = ReplicatedStorage

local RF_GET = MON_FOLDER:FindFirstChild("GetLogs") or Instance.new("RemoteFunction")
RF_GET.Name = "GetLogs"
RF_GET.Parent = MON_FOLDER

local RE_PUSH = MON_FOLDER:FindFirstChild("Push") or Instance.new("RemoteEvent")
RE_PUSH.Name = "Push"
RE_PUSH.Parent = MON_FOLDER

local RE_CMD = MON_FOLDER:FindFirstChild("Cmd") or Instance.new("RemoteEvent")
RE_CMD.Name = "Cmd"
RE_CMD.Parent = MON_FOLDER

--========================
-- Utilities
--========================
local function isAdmin(plr: Player)
	if ADMIN_USER_IDS[plr.UserId] then return true end
	if ALLOW_CREATOR then
		local creatorId = game.CreatorId
		local creatorType = game.CreatorType
		if creatorType == Enum.CreatorType.User and plr.UserId == creatorId then
			return true
		end
	end
	return false
end

local function safeToString(v, depth)
	depth = depth or 0
	if depth > 3 then return "<depth_limit>" end

	local t = typeof(v)
	if t == "string" then
		if #v > 220 then return v:sub(1, 220) .. "...(+)" end
		return v
	elseif t == "number" or t == "boolean" or t == "nil" then
		return tostring(v)
	elseif t == "Instance" then
		return ("<%s:%s>"):format(v.ClassName, v.Name)
	elseif t == "Vector3" or t == "CFrame" or t == "Color3" then
		return tostring(v)
	elseif t == "table" then
		local out = {}
		local n = 0
		for k, val in pairs(v) do
			n += 1
			if n > 20 then
				out[#out+1] = "...(+more)"
				break
			end
			out[#out+1] = ("[%s]=%s"):format(safeToString(k, depth+1), safeToString(val, depth+1))
		end
		return "{ " .. table.concat(out, ", ") .. " }"
	else
		return ("<%s>"):format(t)
	end
end

local function packArgs(...)
	local arr = table.pack(...)
	local parts = {}
	for i = 1, arr.n do
		parts[#parts+1] = safeToString(arr[i], 0)
	end
	local s = table.concat(parts, " | ")
	if #s > MAX_ARG_CHARS then
		s = s:sub(1, MAX_ARG_CHARS) .. "...(trunc)"
	end
	return s
end

--========================
-- Ring Buffer Logs
--========================
local LOGS = {}
local logHead = 0
local logCount = 0
local logId = 0

local function addLog(entry)
	logId += 1
	entry.id = logId

	logHead = (logHead % MAX_LOGS) + 1
	LOGS[logHead] = entry
	logCount = math.min(logCount + 1, MAX_LOGS)

	-- push to admins live
	RE_PUSH:FireAllClients(entry)
end

local function getAllLogs()
	local out = {}
	-- oldest -> newest
	local start = (logHead - logCount + 1)
	for i = 0, logCount - 1 do
		local idx = ((start + i - 1) % MAX_LOGS) + 1
		out[#out+1] = LOGS[idx]
	end
	return out
end

--========================
-- Rate tracking (suspicious)
--========================
local RATE = {} -- [userId][key] = {t0, count}
local function bumpRate(userId, key)
	local now = os.clock()
	RATE[userId] = RATE[userId] or {}
	local r = RATE[userId][key]
	if not r then
		r = { t0 = now, count = 0 }
		RATE[userId][key] = r
	end
	if (now - r.t0) > RATE_WINDOW then
		r.t0 = now
		r.count = 0
	end
	r.count += 1
	return r.count
end

--========================
-- Hooking Remotes
--========================
local function hookRemoteEvent(re: RemoteEvent, path: string)
	if re:GetAttribute("__UFOX_HOOKED") then return end
	re:SetAttribute("__UFOX_HOOKED", true)

	local old = re.OnServerEvent
	re.OnServerEvent = function(plr: Player, ...)
		local args = packArgs(...)
		local rateKey = ("RE:%s"):format(path)
		local c = bumpRate(plr.UserId, rateKey)

		addLog({
			kind = "RemoteEvent",
			remote = re.Name,
			path = path,
			player = ("%s (%d)"):format(plr.Name, plr.UserId),
			args = args,
			rate = c,
			suspicious = (c >= RATE_LIMIT),
			time = os.date("!%Y-%m-%d %H:%M:%S") .. "Z",
		})

		if typeof(old) == "function" then
			return old(plr, ...)
		end
	end
end

local function hookRemoteFunction(rf: RemoteFunction, path: string)
	if rf:GetAttribute("__UFOX_HOOKED") then return end
	rf:SetAttribute("__UFOX_HOOKED", true)

	local old = rf.OnServerInvoke
	rf.OnServerInvoke = function(plr: Player, ...)
		local args = packArgs(...)
		local rateKey = ("RF:%s"):format(path)
		local c = bumpRate(plr.UserId, rateKey)

		addLog({
			kind = "RemoteFunction",
			remote = rf.Name,
			path = path,
			player = ("%s (%d)"):format(plr.Name, plr.UserId),
			args = args,
			rate = c,
			suspicious = (c >= RATE_LIMIT),
			time = os.date("!%Y-%m-%d %H:%M:%S") .. "Z",
		})

		if typeof(old) == "function" then
			return old(plr, ...)
		end
		-- default: nil
		return nil
	end
end

local function fullPath(inst: Instance)
	local parts = {}
	local cur = inst
	while cur and cur ~= game do
		parts[#parts+1] = cur.Name
		cur = cur.Parent
	end
	table.reverse(parts)
	return table.concat(parts, ".")
end

local function scanAndHook(root: Instance)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("RemoteEvent") then
			hookRemoteEvent(d, fullPath(d))
		elseif d:IsA("RemoteFunction") then
			hookRemoteFunction(d, fullPath(d))
		end
	end
end

-- initial scan
scanAndHook(game)

-- hook newly added remotes
game.DescendantAdded:Connect(function(d)
	if d:IsA("RemoteEvent") then
		hookRemoteEvent(d, fullPath(d))
	elseif d:IsA("RemoteFunction") then
		hookRemoteFunction(d, fullPath(d))
	end
end)

--========================
-- Admin UI injection (client)
--========================
local CLIENT_UI_SOURCE = [[
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

local F = ReplicatedStorage:WaitForChild("_UFOX_MONITOR")
local RF_GET = F:WaitForChild("GetLogs")
local RE_PUSH = F:WaitForChild("Push")
local RE_CMD = F:WaitForChild("Cmd")

local gui = Instance.new("ScreenGui")
gui.Name = "UFOX_RemoteMonitor"
gui.ResetOnSpawn = false
gui.Parent = LP:WaitForChild("PlayerGui")

local main = Instance.new("Frame")
main.Parent = gui
main.Size = UDim2.fromOffset(640, 360)
main.Position = UDim2.new(1, -660, 1, -390)
main.BackgroundColor3 = Color3.fromRGB(10,10,10)
main.BorderSizePixel = 0

local uic = Instance.new("UICorner", main); uic.CornerRadius = UDim.new(0, 12)
local st = Instance.new("UIStroke", main); st.Thickness = 2; st.Color = Color3.fromRGB(25,255,125)

local top = Instance.new("Frame", main)
top.Size = UDim2.new(1,0,0,42)
top.BackgroundTransparency = 1

local title = Instance.new("TextLabel", top)
title.BackgroundTransparency = 1
title.Position = UDim2.new(0,12,0,0)
title.Size = UDim2.new(1,-24,1,0)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(255,255,255)
title.Text = "Remote Monitor (Server Logs)"

local search = Instance.new("TextBox", main)
search.Position = UDim2.new(0,12,0,48)
search.Size = UDim2.new(1,-24,0,30)
search.PlaceholderText = "ค้นหา: player / remote / args / path"
search.Text = ""
search.ClearTextOnFocus = false
search.Font = Enum.Font.Gotham
search.TextSize = 14
search.TextColor3 = Color3.fromRGB(255,255,255)
search.BackgroundColor3 = Color3.fromRGB(0,0,0)
local sc = Instance.new("UICorner", search); sc.CornerRadius = UDim.new(0,10)
local ss = Instance.new("UIStroke", search); ss.Thickness = 1.6; ss.Color = Color3.fromRGB(25,255,125)

local btnClear = Instance.new("TextButton", main)
btnClear.Position = UDim2.new(0,12,1,-38)
btnClear.Size = UDim2.fromOffset(120,28)
btnClear.Text = "Clear"
btnClear.Font = Enum.Font.GothamBold
btnClear.TextSize = 14
btnClear.TextColor3 = Color3.fromRGB(255,255,255)
btnClear.BackgroundColor3 = Color3.fromRGB(0,0,0)
btnClear.AutoButtonColor = false
local bc = Instance.new("UICorner", btnClear); bc.CornerRadius = UDim.new(0,10)
local bs = Instance.new("UIStroke", btnClear); bs.Thickness = 1.6; bs.Color = Color3.fromRGB(255,40,40)

local btnRefresh = Instance.new("TextButton", main)
btnRefresh.Position = UDim2.new(0,140,1,-38)
btnRefresh.Size = UDim2.fromOffset(120,28)
btnRefresh.Text = "Refresh"
btnRefresh.Font = Enum.Font.GothamBold
btnRefresh.TextSize = 14
btnRefresh.TextColor3 = Color3.fromRGB(255,255,255)
btnRefresh.BackgroundColor3 = Color3.fromRGB(0,0,0)
btnRefresh.AutoButtonColor = false
local rc = Instance.new("UICorner", btnRefresh); rc.CornerRadius = UDim.new(0,10)
local rs = Instance.new("UIStroke", btnRefresh); rs.Thickness = 1.6; rs.Color = Color3.fromRGB(25,255,125)

local list = Instance.new("ScrollingFrame", main)
list.Position = UDim2.new(0,12,0,86)
list.Size = UDim2.new(1,-24,1,-136)
list.BackgroundTransparency = 1
list.ScrollBarThickness = 6
list.CanvasSize = UDim2.new(0,0,0,0)
list.AutomaticCanvasSize = Enum.AutomaticSize.Y

local lay = Instance.new("UIListLayout", list)
lay.Padding = UDim.new(0,8)
lay.SortOrder = Enum.SortOrder.LayoutOrder

local function norm(s)
	s = tostring(s or ""):lower()
	s = s:gsub("%s+"," ")
	return s
end

local cards = {}
local function makeCard(e)
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1,0,0,86)
	f.BackgroundColor3 = Color3.fromRGB(0,0,0)
	f.BorderSizePixel = 0
	local c = Instance.new("UICorner", f); c.CornerRadius = UDim.new(0,12)
	local s = Instance.new("UIStroke", f); s.Thickness = 1.6
	s.Color = e.suspicious and Color3.fromRGB(255,40,40) or Color3.fromRGB(25,255,125)

	local t = Instance.new("TextLabel", f)
	t.BackgroundTransparency = 1
	t.Position = UDim2.new(0,12,0,8)
	t.Size = UDim2.new(1,-24,0,18)
	t.Font = Enum.Font.GothamBold
	t.TextSize = 13
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextColor3 = Color3.fromRGB(255,255,255)
	t.Text = string.format("[%s] %s • %s", e.kind, e.remote, e.time)

	local p = Instance.new("TextLabel", f)
	p.BackgroundTransparency = 1
	p.Position = UDim2.new(0,12,0,28)
	p.Size = UDim2.new(1,-24,0,18)
	p.Font = Enum.Font.Gotham
	p.TextSize = 12
	p.TextXAlignment = Enum.TextXAlignment.Left
	p.TextColor3 = Color3.fromRGB(200,200,200)
	p.Text = string.format("player: %s | rate:%s | path: %s", e.player, tostring(e.rate), e.path)

	local a = Instance.new("TextLabel", f)
	a.BackgroundTransparency = 1
	a.Position = UDim2.new(0,12,0,46)
	a.Size = UDim2.new(1,-24,0,34)
	a.Font = Enum.Font.Code
	a.TextSize = 12
	a.TextWrapped = true
	a.TextXAlignment = Enum.TextXAlignment.Left
	a.TextYAlignment = Enum.TextYAlignment.Top
	a.TextColor3 = Color3.fromRGB(255,255,255)
	a.Text = "args: " .. tostring(e.args or "")

	f:SetAttribute("_q", norm(e.kind).." "..norm(e.remote).." "..norm(e.path).." "..norm(e.player).." "..norm(e.args))
	return f
end

local function rebuild(logs)
	for _, v in ipairs(cards) do
		if v and v.Parent then v:Destroy() end
	end
	table.clear(cards)

	for i = 1, #logs do
		local e = logs[i]
		local card = makeCard(e)
		card.LayoutOrder = i
		card.Parent = list
		cards[#cards+1] = card
	end
end

local function applyFilter()
	local q = norm(search.Text)
	for _, f in ipairs(cards) do
		local hay = f:GetAttribute("_q") or ""
		f.Visible = (q == "" or hay:find(q, 1, true) ~= nil)
	end
end

search:GetPropertyChangedSignal("Text"):Connect(applyFilter)

btnRefresh.MouseButton1Click:Connect(function()
	local ok, logs = pcall(function() return RF_GET:InvokeServer() end)
	if ok and typeof(logs) == "table" then
		rebuild(logs)
		applyFilter()
	end
end)

btnClear.MouseButton1Click:Connect(function()
	RE_CMD:FireServer("clear")
	task.wait(0.1)
	local ok, logs = pcall(function() return RF_GET:InvokeServer() end)
	if ok and typeof(logs) == "table" then
		rebuild(logs)
		applyFilter()
	end
end)

-- live push
RE_PUSH.OnClientEvent:Connect(function(e)
	-- append
	local card = makeCard(e)
	card.LayoutOrder = (#cards + 1)
	card.Parent = list
	cards[#cards+1] = card
	applyFilter()
end)

-- first load
task.defer(function()
	local ok, logs = pcall(function() return RF_GET:InvokeServer() end)
	if ok and typeof(logs) == "table" then
		rebuild(logs)
		applyFilter()
	end
end)
]]

--========================
-- Wire server <-> client
--========================
RF_GET.OnServerInvoke = function(plr)
	if not isAdmin(plr) then return {} end
	return getAllLogs()
end

RE_CMD.OnServerEvent:Connect(function(plr, cmd)
	if not isAdmin(plr) then return end
	if cmd == "clear" then
		table.clear(LOGS)
		logHead = 0
		logCount = 0
		addLog({
			kind="SYSTEM",
			remote="(monitor)",
			path="",
			player=("%s (%d)"):format(plr.Name, plr.UserId),
			args="logs cleared",
			rate=0,
			suspicious=false,
			time=os.date("!%Y-%m-%d %H:%M:%S").."Z",
		})
	end
end)

-- inject UI for admins only
Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function()
		if not isAdmin(plr) then return end
		local ps = plr:WaitForChild("PlayerScripts")
		local ls = Instance.new("LocalScript")
		ls.Name = "UFOX_RemoteMonitorClient"
		ls.Source = CLIENT_UI_SOURCE
		ls.Parent = ps
	end)
end)

addLog({
	kind="SYSTEM",
	remote="(monitor)",
	path="ServerScriptService",
	player="server",
	args="monitor started; remotes hooked",
	rate=0,
	suspicious=false,
	time=os.date("!%Y-%m-%d %H:%M:%S").."Z",
})
