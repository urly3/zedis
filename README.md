# Zedis

A Redis-compatible in-memory data store written in [Zig](https://ziglang.org/), designed for learning and experimentation. Zedis implements the core Redis protocol and data structures with a focus on simplicity, performance, and thread safety.

> Made for learning purposes. Not intended for production use.

## Features

- **Redis Protocol Compatibility**: Supports the Redis Serialization Protocol (RESP)locks
- **Multiple Data Types**: String and integer value storage with automatic type conversion
- **Core Commands**: Essential Redis commands including GET, SET, INCR, DECR, DEL, EXISTS, and TYPE
- **High Performance**: Written in Zig for optimal performance and memory safety
- **Connection Management**: Handles multiple concurrent client connections
- **Disk persistence (RDB)**: Point-in-time snapshots of your dataset.
- **Memory Management**: No memory allocation during command execution.
- **Pub/Sub**: Decoupled communication between services. **(latest feature)** 🎉

## Roadmap

- [x] Add [RDB snapshots](https://rdb.fnordig.de/file_format.html#string-encoding)
- [x] Implement pub/sub functionality
- [x] Implement key expiration
- [x] Background job for key expiration
- [ ] Add tests to key expiration
- [ ] Implement AOF (Append Only File) logging
- [ ] Implement more Redis commands
- [ ] Add support for lists and sets
- [ ] Add configuration file support
- [ ] Add clustering support
- [ ] Performance benchmarking suite

## Quick Start

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

## Development

### Project Structure

The codebase follows Zig conventions with clear separation of concerns:

- Type-safe operations with compile-time guarantees
- Explicit error handling throughout
- Memory safety without garbage collection
- Modular design for easy extension
- Comprehensive logging for debugging

### Memory Management

All memory allocations are handled during the initialization phase. No dynamic memory allocation occurs during command execution, ensuring high performance and predictability. Hugely inspired by this [article](https://tigerbeetle.com/blog/2022-10-12-a-database-without-dynamic-memory/).

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

### Code Style

- Follow Zig's standard formatting (`zig fmt`)
- Add comprehensive error handling
- Include documentation comments for public APIs
- Write tests for new functionality

## Contact

- GitHub: [@barddoo](https://github.com/barddoo)
- Project Link: [https://github.com/barddoo/zedis](https://github.com/barddoo/zedis)

## Thanks
- Inspired by [Redis](https://redis.io/) and [Zig](https://ziglang.org/)
