const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const BufMap = std.BufMap;
const Buffer = std.Buffer;
const fixedBufferStream = std.io.fixedBufferStream;
const assert = std.debug.assert;

const OrbitMapParseError = error{FormatError};

const OrbitMap = struct {
    alloc: *Allocator,
    map: BufMap,

    const Self = @This();

    pub fn init(allocator: *Allocator) Self {
        return Self{
            .alloc = allocator,
            .map = BufMap.init(alloc),
        };
    }

    pub fn fromStream(allocator: *Allocator, stream: anytype) !Self {
        var map = BufMap.init(allocator);
        var result = Self{
            .alloc = allocator,
            .map = map,
        };

        while (stream.readUntilDelimiterAlloc(allocator, '\n', 1024)) |line| {
            var iter = std.mem.split(line, ")");
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
        try self.map.set(orbiter, orbitee);
    }

    pub fn orbitHierarchy(self: *Self, body: []const u8) !ArrayList([]const u8) {
        var result = ArrayList([]const u8).init(self.alloc);

        var currentBody = body;
        while (!std.mem.eql(u8, currentBody, "")) {
            try result.insert(0, currentBody);
            currentBody = self.map.get(currentBody) orelse "";
        }

        return result;
    }

    pub fn distance(self: *Self, orig: []const u8, dest: []const u8) !usize {
        const orig_hier = try self.orbitHierarchy(orig);
        const dest_hier = try self.orbitHierarchy(dest);

        // Find the common planet of both bodies
        var common_planet: usize = 0;
        for (orig_hier.items) |body, i| {
            if (std.mem.eql(u8, body, dest_hier.items[i])) {
                common_planet = i;
            } else {
                break;
            }
        }

        // Return the final distance
        const dist_orig_common = orig_hier.items.len - common_planet - 2;
        const dist_common_dest = dest_hier.items.len - common_planet - 2;
        return dist_orig_common + dist_common_dest;
    }
};

test "count orbits" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var mem_stream = fixedBufferStream(
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
        \\K)YOU
        \\I)SAN
        \\ 
    );
    const stream = mem_stream.reader();
    var orbit_map = try OrbitMap.fromStream(allocator, stream);

    assert((try orbit_map.distance("YOU", "SAN")) == 4);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    const input_file = try std.fs.cwd().openFile("input06.txt", .{});
    var input_stream = input_file.reader();

    var orbit_map = try OrbitMap.fromStream(allocator, input_stream);

    std.debug.warn("distance between you and santa: {}\n", .{try orbit_map.distance("YOU", "SAN")});
}
