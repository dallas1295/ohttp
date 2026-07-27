package request

import "core:strings"

Request :: struct {
	method:  string,
	path:    string,
	version: string,
	headers: map[string]string,
}

parse :: proc(r: []byte) -> Request {
    req := Request{}
    req.headers = make(map[string]string)

	str := string(r)
    lines := strings.split(str, "\r\n")

    rq := strings.split(lines[0], " ")
    req.method = rq[0]
    req.path = rq[1]
    req.version = rq[2]

    for line in lines[1:] {
        if len(line) == 0 {
            break
        }
        parts := strings.split(line, ": ")
        req.headers[parts[0]] = parts[1]

    }



	return req
}
