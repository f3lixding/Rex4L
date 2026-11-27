//! Minimal WebSocket transport for Rex's local Unix socket. No TCP or TLS.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Self = @This();

io: std.Io,
socket: std.Io.net.Stream,
input: std.Io.net.Stream.Reader,
output: std.Io.net.Stream.Writer,
read_buffer: [4096]u8,
write_buffer: [4096]u8,

pub fn connect(self: *Self, io: std.Io, path: []const u8, comptime route: []const u8, comptime subprotocol: []const u8) !void {
    const address = try std.Io.net.UnixAddress.init(path);
    const socket = try address.connect(io);
    errdefer socket.close(io);
    self.io = io;
    self.socket = socket;
    // The readers borrow these buffers, so Self must stay at a stable address.
    self.input = socket.reader(io, &self.read_buffer);
    self.output = socket.writer(io, &self.write_buffer);

    var nonce: [16]u8 = undefined;
    try io.randomSecure(&nonce);
    const base64 = std.base64.standard.Encoder;
    var key_buffer: [24]u8 = undefined;
    const key = base64.encode(&key_buffer, &nonce);
    const writer = &self.output.interface;
    try writer.print("GET {s} HTTP/1.1\r\nHost: localhost\r\n" ++
        "Upgrade: websocket\r\nConnection: Upgrade\r\n" ++
        "Sec-WebSocket-Version: 13\r\nSec-WebSocket-Key: {s}\r\n" ++
        "Sec-WebSocket-Protocol: {s}\r\n\r\n", .{ route, key, subprotocol });
    try writer.flush();

    var sha = std.crypto.hash.Sha1.init(.{});
    sha.update(key);
    sha.update("258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
    var digest: [20]u8 = undefined;
    sha.final(&digest);
    var accept_buffer: [28]u8 = undefined;
    const expected_accept = base64.encode(&accept_buffer, &digest);

    const reader = &self.input.interface;
    const status = try reader.takeDelimiterInclusive('\n');
    if (!std.mem.startsWith(u8, status, "HTTP/1.1 101 ")) return error.WebSocketUpgradeRejected;
    var accept = false;
    var protocol = false;
    var upgrade = false;
    var connection = false;
    for (0..64) |_| {
        const line = try reader.takeDelimiterInclusive('\n');
        if (std.mem.eql(u8, line, "\r\n")) {
            if (!(accept and protocol and upgrade and connection)) return error.InvalidWebSocketUpgrade;
            return;
        }
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse return error.InvalidWebSocketUpgrade;
        const name = line[0..colon];
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t\r\n");
        if (std.ascii.eqlIgnoreCase(name, "Sec-WebSocket-Accept")) {
            if (accept or !std.mem.eql(u8, value, expected_accept)) return error.InvalidWebSocketUpgrade;
            accept = true;
        } else if (std.ascii.eqlIgnoreCase(name, "Sec-WebSocket-Protocol")) {
            if (protocol or !std.mem.eql(u8, value, subprotocol)) return error.InvalidWebSocketUpgrade;
            protocol = true;
        } else if (std.ascii.eqlIgnoreCase(name, "Upgrade")) {
            upgrade = std.ascii.eqlIgnoreCase(value, "websocket");
        } else if (std.ascii.eqlIgnoreCase(name, "Connection")) {
            var tokens = std.mem.splitScalar(u8, value, ',');
            while (tokens.next()) |token| {
                if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, token, " \t"), "upgrade")) connection = true;
            }
        } else if (std.ascii.eqlIgnoreCase(name, "Sec-WebSocket-Extensions")) {
            return error.InvalidWebSocketUpgrade;
        }
    }
    return error.InvalidWebSocketUpgrade;
}

pub fn close(self: *Self) void {
    self.socket.close(self.io);
}

pub fn sendText(self: *Self, text: []const u8) !void {
    try self.sendFrame(0x1, text);
}

fn sendFrame(self: *Self, opcode: u8, bytes: []const u8) !void {
    const writer = &self.output.interface;
    var mask: [4]u8 = undefined;
    try self.io.randomSecure(&mask);
    try writer.writeByte(0x80 | opcode);
    if (bytes.len < 126) {
        try writer.writeByte(0x80 | @as(u8, @intCast(bytes.len)));
    } else if (bytes.len <= std.math.maxInt(u16)) {
        try writer.writeByte(0xfe);
        try writer.writeInt(u16, @intCast(bytes.len), .big);
    } else {
        try writer.writeByte(0xff);
        try writer.writeInt(u64, bytes.len, .big);
    }
    try writer.writeAll(&mask);
    for (bytes, 0..) |byte, i| try writer.writeByte(byte ^ mask[i % 4]);
    try writer.flush();
}

/// Receive one complete text message, including fragmented messages.
/// The caller owns the returned buffer. Limit applies to the whole message.
pub fn receiveText(self: *Self, alloc: Allocator, limit: usize) ![]u8 {
    const reader = &self.input.interface;
    var message: std.ArrayList(u8) = .empty;
    defer message.deinit(alloc);
    var fragmented = false;
    while (true) {
        const first = try reader.takeByte();
        const second = try reader.takeByte();
        if ((first & 0x70) != 0 or (second & 0x80) != 0) return error.InvalidWebSocketFrame;
        const final = (first & 0x80) != 0;
        const opcode = first & 0x0f;
        const length_code = second & 0x7f;
        if (opcode >= 8) {
            if (!final or length_code > 125) return error.InvalidWebSocketFrame;
            var control: [125]u8 = undefined;
            const payload = control[0..length_code];
            try reader.readSliceAll(payload);
            switch (opcode) {
                0x8 => {
                    if (payload.len == 1) return error.InvalidWebSocketFrame;
                    self.sendFrame(0x8, payload) catch {};
                    return error.WebSocketClosed;
                },
                0x9 => try self.sendFrame(0xa, payload),
                0xa => {},
                else => return error.InvalidWebSocketFrame,
            }
            continue;
        }
        if (opcode != @as(u8, if (fragmented) 0x0 else 0x1)) return error.InvalidWebSocketFrame;
        const len: u64 = switch (length_code) {
            126 => try reader.takeInt(u16, .big),
            127 => try reader.takeInt(u64, .big),
            else => length_code,
        };
        if ((length_code == 126 and len < 126) or
            (length_code == 127 and (len <= std.math.maxInt(u16) or len > std.math.maxInt(i64))))
            return error.InvalidWebSocketFrame;
        const start = message.items.len;
        if (len > limit - start) return error.WebSocketMessageTooLarge;
        try message.resize(alloc, start + @as(usize, @intCast(len)));
        try reader.readSliceAll(message.items[start..]);
        if (final) {
            if (!std.unicode.utf8ValidateSlice(message.items)) return error.InvalidWebSocketText;
            return message.toOwnedSlice(alloc);
        }
        fragmented = true;
    }
}
