package server

import "../request"
import "../response"
import "../socket"
import "../utils"
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
	buf := make([]byte, 16 * 1024 + 1024 * 1024)
	defer delete(buf)


	// Dynamic Allocator for collecting and releasing as necessary
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	context.allocator = mem.dynamic_arena_allocator(&arena)

	// Two Dos defenses:
	// - 5s recv timeout: kills idle connections
	// - 30s request cap: kills slowloris attacks
	net.set_option(c, .Receive_Timeout, 5 * time.Second)


	used: int
	continue_sent: bool

	req_start := time.now()

	for {
		mem.dynamic_arena_free_all(&arena)
		free_all(context.temp_allocator)

		if used > 0 {
			req, ok, consumed := request.parse(buf[:used])
			if ok == .MALFORMED {
				w := response.new()
				response.header(&w, "Connection", "close")
				response.create(&w, 400)
				raw := response.build(&w)

				_, send_err := net.send_tcp(c, transmute([]byte)raw)
				if send_err != nil {
					fmt.eprintf("send error: %v\n", send_err)
				}

				net.close(c)
				break
			}

			if ok == .UNSUPPORTED {
				w := response.new()
				response.header(&w, "Connection", "close")
				response.create(&w, 505)
				raw := response.build(&w)

				_, send_err := net.send_tcp(c, transmute([]byte)raw)
				if send_err != nil {
					fmt.eprintf("send error: %v\n", send_err)
				}

				net.close(c)
				break
			}

			if ok == .TOO_LARGE {
				w := response.new()
				response.header(&w, "Connection", "close")
				response.create(&w, 413)
				raw := response.build(&w)

				_, send_err := net.send_tcp(c, transmute([]byte)raw)
				if send_err != nil {
					fmt.eprintf("send error: %v\n", send_err)
				}

				net.close(c)
				break
			}

			if ok == .READY && !continue_sent {
				raw := "HTTP/1.1 100 Continue\r\n\r\n"

				_, send_err := net.send_tcp(c, transmute([]byte)raw)
				if send_err != nil {
					fmt.eprintf("send error: %v\n", send_err)
				}

				continue_sent = true
			}

			if ok == .EXPECTATION_FAIL {
				w := response.new()
				response.header(&w, "Connection", "close")
				response.create(&w, 417)
				raw := response.build(&w)

				_, send_err := net.send_tcp(c, transmute([]byte)raw)
				if send_err != nil {
					fmt.eprintf("send error: %v\n", send_err)
				}

				net.close(c)
				break
			}

			if ok == .INCOMPLETE && used == len(buf) {
				w := response.new()
				response.header(&w, "Connection", "close")
				response.create(&w, 431)
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

				keep_alive :=
					req.version == "HTTP/1.1" ||
					utils.has_token(req.headers["connection"], "keep-alive")
				should_close := utils.has_token(req.headers["connection"], "close")

				if should_close || !keep_alive {
					response.header(&w, "Connection", "close")
				} else if req.version == "HTTP/1.0" {
					response.header(&w, "Connection", "keep-alive")
				}

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


				if should_close || !keep_alive {
					net.close(c)
					break
				} else {
					copy(buf[0:used - consumed], buf[consumed:used])
					used -= consumed
					req_start = time.now()
					continue_sent = false
					continue
				}
			}
		}

		n, recv_err := net.recv_tcp(c, buf[used:])
		if recv_err != nil {
			if used > 0 {
				w := response.new()
				response.header(&w, "Connection", "close")
				response.create(&w, 408)
				raw := response.build(&w)

				_, send_err := net.send_tcp(c, transmute([]byte)raw)
				if send_err != nil {
					fmt.eprintf("send error: %v\n", send_err)
				}
			}

			fmt.printf("connection %v closed\n", src.address)
			net.close(c)
			break
		}

		if n == 0 {
			fmt.printf("connection %v closed\n", src.address)
			net.close(c)
			break
		}

		used += n
		dur := time.since(req_start)
		max_dur := 30 * time.Second
		if dur > max_dur {
			w := response.new()
			response.header(&w, "Connection", "close")
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
