package request

import "core:strconv"
import "core:strings"

Request :: struct {
	method:  string,
	path:    string,
	version: string,
	headers: map[string]string,
	body:    string,
}

Parse_Result :: enum {
	OK,
	MALFORMED,
	INCOMPLETE,
}

parse :: proc(r: []byte) -> (Request, Parse_Result, int) {
	req := Request{}
	req.headers = make(map[string]string)

	str := string(r)


	bounds := strings.index(str, "\r\n\r\n")
	if bounds == -1 {
		return req, .INCOMPLETE, 0
	}


	lines := strings.split(str[:bounds], "\r\n")
	defer delete(lines)

	rq := strings.split(lines[0], " ")
	defer delete(rq)
	if len(rq) < 3 {
		return req, .MALFORMED, 0
	}

	req.method = rq[0]
	req.path = rq[1]
	req.version = rq[2]

	for line in lines[1:] {
		parts := strings.split(line, ": ")
		defer delete(parts)

		if len(parts) < 2 {
			return req, .MALFORMED, 0
		}
		req.headers[parts[0]] = parts[1]
	}

	body_start := bounds + 4
	consumed := body_start

	if cl, ok := req.headers["Content-Length"]; ok {
		length, ok := strconv.parse_int(cl, 10)
		if !ok || length < 0 {
			return req, .MALFORMED, 0
		}

		needed := body_start + int(length)
		if len(r) < needed {
			return req, .INCOMPLETE, 0
		}
		consumed = needed
		req.body = str[body_start:needed]
	}

	return req, .OK, consumed
}
