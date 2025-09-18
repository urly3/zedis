const std = @import("std");
const Connection = std.net.Server.Connection;

// PubSub now uses fixed matrix allocation in Server struct
// This file kept for compatibility but can be removed later
