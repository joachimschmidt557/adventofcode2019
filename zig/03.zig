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

    pub fn flip(self: Self) Self {
        return Self{ .x = self.y, .y = self.x };
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
                else => {
                    std.debug.warn("{}\n", .{s});
                    return error.InvalidDirection;
                },
            },
            .len = try std.fmt.parseInt(i32, s[1..], 10),
        };
    }
};

const TwoDir = enum {
    Vertical,
    Horizontal,
};

const Line = struct {
    start: Point,
    end: Point,

    const Self = @This();

    pub const IntersectError = Allocator.Error;

    pub fn intersect(alloc: *Allocator, a: Self, b: Self) IntersectError![]Point {
        var result = ArrayList(Point).init(alloc);
        const dir_a = if (a.start.x == a.end.x) TwoDir.Vertical else TwoDir.Horizontal;
        const dir_b = if (b.start.x == b.end.x) TwoDir.Vertical else TwoDir.Horizontal;

        // Parallel
        if (dir_a == TwoDir.Vertical and dir_b == TwoDir.Vertical) {
            // They need to have same x, otherwise it's impossible
            // to have an intersection
            if (a.start.x == b.start.x) {
                const a_bot_p = if (a.start.y < a.end.y) a.start else a.end;
                const a_top_p = if (a.start.y < a.end.y) a.end else a.start;
                const b_bot_p = if (b.start.y < b.end.y) b.start else b.end;
                const b_top_p = if (b.start.y < b.end.y) b.end else b.start;

                if (a_top_p.y > b_top_p.y) {
                    const start_y = b_top_p.y;
                    const end_y = a_bot_p.y;

                    var i: i32 = start_y;
                    while (i >= end_y) : (i -= 1) {
                        try result.append(Point{ .x = a_bot_p.x, .y = i });
                    }
                } else {
                    const start_y = a_top_p.y;
                    const end_y = b_bot_p.y;

                    var i: i32 = start_y;
                    while (i >= end_y) : (i -= 1) {
                        try result.append(Point{ .x = a_bot_p.x, .y = i });
                    }
                }
            }
        } else if (dir_a == TwoDir.Horizontal and dir_b == TwoDir.Horizontal) {
            // Flip x and y
            try result.appendSlice(try Self.intersect(alloc, Self{ .start = a.start.flip(), .end = a.end.flip() }, Self{ .start = b.start.flip(), .end = b.end.flip() }));
        }
        // Crossed
        else if (dir_a == TwoDir.Vertical and dir_b == TwoDir.Horizontal) {
            const a_x = a.start.x;
            const b_y = b.start.y;

            // a_x needs to be in range of b.start.x to b.end.x
            const b_left_p = if (b.start.x < b.end.x) b.start else b.end;
            const b_right_p = if (b.start.x < b.end.x) b.end else b.start;
            if (a_x >= b_left_p.x and a_x <= b_right_p.x) {
                // b_y needs to be in range of a.start.y to a.end.y
                const a_bot_p = if (a.start.y < a.end.y) a.start else a.end;
                const a_top_p = if (a.start.y < a.end.y) a.end else a.start;
                if (b_y >= a_bot_p.y and b_y <= a_top_p.y) {
                    try result.append(Point{ .x = a_x, .y = b_y });
                }
            }
        } else {
            // Flip a and b
            try result.appendSlice(try Self.intersect(alloc, b, a));
        }

        // Remove (0,0) as valid intersections
        var i: usize = 0;
        while (i < result.items.len) {
            if (result.items[i].x == 0 and result.items[i].y == 0) {
                _ = result.orderedRemove(i);
            } else {
                i += 1;
            }
        }

        return result.toOwnedSlice();
    }
};

