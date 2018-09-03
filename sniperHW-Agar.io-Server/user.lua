local battle = require("battle")
local chuck = require("chuck")
local packet = chuck.packet
local log = chuck.log
local M = {}

M.conn2User = {}
M.userID2User = {}

local user = {}
user.__index = user
user.msgHander = {}

local function newUser(conn,userID)
	--设置userID和conn
	local o = {}
	o = setmetatable(o,user)  --给o表设置元表，如果 metatable 是 nil， 将指定表的元表移除
	o.conn = conn
	o.userID = userID
	M.conn2User[conn] = o
	M.userID2User[userID] = o
	return o
end

--用户消息
function user:onMsg(msg)
	local handler = user.msgHander[msg.cmd]
	if handler then
		xpcall(handler,function (err)
			logger:Log(log.error,string.format("error on call onMsg:%s",err))
		end,self,msg)
	end
end

--用户发送给客户端
function user:Send2Client(msg)
	if self.conn then
		local buff = chuck.buffer.New()
		local w = packet.Writer(buff)
		w:WriteTable(msg)
		self.conn:Send(buff)
	end
end

--消息分发
--收到EnterBattle后跳转到战斗服中的进入房间逻辑
user.msgHander["EnterBattle"] = function (self,msg)
	battle.EnterRoom(self)
end

--收到Move后跳转到战斗玩家中的移动逻辑
user.msgHander["Move"] = function (self,msg)
	if self.battleUser then
		self.battleUser:Move(msg)
	end
end

--收到FixTime后与客户端进行对时，保持服务器端与客户端的时间一致
user.msgHander["FixTime"] = function (self,msg)
	if self.battleUser then
		local room = self.battleUser.battle
		local elapse = chuck.time.systick() - room.lastSysTick
		local buff = chuck.buffer.New()
		local w = packet.Writer(buff)
		w:WriteTable({cmd="FixTime" , serverTick = room.tickCount + elapse, clientTick = msg.clientTick})
		self.conn:Send(buff)
	end
end

--收到Stop后跳转到战斗玩家的停止逻辑
user.msgHander["Stop"] = function (self,msg)
	if self.battleUser then
		self.battleUser:Stop(msg)
	end
end

--收到Spit后跳转到战斗玩家的吐孢子逻辑
user.msgHander["Spit"] = function (self,msg)
	if self.battleUser then
		self.battleUser:Spit(msg)
	end
end

--收到Split后跳转到战斗玩家的分裂逻辑
user.msgHander["Split"] = function (self,msg)
	if self.battleUser then
		self.battleUser:Split(msg)
	end
end

--客户端消息分发（传入与服务端连接接收来的消息）
function M.OnClientMsg(conn,msg)
	--print(msg.cmd)
	if msg.cmd == "Login" then
		if not msg.userID or msg.userID < 1000 then

			return
		end
		local user = M.userID2User[msg.userID]
		if not user then
			user = newUser(conn,msg.userID)
		else
			if user.conn ~= nil then

				conn:Close()
				return
			else
				user.conn = conn
				M.conn2User[conn] = user
			end
		end
		user:Send2Client(msg)
	else
		local user = M.conn2User[conn]
		if user then
			user:onMsg(msg)
		end
	end
end

--客户端连接失败(传入与服务端的连接)
function M.OnClientDisconnected(conn)
	local user = M.conn2User[conn]
	if user then
		M.conn2User[conn] = nil
		M.userID2User[user.userID] = nil
		if user.battleUser then
			user.battleUser.player = nil
		end
	end
end

return M
