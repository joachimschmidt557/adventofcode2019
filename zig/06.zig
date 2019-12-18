const std = @import("std");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;
const BufSet = std.BufSet;
const Buffer = std.Buffer;
const SliceInStream = std.io.SliceInStream;
const assert = std.debug.assert;

const OrbitMapParseError = error{
    FormatError,
};

const OrbitMap = struct {
    alloc: *Allocator,
    map: StringHashMap(BufSet),

    const Self = @This();

    pub fn init(allocator: *Allocator) Self {
        return Self{
            .alloc = allocator,
            .map = StringHashMap(BufSet).init(alloc),
        };
    }

    pub fn fromStream(allocator: *Allocator, stream: var) !Self {
        var map = StringHashMap(BufSet).init(allocator);
        var result = Self{
            .alloc = allocator,
            .map = map,
        };

        var buf = try Buffer.initSize(allocator, std.mem.page_size);
        defer buf.deinit();

        while (std.io.readLineFrom(stream, &buf)) |line| {
            var iter = std.mem.separate(line, ")");
            const orbitee = iter.next() orelse return error.FormatError;
            const orbiter = iter.next() orelse return error.FormatError;

            try result.insertOrbit(orbitee, orbiter);
        } else |e| switch (e) {
            error.EndOfStream => {},
            else => return e,
        }

        return result;
    }

    pub fn insertOrbit(self: *Self, orbitee: []const u8, orbiter: []const u8) !void {
        if (self.map.get(orbitee) == null) {
            _ = try self.map.put(orbitee, BufSet.init(self.alloc));
        }
        if (self.map.get(orbiter) == null) {
            _ = try self.map.put(orbiter, BufSet.init(self.alloc));
        }

        try self.map.get(orbitee).?.value.put(orbiter);
    }

    pub fn count(self: *Self, body: []const u8, orbits: usize) usize {
        var result: usize = orbits;

        if (self.map.get(body)) |kv| {
            var iter = kv.value.iterator();
            while (iter.next()) |set_kv| {
                result += self.count(set_kv.key, orbits + 1);
            }
        }

        return result;
    }
};

test "count orbits" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var mem_stream = SliceInStream.init(
        \\COM)B
        \\B)C
        \\C)D
        \\D)E
        \\E)F
        \\B)G
        \\G)H
        \\D)I
        \\E)J
        \\J)K
        \\K)L
        \\ 
    );
    const stream = &mem_stream.stream;
    var orbit_map = try OrbitMap.fromStream(allocator, stream);

    assert(orbit_map.count("COM", 0) == 42);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    const input_file = try std.fs.cwd().openFile("input06.txt", .{});
    const input_stream = &input_file.inStream().stream;

    var orbit_map = try OrbitMap.fromStream(allocator, input_stream);

    std.debug.warn("total orbits: {}\n", .{ orbit_map.count("COM", 0) });
}