const Path = struct {
    lines: []Line,

    const Self = @This();

    pub fn fromInstructions(alloc: *Allocator, instr: []Instruction) !Self {
        var result = ArrayList(Line).init(alloc);
        var current = Point{ .x = 0, .y = 0 };

        for (instr) |i| {
            switch (i.dir) {
                .Right => {
                    const dest_x = current.x + i.len;
                    const dest = Point{ .x = dest_x, .y = current.y };

                    try result.append(Line{ .start = current, .end = dest });
                    current = dest;
                },
                .Left => {
                    const dest_x = current.x - i.len;
                    const dest = Point{ .x = dest_x, .y = current.y };

                    try result.append(Line{ .start = current, .end = dest });
                    current = dest;
                },
                .Down => {
                    const dest_y = current.y - i.len;
                    const dest = Point{ .x = current.x, .y = dest_y };

                    try result.append(Line{ .start = current, .end = dest });
                    current = dest;
                },
                .Up => {
                    const dest_y = current.y + i.len;
                    const dest = Point{ .x = current.x, .y = dest_y };

                    try result.append(Line{ .start = current, .end = dest });
                    current = dest;
                },
            }
        }

        return Path{ .lines = result.toOwnedSlice() };
    }

    pub fn intersections(alloc: *Allocator, a: Path, b: Path) ![]Point {
        var result = ArrayList(Point).init(alloc);
        for (a.lines) |l| {
            for (b.lines) |p| {
                const ints = try Line.intersect(alloc, l, p);
                try result.appendSlice(ints);
            }
        }
        return result.toOwnedSlice();
    }
};

test "test example path" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var instructions_1 = ArrayList(Instruction).init(allocator);
    try instructions_1.append(try Instruction.fromStr("R8"));
    try instructions_1.append(try Instruction.fromStr("U5"));
    try instructions_1.append(try Instruction.fromStr("L5"));
    try instructions_1.append(try Instruction.fromStr("D3"));
    const path_1 = try Path.fromInstructions(allocator, instructions_1.toOwnedSlice());

    var instructions_2 = ArrayList(Instruction).init(allocator);
    try instructions_2.append(try Instruction.fromStr("U7"));
    try instructions_2.append(try Instruction.fromStr("R6"));
    try instructions_2.append(try Instruction.fromStr("D4"));
    try instructions_2.append(try Instruction.fromStr("L4"));
    const path_2 = try Path.fromInstructions(allocator, instructions_2.toOwnedSlice());

    const ints = try Path.intersections(allocator, path_1, path_2);

    assert(path_1.lines.len == 4);
    assert(path_2.lines.len == 4);
    std.debug.warn("ints len {}\n", .{ints.len});
    std.debug.warn("ints 0 {}\n", .{ints[0]});
    std.debug.warn("ints 0 x {}\n", .{ints[0].x});
    std.debug.warn("ints 0 y {}\n", .{ints[0].y});
    assert(ints.len == 2);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var paths = ArrayList(Path).init(allocator);

    const input_file = try std.fs.cwd().openFile("input03.txt", .{});
    var input_stream = input_file.inStream();
    while (input_stream.readUntilDelimiterAlloc(allocator, '\n', 1024)) |line| {
        var instructions = ArrayList(Instruction).init(allocator);
        defer instructions.deinit();

        var iter = std.mem.split(line, ",");
        while (iter.next()) |itm| {
            try instructions.append(try Instruction.fromStr(itm));
        }

        try paths.append(try Path.fromInstructions(allocator, instructions.items));
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => return err,
    }

    const path_1 = paths.items[0];
    const path_2 = paths.items[1];

    const ints = try Path.intersections(allocator, path_1, path_2);

    std.debug.warn("Number of intersections: {}\n", .{ints.len});

    // Find closest intersection
    var min_dist: ?i32 = null;
    for (ints) |p| {
        if (min_dist) |min| {
            if ((try p.distance()) < min)
                min_dist = try p.distance();
        } else {
            min_dist = try p.distance();
        }
    }

    std.debug.warn("Minimum distance: {}\n", .{min_dist});
}
