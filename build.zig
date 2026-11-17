const std = @import("std");

pub fn build(b: *std.Build) void {
    var default_target: std.Target.Query = .{};
    // See flake for this ENV
    if (b.graph.environ_map.get("REX4L_DYNAMIC_LINKER")) |loader_path| {
        default_target.dynamic_linker = .init(loader_path);
    }
    const target = b.standardTargetOptions(.{
        .default_target = default_target,
    });

    const optimize = b.standardOptimizeOption(.{});
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

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    run_cmd.addPassthruArgs();

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
