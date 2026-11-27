//! Blocking Rex control client. Run it on an I/O worker, not the GTK thread.
const std = @import("std");
const WebSocket = @import("Websocket.zig");
const protocol = @import("protocol.zig");

const Self = @This();
const Allocator = std.mem.Allocator;

const max_incoming_bytes = 16 * 1024 * 1024;

alloc: Allocator,
socket: WebSocket = undefined,
welcome: ?std.json.Parsed(protocol.Incoming) = null,
next_id: u64 = 1,

/// Allocate a disconnected client. This does not perform any I/O.
/// The heap allocation keeps the socket's reader/writer buffers stationary.
pub fn init(alloc: Allocator) !*Self {
    const self = try alloc.create(Self);
    self.* = .{ .alloc = alloc };
    return self;
}

/// Convenience constructor for callers that want to connect immediately.
pub fn connect(io: std.Io, alloc: Allocator, path: []const u8) !*Self {
    const self = try init(alloc);
    errdefer self.deinit();
    try self.open(io, path);
    return self;
}

/// Connect an initialized client to an explicit Unix socket path (not a unix:// URI).
/// A failed attempt leaves the client disconnected.
pub fn open(self: *Self, io: std.Io, path: []const u8) !void {
    if (self.welcome != null) return error.AlreadyConnected;
    const alloc = self.alloc;
    try self.socket.connect(io, path, protocol.control_path, protocol.control_subprotocol);
    errdefer self.socket.close();

    const hello = try protocol.encodeHello(alloc, .{ .api_revision = 14, .api_min_revision = 14 });
    defer alloc.free(hello);

    try self.socket.sendText(hello);
    const message = try self.readMessage(max_incoming_bytes);
    errdefer message.deinit();
    if (message.value != .welcome) return error.ExpectedRexWelcome;

    const info = message.value.welcome;
    if (!std.mem.eql(u8, info.protocol, protocol.control_subprotocol) or info.limits.max_message_bytes == 0)
        return error.InvalidRexWelcome;
    if (info.api_revision != 14) return error.UnsupportedRexRevision;

    self.welcome = message;
}

pub fn deinit(self: *Self) void {
    const alloc = self.alloc;
    if (self.welcome) |welcome| {
        welcome.deinit();
        self.socket.close();
    }
    alloc.destroy(self);
}

pub fn send(self: *Self, comptime Method: type, params: Method.Params) !u64 {
    const welcome = self.welcome orelse return error.NotConnected;
    const id = self.next_id;
    const next_id = std.math.add(u64, id, 1) catch return error.RequestIdExhausted;
    var id_buffer: [20]u8 = undefined;
    const id_text = try std.fmt.bufPrint(&id_buffer, "{d}", .{id});
    const bytes = try protocol.encodeRequest(self.alloc, Method, id_text, params);
    defer self.alloc.free(bytes);
    if (bytes.len > welcome.value.welcome.limits.max_message_bytes) return error.RexRequestTooLarge;
    try self.socket.sendText(bytes);
    self.next_id = next_id;

    return id;
}

pub fn receive(self: *Self) !std.json.Parsed(protocol.Incoming) {
    const welcome = self.welcome orelse return error.NotConnected;
    return self.readMessage(@min(max_incoming_bytes, welcome.value.welcome.limits.max_message_bytes));
}

/// Convenience for a single outstanding request. Discards unsolicited events;
/// use send/receive directly when the caller also needs to process events.
/// Inspect the returned response's error or call parseResult before deinit.
pub fn call(self: *Self, comptime Method: type, params: Method.Params) !std.json.Parsed(protocol.Response) {
    const id = try self.send(Method, params);
    var id_buffer: [20]u8 = undefined;
    const id_text = try std.fmt.bufPrint(&id_buffer, "{d}", .{id});
    while (true) {
        const message = try self.receive();
        switch (message.value) {
            .response => |response| {
                if (std.mem.eql(u8, id_text, response.id)) {
                    return .{ .arena = message.arena, .value = response };
                }
                message.deinit();
                return error.UnexpectedRexResponse;
            },
            .event, .unknown => message.deinit(),
            .welcome => {
                message.deinit();
                return error.UnexpectedRexWelcome;
            },
        }
    }
}

fn readMessage(self: *Self, limit: usize) !std.json.Parsed(protocol.Incoming) {
    const bytes = try self.socket.receiveText(self.alloc, limit);
    defer self.alloc.free(bytes);

    return protocol.decodeIncoming(self.alloc, bytes);
}

test "client starts disconnected" {
    const client = try init(std.testing.allocator);
    defer client.deinit();

    try std.testing.expectError(error.NotConnected, client.send(protocol.ServerVersion, .{}));
    try std.testing.expectError(error.NotConnected, client.receive());
}
