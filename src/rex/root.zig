//! Public entry point for the Rex client. The WebSocket transport stays internal.
pub const Client = @import("Client.zig");
pub const protocol = @import("protocol.zig");

test {
    _ = Client;
    _ = protocol;
}
