const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;
const fixedBufferStream = std.io.fixedBufferStream;

const ChemicalQuantity = struct {
    chem: []const u8,
    quant: usize,

    const Self = @This();

    pub fn mult(self: Self, x: usize) Self {
        return Self{
            .chem = self.chem,
            .quant = self.quant * x,
        };
    }

    pub fn print(self: Self) void {
        std.debug.warn("{} {}", .{ self.quant, self.chem });
    }
};

const one_fuel = ChemicalQuantity{ .chem = "FUEL", .quant = 1 };

const Reaction = struct {
    alloc: *Allocator,
    text: []const u8,
    inputs: []ChemicalQuantity,
    output: ChemicalQuantity,

    const Self = @This();

    pub fn fromStr(alloc: *Allocator, str: []const u8) !?Self {
        return try ReactionParser.init(alloc, str).parseReaction();
    }

    pub fn deinit(self: *Self) void {
        // std.debug.warn("{}\n", .{ self.output.chem });
        self.alloc.free(self.text);
        self.alloc.free(self.inputs);
    }

    pub fn print(self: Self) void {
        for (self.inputs) |x| {
            x.print();
            std.debug.warn(", ", .{});
        }
        std.debug.warn(" => ", .{});
        self.output.print();
        std.debug.warn("\n", .{});
    }
};

const ReactionParser = struct {
    alloc: *Allocator,
    str: []const u8,
    pos: usize,

    const Self = @This();

    pub fn init(alloc: *Allocator, str: []const u8) Self {
        return Self{
            .alloc = alloc,
            .str = str,
            .pos = 0,
        };
    }

    pub fn parseReaction(self: *Self) !?Reaction {
        var inputs = ArrayList(ChemicalQuantity).init(self.alloc);

        try inputs.append(self.parseChemicalQuantity() orelse return null);
        self.skipWs();
        while ((self.peek() orelse return null) == ',') {
            _ = self.pop(); // consume the comma
            self.skipWs();
            // std.debug.warn("appending", .{});
            try inputs.append(self.parseChemicalQuantity() orelse return null);
            self.skipWs();
        }

        self.skipWs();
        if (!self.acceptChar('=')) return null;
        if (!self.acceptChar('>')) return null;
        self.skipWs();

        const output = self.parseChemicalQuantity() orelse return null;

        return Reaction{
            .alloc = self.alloc,
            .text = self.str,
            .inputs = inputs.toOwnedSlice(),
            .output = output,
        };
    }

    fn parseChemicalQuantity(self: *Self) ?ChemicalQuantity {
        const quant = self.parseUsize() orelse return null;
        self.skipWs();
        const name = self.parseAlpha() orelse return null;
        self.skipWs();

        return ChemicalQuantity{
            .quant = quant,
            .chem = name,
        };
    }

    fn parseUsize(self: *Self) ?usize {
        var result: usize = 0;
        while (self.peek()) |c| {
            if (c < '0' or '9' < c) break;
            result = result * 10 + (self.pop().? - '0');
        }
        return result;
    }

    fn parseAlpha(self: *Self) ?[]const u8 {
        const old_pos = self.pos;
        while (self.peek()) |c| {
            if (c < 'A' or 'Z' < c) break;
            _ = self.pop();
        }
        return self.str[old_pos..self.pos];
    }

    fn peek(self: Self) ?u8 {
        if (self.pos < self.str.len) {
            return self.str[self.pos];
        } else {
            return null;
        }
    }

    fn pop(self: *Self) ?u8 {
        defer if (self.pos < self.str.len) { self.pos += 1; };
        return self.peek();
    }

    fn skipWs(self: *Self) void {
        while ((self.peek() orelse return) == ' ') _ = self.pop();
    }

    fn acceptChar(self: *Self, char: u8) bool {
        if (self.peek()) |c| {
            if (c == char) _ = self.pop();
            return c == char;
        } else {
            return false;
        }
    }
};

test "parse reaction" {
    const allocator = std.testing.allocator;

    const str = try std.mem.dupe(allocator, u8, "10 ORE => 20 ABC");
    const expected = Reaction{
        .alloc = allocator,
        .text = str,
        .inputs = &[_]ChemicalQuantity{
            ChemicalQuantity{ .chem = str[3..6], .quant = 10 },
        },
        .output = ChemicalQuantity{ .chem = str[13..16], .quant = 20 },
    };
    var actual = (try Reaction.fromStr(allocator, str)).?;
    defer actual.deinit();

    expectEqual(expected.output, actual.output);
    expectEqualSlices(ChemicalQuantity, expected.inputs, actual.inputs);
}

fn reactionsFromStream(alloc: *Allocator, stream: var) ![]Reaction {
    var result = ArrayList(Reaction).init(alloc);

    while (stream.readUntilDelimiterAlloc(alloc, '\n', 1024)) |line| {
        // std.debug.warn("parsing: {}\n", .{ line });
        if (try Reaction.fromStr(alloc, line)) |r| {
            try result.append(r);
        } else {
            std.debug.warn("Could not parse: {}\n", .{ line });
        }
    } else |e| switch (e) {
        error.EndOfStream => {},
        else => return e,
    }

    return result.toOwnedSlice();
}

