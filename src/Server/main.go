package main

import (
	"net"
	"fmt"
)

func main(){
	listen_socket, err := net.Listen("tcp", "127.0.0.1:8000")  //打开监听接口
	if err != nil { //如果有错误
		fmt.Println("sever error")
	}

	defer listen_socket.Close()  //延迟服务器端关闭
	fmt.Println("sever is wating ....")


	for {
		conn, err := listen_socket.Accept() //监听客户端的端口
		if err != nil {
			fmt.Println("conn fail ...")
		}
		fmt.Println("connect client successed") //显示服务器端连接成功
	}
		fmt.Println("client Close\n")
		conn.Close()
}