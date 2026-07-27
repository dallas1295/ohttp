# Step 1 — Raw TCP Echo Server

**Goal:** Get a server listening on a port, accepting connections, reading raw bytes, and echoing them back.

**Exit criteria:** Run your server, connect with `nc localhost 8080`, type something, see it echoed back.

---

## What You Need To Understand First

Before writing any code, you need to understand these concepts. Read about them, don't just skim:

### 1. What is a socket?

A socket is a file descriptor. That's it. In Linux, "everything is a file," and a network socket is no different. You read from it and write to it like any other file, except the bytes go over the network instead of to disk.

### 2. The server lifecycle

Every TCP server follows this pattern:

```
socket()    → create the socket (get an fd)
    ↓
bind()      → attach it to a port (e.g. 8080)
    ↓
listen()    → tell the OS "I want to accept connections on this"
    ↓
accept()    → block and wait for a client to connect
    ↓         (returns a NEW fd for the specific client connection)
recv()      → read bytes from the client
    ↓
send()      → write bytes back to the client
    ↓
close()     → close the client connection
    ↓
(loop back to accept() for the next client)
```

The key insight: `socket()` + `bind()` + `listen()` happens **once** at startup. Then you loop on `accept()` forever, each iteration handling one client.

### 3. Why accept() returns a new fd

The "listening" socket (from `socket()`) is only for accepting connections. When a client connects, `accept()` gives you a **new** fd that represents that specific client connection. You read/write on *that* fd, not the listening fd.

### 4. recv() can return partial data

This is the #1 gotcha. When you call `recv(fd, buffer, size)`, it might not fill your buffer. The client might send 1000 bytes but `recv()` might only give you 500 on the first call and 500 on the second. You almost always need a loop:

```
loop {
    bytes = recv(fd, buffer, size)
    if bytes <= 0 { break }  // connection closed or error
    // process the `bytes` amount of data in buffer
}
```

For an echo server this is straightforward. For HTTP parsing (Phase 2+) this becomes a real design challenge — you need a persistent buffer that accumulates data across multiple `recv()` calls.

---

## The Syscalls You'll Use

| Syscall | What it does | Header |
|---------|-------------|--------|
| `socket(AF_INET, SOCK_STREAM, 0)` | Creates a TCP socket | `<sys/socket.h>` |
| `bind(fd, &addr, sizeof(addr))` | Binds socket to address+port | `<sys/socket.h>` |
| `listen(fd, backlog)` | Marks socket as passive listener | `<sys/socket.h>` |
| `accept(fd, &client_addr, &addr_len)` | Blocks until client connects | `<sys/socket.h>` |
| `recv(fd, buffer, size, 0)` | Reads bytes from client | `<sys/socket.h>` |
| `send(fd, buffer, size, 0)` | Sends bytes to client | `<sys/socket.h>` |
| `close(fd)` | Closes the connection | `<unistd.h>` |
| `setsockopt(...)` | Sets socket options (reuse addr) | `<sys/socket.h>` |

### The sockaddr_in struct

`bind()` needs to know *what address and port* to bind to. This is passed as a `sockaddr_in` struct:

```c
struct sockaddr_in {
    short          sin_family;    // AF_INET (IPv4)
    unsigned short sin_port;      // port in NETWORK byte order (htons!)
    struct in_addr sin_addr;      // IP address (INADDR_ANY = all interfaces)
    char           sin_zero[8];   // padding, ignore
};
```

The `htons()` call is critical — network protocols use big-endian byte order. Your CPU might be little-endian. `htons()` = "host to network short" converts your port number to the correct byte order. Always wrap port numbers in `htons()`.

---

## Resources To Learn From

### Read these (in order):

1. **Beej's Guide to Network Programming** — THE classic.
   - https://beej.us/guide/bgnet/
   - Read chapters 3 (structures), 5 (system calls), and 6 (client-server).
   - It's in C but that's exactly what you need — you're calling the same syscalls from Odin.
   - This is the single most important resource. Read it carefully.

