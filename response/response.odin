package response

import "core:fmt"
import "core:strings"

Writer :: struct {
	status_code: int,
	headers:     map[string]string,
	body:        string,
	// NOTE: While chunking is scaffolded here; current, ohttp isn't set up to use it.
	chunked:     bool,
}

code_response :: proc(code: int) -> string {
	switch code {
	case 200:
		return "OK"
	case 201:
		return "Created"
	case 204:
		return "No Content"
	case 301:
		return "Moved Permanently"
	case 302:
		return "Found"
	case 304:
		return "Not Modified"
	case 307:
		return "Temporary Redirect"
	case 308:
		return "Permanent Redirect"
	case 400:
		return "Bad Request"
	case 401:
		return "Unauthorized"
	case 403:
		return "Forbidden"
	case 404:
		return "Not Found"
	case 405:
		return "Method Not Allowed"
	case 418:
		return "I'm a teapot"
	case 429:
		return "Too Many Requests"
	case 431:
		return "Request Header Fields Too Large"
	case 500:
		return "Internal Server Error"
	case 502:
		return "Bad Gateway"
	case 503:
		return "Service Unavailable"
	case 504:
		return "Gateway Timeout"
	case:
		return "Unknown"
	}
}

new :: proc() -> Writer {
	w := Writer{}
	w.status_code = 200
	w.headers = make(map[string]string)
	w.headers["Content-Type"] = "text/plain"
	return w
}

status :: proc(w: ^Writer, code := 200) {
	w.status_code = code
}

header :: proc(w: ^Writer, key: string, value: string) {
	w.headers[key] = value
}

chunk :: proc(w: ^Writer, enabled := true) {
	w.chunked = enabled
}

write :: proc(w: ^Writer, data: string) {
	w.body = fmt.tprintf("{}{}", w.body, data)
}

create :: proc(w: ^Writer, code: int) {
	w.body = code_response(code)
	w.status_code = code
}

build :: proc(w: ^Writer, version := "1.1") -> string {
	http := fmt.tprintf("HTTP/{}", version)

	status_text := code_response(w.status_code)
	status_line := fmt.tprintf("{} {} {}\r\n", http, w.status_code, status_text)

	headers: string
	for key, val in w.headers {
		pair := fmt.tprintf("{}: {}\r\n", key, val)
		headers = fmt.tprintf("{}{}", headers, pair)
	}

	res: string

	if w.chunked {
		chunked := fmt.tprintf("Transfer-Encoding: chunked\r\n")
		hex := fmt.tprintf("{:x}", len(w.body))
		chunked_body := fmt.tprintf("{}\r\n{}\r\n0\r\n\r\n", hex, w.body)
		res = fmt.tprintf("{}{}{}\r\n{}", status_line, chunked, headers, chunked_body)
	} else {
		content_length := fmt.tprintf("Content-Length: {}\r\n", len(w.body))
		res = fmt.tprintf("{}{}{}\r\n{}", status_line, content_length, headers, w.body)
	}


	return res
}
