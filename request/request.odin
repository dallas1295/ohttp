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
	query:   string,
}

Parse_Result :: enum {
	OK,
	MALFORMED,
	INCOMPLETE,
}

lower_ascii :: proc(s: string) -> string {
	b := make([]byte, len(s))

	for i in 0 ..< len(s) {
		c := s[i]
		b[i] = c + 32 if c >= 'A' && c <= 'Z' else c
	}

	return string(b)
}


parse :: proc(r: []byte) -> (Request, Parse_Result, int) {
	req := Request{}
	req.headers = make(map[string]string)

	str := string(r)


	bounds := strings.index(str, "\r\n\r\n")
	if bounds == -1 {
		double := strings.index(str, "\n\n")
		if double == -1 {
			return req, .INCOMPLETE, 0
		}
		return req, .MALFORMED, 0
	}


	lines := strings.split(str[:bounds], "\r\n")

	rq := strings.split(lines[0], " ")
	if len(rq) < 3 {
		return req, .MALFORMED, 0
	}

	req.method = rq[0]
	q_idx := strings.index(rq[1], "?")
	if q_idx == -1 {
		req.path = rq[1]
	} else {
		req.path = rq[1][:q_idx]
		req.query = rq[1][q_idx + 1:]
	}
	req.version = rq[2]

	for line in lines[1:] {
		colon := strings.index(line, ":")
		if colon == -1 {
			return req, .MALFORMED, 0
		}

		name := lower_ascii(line[:colon])
		value := strings.trim_space(line[colon + 1:])

		if existing, exists := req.headers[name]; exists {
			if name == "content-length" {
				return req, .MALFORMED, 0
			}
			req.headers[name] = fmt.tprintf("{}, {}", existing, value)
		} else {
			req.headers[name] = value
		}
	}

	if _, host := req.headers["host"]; req.version == "HTTP/1.1" && !host {
		return req, .MALFORMED, 0
	}


	body_start := bounds + 4
	consumed := body_start

	if ch, ok := req.headers["transfer-encoding"]; ok {
		if ch != "chunked" {
			return req, .MALFORMED, 0
		}
		if _, ok := req.headers["content-length"]; ok {
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
		if cl, ok := req.headers["content-length"]; ok {
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
