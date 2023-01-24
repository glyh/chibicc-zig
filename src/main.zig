const std = @import("std");
const clap = @import("clap");

pub fn main() !void {
    const params = comptime clap.parseParamsComptime(
        \\-n, --number <usize>   An option param
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    const stdout = std.io.getStdOut().writer();
    if (res.args.number) |n| {
        try stdout.print(
            \\  .global main
            \\main:
            \\  mov ${}, %rax
            \\  ret
            \\
        , .{n});
    }
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
