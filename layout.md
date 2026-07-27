# HTTP/1.1 From Scratch — Project Layout

Building an HTTP/1.1 server in Odin using raw syscalls. No `core:net` wrapper, no external libraries.

---

## Phase Overview

| Phase | Goal | Difficulty | Est. Time | Depends On |
|-------|------|------------|-----------|------------|
| 1 | Raw TCP echo server | ★★★☆☆ | 3-5 days | nothing |
| 2 | Request line + header parsing | ★★☆☆☆ | 3-5 days | Phase 1 |
| 3 | Build & send HTTP responses | ★★☆☆☆ | 2-3 days | Phase 2 |
| 4 | GET + static file serving | ★★★☆☆ | 3-5 days | Phase 3 |
| 5 | POST + request bodies | ★★★☆☆ | 3-5 days | Phase 4 |
| 6 | Keep-alive / persistent connections | ★★★★☆ | 1-2 weeks | Phase 4 |
| 7 | Chunked transfer encoding | ★★★☆☆ | 3-5 days | Phase 6 |
| 8 | Robustness & edge cases | ★★★★☆ | ongoing | Phase 7 |

**Total estimate: 5-8 weeks part-time**

---

## Detailed Breakdown

### Phase 1 — Raw TCP Echo Server

```
┌─────────────────────────────────────────────┐
│  socket()     → create a TCP socket          │
│  bind()       → attach to a port (e.g. 8080) │
│  listen()     → start accepting connections  │
│  accept()     → get a client fd              │
│  recv() /     → read bytes from client       │
│  send()       → write bytes back to client   │
│  close()      → close the connection         │
└─────────────────────────────────────────────┘
```

**What you're learning:** How sockets work at the syscall level. How to open a port, wait for a connection, read raw bytes, write raw bytes back, and close. At the end of this phase you'll have a server that echoes back whatever you send it.

**Key concepts:**
- File descriptors (everything is an fd)
- `sockaddr_in` structs (the address format C uses)
- Byte order (`htonl`, `htons` — network vs host byte order)
- The `recv()` loop — `recv` can return partial data

**Exit criteria:** Run your server, connect with `nc localhost 8080`, type something, see it echoed back.

---

### Phase 2 — Request Line + Header Parsing

```
┌──────────────────────────────────────────────────────────┐
│  GET /index.html HTTP/1.1\r\n          ← request line    │
│  Host: localhost:8080\r\n               ← header          │
│  User-Agent: curl/7.81.0\r\n            ← header          │
│  Accept: */*\r\n                        ← header          │
│  \r\n                                   ← blank line = end│
└──────────────────────────────────────────────────────────┘
```

**What you're learning:** HTTP/1.1 is line-based text. Every line ends with `\r\n` (CRLF). The headers end with a blank `\r\n` line. You need to parse the request line (method, path, version) and each header (key: value).

**Key concepts:**
- CRLF line splitting
- The request line format: `METHOD SP PATH SP VERSION`
- Header format: `Key: Value`
- Where headers end (the `\r\n\r\n` boundary)

**Exit criteria:** Print a parsed request struct to stdout showing method, path, version, and a map of headers.

---

### Phase 3 — Build & Send HTTP Responses

```
┌──────────────────────────────────────────────────────────┐
│  HTTP/1.1 200 OK\r\n                     ← status line   │
│  Content-Type: text/plain\r\n           ← header         │
│  Content-Length: 13\r\n                  ← header         │
│  \r\n                                    ← blank line    │
│  Hello, World!                           ← body          │
└──────────────────────────────────────────────────────────┘
```

**What you're learning:** Responses are the mirror of requests. You build a string with the status line, headers, blank line, then body, and `send()` it.

**Key concepts:**
- Status codes (200, 404, 500, etc.)
- `Content-Length` — tells the client how many body bytes to expect
- `Content-Type` — tells the client what the body is (text, HTML, JSON, etc.)
- String building and byte counting

**Exit criteria:** `curl http://localhost:8080/` returns a proper HTTP response with headers and body.

---

### Phase 4 — GET + Static File Serving

```
Client                          Server
  │                               │
  │  GET /index.html HTTP/1.1     │
  │ ────────────────────────────> │
  │                               │  open("www/index.html")
  │                               │  read file into buffer
  │  HTTP/1.1 200 OK              │
  │  Content-Type: text/html      │
  │  <file contents>              │
  │ <──────────────────────────── │
```

**What you're learning:** Map URL paths to files on disk. Read file contents. Guess the content type from the file extension. Handle the case where the file doesn't exist (404).

