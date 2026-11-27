//! A GTK wrapper that displays terminal view
//! An intersection between ghostty-vt and GTK

const std = @import("std");
const cairo = @import("cairo");
const gtk = @import("gtk");
const vt = @import("ghostty-vt");
const Emulator = @import("../terminal/root.zig").Emulator;

const Self = @This();

area: *gtk.DrawingArea,
emulator: Emulator,
render_state: vt.RenderState = .empty,

pub fn init(io: std.Io, alloc: std.mem.Allocator) !*Self {
    const self = try alloc.create(Self);
    errdefer alloc.destroy(self);

    // TODO: expose the dimension
    const emulator = try Emulator.initPreview(io, alloc, .{ .cols = 80, .rows = 24 });
    self.* = .{ .area = gtk.DrawingArea.new(), .emulator = emulator };

    // GTK owns this callback data once registered and passes it back to draw.
    // The drawing area calls destroy when it releases the callback.
    self.area.setDrawFunc(draw, self, destroy);
    return self;
}

pub fn asWidget(self: *Self) *gtk.Widget {
    return self.area.as(gtk.Widget);
}

pub fn feed(self: *Self, bytes: []const u8) !void {
    self.emulator.feed(bytes);
    try self.emulator.updateRenderState(&self.render_state);
    self.asWidget().queueDraw();
}

fn draw(_: *gtk.DrawingArea, cr: *cairo.Context, _: c_int, _: c_int, data: ?*anyopaque) callconv(.c) void {
    const self: *Self = @ptrCast(@alignCast(data orelse return));

    cr.setSourceRgb(0.08, 0.08, 0.08);
    cr.paint();
    cr.setSourceRgb(0.90, 0.90, 0.90);
    cr.selectFontFace("monospace", .normal, .normal);
    cr.setFontSize(14);

    const rows = self.render_state.row_data.items(.cells);
    for (rows, 0..) |row, y| {
        for (0..row.len) |x| {
            const cp = row.get(x).raw.codepoint();
            if (cp == 0 or cp == ' ') continue;
            var text: [5]u8 = undefined;
            const len = std.unicode.utf8Encode(cp, text[0..4]) catch continue;
            text[len] = 0;
            cr.moveTo(8 + 9 * @as(f64, @floatFromInt(x)), 22 + 18 * @as(f64, @floatFromInt(y)));
            cr.showText(text[0..len :0].ptr);
        }
    }
}

fn destroy(data: ?*anyopaque) callconv(.c) void {
    const self: *Self = @ptrCast(@alignCast(data orelse return));
    const alloc = self.emulator.alloc;
    self.render_state.deinit(alloc);
    self.emulator.deinit();
    alloc.destroy(self);
}