2. **Linux man pages** — Reference for every syscall.
   - `man 2 socket`, `man 2 bind`, `man 2 listen`, `man 2 accept`, `man 2 recv`, `man 2 send`
   - The `2` means section 2 (system calls). Run these in your terminal.

3. **Odin `vendor:libc` package** — How to call C functions from Odin.
   - https://odin-lang.org/docs/libc/
   - You'll be importing C socket functions. Odin's `vendor:libc` exposes them.

### Watch these (optional but helpful):

4. **"Let's code a TCP server in C" type videos** — Search YouTube.
   - Seeing someone write a raw socket server in C will make the Odin version click.
   - Look for ones that use `socket()`, `bind()`, `listen()`, `accept()` explicitly — not high-level wrappers.

### Reference implementations to study (not copy):

5. **Look at how others do it in C first**, then translate the pattern to Odin.
   - The logic is identical. Only the syntax changes.

---

## Your Plan For This Phase

Work through these sub-steps:

### Step 1.1 — Create the socket

- Call `socket(AF_INET, SOCK_STREAM, 0)`
- Check for errors (returns -1 on failure)
- Print the fd to confirm it worked

### Step 1.2 — Bind to a port

- Fill out a `sockaddr_in` struct
- Use `INADDR_ANY` (bind to all interfaces) and a port like `8080`
- Call `bind()` and check for errors
- **Tip:** Use `setsockopt(SO_REUSEADDR)` before `bind()` to avoid "address already in use" errors when restarting your server during development

### Step 1.3 — Listen

- Call `listen(fd, 10)` — the `10` is the backlog (how many pending connections the OS queues)
- Check for errors

### Step 1.4 — Accept a connection

- Call `accept()` in a loop
- Print the client's IP address when they connect
- This blocks — your program will pause here until someone connects

### Step 1.5 — Echo loop

- After `accept()`, enter a `recv()` / `send()` loop on the client fd
- Read bytes, write the same bytes back
- When `recv()` returns 0 or negative, the client disconnected — `close()` the fd
- Then loop back to `accept()`

### Step 1.6 — Test it

```bash
# Terminal 1: run your server
odin run .

# Terminal 2: connect and type
nc localhost 8080
hello
hello          # <- you should see this echoed back
```

---

## Odin-Specific Notes

- You'll import C functions from `vendor:libc` or declare them with `foreign import`.
- `sockaddr_in` will be a struct you define or pull from libc bindings.
- Memory management — use Odin's `context.allocator` or raw buffers. For an echo server, a simple `[4096]byte` buffer on the stack is fine.
- Error handling — C syscalls return -1 on error and set `errno`. In Odin you'll check the return value and possibly read `errno`.

---

## Common Gotchas

| Problem | Cause | Fix |
|---------|-------|-----|
| "Address already in use" on restart | Previous server instance still holds the port | Use `setsockopt(SO_REUSEADDR)` |
| Server connects but no data comes through | Forgot `htons()` on the port | Always use `htons()` for port numbers |
| `recv()` returns weird small numbers | This is normal — TCP gives you partial data | Loop on recv until you have what you need |
| Server hangs forever | `accept()` is blocking and no client connected | This is correct behavior! Connect with `nc` |
| Can't connect from another machine | Firewall or bound to localhost only | Use `INADDR_ANY` and check firewall |

---

## Questions To Test Yourself

Before moving to Phase 2, make sure you can answer:

1. What's the difference between the listening socket fd and the client fd from `accept()`?
2. Why does `recv()` not guarantee it fills your buffer?
3. What does `SO_REUSEADDR` do and why do you need it?
4. What byte order does the network use, and what function converts your port number?
5. What happens when a client disconnects — what does `recv()` return?

If you can answer all five and your echo server works, you're ready for Phase 2.
