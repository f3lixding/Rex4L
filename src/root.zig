const std = @import("std");
const ui = @import("ui/root.zig");
const terminal = @import("terminal/root.zig");
const rex = @import("rex/root.zig");

const RunCtx = ui.RunCtx;

const App = struct {
    io: std.Io,
    alloc: std.mem.Allocator,
    client: *rex.Client,
    socket_path: []const u8,

    // These commands will queue work once the Rex worker is in place.
    const ui_commands: ui.RunCtx.VTable = .{
        .open_pane = paneCommandNotReady,
        .send_key = sendKeyNotReady,
        .close_pane_view = paneCommandNotReady,
    };

    pub fn init(io: std.Io, alloc: std.mem.Allocator, socket_path: []const u8) !App {
        const client = try rex.Client.init(alloc);

        return .{
            .io = io,
            .alloc = alloc,
            .client = client,
            .socket_path = socket_path,
        };
    }

    pub fn deinit(self: App) void {
        self.client.deinit();
    }

    pub fn run(self: *App) !void {
        var storage: [4]ui.PaneUpdate = undefined;
        var updates = ui.PaneQueue.init(&storage);

        var worker = try self.io.concurrent(streamPane, .{ self, &updates });
        defer {
            updates.close(self.io);
            worker.cancel(self.io);
            while (updates.getOneUncancelable(self.io)) |item| {
                item.deinit(self.alloc);
            } else |_| {}
        }

        ui.run(.{ .ptr = self, .vtable = &ui_commands }, self.io, self.alloc, &updates);
    }

    fn streamPane(self: *App, updates: *ui.PaneQueue) void {
        self.attachPane(updates) catch |err| {
            if (err == error.Canceled or err == error.Closed) return;
            updates.putOne(self.io, .{ .failed = err }) catch {};
        };
    }

    fn attachPane(self: *App, updates: *ui.PaneQueue) !void {
        const protocol = rex.protocol;
        try self.client.open(self.io, self.socket_path);

        const list_reply = try self.client.call(protocol.SessionList, .{});
        defer list_reply.deinit();

        const sessions = try list_reply.value.parseResult(protocol.SessionList, self.alloc);
        defer sessions.deinit();

        // For prototype only
        // TODO: replace this with targetted pane attachment
        var chosen: ?[]const u8 = null;
        for (sessions.value.sessions orelse &.{}) |session| {
            if (!std.mem.eql(u8, session.label, "Rex4L")) continue;
            if (chosen != null) return error.AmbiguousRex4LSession;
            chosen = session.session_id;
        }

        const session_id = chosen orelse return error.Rex4LSessionNotFound;
        const attach_reply = try self.client.call(protocol.SessionAttach, .{ .session_id = session_id });
        defer attach_reply.deinit();

        const attached = try attach_reply.value.parseResult(protocol.SessionAttach, self.alloc);
        defer attached.deinit();

        const block_id = try focusedTerminal(attached.value.view);
        const data_reply = try self.client.call(protocol.DataConnect, .{ .session_id = session_id, .block_id = block_id });
        defer data_reply.deinit();
        const ticket = try data_reply.value.parseResult(protocol.DataConnect, self.alloc);
        defer ticket.deinit();

        var stream: rex.TerminalStream = undefined;
        try stream.open(self.io, self.alloc, self.socket_path, ticket.value.ticket);
        defer stream.close();
        var filter = rex.TerminalStream.OutputFilter.init(stream.nonce);
        {
            const initial = try stream.readSnapshot(self.alloc);
            defer self.alloc.free(initial.bytes);
            const snapshot = try self.alloc.dupe(u8, initial.bytes[0..initial.end]);
            updates.putOne(self.io, .{ .snapshot = snapshot }) catch |err| {
                self.alloc.free(snapshot);
                return err;
            };
            try self.queueOutput(updates, &filter, initial.bytes[initial.end..]);
        }

        while (true) {
            const chunk = try stream.receive(self.alloc);
            defer self.alloc.free(chunk);
            try self.queueOutput(updates, &filter, chunk);
        }
    }

    fn queueOutput(self: *App, updates: *ui.PaneQueue, filter: *rex.TerminalStream.OutputFilter, bytes: []const u8) !void {
        const output = try filter.filter(self.alloc, bytes);
        errdefer self.alloc.free(output);

        if (output.len == 0) {
            self.alloc.free(output);
            return;
        }

        try updates.putOne(self.io, .{ .output = output });
    }

    fn focusedTerminal(view: rex.protocol.View) ![]const u8 {
        const active = view.active_window_id orelse return error.NoActiveWindow;
        for (view.windows orelse &.{}) |window| {
            if (!std.mem.eql(u8, window.window_id orelse continue, active)) continue;
            const focused = window.focused_block_id orelse return error.NoFocusedBlock;
            for (window.layers orelse &.{}) |layer| {
                for (layer.blocks orelse &.{}) |block| {
                    if (!std.mem.eql(u8, block.block_id orelse continue, focused)) continue;
                    if (!std.mem.eql(u8, block.creator_name, "com.superlogical.terminal")) return error.FocusedBlockIsNotTerminal;
                    return focused;
                }
            }
            return error.FocusedBlockNotFound;
        }
        return error.NoActiveWindow;
    }

    fn paneCommandNotReady(_: *anyopaque, _: []const u8, _: []const u8) ui.RunCtx.RunCtxError!void {
        return error.NotReady;
    }

    fn sendKeyNotReady(_: *anyopaque, _: []const u8, _: []const u8, _: rex.protocol.KeyEvent) ui.RunCtx.RunCtxError!void {
        return error.NotReady;
    }
};

pub fn run(io: std.Io, alloc: std.mem.Allocator, socket_path: []const u8) !void {
    var app: App = try .init(io, alloc, socket_path);
    defer app.deinit();

    try app.run();
}

test {
    _ = terminal.Emulator;
    _ = rex;
}