test "parse example reactions" {
    const allocator = std.testing.allocator;
    var stream = fixedBufferStream(
        \\9 ORE => 2 A
            \\8 ORE => 3 B
            \\7 ORE => 5 C
            \\3 A, 4 B => 1 AB
            \\5 B, 7 C => 1 BC
            \\4 C, 1 A => 1 CA
            \\2 AB, 3 BC, 4 CA => 1 FUEL
            \\ 
    ).reader();

    const reactions = try reactionsFromStream(allocator, stream);
    defer allocator.free(reactions);
    defer for (reactions) |*x| x.deinit();

    for (reactions) |x| {
        x.print();
    }
}

const UniQueue = struct {
    internal: ArrayList(ChemicalQuantity),

    const Self = @This();

    pub fn init(alloc: *Allocator) Self {
        return Self{
            .internal = ArrayList(ChemicalQuantity).init(alloc),
        };
    }

    pub fn deinit(self: *Self) void {
        self.internal.deinit();
    }

    pub fn onlyOre(self: Self) bool {
        return self.internal.items.len == 1 and std.mem.eql(u8, "ORE", self.internal.items[0].chem);
    }

    pub fn pop(self: *Self) ChemicalQuantity {
        return self.internal.orderedRemove(0);
    }

    pub fn push(self: *Self, c: ChemicalQuantity) !void {
        for (self.internal.items) |*x| {
            if (std.mem.eql(u8, x.chem, c.chem)) {
                x.quant += c.quant;
                return;
            }
        }
        try self.internal.append(c);
    }
};

fn requiredOre(alloc: *Allocator, reactions: []const Reaction) !usize {
    var queue = UniQueue.init(alloc);
    defer queue.deinit();
    try queue.push(one_fuel);

    while (!queue.onlyOre()) {
        const c = queue.pop();

        for (reactions) |r| {
            if (std.mem.eql(u8, c.chem, r.output.chem)) {
                const multiplier = c.quant / r.output.quant + (if (c.quant % r.output.quant > 0) @as(usize, 1) else 0);

                for (r.inputs) |inp| {
                    try queue.push(inp.mult(multiplier));
                }

                break;
            }
        }
    }

    return queue.internal.items[0].quant;
}

test "requirements for example reactions" {
    const allocator = std.testing.allocator;
    var stream = fixedBufferStream(
        \\9 ORE => 2 A
            \\8 ORE => 3 B
            \\7 ORE => 5 C
            \\3 A, 4 B => 1 AB
            \\5 B, 7 C => 1 BC
            \\4 C, 1 A => 1 CA
            \\2 AB, 3 BC, 4 CA => 1 FUEL
            \\ 
    ).reader();

    const reactions = try reactionsFromStream(allocator, stream);
    defer allocator.free(reactions);
    defer for (reactions) |*x| x.deinit();

    expectEqual(@as(usize, 165), try requiredOre(allocator, reactions));
}

test "requirements for example 1" {
    const allocator = std.testing.allocator;
    var stream = fixedBufferStream(
        \\157 ORE => 5 NZVS
            \\165 ORE => 6 DCFZ
            \\44 XJWVT, 5 KHKGT, 1 QDVJ, 29 NZVS, 9 GPVTF, 48 HKGWZ => 1 FUEL
            \\12 HKGWZ, 1 GPVTF, 8 PSHF => 9 QDVJ
            \\179 ORE => 7 PSHF
            \\177 ORE => 5 HKGWZ
            \\7 DCFZ, 7 PSHF => 2 XJWVT
            \\165 ORE => 2 GPVTF
            \\3 DCFZ, 7 NZVS, 5 HKGWZ, 10 PSHF => 8 KHKGT
            \\ 
    ).reader();

    const reactions = try reactionsFromStream(allocator, stream);
    defer allocator.free(reactions);
    defer for (reactions) |*x| x.deinit();

    expectEqual(@as(usize, 13312), try requiredOre(allocator, reactions));
}

test "requirements for example 2" {
    const allocator = std.testing.allocator;
    var stream = fixedBufferStream(
        \\2 VPVL, 7 FWMGM, 2 CXFTF, 11 MNCFX => 1 STKFG
            \\17 NVRVD, 3 JNWZP => 8 VPVL
            \\53 STKFG, 6 MNCFX, 46 VJHF, 81 HVMC, 68 CXFTF, 25 GNMV => 1 FUEL
            \\22 VJHF, 37 MNCFX => 5 FWMGM
            \\139 ORE => 4 NVRVD
            \\144 ORE => 7 JNWZP
            \\5 MNCFX, 7 RFSQX, 2 FWMGM, 2 VPVL, 19 CXFTF => 3 HVMC
            \\5 VJHF, 7 MNCFX, 9 VPVL, 37 CXFTF => 6 GNMV
            \\145 ORE => 6 MNCFX
            \\1 NVRVD => 8 CXFTF
            \\1 VJHF, 6 MNCFX => 4 RFSQX
            \\176 ORE => 6 VJHF
            \\ 
    ).reader();

    const reactions = try reactionsFromStream(allocator, stream);
    defer allocator.free(reactions);
    defer for (reactions) |*x| x.deinit();

    for (reactions) |x| {
        x.print();
    }

    // expectEqual(@as(usize, 180697), try requiredOre(allocator, reactions));
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    const input_file = try std.fs.cwd().openFile("input14.txt", .{});
    var input_stream = input_file.reader();

    const reactions = try reactionsFromStream(allocator, input_stream);
    defer allocator.free(reactions);
    defer for (reactions) |*x| x.deinit();

    std.debug.warn("required ore: {}\n", .{ try requiredOre(allocator, reactions) });
}