**Key concepts:**
- File I/O (`open`, `read`, `close` syscalls)
- MIME types (`.html` → `text/html`, `.css` → `text/css`, etc.)
- Path handling (stripping `/`, preventing directory traversal attacks)
- 404 responses

**Exit criteria:** Serve a real `index.html` file from a `www/` directory. Browser can load it.

---

### Phase 5 — POST + Request Bodies

```
┌────────────────────────────────────────────────────────────────┐
│  POST /submit HTTP/1.1\r\n                                      │
│  Content-Type: application/x-www-form-urlencoded\r\n            │
│  Content-Length: 21\r\n                                         │
│  \r\n                                                           │
│  name=dallas&age=100  ← body (Content-Length bytes)            │
└────────────────────────────────────────────────────────────────┘
```

**What you're learning:** Until now you've only sent responses with bodies. Now you need to read a request body. The body comes *after* the `\r\n\r\n`. `Content-Length` tells you how many bytes to read.

**Key concepts:**
- Reading exactly N bytes after the header section
- Handling the case where `recv()` gives you some body bytes mixed with headers
- URL decoding (`%20` → space, `+` → space, etc.)
- Different body types (form data, JSON, etc.)

**Exit criteria:** Submit an HTML form via POST and have your server read and print the body.

---

### Phase 6 — Keep-Alive / Persistent Connections

```
Without Keep-Alive:              With Keep-Alive:
  Client connects                  Client connects
  Client sends 1 request           Client sends request 1 → response 1
  Server responds                  Client sends request 2 → response 2
  Connection CLOSES                Client sends request 3 → response 3
  Client reconnects for next       ...connection stays open until
  request                          Connection: close or timeout
```

**What you're learning:** HTTP/1.1 defaults to keep-alive. The client can send multiple requests on the same connection. You must NOT close the socket after each response. Instead, loop: read request → respond → read next request → respond.

**Key concepts:**
- The `Connection: keep-alive` vs `Connection: close` header
- Looping on the same fd
- Buffer management across requests (leftover bytes from previous recv might be the start of the next request)
- Timeout handling (don't wait forever for a request that never comes)
- `Connection: close` handling

**Exit criteria:** Open one connection with `nc` or curl, send multiple requests, get multiple responses without reconnecting.

---

### Phase 7 — Chunked Transfer Encoding

```
┌──────────────────────────────────────────────────────────┐
│  HTTP/1.1 200 OK\r\n                                      │
│  Transfer-Encoding: chunked\r\n                           │
│  \r\n                                                     │
│  5\r\n                ← chunk size in hex                 │
│  Hello\r\n            ← chunk data (5 bytes)              │
│  7\r\n                                                     │
│  , World\r\n                                              │
│  0\r\n                ← zero-size chunk = end             │
│  \r\n                                                     │
└──────────────────────────────────────────────────────────┘
```

**What you're learning:** Some responses (and requests) don't know their `Content-Length` upfront. Instead they send data in chunks. Each chunk has a size prefix in hex, then the data. A zero-size chunk signals the end.

**Key concepts:**
- Hex parsing (chunk sizes are in hex)
- Reading chunks: size → data → size → data → 0
- Sending chunks (useful for streaming responses)
- Mixing with keep-alive

**Exit criteria:** Send a chunked response that a browser or curl renders correctly.

---

### Phase 8 — Robustness & Edge Cases

This phase is ongoing and never truly "done." It's about handling the weird stuff:

```
┌───────────────────────────────────────────────────────────────┐
│  • Malformed requests (garbage bytes, wrong line endings)     │
│  • Very large headers / bodies (denial of service protection) │
│  • Empty requests (client connects, sends nothing)            │
│  • Client disconnects mid-request (ECONNRESET, EPIPE)         │
│  • Slow clients (slowloris attack protection)                 │
│  • URL edge cases (query strings, fragments, encoding)        │
│  • Multiple Content-Length headers (attack vector)            │
│  • Pipelined requests (multiple requests in one recv)         │
│  • Graceful shutdown (SIGINT handling)                        │
└───────────────────────────────────────────────────────────────┘
```

---

## Syscall Reference

Every phase builds on these. You'll use them constantly:

```
socket()     Creates an endpoint for communication
bind()       Binds socket to an address/port
listen()     Marks socket as passive (will accept connections)
accept()     Blocks until a client connects, returns new fd
recv()       Reads bytes from a connected fd (may return partial data)
send()       Writes bytes to a connected fd
close()      Closes an fd
setsockopt() Sets socket options (SO_REUSEADDR, timeouts, etc.)
```
