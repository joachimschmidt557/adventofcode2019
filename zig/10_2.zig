const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const math = std.math;
const approxEq = math.approxEq;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Buffer = std.Buffer;
const fixedBufferStream = std.io.fixedBufferStream;

pub const Pos = struct {
    x: isize,
    y: isize,

    const Self = @This();

    pub fn eq(a: Self, b: Self) bool {
        return a.x == b.x and a.y == b.y;
    }
};

pub fn pos(x: isize, y: isize) Pos {
    return Pos{ .x = x, .y = y };
}

fn absDiff(x: isize, y: isize) isize {
    return if (x > y) x - y else y - x;
}

fn diff(x: isize, y: isize) isize {
    return x - y;
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
        return approxEq(f64, divToFloat(origin_obstr_x, origin_dest_x), divToFloat(origin_obstr_y, origin_dest_y), epsilon);
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

fn rotatedAngle(vector: Pos) f64 {
    const angle = math.atan2(f64, @intToFloat(f64, -vector.y), @intToFloat(f64, vector.x));
    const angle_2pi = if (angle < 0.0) 2.0 * math.pi + angle else angle;

    const rotated = @mod((-angle_2pi + (math.pi / 2.0)), (2.0 * math.pi));

    return rotated;
}

test "rotatedAngle" {
    const epsilon = 0.00001;

    expect(approxEq(f64, rotatedAngle(Pos{ .x = 0, .y = -1 }), 0.0, epsilon));
    expect(approxEq(f64, rotatedAngle(Pos{ .x = 1, .y = 0 }), math.pi / 2.0, epsilon));
    expect(approxEq(f64, rotatedAngle(Pos{ .x = 0, .y = 1 }), math.pi, epsilon));
    expect(approxEq(f64, rotatedAngle(Pos{ .x = -1, .y = 0 }), 3.0 * math.pi / 2.0, epsilon));
}

fn lessThan(context: void, lhs: Pos, rhs: Pos) bool {
    const lhs_angle = rotatedAngle(lhs);
    const rhs_angle = rotatedAngle(rhs);

    return lhs_angle < rhs_angle;
}

pub const AsteroidMap = struct {
    asteroids: []Pos,

    const Self = @This();

    pub fn fromStream(stream: var, allocator: *Allocator) !Self {
        var asteroids = ArrayList(Pos).init(allocator);

        var y: isize = 0;
        while (stream.readUntilDelimiterAlloc(allocator, '\n', 1024)) |line| {
            for (line) |c, i| {
                switch (c) {
                    '#' => try asteroids.append(Pos{
                        .x = @intCast(isize, i),
                        .y = y,
                    }),
                    '.' => {},
                    else => {
                        std.debug.warn("invalid char: {}\n", .{c});
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
            .asteroids = asteroids.items,
        };
    }

    pub fn detectableAsteroids(alloc: *Allocator, asteroids: []Pos, position: Pos) ![]Pos {
        var result = ArrayList(Pos).init(alloc);

        for (asteroids) |x| {
            if (x.eq(position))
                continue;

            const obstructed = for (asteroids) |y| {
                if (y.eq(position) or y.eq(x))
                    continue;

                if (obstructs(position, x, y))
                    break true;
            } else false;

            if (!obstructed)
                try result.append(x);
        }

        return result.items;
    }

    pub fn countDetectableAsteroids(self: Self, position: Pos) usize {
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

    pub fn stationLocation(self: Self) ?Pos {
        var max_detectable: ?usize = null;
        var result: ?Pos = null;

        for (self.asteroids) |x| {
            const val = self.countDetectableAsteroids(x);
            if (max_detectable) |max| {
                if (val > max) {
                    max_detectable = val;
                    result = x;
                }
            } else {
                max_detectable = val;
                result = x;
            }
        }

        return result;
    }

    pub fn maxDetectableAsteroids(self: Self) ?usize {
        if (self.stationLocation()) |loc| {
            return self.countDetectableAsteroids(loc);
        } else {
            return null;
        }
    }

    pub fn initiateVaporization(self: Self, alloc: *Allocator, station: Pos) ![]Pos {
        var result = ArrayList(Pos).init(alloc);

        var remaining_asteroids = ArrayList(Pos).init(alloc);
        try remaining_asteroids.appendSlice(self.asteroids);
        defer remaining_asteroids.deinit();
        var i: usize = 0;
        while (i < remaining_asteroids.items.len) : (i += 1) {
            if (station.eq(remaining_asteroids.items[i])) {
                _ = remaining_asteroids.swapRemove(i);
            }
        }

        while (remaining_asteroids.items.len > 0) {
            var this_rotation = try Self.detectableAsteroids(alloc, remaining_asteroids.items, station);
            defer alloc.free(this_rotation);

            // Convert asteroids to vectors
            for (this_rotation) |*x| {
                x.x = x.x - station.x;
                x.y = x.y - station.y;
            }

            // Sort asteroids to remove
            std.sort.sort(Pos, this_rotation, {}, lessThan);

            // Convert vectors back to asteroids
            for (this_rotation) |*x| {
                x.x = x.x + station.x;
                x.y = x.y + station.y;
            }

            // Remove from remaining asteroids
            for (this_rotation) |x| {
                i = 0;
                while (i < remaining_asteroids.items.len) : (i += 1) {
                    if (x.eq(remaining_asteroids.items[i])) {
                        _ = remaining_asteroids.swapRemove(i);
                    }
                }
            }

            // Add to removed asteroids
            try result.appendSlice(this_rotation);
        }

        return result.items;
    }
};

test "read asteroid map" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var input_stream = fixedBufferStream(
        \\..#
        \\#.#
        \\...
        \\ 
    ).reader();

    const map = try AsteroidMap.fromStream(input_stream, allocator);
    expectEqual(@intCast(usize, 3), map.asteroids.len);
    expectEqual(map.asteroids[0], Pos{ .x = 2, .y = 0 });
    expectEqual(map.asteroids[1], Pos{ .x = 0, .y = 1 });
    expectEqual(map.asteroids[2], Pos{ .x = 2, .y = 1 });
}

test "count visible asteroids" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var input_stream = fixedBufferStream(
        \\.#..#
        \\.....
        \\#####
        \\....#
        \\...##
        \\ 
    ).reader();

    const map = try AsteroidMap.fromStream(input_stream, allocator);
    expectEqual(@intCast(usize, 10), map.asteroids.len);
    expectEqual(@intCast(usize, 7), map.countDetectableAsteroids(pos(1, 0)));
    expectEqual(@intCast(usize, 7), map.countDetectableAsteroids(pos(4, 0)));
    expectEqual(@intCast(usize, 6), map.countDetectableAsteroids(pos(0, 2)));
    expectEqual(@intCast(usize, 7), map.countDetectableAsteroids(pos(1, 2)));
    expectEqual(@intCast(usize, 7), map.countDetectableAsteroids(pos(2, 2)));
    expectEqual(@intCast(usize, 7), map.countDetectableAsteroids(pos(3, 2)));
    expectEqual(@intCast(usize, 5), map.countDetectableAsteroids(pos(4, 2)));
    expectEqual(@intCast(usize, 7), map.countDetectableAsteroids(pos(4, 3)));
    expectEqual(@intCast(usize, 7), map.countDetectableAsteroids(pos(4, 4)));
    expectEqual(@intCast(usize, 8), map.countDetectableAsteroids(pos(3, 4)));
}

test "max visible asteroids 1" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var input_stream = fixedBufferStream(
        \\.#..#
        \\.....
        \\#####
        \\....#
        \\...##
        \\ 
    ).reader();

    const map = try AsteroidMap.fromStream(input_stream, allocator);
    expectEqual(@intCast(usize, 10), map.asteroids.len);
    expectEqual(@intCast(usize, 8), map.maxDetectableAsteroids().?);
}

test "max visible asteroids 2" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var input_stream = fixedBufferStream(
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
    ).reader();

    const map = try AsteroidMap.fromStream(input_stream, allocator);
    expectEqual(@intCast(usize, 33), map.maxDetectableAsteroids().?);
}

test "max visible asteroids 3" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var input_stream = fixedBufferStream(
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
    ).reader();

    const map = try AsteroidMap.fromStream(input_stream, allocator);
    expectEqual(@intCast(usize, 35), map.maxDetectableAsteroids().?);
}

