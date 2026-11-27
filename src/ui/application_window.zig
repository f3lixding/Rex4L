const std = @import("std");
const gtk = @import("gtk");
const gobject = @import("gobject");
const TerminalView = @import("TerminalView.zig");
const RunCtx = @import("RunCtx.zig");

pub const MainWindow = extern struct {
    const Self = @This();

    pub const Parent = gtk.ApplicationWindow;
    parent_instance: Parent,
    status: *gtk.Label,
    content: *gtk.Box,
    view: ?*TerminalView,

    pub const Class = extern struct {
        pub const Instance = Self;
        parent_class: Parent.Class,
    };

    pub const getGObjectType = gobject.ext.defineClass(Self, .{
        .name = "Rex4LMainWindow",
    });

    pub fn new(app: *gtk.Application) *Self {
        const self = gobject.ext.newInstance(Self, .{
            .application = app,
        });
        const window = gobject.ext.as(gtk.Window, self);
        window.setTitle("Rex4L");
        window.setDefaultSize(800, 600);

        self.view = null;
        self.status = gtk.Label.new("Connecting to Rex…");
        self.content = gtk.Box.new(.vertical, 0);
        self.content.append(self.status.as(gtk.Widget));
        window.setChild(self.content.as(gtk.Widget));
        return self;
    }

    pub fn showTerminal(self: *Self, io: std.Io, alloc: std.mem.Allocator, run_ctx: RunCtx, snapshot: []const u8) !void {
        if (self.view != null) return error.UnexpectedSecondSnapshot;
        const view = try TerminalView.initFromSnapshot(io, alloc, run_ctx, snapshot);
        view.asWidget().setVexpand(1);
        self.content.append(view.asWidget());
        self.view = view;
        self.status.as(gtk.Widget).setVisible(0);
        std.log.info("Rex terminal snapshot displayed", .{});
    }

    pub fn applyOutput(self: *Self, bytes: []const u8) !void {
        const view = self.view orelse return;
        try view.feed(bytes);
    }

    pub fn showError(self: *Self, err: anyerror) void {
        var buffer: [192]u8 = undefined;
        const message = std.fmt.bufPrintSentinel(&buffer, "Rex: {s}", .{@errorName(err)}, 0) catch "Rex connection failed";
        self.status.setText(message.ptr);
        self.status.as(gtk.Widget).setVisible(1);
        std.log.err("Rex terminal: {s}", .{@errorName(err)});
    }

    pub fn present(self: *Self) void {
        gobject.ext.as(gtk.Window, self).present();
    }
};
