const std = @import("std");
const abs = std.math.absInt;
const expectEqual = std.testing.expectEqual;
const ArrayList = std.ArrayList;

pub const Vec3 = struct {
    x: i32,
    y: i32,
    z: i32,

    const Self = @This();

    pub fn v(x: i32, y: i32, z: i32) Self {
        return Self{
            .x = x,
            .y = y,
            .z = z,
        };
    }

    pub fn sumAbs(self: Self) !i32 {
        return (try abs(self.x)) +
            (try abs(self.y)) +
            (try abs(self.z));
    }

    pub fn add(a: *Self, b: Self) void {
        a.x += b.x;
        a.y += b.y;
        a.z += b.z;
    }

    pub fn parse(s: []const u8) !Self {
        var parser = Vec3Parser.init(s);
        return try parser.parse();
    }
};

pub const Vec3Parser = struct {
    buf: []const u8,
    pos: usize,

    const Self = @This();

    pub fn init(buf: []const u8) Self{
        return Self{ .buf = buf, .pos = 0, };
    }

    pub fn parse(self: *Self) !Vec3 {
        try self.acceptChar('<');

        try self.acceptChar('x');
        try self.acceptChar('=');
        const x = self.parseInt();
        try self.acceptChar(',');

        try self.acceptChar('y');
        try self.acceptChar('=');
        const y = self.parseInt();
        try self.acceptChar(',');

        try self.acceptChar('z');
        try self.acceptChar('=');
        const z = self.parseInt();

        try self.acceptChar('>');

        return Vec3.v(x, y, z);
    }

    fn acceptChar(self: *Self, ch: u8) !void {
        while (self.buf[self.pos] == ' ')
            self.pos += 1;

        if (self.buf[self.pos] == ch) {
            self.pos += 1;
        } else {
            return error.InvalidCharacter;
        }
    }

    fn parseInt(self: *Self) i32 {
        var result: i32 = 0;
        var negate = false;

        if (self.buf[self.pos] == '-') {
            negate = true;
            self.pos += 1;
        }

        while (self.buf[self.pos] >= '0' and self.buf[self.pos] <= '9') {
            result = result * 10 + @intCast(i32, self.buf[self.pos] - '0');
            self.pos += 1;
        }

        return if (negate) -result else result;
    }
};

test "parse Vec3" {
    expectEqual(Vec3.v(1, 2, 3), try Vec3.parse("<x=1, y=2, z=3>"));
    expectEqual(Vec3.v(5, 5, 5), try Vec3.parse("<x=5, y=5, z=5>"));
    expectEqual(Vec3.v(0, -1, 1), try Vec3.parse("<x=00, y=-1, z=01>"));
}

pub fn gravityChange(a: i32, b: i32) i32 {
    if (a > b) {
        return -1;
    } else if (a < b) {
        return 1;
    } else {
        return 0;
    }
}

pub const Moon = struct {
    pos: Vec3,
    vel: Vec3,

    const Self = @This();

    pub fn init(pos: Vec3) Self {
        return Self{ .pos = pos, .vel = Vec3.v(0, 0, 0) };
    }

    pub fn potEnergy(self: Self) !i32 {
        return try self.pos.sumAbs();
    }

    pub fn kinEnergy(self: Self) !i32 {
        return try self.vel.sumAbs();
    }

    pub fn applyGravity(self: *Self, other: Self) void {
        self.vel.x += gravityChange(self.pos.x, other.pos.x);
        self.vel.y += gravityChange(self.pos.y, other.pos.y);
        self.vel.z += gravityChange(self.pos.z, other.pos.z);
    }

    pub fn applyVelocity(self: *Self) void {
        self.pos.add(self.vel);
    }
};

pub fn simulateStep(moons: []Moon) void {
    // apply gravity
    for (moons) |*m, i| {
        for (moons) |n, j| {
            if (i == j)
                continue;

            m.applyGravity(n);
        }
    }

    // apply velocity
    for (moons) |*m| {
        m.applyVelocity();
    }
}

pub fn totalEnergy(moons: []Moon) !i32 {
    var result: i32 = 0;

    for (moons) |m| {
        result += (try m.potEnergy()) * (try m.kinEnergy());
    }

    return result;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var moons = ArrayList(Moon).init(allocator);
    const input_file = try std.fs.cwd().openFile("input12.txt", .{});
    var input_stream = input_file.inStream();

    while (input_stream.readUntilDelimiterAlloc(allocator, '\n', 1024)) |line| {
        defer allocator.free(line);
        try moons.append(Moon.init(try Vec3.parse(line)));
    } else |e| switch (e) {
        error.EndOfStream => {},
        else => return e,
    }

    // simulate steps
    const steps = 1000;
    var i: u32 = 0;
    while (i < steps) : (i += 1) {
        simulateStep(moons.toSlice());
    }

    // output total energy
    std.debug.warn("total energy after {} steps: {}\n", .{ steps, totalEnergy(moons.toSlice()) });
}
