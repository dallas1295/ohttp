package socket

import "core:net"
import "core:fmt"

ENDPOINT :: net.Endpoint {
	address = net.IP4_Any,
	port    = 8080,
}

open :: proc() -> (net.TCP_Socket, net.Network_Error) {
	s, err := net.listen_tcp(ENDPOINT)
	if err != nil {
		fmt.eprintln("Error creating socket")
		return s, err
	}

    return s, nil
}


close :: proc(s: net.Any_Socket) {
    net.close(s)
}
