const std = @import("std");
const assert = std.debug.assert;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const ExecError = error{
    InvalidOpcode,
    InvalidParamMode,
};

fn opcode(ins: i32) i32 {
    return @rem(ins, 100);
}

test "opcode extraction" {
    assert(opcode(1002) == 2);
}

fn paramMode(ins: i32, pos: i32) i32 {
    var div: i32 = 100; // Mode of parameter 0 is in digit 3
    var i: i32 = 0;
    while (i < pos) : (i += 1) {
        div *= 10;
    }
    return @rem(@divTrunc(ins, div), 10);
}

test "param mode extraction" {
    assert(paramMode(1002, 0) == 0);
    assert(paramMode(1002, 1) == 1);
    assert(paramMode(1002, 2) == 0);
}

pub const Intcode = []i32;

pub const IntcodeComputer = struct {
    mem: []i32,
    pc: usize,
    state: State,
    input: ?i32,
    output: ?i32,

    const Self = @This();

    pub const State = enum {
        Stopped,
        Running,
        AwaitingInput,
        AwaitingOutput,
    };

    pub fn init(intcode: []i32) Self {
        return Self{
            .mem = intcode,
            .pc = 0,
            .state = State.Running,
            .input = null,
            .output = null,
        };
    }

    fn getParam(self: Self, n: usize, mode: i32) !i32 {
        return switch (mode) {
            0 => self.mem[@intCast(usize, self.mem[self.pc + 1 + n])],
            1 => self.mem[self.pc + 1 + n],
            else => return error.InvalidParamMode,
        };
    }

    pub fn exec(self: *Self) !void {
        const instr = self.mem[self.pc];
        switch (opcode(instr)) {
            99 => self.state = State.Stopped,
            1 => {
                const val_x = try self.getParam(0, paramMode(instr, 0));
                const val_y = try self.getParam(1, paramMode(instr, 1));
                const pos_result = @intCast(usize, self.mem[self.pc + 3]);
                self.mem[pos_result] = val_x + val_y;
                self.pc += 4;
            },
            2 => {
                const val_x = try self.getParam(0, paramMode(instr, 0));
                const val_y = try self.getParam(1, paramMode(instr, 1));
                const pos_result = @intCast(usize, self.mem[self.pc + 3]);
                self.mem[pos_result] = val_x * val_y;
                self.pc += 4;
            },
            3 => {
                const pos_x = @intCast(usize, self.mem[self.pc + 1]);
                var buf: [1024]u8 = undefined;
                if (self.input) |val| {
                    self.mem[pos_x] = val;
                    self.pc += 2;
                    self.input = null;
                } else {
                    self.state = State.AwaitingInput;
                }
            },
            4 => {
                const val_x = try self.getParam(0, paramMode(instr, 0));
                if (self.output) |_| {
                    self.state = State.AwaitingOutput;
                } else {
                    self.output = val_x;
                    self.pc += 2;
                }
            },
            5 => {
                const val_x = try self.getParam(0, paramMode(instr, 0));
                if (val_x != 0) {
                    const val_y = try self.getParam(1, paramMode(instr, 1));
                    self.pc = @intCast(usize, val_y);
                } else {
                    self.pc += 3;
                }
            },
            6 => {
                const val_x = try self.getParam(0, paramMode(instr, 0));
                if (val_x == 0) {
                    const val_y = try self.getParam(1, paramMode(instr, 1));
                    self.pc = @intCast(usize, val_y);
                } else {
                    self.pc += 3;
                }
            },
            7 => {
                const val_x = try self.getParam(0, paramMode(instr, 0));
                const val_y = try self.getParam(1, paramMode(instr, 1));
                const pos_result = @intCast(usize, self.mem[self.pc + 3]);
                self.mem[pos_result] = if (val_x < val_y) 1 else 0;
                self.pc += 4;
            },
            8 => {
                const val_x = try self.getParam(0, paramMode(instr, 0));
                const val_y = try self.getParam(1, paramMode(instr, 1));
                const pos_result = @intCast(usize, self.mem[self.pc + 3]);
                self.mem[pos_result] = if (val_x == val_y) 1 else 0;
                self.pc += 4;
            },
            else => {
                std.debug.warn("pos: {}, instr: {}\n", .{ self.pc, instr });
                return error.InvalidOpcode;
            },
        }
    }

    pub fn execUntilHalt(self: *Self) !void {
        // try to jump-start the computer if it was waiting for I/O
        if (self.state != State.Stopped)
            self.state = State.Running;

        while (self.state == State.Running)
            try self.exec();
    }
};

test "test exec 1" {
    var intcode = [_]i32{ 1, 0, 0, 0, 99 };
    var comp = IntcodeComputer.init(&intcode);
    try comp.execUntilHalt();
    assert(intcode[0] == 2);
}

