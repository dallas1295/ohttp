package main

import "response"
import "request"
import "server"
import "files"

handler :: proc(w: ^response.Writer, r: request.Request) {
    c, ct, ok := files.read(r.path)

    if ok {
        response.header(w,"Content-Type", ct)
        response.write(w, c)
        return

    }
    response.status(w, 404)
    response.write(w,"Not Found")
}

main :: proc() {
    server.listen(handler)
}
