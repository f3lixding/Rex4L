const gtk = @import("gtk");
const gobject = @import("gobject");

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
        return self;
    }

    pub fn present(self: *Self) void {
        gobject.ext.as(gtk.Window, self).present();
    }
};
