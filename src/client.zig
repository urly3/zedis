const std = @import("std");
const Connection = std.net.Server.Connection;
const posix = std.posix;
const pollfd = posix.pollfd;
const Parser = @import("parser.zig").Parser;
const store_mod = @import("store.zig");
const Store = store_mod.Store;
const ZedisObject = store_mod.ZedisObject;
const ZedisValue = store_mod.ZedisValue;
const Command = @import("parser.zig").Command;
const CommandRegistry = @import("./commands/registry.zig").CommandRegistry;
const Server = @import("./server.zig").Server;
const PubSubContext = @import("./pubsub/pubsub.zig").PubSubContext;
const ServerConfig = @import("./server_config.zig").ServerConfig;
const Value = @import("./parser.zig").Value;
const resp = @import("./commands/resp.zig");

var next_client_id: std.atomic.Value(u64) = std.atomic.Value(u64).init(1);

pub const Client = struct {
    allocator: std.mem.Allocator,
    authenticated: bool,
    client_id: u64,
    command_registry: *CommandRegistry,
    connection: Connection,
    is_in_pubsub_mode: bool,
    pubsub_context: *PubSubContext,
    server: *Server,
    store: *Store,
    writer: std.net.Stream.Writer,

    pub fn init(
        allocator: std.mem.Allocator,
        connection: Connection,
        pubsub_context: *PubSubContext,
        registry: *CommandRegistry,
        server: *Server,
        store: *Store,
    ) Client {
        const id = next_client_id.fetchAdd(1, .monotonic);
        return .{
            .allocator = allocator,
            .authenticated = false,
            .client_id = id,
            .command_registry = registry,
            .connection = connection,
            .is_in_pubsub_mode = false,
            .pubsub_context = pubsub_context,
            .server = server,
            .store = store,
            .writer = connection.stream.writer(&.{}),
        };
    }

    pub fn deinit(self: *Client) void {
        self.connection.stream.close();
    }

    pub fn enterPubSubMode(self: *Client) void {
        self.is_in_pubsub_mode = true;
        std.log.debug("Client {} entered pubsub mode", .{self.client_id});
    }

    pub fn handle(self: *Client) !void {
        var sr = self.connection.stream.reader(&.{});
        var sw = self.connection.stream.writer(&.{});
        const reader = sr.interface();
        const writer = &sw.interface;

        while (true) {
            // Parse the incoming command from the client's stream.
            var parser = Parser.init(self.allocator);
            var command = parser.parse(reader) catch |err| {
                // If there's an error (like a closed connection), we stop handling this client.
                if (err == error.EndOfStream) {
                    // In pubsub mode, we might want to keep the connection open even on EndOfStream
                    if (self.is_in_pubsub_mode) {
                        std.log.debug("Client {} in pubsub mode, connection ended", .{self.client_id});
                    }
                    return;
                }
                if (err == error.ReadFailed) {
                    if (self.is_in_pubsub_mode) {
                        std.log.debug("Client {} in pubsub mode, read failed", .{self.client_id});
                    }
                    return;
                }
                std.log.err("Parse error: {s}", .{@errorName(err)});
                resp.writeError(writer, "ERR protocol error") catch {};
                continue;
            };
            defer command.deinit();

            // Check if auth is needed for this command
            const first_arg = command.args.items[0].asSlice();
            const first_arg_upper = try std.ascii.allocUpperString(self.allocator, first_arg);
            defer self.allocator.free(first_arg_upper);

            if (!std.mem.eql(u8, first_arg_upper[0..@min(4, first_arg_upper.len)], "AUTH") and
                !std.mem.eql(u8, first_arg_upper[0..@min(4, first_arg_upper.len)], "PING") and
                !self.isAuthenticated())
            {
                return resp.writeError(writer, "NOAUTH Authentication required");
            }

            // Execute the parsed command.
            self.executeCommand(command) catch |err| {
                if (err == error.ClientQuit) {
                    return;
                }
                return err;
            };

            // If we're in pubsub mode after executing a command, stay connected
            if (self.is_in_pubsub_mode) {
                std.log.debug("Client {} staying in pubsub mode", .{self.client_id});
            }
        }
    }

    // Dispatches the parsed command to the appropriate handler function.
    fn executeCommand(self: *Client, command: Command) !void {
        const writer = &self.writer.interface;
        try self.command_registry.executeCommand(writer, self, self.store, command.args.items);
    }

    pub fn isAuthenticated(self: *Client) bool {
        return !self.server.config.requiresAuth() or self.authenticated;
    }
};
