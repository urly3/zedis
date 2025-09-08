# Zedis 🚀

A Redis-compatible in-memory data store written in [Zig](https://ziglang.org/), designed for learning and experimentation. Zedis implements the core Redis protocol and data structures with a focus on simplicity, performance, and thread safety.

## Features ✨

- **Redis Protocol Compatibility**: Supports the Redis Serialization Protocol (RESP)
- **Thread-Safe Operations**: Built with concurrent access in mind using read-write locks
- **Multiple Data Types**: String and integer value storage with automatic type conversion
- **Core Commands**: Essential Redis commands including GET, SET, INCR, DECR, DEL, EXISTS, and TYPE
- **High Performance**: Written in Zig for optimal performance and memory safety
- **Connection Management**: Handles multiple concurrent client connections
- **Detailed Logging**: Comprehensive logging for debugging and monitoring

## Quick Start 🏃‍♂️

### Prerequisites

- [Zig](https://ziglang.org/download/) (minimum version 0.15.1)

### Building and Running

```bash
# Clone the repository
git clone https://github.com/barddoo/zedis.git
cd zedis

# Build the project
zig build

# Run the server
zig build run
```

The server will start on `127.0.0.1:6379` by default.

### Testing with Redis CLI

You can test Zedis using the standard `redis-cli` or any Redis client:

```bash
# Connect to Zedis
redis-cli -h 127.0.0.1 -p 6379

# Try some commands
127.0.0.1:6379> SET mykey "Hello, Zedis!"
OK
127.0.0.1:6379> GET mykey
"Hello, Zedis!"
127.0.0.1:6379> INCR counter
(integer) 1
127.0.0.1:6379> TYPE mykey
string
```

## Supported Commands 📝

### String Commands
- `SET key value` - Set a key to hold a string value
- `GET key` - Get the value of a key
- `INCR key` - Increment the integer value of a key by one
- `DECR key` - Decrement the integer value of a key by one
- `INCRBY key increment` - Increment the integer value of a key by the given amount
- `DECRBY key decrement` - Decrement the integer value of a key by the given amount

### Generic Commands
- `DEL key [key ...]` - Delete one or more keys
- `EXISTS key [key ...]` - Check if keys exist
- `TYPE key` - Determine the type stored at key

### Connection Commands
- `PING [message]` - Ping the server
- `ECHO message` - Echo the given string

## Architecture 🏗️

Zedis is built with a modular architecture:

```
src/
├── main.zig          # Entry point and server initialization
├── server.zig        # TCP server and connection handling
├── client.zig        # Client connection management
├── store.zig         # Thread-safe in-memory data store
├── parser.zig        # RESP protocol parser
└── commands/         # Command implementations
    ├── registry.zig  # Command registration and dispatch
    ├── t_string.zig  # String type commands
    └── connection.zig # Connection commands
```

### Key Components

- **Server**: Manages TCP connections and spawns handlers for each client
- **Store**: Thread-safe HashMap with read-write locks for concurrent access
- **Parser**: Implements the Redis Serialization Protocol (RESP) for parsing client commands
- **Command Registry**: Extensible command system for easy addition of new commands
- **Client**: Handles individual client sessions and command execution

## Performance 🚄

Zedis is designed for high performance:

- **Zero-copy parsing** where possible
- **Efficient memory management** with arena allocators
- **Read-write locks** for optimal concurrent read performance
- **Minimal allocations** in hot paths
- **Connection pooling** ready architecture

## Development 🛠️

### Project Structure

The codebase follows Zig conventions with clear separation of concerns:

- Type-safe operations with compile-time guarantees
- Explicit error handling throughout
- Memory safety with RAII patterns
- Comprehensive logging for debugging

### Building for Development

```bash
# Build in debug mode (default)
zig build -Doptimize=Debug

# Build optimized release
zig build -Doptimize=ReleaseFast

# Run tests (when available)
zig build test
```

### Adding New Commands

1. Implement the command handler in the appropriate file under `src/commands/`
2. Register the command in the command registry
3. Add tests for the new functionality

Example:
```zig
pub fn myCommand(client: *Client, args: []const Value) !void {
    // Command implementation
    try client.writeSimpleString("OK");
}
```

## Limitations ⚠️

Current limitations (contributions welcome!):

- **Persistence**: No disk persistence (memory-only)
- **Clustering**: Single-node only
- **Advanced Data Types**: No lists, sets, hashes, or sorted sets yet
- **Pub/Sub**: No publish/subscribe functionality
- **Lua Scripting**: No scripting support
- **Transactions**: No multi-command transactions
- **Memory Management**: No expiration or eviction policies

## Roadmap 🗺️

- [ ] Add [RDB snapshots](https://rdb.fnordig.de/file_format.html#string-encoding) (WIP)
- [ ] Implement AOF (Append Only File) logging
- [ ] Implement more Redis commands
- [ ] Add support for lists and sets
- [ ] Implement pub/sub functionality
- [ ] Add configuration file support
- [ ] Implement key expiration
- [ ] Add clustering support
- [ ] Performance benchmarking suite

## Contributing 🤝

Contributions are welcome! Here's how you can help:

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/amazing-feature`
3. **Make your changes** and add tests
4. **Commit your changes**: `git commit -m 'Add amazing feature'`
5. **Push to the branch**: `git push origin feature/amazing-feature`
6. **Open a Pull Request**

### Code Style

- Follow Zig's standard formatting (`zig fmt`)
- Add comprehensive error handling
- Include documentation comments for public APIs
- Write tests for new functionality

## License 📄

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments 🙏

- Inspired by the original [Redis](https://redis.io/) project
- Built with the amazing [Zig](https://ziglang.org/) programming language
- Thanks to the Zig community for excellent documentation and support

## Contact 📧

- GitHub: [@barddoo](https://github.com/barddoo)
- Project Link: [https://github.com/barddoo/zedis](https://github.com/barddoo/zedis)

---

**Zedis** - Learning Redis internals through Zig! 🦎⚡