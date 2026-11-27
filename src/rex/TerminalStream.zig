//! Initial terminal attachment and output for rex.data.terminal.v1.
//! Wire reference: https://github.com/shuv1337/rex-rune/blob/master/src/wire.rs
const std = @import("std");
const protocol = @import("protocol.zig");
const WebSocket = @import("Websocket.zig");
const Self = @This();
const Allocator = std.mem.Allocator;

const max_message = 16 * 1024 * 1024;
const max_snapshot = 256 * 1024 * 1024;
const max_metadata = 1024 * 1024;

socket: WebSocket,
nonce: u64,

/// Initialize in place: the WebSocket borrows its own buffers.
pub fn open(self: *Self, io: std.Io, alloc: Allocator, path: []const u8, ticket: []const u8) !void {
    var hello: [17]u8 = undefined;
    hello[0] = 1;
    const decoder = std.base64.url_safe_no_pad.Decoder;
    if (try decoder.calcSizeForSlice(ticket) != 16) return error.InvalidDataTicket;
    try decoder.decode(hello[1..], ticket);

    try self.socket.connect(io, path, protocol.data_path, protocol.terminal_subprotocol);
    errdefer self.close();
    try self.socket.sendBinary(&hello);
    const welcome = try self.socket.receiveBinary(alloc, 32);
    defer alloc.free(welcome);
    if (welcome.len != 0 and welcome[0] == 0x82) return error.DataTicketRejected;
    if (welcome.len != 32 or welcome[0] != 0x81) return error.InvalidDataWelcome;
    self.nonce = std.mem.readInt(u64, welcome[24..32], .little);
    if (self.nonce == 0) return error.InvalidDataWelcome;
}

pub fn close(self: *Self) void {
    self.socket.close();
}

pub fn receive(self: *Self, alloc: Allocator) ![]u8 {
    return self.socket.receiveBinary(alloc, max_message);
}

/// Returns the complete snapshot and any live bytes received with its end.
/// Both slices are backed by `bytes`, which the caller owns.
pub fn readSnapshot(self: *Self, alloc: Allocator) !Snapshot {
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(alloc);
    var scan: SnapshotScan = .{};
    while (true) {
        const chunk = try self.receive(alloc);
        defer alloc.free(chunk);
        if (chunk.len > max_snapshot + max_message - bytes.items.len) return error.SnapshotTooLarge;
        try bytes.appendSlice(alloc, chunk);
        if (try scan.scan(bytes.items)) |end| return .{ .bytes = try bytes.toOwnedSlice(alloc), .end = end };
        if (bytes.items.len >= max_snapshot) return error.SnapshotTooLarge;
    }
}

pub const Snapshot = struct { bytes: []u8, end: usize };

const SnapshotScan = struct {
    const envelope = "GHOSTSNP\x01\x00";
    const header_len = 10;
    const finish_tag = 6;
    offset: usize = 0,

    fn scan(self: *SnapshotScan, bytes: []const u8) !?usize {
        if (self.offset == 0) {
            if (bytes.len < envelope.len) return null;
            if (!std.mem.startsWith(u8, bytes, envelope)) return error.UnsupportedSnapshot;
            self.offset = envelope.len;
        }
        while (bytes.len - self.offset >= header_len) {
            const header = bytes[self.offset..][0..header_len];
            const len = std.mem.readInt(u32, header[2..6], .little);
            if (self.offset + header_len > max_snapshot or len > max_snapshot - self.offset - header_len)
                return error.SnapshotTooLarge;
            const end = self.offset + header_len + len;
            if (end > bytes.len) return null;
            self.offset = end;
            if (std.mem.readInt(u16, header[0..2], .little) == finish_tag) return end;
        }
        return null;
    }
};

/// Strip nonce-tagged Rex metadata while preserving ordinary VT escapes.
/// This read-only preview does not act on metadata (resize, theme, etc.).
pub const OutputFilter = struct {
    prefix: [32]u8 = undefined,
    prefix_len: usize = 0,
    matched: usize = 0,
    metadata_len: usize = 0,
    metadata_escape: bool = false,

    pub fn init(nonce: u64) OutputFilter {
        var self: OutputFilter = .{};
        self.prefix_len = (std.fmt.bufPrint(&self.prefix, "\x1b_rex1;{d};", .{nonce}) catch unreachable).len;
        return self;
    }

    pub fn filter(self: *OutputFilter, alloc: Allocator, bytes: []const u8) ![]u8 {
        var output: std.ArrayList(u8) = .empty;
        defer output.deinit(alloc);
        const prefix = self.prefix[0..self.prefix_len];
        for (bytes) |byte| {
            if (self.matched == prefix.len) {
                if (self.metadata_escape and byte == '\\') {
                    self.matched = 0;
                    self.metadata_len = 0;
                    self.metadata_escape = false;
                } else {
                    self.metadata_len += 1;
                    if (self.metadata_len > max_metadata) return error.DataMetadataTooLarge;
                    self.metadata_escape = byte == 0x1b;
                }
                continue;
            }
            if (byte == prefix[self.matched]) {
                self.matched += 1;
                continue;
            }
            try output.appendSlice(alloc, prefix[0..self.matched]);
            self.matched = 0;
            if (byte == prefix[0]) self.matched = 1 else try output.append(alloc, byte);
        }
        return output.toOwnedSlice(alloc);
    }
};

test "snapshot boundary can span messages and leave live output" {
    const bytes = "GHOSTSNP\x01\x00" ++ "\x06\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++ "live";
    var scan: SnapshotScan = .{};
    try std.testing.expectEqual(@as(?usize, null), try scan.scan(bytes[0..17]));
    const end = (try scan.scan(bytes)).?;
    try std.testing.expectEqualStrings("live", bytes[end..]);
}

test "strip only Rex metadata across message boundaries" {
    const alloc = std.testing.allocator;
    var filter = OutputFilter.init(42);
    const first = try filter.filter(alloc, "a\x1b_rex1;");
    defer alloc.free(first);
    try std.testing.expectEqualStrings("a", first);
    const second = try filter.filter(alloc, "42;{}\x1b");
    defer alloc.free(second);
    try std.testing.expectEqualStrings("", second);
    const third = try filter.filter(alloc, "\\b\x1b[32m");
    defer alloc.free(third);
    try std.testing.expectEqualStrings("b\x1b[32m", third);
}