test "test exec 2" {
    var intcode = [_]i32{ 2, 3, 0, 3, 99 };
    var comp = IntcodeComputer.init(&intcode);
    try comp.execUntilHalt();
    assert(intcode[3] == 6);
}

test "test exec 3" {
    var intcode = [_]i32{ 2, 4, 4, 5, 99, 0 };
    var comp = IntcodeComputer.init(&intcode);
    try comp.execUntilHalt();
    assert(intcode[5] == 9801);
}

test "test exec with different param mode" {
    var intcode = [_]i32{ 1002, 4, 3, 4, 33 };
    var comp = IntcodeComputer.init(&intcode);
    try comp.execUntilHalt();
    assert(intcode[4] == 99);
}

test "test exec with negative integers" {
    var intcode = [_]i32{ 1101, 100, -1, 4, 0 };
    var comp = IntcodeComputer.init(&intcode);
    try comp.execUntilHalt();
    assert(intcode[4] == 99);
}

test "test equal 1" {
    var intcode = [_]i32{ 3, 9, 8, 9, 10, 9, 4, 9, 99, -1, 8 };
    var comp = IntcodeComputer.init(&intcode);
    comp.input = 8;
    try comp.execUntilHalt();
    assert(comp.output.? == 1);
}

test "test equal 2" {
    var intcode = [_]i32{ 3, 9, 8, 9, 10, 9, 4, 9, 99, -1, 8 };
    var comp = IntcodeComputer.init(&intcode);
    comp.input = 13;
    try comp.execUntilHalt();
    assert(comp.output.? == 0);
}

test "test less than 1" {
    var intcode = [_]i32{ 3, 9, 7, 9, 10, 9, 4, 9, 99, -1, 8 };
    var comp = IntcodeComputer.init(&intcode);
    comp.input = 5;
    try comp.execUntilHalt();
    assert(comp.output.? == 1);
}

test "test less than 2" {
    var intcode = [_]i32{ 3, 9, 7, 9, 10, 9, 4, 9, 99, -1, 8 };
    var comp = IntcodeComputer.init(&intcode);
    comp.input = 20;
    try comp.execUntilHalt();
    assert(comp.output.? == 0);
}

test "test equal immediate" {
    var intcode = [_]i32{ 3, 3, 1108, -1, 8, 3, 4, 3, 99 };
    var comp = IntcodeComputer.init(&intcode);
    comp.input = 8;
    try comp.execUntilHalt();
    assert(comp.output.? == 1);
}

test "test less than immediate" {
    var intcode = [_]i32{ 3, 3, 1107, -1, 8, 3, 4, 3, 99 };
    var comp = IntcodeComputer.init(&intcode);
    comp.input = 3;
    try comp.execUntilHalt();
    assert(comp.output.? == 1);
}

fn runAmp(amp: *IntcodeComputer, phase: i32, input: i32) !i32 {
    amp.input = phase;
    try amp.execUntilHalt();
    amp.input = input;
    try amp.execUntilHalt();

    defer amp.output = null;
    return amp.output orelse error.NoOutput;
}

fn runAmpNoPhase(amp: *IntcodeComputer, input: i32) !i32 {
    amp.input = input;
    try amp.execUntilHalt();

    defer amp.output = null;
    return amp.output orelse error.NoOutput;
}

fn runAmps(amps: []IntcodeComputer, phase_sequence: []i32) !i32 {
    var x: i32 = 0;
    for (amps) |*amp, i| {
        x = try runAmp(amp, phase_sequence[i], x);
    }
    while (amps[0].state != .Stopped) {
        for (amps) |*amp| {
            x = try runAmpNoPhase(amp, x);
        }
    }
    return x;
}

test "run amps" {
    const amp = [_]i32{ 3, 15, 3, 16, 1002, 16, 10, 16, 1, 16, 15, 15, 4, 15, 99, 0, 0 };
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var amps: [5]IntcodeComputer = undefined;
    for (amps) |*a| {
        a.* = IntcodeComputer.init(try std.mem.dupe(allocator, i32, &amp));
    }

    var phase_sequence = [_]i32{ 4, 3, 2, 1, 0 };
    const expected: i32 = 43210;
    expectEqual(expected, try runAmps(&amps, &phase_sequence));
}

test "run amps with feedback" {
    const amp = [_]i32{
        3,  26, 1001, 26,   -4, 26, 3,  27,   1002, 27, 2,  27, 1, 27, 26,
        27, 4,  27,   1001, 28, -1, 28, 1005, 28,   6,  99, 0,  0, 5,
    };
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var amps: [5]IntcodeComputer = undefined;
    for (amps) |*a| {
        a.* = IntcodeComputer.init(try std.mem.dupe(allocator, i32, &amp));
    }

    var phase_sequence = [_]i32{ 9, 8, 7, 6, 5 };
    const expected: i32 = 139629729;
    expectEqual(expected, try runAmps(&amps, &phase_sequence));
}

