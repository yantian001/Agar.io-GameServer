package.path = './lib/?.lua;./Agar.io-Server/?.lua'
package.cpath = './lib/?.so;'

math.randomseed(os.time())  --把 系统时间 设为伪随机数发生器的“种子”： 相同的种子产生相同的随机数列。

local chuck = require("chuck")  --导入chuck包
local socket = chuck.socket
local buffer = chuck.buffer
local packet = chuck.packet
event_loop = chuck.event_loop.New()
local log = chuck.log
logger = log.CreateLogfile("Agar.io")  --声明日志文件名 Agar.io

local addr = socket.addr(socket.AF_INET,"0.0.0.0",9100)  --建立服务器端口号

local user = require("user")  --导入user文件

local server = socket.stream.listen(event_loop,addr,function (fd)  --监听函数，监听端口
	local conn = socket.stream.socket(fd,4096,packet.Decoder(4096))  --接收到连接，设置通道容量为4096字节
	--判断连接是否成功
	if conn then
		conn:Start(event_loop,function (msg)  --开启服务器
			if msg then
				local reader = packet.Reader(msg)
				msg = reader:ReadTable()
				user.OnClientMsg(conn,msg)
			else
				log.SysLog(log.info,"client disconnected") --
				conn:Close()
				user.OnClientDisconnected(conn)
			end
		end)
	end
end)

--服务器连接成功后的逻辑
if server then
	log.SysLog(log.info,"server start")
	local timer1 = event_loop:AddTimer(1000,function ()
		collectgarbage("collect")
	end)
	event_loop:WatchSignal(chuck.signal.SIGINT,function()
		log.SysLog(log.info,"recv SIGINT stop server")
		event_loop:Stop()
	end)
	event_loop:Run()
end
