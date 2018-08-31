## Agar.io 服务器端框架解读  
代码解读、文件之间的关系、服务端逻辑  
#### 各lua文件的含义  
- ai.lua：设定玩家信息，并随机更新AI的移动方向和位置。  
- ball.lua：定义了ball中的所有属性和方法。  
不理解之处如下  
1，function ball:fixBorder()；    
2，function ball:OnSelfBallOverLap(other)，还有函数下的manifold；  
- util.lua：一个封装了游戏服务端所需要的各种方法的工具文件，计算向量、去膜、更新、判断距离、加减乘除操作、转换、速率等。  
- battle.lua：属于战斗服务器逻辑，包含了获取球的ID，新建房间，进入房间，进入战斗，更新战斗，战斗结束，统计分数。  
- battleuser.lua：战斗玩家的逻辑，包含验证是否为真实玩家（防止作弊），玩家复活，移动，更新位置，释放球，吐孢子，分裂。  
- collision.lua：检测对象是否与其他对它对象产生碰撞，开启碰撞，结束碰撞的逻辑。    
对function collision:Update(o) --根据对象坐标更新管理块 不理解。  
- collisionGrid.lua：检测碰撞。  
- config.lua：对战斗环境的基本元素进行初始化；设置分数，速度，吃的因素。  
不理解之处如下  
M.thornColorID = 22  
M.thornColor = {1,0,1,1}  
- genstar.lua：随机生成系统时间，界面长宽和玩家的颜色。  
- minheap.lua：整合了上下左右方向移动的逻辑，但对最小堆minheap这个概念不清晰。  
- objtype.lua：设定M的协议，有star，ball，spore，thorn。  
- QuadTree.lua：四叉树算法（很重要）。  
- server.lua：建立服务器端口号与客户端连接的逻辑和连接成功后的逻辑。  
- star.lua：星星逻辑，包含存活，更新，死亡，向客户端通知死亡。  
- testclient.lua：客户端测试逻辑，包含于服务器端的连接逻辑和心跳机制。   
- user.lua：接收用户与服务端的逻辑和消息分发的逻辑。  
不理解之处  
1，user.msgHander["FixTime"] = function (self,msg)  
- vision.lua：视野模块。  
不理解之处  
1，function block:RemoveObserver(o)  --移动observer模块？  
2，function visionMgr:getBlockByPoint(pos) --视野添加模块？  
3，function visionMgr:calUserVisionBlocks(user)  --视野内通知用户模块？  
4，function visionMgr:updateViewPort(user) ？  



