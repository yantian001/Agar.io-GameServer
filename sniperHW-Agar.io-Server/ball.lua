local util = require("util")
local config = require("config")
local chuck = require("chuck")
local objtype = require("objtype")
local packet = chuck.packet
local buffer = chuck.buffer

local M = {}
local ball = {}
ball.__index = ball  --定义一个元表，ball是__index的元方法

function M.new(id,owner,type,pos,score,color)  --新的对象
	local o = {}
	o = setmetatable(o,ball)  --把ball设为o的元表
	o.owner = owner
	o.pos = {x=pos.x , y=pos.y}
	o.score = score
	o.r = config.Score2R(score)
	o.color = color
	o.id = id
	o.type = type
	o.otherVelocitys = {}
	o.reqDirection = 0
	o.v = util.vector2D.new(0,0)
	owner.balls[id] = o
	owner.ballCount = owner.ballCount + 1
	o.clientR = o.r
	o.clientPos = {x=pos.x , y=pos.y}
	o.bornTick = owner.battle.tickCount
	owner.battle.colMgr:Enter(o)

	--优化碰撞用
	o.collPos = {x=pos.x , y=pos.y}
	o.collR = o.r

	return o
end


--给球这个类创建正在死亡的方法
function ball:OnDead()
	if self.type == objtype.thorn then
		self.owner.battle.thornMgr:OnThornDead()
	end
	self.owner.battle.colMgr:Leave(self)
	self.owner.battle.visionMgr:Leave(self)
	self.owner:OnBallDead(self)
end

--给球这个类创建修复边境（没看懂英文）的方法
function ball:fixBorder()
	local mapBorder = self.owner.battle.mapBorder
	local bottomLeft = mapBorder.bottomLeft
	local topRight = mapBorder.topRight
	local R = self.r * math.sin(util.PI/4)
	self.pos.x = util.max(R + bottomLeft.x,self.pos.x)
	self.pos.x = util.min(topRight.x - R,self.pos.x)
	self.pos.y = util.max(R + bottomLeft.y,self.pos.y)
	self.pos.y = util.min(topRight.y - R,self.pos.y)
end

--给球这个类创建更新位置的方法
function ball:UpdatePosition(averageV,elapse)
	elapse = elapse/1000
	self.pos.x = self.pos.x + averageV.x * elapse
	self.pos.y = self.pos.y + averageV.y * elapse
	self:fixBorder()
end

--给球这个类创建预知的方法
function ball:PredictV()
	--计算一个预测速度
	local predictVelocitys = {}

	if self.moveVelocity then
		table.insert(predictVelocitys,self.moveVelocity:Copy())
	end

	for k,v in pairs(self.otherVelocitys) do
		table.insert(predictVelocitys,v:Copy())
	end

	local predictV = util.vector2D.new(0,0)
	for k,v in pairs(predictVelocitys) do
		predictV = predictV + v:Update(battle.tickInterval)
	end

	local predictV = predictV/3
end

--给球这个类创建更新的方法
function ball:Update(elapse)

	if self.splitTimeout and self.owner.battle.tickCount > self.splitTimeout then
		self.splitTimeout = nil
	end

	self.v = util.vector2D.new(0,0)

	if self.moveVelocity then
		self.v = self.moveVelocity:Update(elapse)
	end

	for k,v in pairs(self.otherVelocitys) do
		self.v = self.v + v:Update(elapse)
		if v.duration <= 0 then
			self.otherVelocitys[k] = nil
		end
	end

	if self.v:mag() <= 0 then
		self.moveVelocity = nil
		return
	end

	--更新位置
	self:UpdatePosition(self.v,elapse)
	if self.type ~= objtype.thorn then
		--如果球的半径和坐标自上次更新碰撞之后都没变更过，就不需要再更新碰撞
		if self.collR ~= self.r or (not util.point2D.equal(self.collPos,self.pos)) then
			self.collR = self.r
			self.collPos = {x = self.pos.x , y = self.pos.y}
			self.owner.battle.colMgr:Update(self)
		end
	end

	self:ProcessThorn()

end

--给球这个类创建移动的方法（传入移动的方向）
function ball:Move(direction)
	--print("ball:Move",self.id)
	--首先根据小球半径计算速度标量值
	local speed = config.SpeedByR(self.r)
	self.reqDirection = math.modf(direction,360)
	--将传入的角度和速度标量转换成一个速度向量
	local maxVeLocity = util.TransformV(self.reqDirection,speed)
	if self.moveVelocity then
		self.moveVelocity = util.velocity.new(self.moveVelocity.v,maxVeLocity,200)
	else
		self.moveVelocity = util.velocity.new(util.TransformV(0,0),maxVeLocity,200)
	end
end

