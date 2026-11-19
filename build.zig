const std = @import("std");

pub fn build(b: *std.Build) void {
    const run_target = b.option([]const u8, "run-target", "target to run");

    var default_target: std.Target.Query = .{};
    // See flake for this ENV
    if (b.graph.environ_map.get("REX4L_DYNAMIC_LINKER")) |loader_path| {
        default_target.dynamic_linker = .init(loader_path);
    }
    const target = b.standardTargetOptions(.{
        .default_target = default_target,
    });

    const optimize = b.standardOptimizeOption(.{});

    const tutorial_run = registerTutorialTargets(
        b,
        run_target,
        .{ .target = target, .optimize = optimize },
    ) catch |err| std.debug.panic("could not register GTK tutorials: {s}", .{@errorName(err)});

    const mod = b.addModule("Rex4L", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });
    addGTKToModule(b, mod, .{ .target = target, .optimize = optimize });

    const exe = b.addExecutable(.{
        .name = "Rex4L",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "Rex4L", .module = mod },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app or the selected GTK tutorial");
    if (tutorial_run) |step| {
        run_step.dependOn(step);
    } else {
        const run_cmd = b.addRunArtifact(exe);
        run_step.dependOn(&run_cmd.step);
        run_cmd.step.dependOn(b.getInstallStep());
        run_cmd.addPassthruArgs();
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}

fn addGTKToModule(b: *std.Build, mod: *std.Build.Module, opts: anytype) void {
    const gobject = b.dependency("gobject", .{
        .target = opts.target,
        .optimize = opts.optimize,
    });
    const gtk_imports = .{
        .{ "gtk", "gtk4" },
        .{ "gdk", "gdk4" },
        .{ "glib", "glib2" },
        .{ "gio", "gio2" },
        .{ "gobject", "gobject2" },
    };
    inline for (gtk_imports) |import| {
        const name, const module = import;
        mod.addImport(name, gobject.module(module));
    }
}

fn registerTutorialTargets(
    b: *std.Build,
    run_target: ?[]const u8,
    opts: struct { optimize: std.builtin.Optimize, target: std.Build.ResolvedTarget },
) !?*std.Build.Step {
    const io = b.graph.io;
    const tutorials_dir = "src/gtk_tutorials";
    const dir = try b.root.openDir(io, tutorials_dir, .{ .iterate = true });
    defer dir.close(io);

    var walker = try dir.walk(b.allocator);
    defer walker.deinit();

    var selected: ?*std.Build.Step = null;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".zig")) continue;

        const name = b.dupe(std.fs.path.stem(entry.basename));
        const exe = b.addExecutable(.{
            .name = name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(b.pathJoin(&.{ tutorials_dir, entry.path })),
                .target = opts.target,
                .optimize = opts.optimize,
            }),
        });
        addGTKToModule(b, exe.root_module, .{ .target = opts.target, .optimize = opts.optimize });

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.addPassthruArgs();
        const step = b.step(b.fmt("run-{s}", .{name}), b.fmt("Run the {s} GTK tutorial", .{name}));
        step.dependOn(&run_cmd.step);

        if (run_target) |requested| {
            if (std.mem.eql(u8, requested, name)) selected = step;
        }
    }

    return selected;
}
