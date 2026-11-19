const std = @import("std");

const gtk = @import("gtk");
const gio = @import("gio");
const gdk = @import("gdk");
const cairo = @import("cairo");

const Point = struct {
    x: f64,
    y: f64,
};

// The backing image keeps the scribbles between GTK redraws
var surface: ?*cairo.Surface = null;

var drag_start: Point = .{ .x = 0, .y = 0 };
var previous: Point = .{ .x = 0, .y = 0 };

const brush_width: f64 = 6;

fn clearSurface() void {
    const image = surface orelse return;
    const cr = cairo.Context.create(image);
    defer cr.destroy();

    cr.setSourceRgb(1, 1, 1);
    cr.paint();
}

fn draw(_: *gtk.DrawingArea, cr: *cairo.Context, _: c_int, _: c_int, _: ?*anyopaque) callconv(.c) void {
    if (surface) |image| {
        cr.setSourceSurface(image, 0, 0);
        cr.paint();
    }
}

fn resize(_: *gtk.DrawingArea, width: c_int, height: c_int, _: ?*anyopaque) callconv(.c) void {
    if (width <= 0 or height <= 0) return;

    const old = surface;
    const old_width = if (old) |s| s.imageGetWidth() else 0;
    const old_height = if (old) |s| s.imageGetHeight() else 0;
    if (width <= old_width and height <= old_height) return;

    const backing = cairo.Surface.imageCreate(
        .argb32,
        @max(width, old_width),
        @max(height, old_height),
    );
    surface = backing;
    clearSurface();

    if (old) |s| {
        defer s.destroy();
        const cr = cairo.Context.create(backing);
        defer cr.destroy();

        cr.setSourceSurface(s, 0, 0);
        cr.paint();
    }
}

fn drawBrush(area: *gtk.Widget, x: f64, y: f64) void {
    const image = surface orelse return;
    const cr = cairo.Context.create(image);
    defer cr.destroy();

    cr.setSourceRgb(0, 0, 0);
    cr.rectangle(x - 3, y - 3, 6, 6);
    cr.fill();
    area.queueDraw();
}

fn dragBegin(_: *gtk.GestureDrag, x: f64, y: f64, area: *gtk.Widget) callconv(.c) void {
    drag_start = .{ .x = x, .y = y };
    previous = drag_start;

    const backing = surface orelse return;
    const cr = cairo.Context.create(backing);
    defer cr.destroy();

    // this draws the dot that starts the drag
    cr.setSourceRgb(0, 0, 0);
    cr.arc(x, y, brush_width / 2, 0, 2 * std.math.pi);
    cr.fill();
    area.queueDraw();
}

fn dragOffset(_: *gtk.GestureDrag, dx: f64, dy: f64, area: *gtk.Widget) callconv(.c) void {
    const current: Point = .{ .x = drag_start.x + dx, .y = drag_start.y + dy };
    const from = previous;
    previous = current;

    if (from.x == current.x and from.y == current.y) return;

    const backing = surface orelse return;
    const cr = cairo.Context.create(backing);
    defer cr.destroy();

    cr.setSourceRgb(0, 0, 0);
    cr.setLineWidth(brush_width);
    cr.setLineCap(.round);
    cr.moveTo(from.x, from.y);
    cr.lineTo(current.x, current.y);
    cr.stroke();
    area.queueDraw();
}

fn pressed(_: *gtk.GestureClick, _: c_int, _: f64, _: f64, area: *gtk.Widget) callconv(.c) void {
    clearSurface();
    area.queueDraw();
}

pub fn main(init: std.process.Init) !void {
    var buf: [1024]u8 = undefined;
    var stdout = std.Io.File.Writer.init(.stdout(), init.io, &buf);

    try stdout.interface.print("Rendering cairo", .{});
    try stdout.interface.flush();

    const app = gtk.Application.new(null, .{});
    defer {
        app.unref();
        if (surface) |image| image.destroy();
    }

    _ = gio.Application.signals.activate.connect(
        app,
        ?*anyopaque,
        struct {
            pub fn activate(_app: *gtk.Application, _: ?*anyopaque) callconv(.c) void {
                const window = gtk.ApplicationWindow.new(_app).as(gtk.Window);
                window.setTitle("cairo example");

                const frame = gtk.Frame.new(null);
                window.setChild(frame.as(gtk.Widget));

                const area = gtk.DrawingArea.new();
                const widget = area.as(gtk.Widget);
                widget.setSizeRequest(100, 100);
                frame.setChild(widget);

                area.setDrawFunc(draw, null, null);
                _ = gtk.DrawingArea.signals.resize.connect(area, ?*anyopaque, resize, null, .{ .after = true });

                const drag = gtk.GestureDrag.new();
                drag.as(gtk.GestureSingle).setButton(gdk.BUTTON_PRIMARY);
                widget.addController(drag.as(gtk.EventController));
                _ = gtk.GestureDrag.signals.drag_begin.connect(drag, *gtk.Widget, dragBegin, widget, .{});
                _ = gtk.GestureDrag.signals.drag_update.connect(drag, *gtk.Widget, dragOffset, widget, .{});
                _ = gtk.GestureDrag.signals.drag_end.connect(drag, *gtk.Widget, dragOffset, widget, .{});

                const click = gtk.GestureClick.new();
                click.as(gtk.GestureSingle).setButton(gdk.BUTTON_SECONDARY);
                widget.addController(click.as(gtk.EventController));
                _ = gtk.GestureClick.signals.pressed.connect(click, *gtk.Widget, pressed, widget, .{});

                window.present();
            }
        }.activate,
        null,
        .{},
    );

    _ = app.as(gio.Application).run(0, null);
}
