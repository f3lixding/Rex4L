//! More or less the same as assigning signals.
//! But doing so allows custom type components that are dynamically spawned to
//! be done without going back to user code
const std = @import("std");
const gtk = @import("gtk");
const gio = @import("gio");
const gobject = @import("gobject");
const glib = @import("glib");

const ExampleApp = extern struct {
    pub const Parent = gtk.Application;
    parent_instance: Parent,

    pub const Class = extern struct {
        pub const Instance = ExampleApp;
        parent_class: Parent.Class,

        var parent: *Parent.Class = undefined;
    };

    // The Zig equivalent of G_DEFINE_TYPE for this subclass
    pub const getGObjectType = gobject.ext.defineClass(ExampleApp, .{
        .name = "ExampleApp",
        .classInit = &classInit,
        .parent_class = &Class.parent,
    });

    fn new() *ExampleApp {
        return gobject.ext.newInstance(ExampleApp, .{
            .@"application-id" = @as([*:0]const u8, "org.gtk.exampleapp"),
            .flags = gio.ApplicationFlags{ .handles_open = true },
        });
    }

    fn classInit(class: *Class) callconv(.c) void {
        gio.Application.virtual_methods.activate.implement(class, &activate);
        gio.Application.virtual_methods.open.implement(class, &open);
        gio.Application.virtual_methods.startup.implement(class, &startup);
    }

    fn activate(self: *ExampleApp) callconv(.c) void {
        const window = ExampleAppWindow.new(self);
        gobject.ext.as(gtk.Window, window).present();
    }

    fn startup(self: *ExampleApp) callconv(.c) void {
        const app = gobject.ext.as(gtk.Application, self);

        // We overrode startup, so explicitly run GTK's startup first
        // kind of like calling super
        gio.Application.virtual_methods.startup.call(Class.parent, app);

        const actions = app.as(gio.ActionMap);

        const preferences = gio.SimpleAction.new("preferences", null);
        defer preferences.unref();
        actions.addAction(preferences.as(gio.Action));

        const quit = gio.SimpleAction.new("exit-app", null);
        defer quit.unref();
        _ = gio.SimpleAction.signals.activate.connect(
            quit,
            *ExampleApp,
            onQuit,
            self,
            .{},
        );
        actions.addAction(quit.as(gio.Action));

        const shortcuts = [_:null]?[*:0]const u8{"<Ctrl>q"};
        app.setAccelsForAction("app.exit-app", &shortcuts);
    }

    fn onQuit(_: *gio.SimpleAction, _: ?*glib.Variant, self: *ExampleApp) callconv(.c) void {
        gobject.ext.as(gio.Application, self).quit();
    }

    fn open(
        self: *ExampleApp,
        files: [*]*gio.File,
        count: c_int,
        _: [*:0]const u8,
    ) callconv(.c) void {
        const app = gobject.ext.as(gtk.Application, self);

        const existing = if (app.getActiveWindow()) |window|
            gobject.ext.cast(ExampleAppWindow, window)
        else
            null;
        const window = existing orelse ExampleAppWindow.new(self);

        for (files[0..@intCast(count)]) |file| {
            window.openFile(file);
        }

        gobject.ext.as(gtk.Window, window).present();
    }
};

const ExampleAppWindow = extern struct {
    pub const Parent = gtk.ApplicationWindow;
    parent_instance: Parent,
    stack: *gtk.Stack,
    menu_button: *gtk.MenuButton,

    pub const Class = extern struct {
        pub const Instance = ExampleAppWindow;
        parent_class: Parent.Class,
    };

    pub const getGObjectType = gobject.ext.defineClass(ExampleAppWindow, .{
        .name = "ExampleAppWindow",
        .classInit = &classInit,
        .instanceInit = &instanceInit,
    });

    fn classInit(class: *Class) callconv(.c) void {
        const ui = @embedFile("window.ui");
        const bytes = glib.Bytes.newStatic(ui, ui.len);
        defer bytes.unref();

        // what the fuck is this
        const widget_class = gobject.ext.as(gtk.WidgetClass, class);
        widget_class.setTemplate(bytes);
        widget_class.bindTemplateChildFull("stack", 0, @offsetOf(ExampleAppWindow, "stack"));
        widget_class.bindTemplateChildFull("menu_button", 0, @offsetOf(ExampleAppWindow, "menu_button"));
    }

    fn instanceInit(self: *ExampleAppWindow, _: *Class) callconv(.c) void {
        gobject.ext.as(gtk.Widget, self).initTemplate();

        const ui = @embedFile("menu.ui");
        const builder = gtk.Builder.newFromString(ui, ui.len);
        defer builder.unref();

        const object = builder.getObject("menu") orelse @panic("Missing menu");
        const menu = gobject.ext.cast(gio.MenuModel, object) orelse @panic("Expected a menu model");
        self.menu_button.setMenuModel(menu);
    }

    fn new(app: *ExampleApp) *ExampleAppWindow {
        return gobject.ext.newInstance(ExampleAppWindow, .{
            .application = gobject.ext.as(gtk.Application, app),
        });
    }

    fn openFile(self: *ExampleAppWindow, file: *gio.File) void {
        const basename = file.getBasename() orelse return;
        defer glib.free(basename);

        var contents: [*]u8 = undefined;
        var length: usize = 0;
        if (file.loadContents(null, &contents, &length, null, null) == 0) {
            std.debug.print("Could not read {s}\n", .{basename});
            return;
        }
        defer glib.free(contents);

        if (length > std.math.maxInt(c_int) or glib.utf8ValidateLen(contents, length, null) == 0) {
            std.debug.print("Cannot displlay {s}: expected UTF-8 text that fits in the buffer\n", .{basename});
            return;
        }

        const view = gtk.TextView.new();
        view.setEditable(0);
        view.setCursorVisible(0);
        // GIO adds a zero terminator after the file contents.
        view.getBuffer().setText(contents[0..length :0].ptr, @intCast(length));

        const scrolled = gtk.ScrolledWindow.new();
        const page = scrolled.as(gtk.Widget);
        page.setHexpand(1);
        page.setVexpand(1);
        scrolled.setChild(view.as(gtk.Widget));

        // Use the basename as the visible title, not as a unique page name.
        _ = self.stack.addTitled(page, null, basename);
    }
};

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const argv = try arena.allocSentinel(?[*:0]u8, args.len, null);
    for (args, argv) |arg, *slot| {
        slot.* = (try arena.dupeSentinel(u8, arg, 0)).ptr;
    }

    const app = ExampleApp.new();
    defer gobject.ext.as(gobject.Object, app).unref();

    const status = gobject.ext.as(gio.Application, app).run(
        @intCast(args.len),
        @ptrCast(argv.ptr),
    );
    return @intCast(status);
}
