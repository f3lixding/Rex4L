const std = @import("std");
const gio = @import("gio");
const glib = @import("glib");
const gtk = @import("gtk");
const gobject = @import("gobject");

const MainWindow = @import("application_window.zig").MainWindow;
pub const RunCtx = @import("RunCtx.zig");

const UiContext = struct {
    run_ctx: RunCtx,
    app: *gtk.Application,
    io: std.Io,
    alloc: std.mem.Allocator,
    updates: *PaneQueue,
};

pub const PaneUpdate = union(enum) {
    snapshot: []u8,
    output: []u8,
    failed: anyerror,

    pub fn deinit(self: PaneUpdate, alloc: std.mem.Allocator) void {
        switch (self) {
            .snapshot, .output => |bytes| alloc.free(bytes),
            .failed => {},
        }
    }
};

pub const PaneQueue = std.Io.Queue(PaneUpdate);

pub fn run(run_ctx: RunCtx, io: std.Io, alloc: std.mem.Allocator, updates: *PaneQueue) void {
    const app = gtk.Application.new("com.github.f3lixding.Rex4L", .{});
    defer app.unref();

    var ctx: UiContext = .{ .run_ctx = run_ctx, .app = app, .io = io, .alloc = alloc, .updates = updates };
    _ = gio.Application.signals.activate.connect(app, *UiContext, activate, &ctx, .{});

    // Drain the local handoff queue on the GTK thread; network I/O stays on the worker.
    const source = glib.timeoutAdd(16, drain, &ctx);
    defer _ = glib.Source.remove(source);

    _ = app.as(gio.Application).run(0, null);
}

fn activate(application: *gtk.Application, _: *UiContext) callconv(.c) void {
    if (application.getActiveWindow()) |window| {
        window.present();
        return;
    }
    const window = MainWindow.new(application);
    window.present();
}

fn drain(data: ?*anyopaque) callconv(.c) c_int {
    const ctx: *UiContext = @ptrCast(@alignCast(data orelse return 0));
    const active = ctx.app.getActiveWindow() orelse return 1;
    const window = gobject.ext.cast(MainWindow, active) orelse return 1;

    for (0..8) |_| {
        var item: [1]PaneUpdate = undefined;
        const count = ctx.updates.getUncancelable(ctx.io, &item, 0) catch break;
        if (count == 0) break;
        const update = item[0];
        defer update.deinit(ctx.alloc);
        switch (update) {
            .snapshot => |bytes| window.showTerminal(ctx.io, ctx.alloc, ctx.run_ctx, bytes) catch |err| window.showError(err),
            .output => |bytes| window.applyOutput(bytes) catch |err| window.showError(err),
            .failed => |err| window.showError(err),
        }
    }

    return 1;
}