--给球这个类创建聚合的方法（传入中心点）
function ball:GatherTogeter(centerPos)
	local vv = util.vector2D.new(centerPos.x - self.pos.x , centerPos.y - self.pos.y)
	local speed = config.SpeedByR(self.r) * config.centripetalSpeedCoef
	self.reqDirection = vv:getDirAngle()
	local velocity = util.TransformV(self.reqDirection,speed)
	self.moveVelocity = util.velocity.new(velocity)
end

--停止的方法
function ball:Stop()
	if self.moveVelocity then
		self.moveVelocity = util.velocity.new(self.moveVelocity.v,util.vector2D.new(0,0),200,200)
	end
end

--
function ball:PackOnBeginSee(t)
	local tt = {}
	tt.userID = self.owner.userID  --用户ID
	tt.id = self.id
	tt.r = self.r  --半径
	tt.pos = {x = self.pos.x,y = self.pos.y}  --位置
	tt.color = self.color  --自身颜色
	local velocitys = {}  --移动速率
	if self.moveVelocity then
		self.moveVelocity:Pack(velocitys)
	end

	if self.otherVelocitys then
		for k,v in pairs(self.otherVelocitys) do
			v:Pack(velocitys)
		end
	end

	if #velocitys > 0 then
		tt.velocitys = velocitys
	end

	table.insert(t,tt)
end

local function calSplitTimeout(score)  --超时
	return math.floor(math.sqrt(score*4))*1000
end

--吃星星
function ball:EatStar(star)
	self.owner.battle.starMgr:OnStarDead(star)
	self.score = self.score + config.starScore  --总分数=目前自身分数+星星分数
	self.r = config.Score2R(self.score)
	if not self.owner.stop and self.moveVelocity then
		local speed = config.SpeedByR(self.r)
		--将传入的角度和速度标量转换成一个速度向量
		local maxVeLocity = util.TransformV(self.reqDirection,speed)  --最大速率
		self.moveVelocity = util.velocity.new(self.moveVelocity.v,maxVeLocity,200)  --自身移动速率
	end
end

--吃孢子（传入另一个玩家数据）
function ball:EatSpore(other)
	other:OnDead()  --另一个玩家死亡
	self.score = self.score + other.score  --总分数=自身分数+另一个玩家分数
	self.r = config.Score2R(self.score)  --自身半径=分数*2
	if not self.owner.stop and self.moveVelocity then
		local speed = config.SpeedByR(self.r)  --速度
		--将传入的角度和速度标量转换成一个速度向量
		local maxVeLocity = util.TransformV(self.reqDirection,speed)
		self.moveVelocity = util.velocity.new(self.moveVelocity.v,maxVeLocity,200)
	end
end

--处理刺
function ball:ProcessThorn()

	if not self.needThorn then
		return
	end

	self.needThorn = nil  --自身刺为空

	local eatFactor = config.EatFactor(self.score)
	local n1 = math.min(config.maxUserBallCount - self.owner.ballCount , config.maxThornBallCount)
	local x = self.score / n1
	local n,S2
	if x < config.initScore * eatFactor then
		n = self.score/(config.initScore * eatFactor)
		S2 = config.initScore * eatFactor
	elseif x <= config.initScore * (eatFactor + 2) then
		n = n1
		S2 = self.score/n
	else
		n = n1
		S2 = config.initScore * (2 + eatFactor)
	end
	local splitCount = n - 1
	if splitCount == 0 or self.owner.ballCount + splitCount > config.maxUserBallCount then
		self.r = config.Score2R(self.score)
		if not self.owner.stop and self.moveVelocity then
			local speed = config.SpeedByR(self.r)
			--将传入的角度和速度标量转换成一个速度向量
			local maxVeLocity = util.TransformV(self.reqDirection,speed)
			self.moveVelocity = util.velocity.new(self.moveVelocity.v,maxVeLocity,200)
		end
		return
	end

	local delta = math.floor(360/splitCount)
	local L = 8 * config.screenSizeFactor
	local v0 = config.SpeedByR(config.Score2R(S2)) * config.spitV0Factor;
	local spitDuration = math.floor((2*L/v0)*1000)  --饱和度

	local _scoreRemain = self.score - S2*splitCount

	local i = 0
	while splitCount > 0 do
		local newBall = self:spit(self.owner,objtype.ball,S2,_scoreRemain,i,v0,spitDuration,dontEnterColMgr)
		i = i + delta
		splitCount = splitCount - 1
	end
	self.splitTimeout = self.owner.battle.tickCount + calSplitTimeout(self.score)
end

