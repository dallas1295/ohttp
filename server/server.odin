package server

import "../request"
import "../response"
import "../socket"
import "core:fmt"
import "core:net"
import "core:time"

shutdown: bool = false
Handler :: proc(w: ^response.Writer, r: request.Request)

listen :: proc(h: Handler) {
	s, err := socket.open()
	if err != nil {
		fmt.eprintf("Error opening socket: %v", err)
		return
	}
	defer socket.close(s)

	register_signal_handler()

	for {
		if shutdown {
			fmt.println("Shutting down...")
			break
		}
		c, src, err := net.accept_tcp(s)
		if err != nil {
			if shutdown {
				fmt.println("Shutting down...")
				break
			}
			fmt.eprintln("error accepting tcp connection, closing socket")
			continue}
		fmt.printf("%v\n", src)
		fmt.println("Connection accepted")
		handle_connection(c, src, h)
	}
}

handle_connection :: proc(c: net.TCP_Socket, src: net.Endpoint, h: Handler) {
	// Timeout after 5 seconds of empty connection.
	net.set_option(c, .Receive_Timeout, 5 * time.Second)

	buf: [4096]byte
	used: int

	for {
		if used == len(buf) {
			w := response.new()
			response.create(&w, 431)
			raw := response.build(&w)
			defer delete(w.headers)
			defer delete(w.body)

			_, send_err := net.send_tcp(c, transmute([]byte)raw)
			defer delete(raw)

			if send_err != nil {
				fmt.eprintf("send error: %v\n", send_err)
			}

			net.close(c)
			break
		}

		if used > 0 {
			req, ok, consumed := request.parse(buf[:used])
			defer delete(req.headers)
			if ok == .MALFORMED {
				w := response.new()
				response.create(&w, 400)
				raw := response.build(&w)
				defer delete(w.headers)
				defer delete(w.body)

				_, send_err := net.send_tcp(c, transmute([]byte)raw)
				defer delete(raw)
				if send_err != nil {
					fmt.eprintf("send error: %v\n", send_err)
				}

				net.close(c)
				break
			}

			if ok == .OK {
				w := response.new()
				h(&w, req)
				raw := response.build(&w)
				defer delete(w.headers)
				defer delete(w.body)

				_, send_err := net.send_tcp(c, transmute([]byte)raw)
				defer delete(raw)

				if send_err != nil {
					fmt.eprintf("send error: %v\n", send_err)
					net.close(c)
					break
				}
				if req.headers["Connection"] == "close" {
					net.close(c)
					break
				} else {
					copy(buf[0:used - consumed], buf[consumed:used])
					used -= consumed
					continue
				}
			}
		}

		n, recv_err := net.recv_tcp(c, buf[used:])
		if recv_err != nil || n == 0 {
			if recv_err == .Would_Block {
				fmt.printf("connection %v idle timeout\n", src.address)
			} else {
				fmt.printf("connection %v closed\n", src.address)
				net.close(c)
				break
			}
		}

		used += n
	}
}