const PermutationError = std.mem.Allocator.Error;

fn permutations(comptime T: type, alloc: *Allocator, options: []T) PermutationError!ArrayList(ArrayList(T)) {
    var result = ArrayList(ArrayList(T)).init(alloc);

    if (options.len < 1)
        try result.append(ArrayList(T).init(alloc));

    for (options) |opt, i| {
        var cp = try std.mem.dupe(alloc, T, options);
        var remaining = ArrayList(T).fromOwnedSlice(alloc, cp);
        _ = remaining.orderedRemove(i);

        for ((try permutations(T, alloc, remaining.items)).items) |*p| {
            try p.insert(0, opt);
            try result.append(p.*);
        }
    }

    return result;
}

test "empty permutation" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var options = [_]u8{};
    const perm = try permutations(u8, allocator, &options);
    assert(perm.items.len == 1);
}

test "permutation with 2 elements" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var options = [_]u8{ 0, 1 };
    const perm = try permutations(u8, allocator, &options);
    assert(perm.items.len == 2);
}

test "permutation with 4 elements" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var options = [_]u8{ 0, 1, 2, 3 };
    const perm = try permutations(u8, allocator, &options);
    assert(perm.items.len == 24);
}

fn findMaxOutput(alloc: *Allocator, amps_orig: []const Intcode) !i32 {
    // Duplicate the amps
    var amps = try alloc.alloc(IntcodeComputer, amps_orig.len);
    for (amps) |*a, i| {
        a.* = IntcodeComputer.init(try std.mem.dupe(alloc, i32, amps_orig[i]));
    }

    // free the duplicates later
    defer {
        for (amps) |a|
            alloc.free(a.mem);
        alloc.free(amps);
    }

    // Iterate through permutations
    var phases = [_]i32{ 5, 6, 7, 8, 9 };
    var max_perm: ?[]i32 = null;
    var max_output: ?i32 = null;
    for ((try permutations(i32, alloc, &phases)).items) |perm| {
        // reset amps intcode
        for (amps) |*a, i| {
            std.mem.copy(i32, a.mem, amps_orig[i]);
            a.* = IntcodeComputer.init(a.mem);
        }

        // run
        const output = try runAmps(amps, perm.items);
        if (max_output) |max| {
            if (output > max) {
                max_perm = perm.items;
                max_output = output;
            }
        } else {
            max_perm = perm.items;
            max_output = output;
        }
    }

    return max_output orelse return error.NoPermutations;
}

test "max output 1" {
    const amp = [_]i32{
        3,  26, 1001, 26,   -4, 26, 3,  27,   1002, 27, 2,  27, 1, 27, 26,
        27, 4,  27,   1001, 28, -1, 28, 1005, 28,   6,  99, 0,  0, 5,
    };
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var amps: [5]Intcode = undefined;
    for (amps) |*a| {
        a.* = try std.mem.dupe(allocator, i32, &amp);
    }

    const output = try findMaxOutput(allocator, &amps);
    const expected_output: i32 = 139629729;
    expectEqual(expected_output, output);
}

test "max output 2" {
    const amp = [_]i32{
        3,  52, 1001, 52, -5, 52, 3,    53, 1,  52,   56, 54, 1007, 54,   5,  55, 1005, 55, 26, 1001, 54,
        -5, 54, 1105, 1,  12, 1,  53,   54, 53, 1008, 54, 0,  55,   1001, 55, 1,  55,   2,  53, 55,   53,
        4,  53, 1001, 56, -1, 56, 1005, 56, 6,  99,   0,  0,  0,    0,    10,
    };
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var amps: [5]Intcode = undefined;
    for (amps) |*a| {
        a.* = try std.mem.dupe(allocator, i32, &amp);
    }

    const output = try findMaxOutput(allocator, &amps);
    const expected_output: i32 = 18216;
    expectEqual(expected_output, output);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    const input_file = try std.fs.cwd().openFile("input07.txt", .{});
    var input_stream = input_file.inStream();
    var buf: [1024]u8 = undefined;
    var ints = std.ArrayList(i32).init(allocator);

    // read amp intcode into an int arraylist
    while (try input_stream.readUntilDelimiterOrEof(&buf, ',')) |item| {
        // add an empty element to the input file because I don't want to modify
        // this to discard newlines
        try ints.append(std.fmt.parseInt(i32, item, 10) catch -1);
    }

    // duplicate amps 5 times
    var amps: [5]Intcode = undefined;
    for (amps) |*a| {
        a.* = try std.mem.dupe(allocator, i32, ints.items);
    }

    // try combinations of phase sequences
    std.debug.warn("max achievable output: {}\n", .{try findMaxOutput(allocator, &amps)});
}
