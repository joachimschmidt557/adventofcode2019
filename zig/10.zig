const std = @import("std");
const expectEqual = std.testing.expectEqual;
const approxEq = std.math.approxEq;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Buffer = std.Buffer;
const SliceInStream = std.io.SliceInStream;

pub const Pos = struct {
    x: usize,
    y: usize,

    const Self = @This();

    pub fn eq(a: Self, b: Self) bool {
        return a.x == b.x and a.y == b.y;
    }
};

pub fn pos(x: usize, y: usize) Pos {
    return Pos{ .x = x, .y = y };
}

fn absDiff(x: usize, y: usize) usize {
    return if (x > y) x - y else y - x;
}

fn diff(x: usize, y: usize) isize {
    return @intCast(isize, x) - @intCast(isize, y);
}

fn sign(x: isize) isize {
    if (x > 0) {
        return 1;
    } else if (x < 0) {
        return -1;
    } else {
        return 0;
    }
}

fn divToFloat(x: isize, y: isize) f64 {
    return @intToFloat(f64, x) / @intToFloat(f64, y);
}

pub fn obstructs(origin: Pos, dest: Pos, obstr: Pos) bool {
    // the possible obstruction must be nearer
    if (absDiff(origin.x, dest.x) < absDiff(origin.x, obstr.x))
        return false;
    if (absDiff(origin.y, dest.y) < absDiff(origin.y, obstr.y))
        return false;

    const origin_dest_x = diff(dest.x, origin.x);
    const origin_obstr_x = diff(obstr.x, origin.x);
    if (sign(origin_dest_x) != sign(origin_obstr_x))
        return false;

    const origin_dest_y = diff(dest.y, origin.y);
    const origin_obstr_y = diff(obstr.y, origin.y);
    if (sign(origin_dest_y) != sign(origin_obstr_y))
        return false;

    // the multiple of x and y must be the same
    if (origin_dest_x == 0) {
        return origin_obstr_x == 0;
    } else if (origin_dest_y == 0) {
        return origin_obstr_y == 0;
    } else {
        const epsilon = 0.000001;
        return approxEq(f64, divToFloat(origin_obstr_x, origin_dest_x),
                        divToFloat(origin_obstr_y, origin_dest_y), epsilon);
    }
}

test "obstruction" {
    expectEqual(true, obstructs(pos(0, 0), pos(4, 4), pos(2, 2)));
    expectEqual(true, obstructs(pos(0, 0), pos(6, 6), pos(2, 2)));
    expectEqual(true, obstructs(pos(0, 0), pos(6, 6), pos(4, 4)));
    expectEqual(false, obstructs(pos(0, 0), pos(2, 2), pos(4, 4)));
    expectEqual(false, obstructs(pos(2, 2), pos(0, 0), pos(4, 4)));
    expectEqual(false, obstructs(pos(2, 2), pos(4, 0), pos(4, 4)));
    expectEqual(true, obstructs(pos(0, 0), pos(2, 6), pos(1, 3)));
    expectEqual(false, obstructs(pos(0, 0), pos(2, 7), pos(1, 3)));
    expectEqual(true, obstructs(pos(0, 0), pos(0, 5), pos(0, 2)));
    expectEqual(true, obstructs(pos(0, 0), pos(5, 0), pos(2, 0)));
}

pub const AsteroidMap = struct {
    asteroids: []Pos,

    const Self = @This();

    pub fn fromStream(stream: var, allocator: *Allocator) !Self {
        var asteroids = ArrayList(Pos).init(allocator);

        var y: usize = 0;
        while (stream.readUntilDelimiterAlloc(allocator, '\n', 1024)) |line| {
            for (line) |c, i| {
                switch (c) {
                    '#' => try asteroids.append(Pos{
                        .x = i,
                        .y = y,
                    }),
                    '.' => {},
                    else => {
                        std.debug.warn("invalid char: {}\n", .{ c });
                        return error.InvalidMapCharacter;
                    },
                }
            }
            y += 1;
        } else |e| switch (e) {
            error.EndOfStream => {},
            else => return e,
        }

        return Self{
            .asteroids = asteroids.toSlice(),
        };
    }

    pub fn detectableAsteroids(self: Self, position: Pos) usize {
        var result: usize = 0;

        for (self.asteroids) |x| {
            if (x.eq(position))
                continue;

            const obstructed = for (self.asteroids) |y| {
                if (y.eq(position) or y.eq(x))
                    continue;

                if (obstructs(position, x, y))
                    break true;
            } else false;

            if (!obstructed)
                result += 1;
        }

        return result;
    }

    pub fn maxDetectableAsteroids(self: Self) ?usize {
        var result: ?usize = null;

        for (self.asteroids) |x| {
            const val = self.detectableAsteroids(x);
            if (result) |max| {
                if (val > max)
                    result = val;
            } else {
                result = val;
            }
        }

        return result;
    }
};

