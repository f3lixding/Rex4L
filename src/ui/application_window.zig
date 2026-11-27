const std = @import("std");
const gtk = @import("gtk");
const gobject = @import("gobject");
const vt = @import("ghostty-vt");
const TerminalView = @import("TerminalView.zig");

pub const MainWindow = extern struct {
    const Self = @This();

    pub const Parent = gtk.ApplicationWindow;
    parent_instance: Parent,

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

        if (TerminalView.init(vt.TinyIo.init.io(), std.heap.page_allocator)) |view| {
            window.setChild(view.asWidget());
            view.feed("Rex4L terminal preview\r\nWaiting for a Rex connection.\r\n") catch |err| {
                std.log.err("could not render terminal preview: {t}", .{err});
            };
        } else |err| {
            std.log.err("could not create terminal view: {t}", .{err});
        }
        return self;
    }

    pub fn present(self: *Self) void {
        gobject.ext.as(gtk.Window, self).present();
    }
};
