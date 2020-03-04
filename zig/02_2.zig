const std = @import("std");
const assert = std.debug.assert;

const ExecError = error{ InvalidOpcode };

fn exec(intcode: []i32) !void {
    var pos: usize = 0;

    while (true) {
        switch (intcode[pos]) {
            99 => break,
            1 => {
                const pos_x = @intCast(usize, intcode[pos + 1]);
                const pos_y = @intCast(usize, intcode[pos + 2]);
                const pos_result = @intCast(usize, intcode[pos + 3]);
                intcode[pos_result] = intcode[pos_x] + intcode[pos_y];
                pos += 4;
            },
            2 => {
                const pos_x = @intCast(usize, intcode[pos + 1]);
                const pos_y = @intCast(usize, intcode[pos + 2]);
                const pos_result = @intCast(usize, intcode[pos + 3]);
                intcode[pos_result] = intcode[pos_x] * intcode[pos_y];
                pos += 4;
            },
            else => return error.InvalidOpcode,
        }
    }
}

test "test exec 1" {
    var intcode = [_]i32{ 1, 0, 0, 0, 99 };
    try exec(intcode[0..]);
    assert(intcode[0] == 2);
}

test "test exec 2" {
    var intcode = [_]i32{ 2, 3, 0, 3, 99 };
    try exec(intcode[0..]);
    assert(intcode[3] == 6);
}

test "test exec 3" {
    var intcode = [_]i32{ 2, 4, 4, 5, 99, 0 };
    try exec(intcode[0..]);
    assert(intcode[5] == 9801);
}


pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.direct_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    const stdin = std.io.getStdIn();
    var stdin_stream = stdin.inStream();
    var buf: [1024]u8 = undefined;
    var ints = std.ArrayList(i32).init(allocator);

    // read everything into an int arraylist
    while (try (&stdin_stream.stream).readUntilDelimiterOrEof(&buf, ',')) |item| {
        try ints.append(try std.fmt.parseInt(u8, item, 10));
    }

    // try combinations of noun and verb
    const max_search: i32 = 100;
    const desired_result: i32 = 19690720;
    var noun: i32 = 0;
    var verb: i32 = 0;

    outer: while (noun < max_search) : (noun += 1) {
        verb = 0;
        inner: while (verb < max_search) : (verb += 1) {
            const copy = try std.mem.dupe(allocator, i32, ints.toSliceConst());
            defer allocator.free(copy);

            copy[1] = noun;
            copy[2] = verb;

            try exec(copy);
            if (copy[0] == desired_result) break :outer;
        }
    }

    // output solution
    std.debug.warn("noun: {} verb: {}\n", .{noun, verb});
    std.debug.warn("100 * noun + verb = {}\n", .{100 * noun + verb});
}
