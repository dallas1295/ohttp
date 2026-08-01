package response

import "core:fmt"

code_response :: proc(code: int) -> string {
    switch code {
    case 200: return "OK"
    case 201: return "Created"
    case 204: return "No Content"
    case 301: return "Moved Permanently"
    case 302: return "Found"
    case 304: return "Not Modified"
    case 307: return "Temporary Redirect"
    case 308: return "Permanent Redirect"
    case 400: return "Bad Request"
    case 401: return "Unauthorized"
    case 403: return "Forbidden"
    case 404: return "Not Found"
    case 405: return "Method Not Allowed"
    case 418: return "I'm a teapot"
    case 429: return "Too Many Requests"
    case 500: return "Internal Server Error"
    case 502: return "Bad Gateway"
    case 503: return "Service Unavailable"
    case 504: return "Gateway Timeout"
    case:    return "Unknown"
    }
}

build :: proc(body: string, status_code: int, content_type := "text/plain", version := "1.1") -> string {
    http := fmt.tprintf("HTTP/{}", version)

    status_text := code_response(status_code)
    status_line := fmt.tprintf("{} {} {}\r\n", http, status_code, status_text)

    cl := fmt.tprintf("Content-Length: {}\r\n", len(body))
    ct := fmt.tprintf("Content-Type: {}\r\n", content_type)

    output := fmt.tprintf("{}{}{}\r\n{}", status_line, cl, ct, body)

    return output
}
