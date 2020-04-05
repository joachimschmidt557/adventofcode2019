const std = @import("std");
const assert = std.debug.assert;

const Module = struct {
    mass: u32,

    const Self = @This();

    pub fn requiredFuel(self: Self) u32 {
        const before_subtraction = self.mass / 3;
        if (before_subtraction <= 2) return 0;

        const m = before_subtraction - 2;
        return m + (Module{ .mass = m }).requiredFuel();
    }
};

test "tests from website" {
    assert((Module{ .mass = 12 }).requiredFuel() == 2);
    assert((Module{ .mass = 14 }).requiredFuel() == 2);
    assert((Module{ .mass = 1969 }).requiredFuel() == 966);
    assert((Module{ .mass = 100756 }).requiredFuel() == 50346);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    const stdin = std.io.getStdIn();
    var stdin_stream = stdin.inStream();
    var modules = std.ArrayList(Module).init(allocator);

    while (stdin_stream.readUntilDelimiterAlloc(allocator, '\n', 1024)) |line| {
        defer allocator.free(line);
        try modules.append(Module{ .mass = try std.fmt.parseInt(u32, line, 10) });
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => return err,
    }

    var sum: u32 = 0;
    for (modules.items) |mod| {
        sum += mod.requiredFuel();
    }
    std.debug.warn("{}\n", .{sum});
}
