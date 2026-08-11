package server

import "../request"
import "../response"
import "../socket"
import "core:fmt"
import "core:mem"
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
			fmt.printf("Shutting down...\n")
			break
		}
		c, src, err := net.accept_tcp(s)
		if err != nil {
			if shutdown {
				fmt.printf("Shutting down...\n")
				break
			}
			fmt.eprintln("error accepting tcp connection, closing socket")
			continue}
		fmt.printf("%v\n", src)
		handle_connection(c, src, h)
	}
}

handle_connection :: proc(c: net.TCP_Socket, src: net.Endpoint, h: Handler) {
	// Dynamic Allocator for collecting and releasing as necessary
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	context.allocator = mem.dynamic_arena_allocator(&arena)

	// Timeout after 5 seconds of empty connection.
	net.set_option(c, .Receive_Timeout, 5 * time.Second)

	buf: [4096]byte
	used: int

	req_start := time.now()

	for {
		mem.dynamic_arena_free_all(&arena)
		free_all(context.temp_allocator)

		if used == len(buf) {
			w := response.new()
			response.create(&w, 431)
			raw := response.build(&w)

			_, send_err := net.send_tcp(c, transmute([]byte)raw)
			if send_err != nil {
				fmt.eprintf("send error: %v\n", send_err)
			}

			net.close(c)
			break
		}

		if used > 0 {
			req, ok, consumed := request.parse(buf[:used])
			if ok == .MALFORMED {
				w := response.new()
				response.create(&w, 400)
				raw := response.build(&w)

				_, send_err := net.send_tcp(c, transmute([]byte)raw)
				if send_err != nil {
					fmt.eprintf("send error: %v\n", send_err)
				}

				net.close(c)
				break
			}

			if ok == .OK {
				w := response.new()
				h(&w, req)
				if req.method == "HEAD" {
					w.head = true
				}
				raw := response.build(&w)

				_, send_err := net.send_tcp(c, transmute([]byte)raw)

				if send_err != nil {
					fmt.eprintf("send error: %v\n", send_err)
					net.close(c)
					break
				}
				if req.headers["connection"] == "close" {
					net.close(c)
					break
				} else {
					copy(buf[0:used - consumed], buf[consumed:used])
					used -= consumed
					req_start = time.now()
					continue
				}
			}
		}

		n, recv_err := net.recv_tcp(c, buf[used:])
		if recv_err != nil || n == 0 {
			fmt.printf("connection %v closed\n", src.address)
			net.close(c)
			break
		}

		used += n
		dur := time.since(req_start)
		max_dur := 30 * time.Second
		if dur > max_dur {
			w := response.new()
			response.create(&w, 408)
			raw := response.build(&w)

			_, send_err := net.send_tcp(c, transmute([]byte)raw)
			if send_err != nil {
				fmt.eprintf("send error: %v\n", send_err)
			}

			net.close(c)
			break
		}
	}

}