test "read asteroid map" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var input_stream = SliceInStream.init(
        \\..#
            \\#.#
            \\...
            \\ 
    );

    const map = try AsteroidMap.fromStream(&input_stream.stream, allocator);
    expectEqual(@intCast(usize, 3), map.asteroids.len);
    expectEqual(map.asteroids[0], Pos{ .x = 2, .y = 0 });
    expectEqual(map.asteroids[1], Pos{ .x = 0, .y = 1 });
    expectEqual(map.asteroids[2], Pos{ .x = 2, .y = 1 });
}

test "count visible asteroids" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var input_stream = SliceInStream.init(
        \\.#..#
            \\.....
            \\#####
            \\....#
            \\...##
            \\ 
    );

    const map = try AsteroidMap.fromStream(&input_stream.stream, allocator);
    expectEqual(@intCast(usize, 10), map.asteroids.len);
    expectEqual(@intCast(usize, 7), map.detectableAsteroids(pos(1, 0)));
    expectEqual(@intCast(usize, 7), map.detectableAsteroids(pos(4, 0)));
    expectEqual(@intCast(usize, 6), map.detectableAsteroids(pos(0, 2)));
    expectEqual(@intCast(usize, 7), map.detectableAsteroids(pos(1, 2)));
    expectEqual(@intCast(usize, 7), map.detectableAsteroids(pos(2, 2)));
    expectEqual(@intCast(usize, 7), map.detectableAsteroids(pos(3, 2)));
    expectEqual(@intCast(usize, 5), map.detectableAsteroids(pos(4, 2)));
    expectEqual(@intCast(usize, 7), map.detectableAsteroids(pos(4, 3)));
    expectEqual(@intCast(usize, 7), map.detectableAsteroids(pos(4, 4)));
    expectEqual(@intCast(usize, 8), map.detectableAsteroids(pos(3, 4)));
}

test "max visible asteroids 1" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var input_stream = SliceInStream.init(
        \\.#..#
            \\.....
            \\#####
            \\....#
            \\...##
            \\ 
    );

    const map = try AsteroidMap.fromStream(&input_stream.stream, allocator);
    expectEqual(@intCast(usize, 10), map.asteroids.len);
    expectEqual(@intCast(usize, 8), map.maxDetectableAsteroids().?);
}

test "max visible asteroids 2" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var input_stream = SliceInStream.init(
        \\......#.#.
            \\#..#.#....
            \\..#######.
            \\.#.#.###..
            \\.#..#.....
            \\..#....#.#
            \\#..#....#.
            \\.##.#..###
            \\##...#..#.
            \\.#....####
            \\ 
    );

    const map = try AsteroidMap.fromStream(&input_stream.stream, allocator);
    expectEqual(@intCast(usize, 33), map.maxDetectableAsteroids().?);
}

test "max visible asteroids 3" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var input_stream = SliceInStream.init(
        \\#.#...#.#.
            \\.###....#.
            \\.#....#...
            \\##.#.#.#.#
            \\....#.#.#.
            \\.##..###.#
            \\..#...##..
            \\..##....##
            \\......#...
            \\.####.###.
            \\ 
    );

    const map = try AsteroidMap.fromStream(&input_stream.stream, allocator);
    expectEqual(@intCast(usize, 35), map.maxDetectableAsteroids().?);
}

test "max visible asteroids 4" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var input_stream = SliceInStream.init(
        \\.#..#..###
            \\####.###.#
            \\....###.#.
            \\..###.##.#
            \\##.##.#.#.
            \\....###..#
            \\..#.#..#.#
            \\#..#.#.###
            \\.##...##.#
            \\.....#.#..
            \\ 
    );

    const map = try AsteroidMap.fromStream(&input_stream.stream, allocator);
    expectEqual(@intCast(usize, 41), map.maxDetectableAsteroids().?);
}

test "max visible asteroids 5" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var input_stream = SliceInStream.init(
        \\.#..##.###...#######
            \\##.############..##.
            \\.#.######.########.#
            \\.###.#######.####.#.
            \\#####.##.#.##.###.##
            \\..#####..#.#########
            \\####################
            \\#.####....###.#.#.##
            \\##.#################
            \\#####.##.###..####..
            \\..######..##.#######
            \\####.##.####...##..#
            \\.#####..#.######.###
            \\##...#.##########...
            \\#.##########.#######
            \\.####.#.###.###.#.##
            \\....##.##.###..#####
            \\.#.#.###########.###
            \\#.#.#.#####.####.###
            \\###.##.####.##.#..##
            \\ 
    );

    const map = try AsteroidMap.fromStream(&input_stream.stream, allocator);
    expectEqual(@intCast(usize, 210), map.maxDetectableAsteroids().?);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    const input_file = try std.fs.cwd().openFile("input10.txt", .{});
    var input_stream = input_file.inStream();

    const map = try AsteroidMap.fromStream(&input_stream.stream, allocator);
    const max = map.maxDetectableAsteroids().?;
    std.debug.warn("max detectable asteroids: {}\n", .{ max });
}
