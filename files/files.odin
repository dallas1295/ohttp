package files

import "core:fmt"
import "core:os"
import "core:strings"

File_Result :: enum {
	OK,
	NOT_FOUND,
	FORBIDDEN,
}

get_type :: proc(path: string) -> string {
	dot := strings.last_index_byte(path, '.')
	if dot == -1 {
		return "application/octet-stream"
	}
	ext := path[dot:]

	switch ext {
	case ".html":
		return "text/html"
	case ".css":
		return "text/css"
	case ".js":
		return "application/javascript"
	case ".json":
		return "application/json"
	case ".png":
		return "image/png"
	case ".jpg":
		return "image/jpeg"
	case ".svg":
		return "image/svg+xml"
	case ".ico":
		return "image/x-icon"
	case ".txt":
		return "text/plain"
	case:
		return "application/octet-stream"
	}
}

read :: proc(
	raw_path: string,
	root := "static",
) -> (
	content: string,
	content_type: string,
	result: File_Result,
) {
	if strings.contains(raw_path, "..") {
		return "", "", .FORBIDDEN
	}
	path := fmt.tprintf("{}{}", root, raw_path)
	ct := get_type(path)

	b, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		return "", "", .NOT_FOUND
	}
	f := string(b)

	return f, ct, .OK
}
