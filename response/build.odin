package response

import "../utils"
import "core:fmt"
import "core:time"

Writer :: struct {
	status_code: int,
	headers:     map[string]string,
	body:        string,
	chunked:     bool,
	head:        bool,
	payload_len: int,
}

code_response :: proc(code: int) -> string {
	switch code {
	case 100:
		return "Continue"
	case 101:
		return "Switching Protocols"
	case 200:
		return "OK"
	case 201:
		return "Created"
	case 202:
		return "Accepted"
	case 203:
		return "Non-Authoritative Information"
	case 204:
		return "No Content"
	case 205:
		return "Reset Content"
	case 206:
		return "Partial Content"
	case 300:
		return "Multiple Choices"
	case 301:
		return "Moved Permanently"
	case 302:
		return "Found"
	case 303:
		return "See Other"
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
	case 402:
		return "Payment Required"
	case 403:
		return "Forbidden"
	case 404:
		return "Not Found"
	case 405:
		return "Method Not Allowed"
	case 406:
		return "Not Acceptable"
	case 407:
		return "Proxy Authentication Required"
	case 408:
		return "Request Timeout"
	case 409:
		return "Conflict"
	case 410:
		return "Gone"
	case 411:
		return "Length Required"
	case 412:
		return "Precondition Failed"
	case 413:
		return "Content Too Large"
	case 414:
		return "URI Too Long"
	case 415:
		return "Unsupported Media Type"
	case 416:
		return "Range Not Satisfiable"
	case 417:
		return "Expectation Failed"
	case 418:
		return "I'm a teapot"
	case 421:
		return "Misdirected Request"
	case 422:
		return "Unprocessable Content"
	case 426:
		return "Upgrade Required"
	case 429:
		return "Too Many Requests"
	case 431:
		return "Request Header Fields Too Large"
	case 451:
		return "Unavailable For Legal Reasons"
	case 500:
		return "Internal Server Error"
	case 501:
		return "Not Implemented"
	case 502:
		return "Bad Gateway"
	case 503:
		return "Service Unavailable"
	case 504:
		return "Gateway Timeout"
	case 505:
		return "HTTP Version Not Supported"
	case 511:
		return "Network Authentication Required"
	case:
		return "Unknown"
	}
}

new :: proc() -> Writer {
	w := Writer{}
	w.status_code = 200
	w.headers = make(map[string]string)
	w.headers["Date"] = utils.get_date(time.now())
	w.headers["Content-Type"] = "text/plain"
	return w
}

status :: proc(w: ^Writer, code := 200) {
	w.status_code = code
}

header :: proc(w: ^Writer, key: string, value: string) {
	w.headers[key] = value
}

chunk :: proc(w: ^Writer, data: string) {
	w.chunked = true
	w.payload_len += len(data)

	hex := fmt.tprintf("{:x}", len(data))
	w.body = fmt.tprintf("{}{}\r\n{}\r\n", w.body, hex, data)
}

write :: proc(w: ^Writer, data: string) {
	w.body = fmt.tprintf("{}{}", w.body, data)
}

create :: proc(w: ^Writer, code: int) {
	w.status_code = code
	if code == 204 || code == 304 || code >= 100 && code < 200 {
		return
	}
	w.body = code_response(code)
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

	if w.status_code == 204 ||
	   w.status_code == 304 ||
	   (w.status_code >= 100 && w.status_code < 200) {
		res = fmt.tprintf("{}{}\r\n", status_line, headers)
		return res

	}

	if w.head {
		length := w.payload_len if w.chunked else len(w.body)
		content_length := fmt.tprintf("Content-Length: {}\r\n", length)
		res = fmt.tprintf("{}{}{}\r\n", status_line, content_length, headers)
	} else if w.chunked {
		chunked := fmt.tprintf("Transfer-Encoding: chunked\r\n")
		res = fmt.tprintf("{}{}{}\r\n{}0\r\n\r\n", status_line, chunked, headers, w.body)
	} else {
		content_length := fmt.tprintf("Content-Length: {}\r\n", len(w.body))
		res = fmt.tprintf("{}{}{}\r\n{}", status_line, content_length, headers, w.body)
	}

	return res
}
