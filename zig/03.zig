const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const abs = std.math.absInt;
const assert = std.debug.assert;

const Point = struct {
    x: i32,
    y: i32,

    const Self = @This();

    pub fn distance(self: Self) !i32 {
        return (try abs(self.x)) + (try abs(self.y));
    }

    pub fn eql(a: Self, b: Self) bool {
        return a.x == b.x and a.y == b.y;
    }
};

const Direction = enum {
    Up,
    Down,
    Left,
    Right,
};

const Instruction = struct {
    dir: Direction,
    len: i32,

    const Self = @This();

    pub fn fromStr(s: []const u8) !Self {
        return Self{
            .dir = switch (s[0]) {
                'U' => .Up,
                'D' => .Down,
                'L' => .Left,
                'R' => .Right,
                else => return error.InvalidDirection,
            },
            .len = try std.fmt.parseInt(i32, s[1..], 10),
        };
    }
};

const Path = struct {
    points: []Point,

    const Self = @This();

    pub fn fromInstructions(alloc: *Allocator, instr: []Instruction) !Self {
        var result = ArrayList(Point).init(alloc);
        var current = Point{ .x = 0, .y = 0 };

        for (instr) |i| {
            switch (i.dir) {
                .Right => {
                    const dest_x = current.x + i.len;

                    current.x += 1;
                    while (current.x <= dest_x) : (current.x += 1) {
                        try result.append(current);
                    }
                },
                .Left => {
                    const dest_x = current.x - i.len;

                    current.x -= 1;
                    while (current.x >= dest_x) : (current.x -= 1) {
                        try result.append(current);
                    }
                },
                .Down => {
                    const dest_y = current.y - i.len;

                    current.y -= 1;
                    while (current.y >= dest_y) : (current.y -= 1) {
                        try result.append(current);
                    }
                },
                .Up => {
                    const dest_y = current.y + i.len;

                    current.y += 1;
                    while (current.y <= dest_y) : (current.y += 1) {
                        try result.append(current);
                    }
                },
            }
        }

        return Path{ .points = result.toOwnedSlice() };
    }

    pub fn has(self: Self, p: Point) bool {
        for (self.points) |q| {
            if (p.eql(q)) return true;
        }
        return false;
    }

    pub fn intersections(a: Self, b: Self, alloc: *Allocator) ![]Point {
        var result = ArrayList(Point).init(alloc);
        for (a.points) |p| {
            if (b.has(p)) try result.append(p);
        }
        return result.toOwnedSlice();
    }
};

test "test example path" {
    var arena = std.heap.ArenaAllocator.init(std.heap.direct_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var instructions = ArrayList(Instruction).init(allocator);
    try instructions.append(try Instruction.fromStr("R8"));
    try instructions.append(try Instruction.fromStr("U5"));
    try instructions.append(try Instruction.fromStr("L5"));
    try instructions.append(try Instruction.fromStr("D3"));

    const path = try Path.fromInstructions(allocator, instructions.toOwnedSlice());
    assert(path.points.len == 8 + 5 + 5 + 3);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.direct_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var paths = ArrayList(Path).init(allocator);

    var buf = try std.Buffer.initSize(allocator, std.mem.page_size);
    while (std.io.readLine(&buf)) |line| {
        var instructions = ArrayList(Instruction).init(allocator);

        var iter = std.mem.separate(line, ",");
        while (iter.next()) |itm| {
            try instructions.append(try Instruction.fromStr(itm));
        }

        try paths.append(try Path.fromInstructions(allocator, instructions.toOwnedSlice()));
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => return err,
    }

    const path_1 = paths.at(0);
    const path_2 = paths.at(1);

    std.debug.warn("{}\n", path_1.points.len);
    std.debug.warn("{}\n", path_2.points.len);

    // Iterate over all points in a specific
    // Manhattan Distance
    const max_n = 1000;
    var result: ?Point = null;
    var n: i32 = 0;
    outer: while (n < max_n) : (n += 1) {
        var x: i32 = -n;
        while (x <= n) : (x += 1) {
            var p_1 = Point{ .x = x, .y = n - x };
            var p_2 = Point{ .x = x, .y = x - n };

            if (path_1.has(p_1) and path_2.has(p_1)) {
                result = p_1;
                break :outer;
            } else if (path_1.has(p_2) and path_2.has(p_2)) {
                result = p_2;
                break :outer;
            }
        }
    }
}
