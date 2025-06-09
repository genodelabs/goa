const std = @import("std");

pub fn build(b: *std.Build) void {
    const target: std.Target.Query = .{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
    };
    // compile base64.zig to base64.o
    const obj = b.addObject(.{
        .name = "base64",
        .root_source_file = b.path("base64.zig"),
        .target = b.resolveTargetQuery(target),
    });
    obj.bundle_compiler_rt = true;
    // pack base64.o in libziglib.a
    const ziglib = b.addStaticLibrary(.{
        .name = "ziglib",
        .link_libc = true,
        .target = b.resolveTargetQuery(target),
        .version = std.SemanticVersion.parse("1.0.0") catch unreachable,
    });
    ziglib.addObject(obj);
    // install libziglib.a to zig-out/lib/
    b.installArtifact(ziglib);
}