test "max visible asteroids 4" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var input_stream = fixedBufferStream(
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
    ).reader();

    const map = try AsteroidMap.fromStream(input_stream, allocator);
    expectEqual(@intCast(usize, 41), map.maxDetectableAsteroids().?);
}

test "max visible asteroids 5" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var input_stream = fixedBufferStream(
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
    ).reader();

    const map = try AsteroidMap.fromStream(input_stream, allocator);
    expectEqual(@intCast(usize, 210), map.maxDetectableAsteroids().?);
}

test "vaporize" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var input_stream = fixedBufferStream(
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
    ).reader();

    const map = try AsteroidMap.fromStream(input_stream, allocator);
    const vaporize_order = try map.initiateVaporization(allocator, Pos{ .x = 11, .y = 13 });

    expectEqual(Pos{ .x = 11, .y = 12 }, vaporize_order[0]);
    expectEqual(Pos{ .x = 12, .y = 1 }, vaporize_order[1]);
    expectEqual(Pos{ .x = 12, .y = 2 }, vaporize_order[2]);
    expectEqual(Pos{ .x = 12, .y = 8 }, vaporize_order[9]);
    expectEqual(Pos{ .x = 16, .y = 0 }, vaporize_order[19]);
    expectEqual(Pos{ .x = 16, .y = 9 }, vaporize_order[49]);
    expectEqual(Pos{ .x = 10, .y = 16 }, vaporize_order[99]);
    expectEqual(Pos{ .x = 9, .y = 6 }, vaporize_order[198]);
    expectEqual(Pos{ .x = 8, .y = 2 }, vaporize_order[199]);
    expectEqual(Pos{ .x = 10, .y = 9 }, vaporize_order[200]);
    expectEqual(Pos{ .x = 11, .y = 1 }, vaporize_order[298]);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    const input_file = try std.fs.cwd().openFile("input10.txt", .{});
    var input_stream = input_file.reader();

    const map = try AsteroidMap.fromStream(input_stream, allocator);
    const station_location = map.stationLocation() orelse return error.NoStationLocation;
    std.debug.warn("max detectable asteroids: {}\n", .{map.countDetectableAsteroids(station_location)});
    std.debug.warn("station location: {}\n", .{station_location});

    const vaporization_order = try map.initiateVaporization(allocator, station_location);
    std.debug.warn("200th asteroid: {}\n", .{vaporization_order[199]});
    std.debug.warn("soltion: {}\n", .{vaporization_order[199].x * 100 + vaporization_order[199].y});
}
