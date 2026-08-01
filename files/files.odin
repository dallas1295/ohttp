package files

import "core:strings"
import "core:fmt"
import "core:os"

// .html  → text/html
// .css   → text/css
// .js    → application/javascript
// .json  → application/json
// .png   → image/png
// .jpg   → image/jpeg
// .svg   → image/svg+xml
// .ico   → image/x-icon
// .txt   → text/plain
// default → application/octet-stream
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

read :: proc(raw_path: string, root := "static") -> (content: string, content_type: string, ok: bool) {
    path := fmt.tprintf("{}{}", root, raw_path)
    ct := get_type(path)

    b, err := os.read_entire_file(path, context.allocator)
    if err != nil {
        fmt.eprintln("could not read provided path")
        return "", "", false
    }
    f := string(b)

    return f, ct, true
}
