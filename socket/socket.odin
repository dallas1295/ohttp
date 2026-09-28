package socket

import "core:fmt"
import "core:net"

ENDPOINT :: net.Endpoint {
	address = net.IP4_Any,
	port    = 8080,
}

set_endpoint :: proc(port: int) -> net.Endpoint {
	return {address = net.IP4_Any, port = port}
}

open :: proc(endpoint := ENDPOINT) -> (net.TCP_Socket, net.Network_Error) {
	s, err := net.listen_tcp(endpoint)
	if err != nil {
		fmt.eprintln("Error creating socket")
		return s, err
	}

	return s, nil
}


close :: proc(s: net.Any_Socket) {
	net.close(s)
}
