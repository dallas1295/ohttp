package server

import "../request"
import "../response"
import "../socket"
import "../utils"
import "core:fmt"
import "core:mem"
import "core:net"
import "core:thread"
import "core:time"

DEFAULT_MAX_CONNECTIONS :: 64

shutdown: bool = false

Handler :: proc(w: ^response.Writer, r: request.Request)

Connection_Info :: struct {
	c:   net.TCP_Socket,
	src: net.Endpoint,
	h:   Handler,
}

listen :: proc(h: Handler, port := 8080, max_connections := DEFAULT_MAX_CONNECTIONS) {
	ep := socket.set_endpoint(port)
	s, err := socket.open(ep)
	if err != nil {
		fmt.eprintf("Error opening socket: %v", err)
		return
	}
	defer socket.close(s)

	register_signal_handler()

	handles: [dynamic]^thread.Thread
	defer delete(handles)

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
			continue
		}
		fmt.printf("%v\n", src)

		i := 0
		for t in handles {
			if thread.is_done(t) {
				thread.destroy(t)
			} else {
				handles[i] = t
				i += 1
			}
		}
		resize(&handles, i)

		if len(handles) >= max_connections {
			net.close(c)
			continue
		}


		t := thread.create_and_start_with_poly_data(Connection_Info{c, src, h}, connection_worker)
		if t == nil {
			net.close(c)
			continue
		}
		append(&handles, t)
	}

	thread.join_multiple(..handles[:])
	for t in handles {
		thread.destroy(t)
	}
}

connection_worker :: proc(info: Connection_Info) {
	handle_connection(info.c, info.src, info.h)
}

handle_connection :: proc(c: net.TCP_Socket, src: net.Endpoint, h: Handler) {
	buf := make([]byte, 16 * 1024 + 1024 * 1024)
	defer delete(buf)


	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	context.allocator = mem.dynamic_arena_allocator(&arena)

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
