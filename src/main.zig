const std = @import("std");
const clap = @import("clap");

const stdout = std.io.getStdOut().writer();
pub fn run(a: std.mem.Allocator, code: []u8) !u32 {
    var tmp_d = std.testing.tmpDir(.{});
    defer tmp_d.cleanup();

    try stdout.print(
        \\Compiled code:
        \\-------------
        \\{s}
        \\-------------
    , .{code});

    try stdout.print("Writing compiled code to {}", .{tmp_d.dir});
    try tmp_d.dir.writeFile("tmp.s", code);
    var link_result = try std.ChildProcess.exec(.{
        .allocator = a,
        .argv = &[_][]const u8{ "gcc", "-static", "-o", "tmp", "tmp.s" },
        .cwd_dir = tmp_d.dir,
    });
    try stdout.print("Link result: {s}\n{s}\n", .{ link_result.stdout, link_result.stderr });
    var run_result = try std.ChildProcess.exec(.{
        .allocator = a,
        .argv = &[_][]const u8{"./tmp"},
        .cwd_dir = tmp_d.dir,
        .expand_arg0 = .expand,
    });
    defer a.free(run_result.stderr);
    defer a.free(run_result.stdout);
    switch (run_result.term) {
        .Exited => |exit_code| return exit_code,
        else => unreachable,
    }
}

// returns file path
pub fn compile(a: std.mem.Allocator, n: i32) ![]u8 {
    return std.fmt.allocPrint(a,
        \\  .global main
        \\main:
        \\  mov ${}, %rax
        \\  ret
        \\
    , .{n});
}

pub fn compile_and_run(a: std.mem.Allocator, n: i32) !u32 {
    const code = try compile(a, n);
    defer a.free(code);
    return run(a, code);
}

pub fn main() !void {
    const params = comptime clap.parseParamsComptime(
        \\-n, --number <i32>   An option param
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!gpa.deinit());
    const a = gpa.allocator();
    if (res.args.number) |n| {
        const compile_out = try compile(a, n);
        defer a.free(compile_out);

        try stdout.writeAll(compile_out);
    }
}

test "one integer" {
    const testing = std.testing;
    try testing.expectEqual(try compile_and_run(testing.allocator, 42), 42);
    try testing.expectEqual(try compile_and_run(testing.allocator, 1), 1);
    try testing.expectEqual(try compile_and_run(testing.allocator, 0), 0);
}
