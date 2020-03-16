const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

const Chemical = []const u8;
const ChemicalQuantity = struct {
    chem: Chemical,
    quant: usize,
};

const Reaction = struct {
    alloc: *Allocator,
    inputs: []ChemicalQuantity,
    output: ChemicalQuantity,

    const Self = @This();

    pub fn fromStr(alloc: *Allocator, str: []const u8) !?Self {
        return try ReactionParser.init(alloc, str).parseReaction();
    }

    pub fn deinit(self: *Self) void {
        self.alloc.free(self.inputs);
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
        if (self.pop()) |c| {
            return c == char;
        } else {
            return false;
        }
    }
};

test "parse reaction" {
    const allocator = std.testing.allocator;

    const str = "10 ORE => 20 ABC";
    const expected = Reaction{
        .alloc = allocator,
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

fn onlyOre(materials: []ChemicalQuantity) bool {
    return materials.len == 1 and std.mem.eql(u8, "ORE", materials[0].chem);
}

fn requiredOre(allocator: *Allocator, reactions: []Reaction) usize {
    var required_materials = ArrayList(ChemicalQuantity).init(allocator);

    while (!onlyOre(required_materials.toSlice())) {
        var old_required_materials = required_materials;
        var new_required_materials = ArrayList(ChemicalQuantity).init(allocator);

        old_required_materials.deinit();
        required_materials = new_required_materials;
    }

    return required_materials.toSlice()[0].quant;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const stdin_file = std.io.getStdIn();
    var stdin_stream = stdin_file.inStream().stream;

    var reactions = ArrayList(Reaction).init(allocator);
    defer reactions.deinit();

    while (stdin_stream.readUntilDelimiterAlloc(allocator, '\n', 1024)) |line| {
        if (try Reaction.fromStr(allocator, line)) |r|
            try reactions.append(r);
    } else |e| switch (e) {
        error.EndOfStream => {},
        else => return e,
    }

    std.debug.warn("required ore: {}\n", .{ requiredOre(allocator, reactions.toSlice()) });
}