--吃刺（传入刺）
function ball:EatThorn(thorn)
	thorn:OnDead()
	self.score = self.score + thorn.score
	if self.owner.ballCount < config.maxUserBallCount then
		self.needThorn = true
		--[[
			不能再这里直接调用ProcessThorn,会导致collision中迭代出错
			（这个函数是在collision的迭代中调进来的,thorn:OnDead会从collision中移除元素，如果同时调用ProcessThorn向collision中添加元素
			就会导致迭代器出错）
		]]
	else
		self.r = config.Score2R(self.score)
		if not self.owner.stop and self.moveVelocity then
			local speed = config.SpeedByR(self.r)
			--将传入的角度和速度标量转换成一个速度向量
			local maxVeLocity = util.TransformV(self.reqDirection,speed)
			self.moveVelocity = util.velocity.new(self.moveVelocity.v,maxVeLocity,200)
		end
	end
end

--吃球（传入其他玩家信息）
function ball:EatBall(other)
	other:OnDead()
	self.score = self.score + other.score
	self.r = config.Score2R(self.score)
	if self.owner == other.owner then
		self.splitTimeout = self.owner.battle.tickCount + calSplitTimeout(self.score)
	end
	if not self.owner.stop and self.moveVelocity then
		local speed = config.SpeedByR(self.r)
		--将传入的角度和速度标量转换成一个速度向量
		local maxVeLocity = util.TransformV(self.reqDirection,speed)
		self.moveVelocity = util.velocity.new(self.moveVelocity.v,maxVeLocity,200)
	end
end

--判断能否吃
local function canEat(b1,b2)
	local eatFactor = config.EatFactor(b1.score)
	if b1.score/b2.score >= eatFactor then
		return true
	else
		return false
	end
end

--检查球之间的冲突
local function checkCellCollision(ball1,ball2)
	local totalR = ball1.r + ball2.r
	local dx = ball2.pos.x - ball1.pos.x
	local dy = ball2.pos.y - ball1.pos.y
	local squared = dx * dx + dy * dy
	if squared > totalR * totalR then
		return nil
	else
		return {totalR = totalR , dx = dx , dy = dy, squared = squared}
	end

end

--自身一圈？？不懂
function ball:OnSelfBallOverLap(other)
	local manifold = checkCellCollision(self,other)  --折叠
	if manifold then
		local ball1 = self
		local ball2 = other
		local d = math.sqrt(manifold.squared)
		if d <= 0 then
			return
		end

		local invd = 1 / d
		local nx = math.floor(manifold.dx) * invd
		local ny = math.floor(manifold.dy) * invd
		local penetration =(manifold.totalR - d) * 0.75
		if penetration <= 0 then
			return
		end

		local px = penetration * nx;
		local py = penetration * ny;

		local totalMass,invTotalMass,impulse1,impulse2  --??


		totalMass = ball1.score + ball2.score
		if totalMass <= 0 then
			return
		end

		invTotalMass = 1 / totalMass;
		impulse1 = ball2.score * invTotalMass
		impulse2 = ball1.score * invTotalMass

		ball1.pos.x = ball1.pos.x - (px * impulse1)
		ball1.pos.y = ball1.pos.y - (py * impulse1)
		ball2.pos.x = ball2.pos.x + (px * impulse2)
		ball2.pos.y = ball2.pos.y + (py * impulse2)

		ball1:fixBorder()
		ball2:fixBorder()

	end
end

--增加冲突灵活性(传入ball1和ball2)
local function addCollisionElasticity(ball1,ball2)
	local dir1To2 = util.vector2D.new(ball2.pos.x - ball1.pos.x , ball2.pos.y - ball1.pos.y):getDirAngle()
	local dir2To1 = math.modf(dir1To2 + 180,360)
	local manifold = checkCellCollision(ball1,ball2)
	if manifold then
		local d = math.sqrt(manifold.squared)
		if d <= 0 then
			return
		end

		local invd = 1 / d
		local nx = math.floor(manifold.dx) * invd
		local ny = math.floor(manifold.dy) * invd
		local penetration =(manifold.totalR - d) * 0.75  --突破
		if penetration <= 0 then
			return
		end

		local px = penetration * nx;
		local py = penetration * ny;

		local totalMass,invTotalMass,impulse1,impulse2


		totalMass = ball1.score + ball2.score
		if totalMass <= 0 then
			return
		end

		invTotalMass = 1 / totalMass;
		impulse1 = ball2.score * invTotalMass
		impulse2 = ball1.score * invTotalMass

		local v1 = util.TransformV(dir2To1,ball1.v:mag() * 0.8 * impulse2)
		local velocity1 = util.velocity.new(v1,util.TransformV(0,0),200,200)
		table.insert(ball1.otherVelocitys,velocity1)

		local v2 = util.TransformV(dir1To2,ball1.v:mag() * 0.8 * impulse1)
		local velocity2 = util.velocity.new(v2,util.TransformV(0,0),200,200)
		table.insert(ball2.otherVelocitys,velocity2)

		ball1.bornTick = nil
		ball2.bornTick = nil
	end
