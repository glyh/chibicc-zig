const std = @import("std");
const clap = @import("clap");

const stdout = std.io.getStdOut().writer();
pub fn run(a: std.mem.Allocator, code: []const u8) !u32 {
    var tmp_d = std.testing.tmpDir(.{});
    defer tmp_d.cleanup();

    try tmp_d.dir.writeFile("tmp.s", code);
    _ = try std.ChildProcess.exec(.{
        .allocator = a,
        .argv = &[_][]const u8{ "gcc", "-static", "-o", "tmp", "tmp.s" },
        .cwd_dir = tmp_d.dir,
    });
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
pub fn compile(a: std.mem.Allocator, src: []const u8) ![]u8 {
    var generated_asm = std.ArrayList(u8).init(a);
    const writer = generated_asm.writer();

    try writer.writeAll(
        \\  .global main
        \\main:
        \\
    );
    var cur_int: i32 = 0;
    // var last_is_plus: ?bool = null;
    const Operator = enum { mov, add, sub };
    var last_op = Operator.mov;

    for (src) |char| {
        switch (char) {
            '0'...'9' => {
                cur_int = cur_int * 10 + char - '0';
            },
            '+', '-' => {
                switch (last_op) {
                    Operator.mov => {
                        try writer.print("  mov ${}, %rax\n", .{cur_int});
                    },
                    Operator.add => {
                        try writer.print("  add ${}, %rax\n", .{cur_int});
                    },
                    Operator.sub => {
                        try writer.print("  sub ${}, %rax\n", .{cur_int});
                    },
                }
                if (char == '+') { // add
                    last_op = Operator.add;
                } else { // sub
                    last_op = Operator.sub;
                }
                cur_int = 0;
            },
            else => continue,
        }
    }
    // TODO: read expression supporting +, -
    switch (last_op) {
        Operator.mov => {
            try writer.print("  mov ${}, %rax\n", .{cur_int});
        },
        Operator.add => {
            try writer.print("  add ${}, %rax\n", .{cur_int});
        },
        Operator.sub => {
            try writer.print("  sub ${}, %rax\n", .{cur_int});
        },
    }
    try writer.writeAll("  ret\n");
    const out = generated_asm.toOwnedSlice();
    return out;
}

pub fn compile_and_run(a: std.mem.Allocator, src: []const u8) !u32 {
    const generated_asm = try compile(a, src);
    defer a.free(generated_asm);
    return run(a, generated_asm);
}

pub fn main() !void {
    const params = comptime clap.parseParamsComptime(
        \\-s, --source <str>   Source code to compile
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
    if (res.args.source) |s| {
        const compile_out = try compile(a, s);
        defer a.free(compile_out);
        try stdout.writeAll(compile_out);
    }
}

test "one integer" {
    const testing = std.testing;
    try testing.expectEqual(try compile_and_run(testing.allocator, &"42".*), 42);
    try testing.expectEqual(try compile_and_run(testing.allocator, &"1".*), 1);
    try testing.expectEqual(try compile_and_run(testing.allocator, &"0".*), 0);
}

test "add/sub" {
    const testing = std.testing;
    try testing.expectEqual(try compile_and_run(testing.allocator, &"1+2+3".*), 6);
    try testing.expectEqual(try compile_and_run(testing.allocator, &"5+20-4".*), 21);
}
