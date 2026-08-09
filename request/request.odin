package request

import "core:fmt"
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

	if ch, ok := req.headers["Transfer-Encoding"]; ok {
		if ch != "chunked" {
			return req, .MALFORMED, 0
		}
		if _, ok := req.headers["Content-Length"]; ok {
			return req, .MALFORMED, 0
		}

		pos := body_start
		for {
			size_idx := strings.index(str[pos:], "\r\n")
			if size_idx == -1 {
				return req, .INCOMPLETE, 0
			}

			size_end := pos + size_idx
			size_text := str[pos:size_end]

			end_idx := strings.index(size_text, ";")
			if end_idx != -1 {
				size_end = pos + end_idx
			}
			size_text = str[pos:size_end]

			val, ok := strconv.parse_int(size_text, 16)
			if !ok {
				return req, .MALFORMED, 0
			}

			if val == 0 {
				cursor := size_end + 2

				for {
					offset := strings.index(str[cursor:], "\r\n")

					if offset == -1 {
						return req, .INCOMPLETE, 0
					}

					if offset == 0 {
						consumed = cursor + 2
						break
					}

					cursor += offset + 2
				}
				break
			}

			if val > 0 {
				cursor := size_end + 2
				end := cursor + val

				if end + 2 > len(r) {
					return req, .INCOMPLETE, 0
				}

				payload := str[cursor:end]
				req.body = fmt.tprintf("{}{}", req.body, payload)

				pos = end + 2
			}
		}

	} else {
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

	}

	return req, .OK, consumed
}