end

--超过一圈???
function ball:OnOverLap(other)
	if self.type == objtype.spore then
		return
	end
	if other.type == objtype.star then
		self:EatStar(other)
	elseif other.type == objtype.spore then
		local distance = util.point2D.distance(self.pos,other.pos)
		if distance <= self.r and canEat(self,other) then
			self:EatSpore(other)
		end
	elseif other.type == objtype.ball then
		if other.owner == self.owner then
			--print(other.splitTimeout , self.splitTimeout)
			if other.splitTimeout or self.splitTimeout then
				--if #self.otherVelocitys > 0 then
				if self.bornTick and self.owner.battle.tickCount < self.bornTick + config.splitDuration then
					--添加碰撞弹射运动量
					addCollisionElasticity(self,other)
				else
					self:OnSelfBallOverLap(other)
				end
			else
				local distance = util.point2D.distance(self.pos,other.pos)
				if distance <= self.r then
					self:EatBall(other)
				end
			end
		else
			local distance = util.point2D.distance(self.pos,other.pos)
			if distance <= self.r and canEat(self,other) then
				self:EatBall(other)
			end
		end
	elseif other.type == objtype.thorn then
		local distance = util.point2D.distance(self.pos,other.pos)
		if distance <= self.r and canEat(self,other) then
			self:EatThorn(other)
		end
	end
end

--球吐孢子
function ball:spit(owner,newtype,spitScore,spitterScore,dir,v0,duration,dontEnterColMgr)
	local spitR = config.Score2R(spitScore)
	local leftBottom = {x = spitR, y = spitR}
	local rightTop = {x = config.mapWidth - spitR, y = config.mapWidth - spitR}
	local spiterR = config.Score2R(spitterScore)
	local bornPoint = util.point2D.moveto(self.pos , dir , spiterR + spitR , leftBottom , rightTop)
	local color

	if newtype == objtype.ball then
		color = self.color
	else
		color = math.random(1,#config.colors)
	end

	self.score = spitterScore
	self.r = spiterR

	local newBall = M.new(self.owner.battle:GetBallID(),owner,newtype,bornPoint,spitScore,color,dontEnterColMgr)

	if newtype == objtype.ball then
		newBall.splitTimeout = self.owner.battle.tickCount + calSplitTimeout(newBall.score)
	end


	--添加弹射运动量
	local velocity = util.velocity.new(util.TransformV(dir,v0),util.TransformV(0,0),duration,duration)
	table.insert(newBall.otherVelocitys,velocity)
	if not self.owner.stop then
		if newtype == objtype.ball then
			local speed = config.SpeedByR(spitR)
			--将传入的角度和速度标量转换成一个速度向量
			local maxVeLocity = util.TransformV(self.reqDirection,speed)
			newBall.moveVelocity = util.velocity.new(maxVeLocity)
		end
		--自己的积分减少，速度改变了
		local speed = config.SpeedByR(self.r)
		--将传入的角度和速度标量转换成一个速度向量
		local maxVeLocity = util.TransformV(self.reqDirection,speed)
		self.moveVelocity = util.velocity.new(self.moveVelocity.v,maxVeLocity,200)
	end

	self.owner.battle.visionMgr:Enter(newBall)

	return newBall

end

function ball:Spit()
	local eatFactor = config.EatFactor(self.score)
	if self.score >= config.sp0 * (1 + eatFactor) then
		local spitR = config.Score2R(config.sp0)
		local L = 9 * config.screenSizeFactor
		local v0 = config.SpeedByR(spitR) * config.spitV0Factor
		local spitDuration = math.floor((2*L/v0)*1000)
		self:spit(self.owner.battle.dummyUser , objtype.spore , config.sp0 , self.score - config.sp0 , self.reqDirection , v0 , spitDuration)
	end
end

--判断能否吐孢子
function ball:splitAble()
	local eatFactor = config.EatFactor(self.score)
	if self.score < config.sp0 * eatFactor * 2 then
		return false
	else
		return true
	end

end

function ball:Split()
	if self.owner.ballCount >= config.maxUserBallCount then
		return
	end

	if not self:splitAble() then
		return
	end

	local newR = config.Score2R(self.score/2)
	local L = newR + 5.5 * config.screenSizeFactor
	local v0 = math.floor(2 * L * 1000 / config.splitDuration)
	self:spit(self.owner , objtype.ball , self.score/2 , self.score/2 , self.reqDirection , v0 , config.splitDuration)
	self.splitTimeout = self.owner.battle.tickCount + calSplitTimeout(self.score)
end

return M
