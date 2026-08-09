package main

import "files"
import "request"
import "response"
import "server"

import "core:fmt"

handler :: proc(w: ^response.Writer, r: request.Request) {
	if r.path == "/chunked" {
		response.chunk(w, "Hello")
		// response.chunk(w, ", World\n")
		return
	}

	path := r.path
	if path == "/" {
		path = "/index.html"
	}

	if r.method == "POST" {
		fmt.printfln("body: {}", r.body)
	}

	c, ct, result := files.read(path)

	switch result {
	case .OK:
		response.header(w, "Content-Type", ct)
		response.write(w, c)
	case .NOT_FOUND:
		response.create(w, 404)
	case .FORBIDDEN:
		response.create(w, 403)
	}
}

main :: proc() {
	server.listen(handler)
}
