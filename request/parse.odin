package request

import "../utils"
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
	UNSUPPORTED,
	TOO_LARGE,
	READY,
	EXPECTATION_FAIL,
}

MAX_BODY :: 1024 * 1024

is_hex_digit :: proc(c: byte) -> bool {
	return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
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
	if len(rq) != 3 {
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

	if req.method == "" || req.path == "" {
		return req, .MALFORMED, 0
	}

	req.version = rq[2]
	if len(req.version) != 8 ||
	   req.version[:5] != "HTTP/" ||
	   req.version[6] != '.' ||
	   req.version[5] < '0' ||
	   req.version[5] > '9' ||
	   req.version[7] < '0' ||
	   req.version[7] > '9' {
		return req, .MALFORMED, 0
	}

	if req.version[5] != '1' {
		return req, .UNSUPPORTED, 0
	}

	for line in lines[1:] {
		if len(line) > 0 && (line[0] == ' ' || line[0] == '\t') {
			return req, .MALFORMED, 0
		}

		colon := strings.index(line, ":")
		if colon <= 0 {
			return req, .MALFORMED, 0
		}

		name := utils.lower_ascii(strings.trim_space(line[:colon]))
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

	if v, host := req.headers["host"]; req.version == "HTTP/1.1" && (!host || v == "") {
		return req, .MALFORMED, 0
	}

	if e, ok := req.headers["expect"]; ok && !utils.has_token(e, "100-continue") {
		return req, .EXPECTATION_FAIL, 0
	}


	body_start := bounds + 4
	consumed := body_start

	if ch, ok := req.headers["transfer-encoding"]; ok {
		tokens := strings.split(ch, ",")
		last := utils.lower_ascii(strings.trim_space(tokens[len(tokens) - 1]))
		if last != "chunked" {
			return req, .MALFORMED, 0
		}
		if _, ok := req.headers["content-length"]; ok {
			return req, .MALFORMED, 0
		}

		total: int
		pos := body_start

		for {
			size_idx := strings.index(str[pos:], "\r\n")
			if size_idx == -1 {
				if utils.has_token(req.headers["expect"], "100-continue") {
					return req, .READY, 0
				}
				return req, .INCOMPLETE, 0
			}

			size_end := pos + size_idx
			size_text := str[pos:size_end]

			end_idx := strings.index(size_text, ";")
			if end_idx != -1 {
				size_end = pos + end_idx
			}
			size_text = str[pos:size_end]

			for c in size_text {
				if !is_hex_digit(byte(c)) {
					return req, .MALFORMED, 0
				}
			}

			val, ok := strconv.parse_int(size_text, 16)
			if !ok {
				return req, .MALFORMED, 0
			}


			if val == 0 {
				cursor := size_end + 2

				for {
					offset := strings.index(str[cursor:], "\r\n")

					if offset == -1 {
						if utils.has_token(req.headers["expect"], "100-continue") {
							return req, .READY, 0
						}
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
				total += val
				if total > MAX_BODY {
					return req, .TOO_LARGE, 0
				}

				cursor := size_end + 2
				end := cursor + val

				if end + 2 > len(r) {
					if utils.has_token(req.headers["expect"], "100-continue") {
						return req, .READY, 0
					}
					return req, .INCOMPLETE, 0
				}

				if str[end] != '\r' || str[end + 1] != '\n' {
					return req, .MALFORMED, 0
				}

				payload := str[cursor:end]
				req.body = fmt.tprintf("{}{}", req.body, payload)

				pos = end + 2
			}

			if val < 0 {
				return req, .MALFORMED, 0
			}
		}
	} else {
		if cl, ok := req.headers["content-length"]; ok {
			for digit in cl {
				if digit < '0' || digit > '9' {
					return req, .MALFORMED, 0
				}
			}
			length, ok := strconv.parse_int(cl, 10)
			if !ok || length < 0 {
				return req, .MALFORMED, 0
			}

			if length > MAX_BODY {
				return req, .TOO_LARGE, 0
			}

			needed := body_start + int(length)
			if len(r) < needed {
				if utils.has_token(req.headers["expect"], "100-continue") {
					return req, .READY, 0
				}
				return req, .INCOMPLETE, 0
			}
			consumed = needed
			req.body = str[body_start:needed]
		}

	}

	return req, .OK, consumed
}
