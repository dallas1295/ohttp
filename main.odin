package main

import "request"
import "server"
import "files"

handler :: proc(r: request.Request) -> (b: string, sc: int, ct: string){
    contents, type, ok := files.read(r.path)

    if ok {
        return contents, 200, ct
    }
    return "Not Found", 404, "text/plain"
}

main :: proc() {
    server.listen(handler)
}
