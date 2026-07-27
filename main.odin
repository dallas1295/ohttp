package main

import "request"
import "socket"
import "core:net"
import "core:fmt"

main :: proc() {
    s, err := socket.open()
    if err != nil {
        fmt.eprintf("Error opening socket: %v", err)
        return
    }
    defer socket.close(s)

	for {
		c, src, err := net.accept_tcp(s)
		if err != nil {
			fmt.eprintln("error accepting tcp connection, closing socket")
			continue
		}
		fmt.printf("%v\n", src)
		fmt.println("Connection accepted")

		buf: [4096]byte

		for {
			n, err := net.recv_tcp(c, buf[:])
			if err != nil || n == 0 {
				fmt.printf("connction %v closed\n", src.address)
				net.close(c)
				break
			}

            req := request.parse(buf[:n])
            // fmt.println(req.method, req.path, req.version)

            for key, value in req.headers {
                fmt.println(key, ":", value)
            }
		}
	}
}
