const std = @import("std");
const assert = std.debug.assert;
const expect = std.testing.expect;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const fixedBufferStream = std.io.fixedBufferStream;
const countingOutStream = std.io.countingOutStream;

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

fn getParam(intcode: []i32, pos: usize, n: usize, mode: i32) !i32 {
    return switch (mode) {
        0 => intcode[@intCast(usize, intcode[pos + 1 + n])],
        1 => intcode[pos + 1 + n],
        else => return error.InvalidParamMode,
    };
}

fn exec(intcode: []i32, input_stream: var, output_stream: var) !void {
    var pos: usize = 0;

    while (true) {
        const instr = intcode[pos];
        switch (opcode(instr)) {
            99 => break,
            1 => {
                const val_x = try getParam(intcode, pos, 0, paramMode(instr, 0));
                const val_y = try getParam(intcode, pos, 1, paramMode(instr, 1));
                const pos_result = @intCast(usize, intcode[pos + 3]);
                intcode[pos_result] = val_x + val_y;
                pos += 4;
            },
            2 => {
                const val_x = try getParam(intcode, pos, 0, paramMode(instr, 0));
                const val_y = try getParam(intcode, pos, 1, paramMode(instr, 1));
                const pos_result = @intCast(usize, intcode[pos + 3]);
                intcode[pos_result] = val_x * val_y;
                pos += 4;
            },
            3 => {
                const pos_x = @intCast(usize, intcode[pos + 1]);
                var buf: [1024]u8 = undefined;
                const line = (try input_stream.readUntilDelimiterOrEof(&buf, '\n')) orelse "";
                const val = try std.fmt.parseInt(i32, line, 10);
                intcode[pos_x] = val;
                pos += 2;
            },
            4 => {
                const val_x = try getParam(intcode, pos, 0, paramMode(instr, 0));
                try output_stream.print("{}\n", .{val_x});
                pos += 2;
            },
            5 => {
                const val_x = try getParam(intcode, pos, 0, paramMode(instr, 0));
                if (val_x != 0) {
                    const val_y = try getParam(intcode, pos, 1, paramMode(instr, 1));
                    pos = @intCast(usize, val_y);
                } else {
                    pos += 3;
                }
            },
            6 => {
                const val_x = try getParam(intcode, pos, 0, paramMode(instr, 0));
                if (val_x == 0) {
                    const val_y = try getParam(intcode, pos, 1, paramMode(instr, 1));
                    pos = @intCast(usize, val_y);
                } else {
                    pos += 3;
                }
            },
            7 => {
                const val_x = try getParam(intcode, pos, 0, paramMode(instr, 0));
                const val_y = try getParam(intcode, pos, 1, paramMode(instr, 1));
                const pos_result = @intCast(usize, intcode[pos + 3]);
                intcode[pos_result] = if (val_x < val_y) 1 else 0;
                pos += 4;
            },
            8 => {
                const val_x = try getParam(intcode, pos, 0, paramMode(instr, 0));
                const val_y = try getParam(intcode, pos, 1, paramMode(instr, 1));
                const pos_result = @intCast(usize, intcode[pos + 3]);
                intcode[pos_result] = if (val_x == val_y) 1 else 0;
                pos += 4;
            },
            else => {
                std.debug.warn("pos: {}, instr: {}\n", .{ pos, intcode[pos] });
                return error.InvalidOpcode;
            },
        }
    }
}

test "test exec 1" {
    var intcode = [_]i32{ 1, 0, 0, 0, 99 };
    var in_stream = fixedBufferStream("").inStream();
    try exec(&intcode, in_stream, std.io.null_out_stream);
    assert(intcode[0] == 2);
}

test "test exec 2" {
    var intcode = [_]i32{ 2, 3, 0, 3, 99 };
    var in_stream = fixedBufferStream("").inStream();
    try exec(&intcode, in_stream, std.io.null_out_stream);
    assert(intcode[3] == 6);
}

test "test exec 3" {
    var intcode = [_]i32{ 2, 4, 4, 5, 99, 0 };
    var in_stream = fixedBufferStream("").inStream();
    try exec(&intcode, in_stream, std.io.null_out_stream);
    assert(intcode[5] == 9801);
}

test "test exec with different param mode" {
    var intcode = [_]i32{ 1002, 4, 3, 4, 33 };
    var in_stream = fixedBufferStream("").inStream();
    try exec(&intcode, in_stream, std.io.null_out_stream);
    assert(intcode[4] == 99);
}

test "test exec with negative integers" {
    var intcode = [_]i32{ 1101, 100, -1, 4, 0 };
    var in_stream = fixedBufferStream("").inStream();
    try exec(&intcode, in_stream, std.io.null_out_stream);
    assert(intcode[4] == 99);
}

test "test equal 1" {
    var intcode = [_]i32{ 3, 9, 8, 9, 10, 9, 4, 9, 99, -1, 8 };
    var output_buf: [32]u8 = undefined;
    var in_stream = fixedBufferStream("8\n").inStream();
    var out_stream = fixedBufferStream(&output_buf).outStream();
    try exec(&intcode, in_stream, out_stream);
    assert(std.mem.eql(u8, "1\n", output_buf[0..2]));
}

test "test equal 2" {
    var intcode = [_]i32{ 3, 9, 8, 9, 10, 9, 4, 9, 99, -1, 8 };
    var output_buf: [32]u8 = undefined;
    var in_stream = fixedBufferStream("13\n").inStream();
    var out_stream = fixedBufferStream(&output_buf).outStream();
    try exec(&intcode, in_stream, out_stream);
    assert(std.mem.eql(u8, "0\n", output_buf[0..2]));
}

test "test less than 1" {
    var intcode = [_]i32{ 3, 9, 7, 9, 10, 9, 4, 9, 99, -1, 8 };
    var output_buf: [32]u8 = undefined;
    var in_stream = fixedBufferStream("5\n").inStream();
    var out_stream = fixedBufferStream(&output_buf).outStream();
    try exec(&intcode, in_stream, out_stream);
    assert(std.mem.eql(u8, "1\n", output_buf[0..2]));
}

test "test less than 2" {
    var intcode = [_]i32{ 3, 9, 7, 9, 10, 9, 4, 9, 99, -1, 8 };
    var output_buf: [32]u8 = undefined;
    var in_stream = fixedBufferStream("20\n").inStream();
    var out_stream = fixedBufferStream(&output_buf).outStream();
    try exec(&intcode, in_stream, out_stream);
    assert(std.mem.eql(u8, "0\n", output_buf[0..2]));
}

test "test equal immediate" {
    var intcode = [_]i32{ 3, 3, 1108, -1, 8, 3, 4, 3, 99 };
    var output_buf: [32]u8 = undefined;
    var in_stream = fixedBufferStream("8\n").inStream();
    var out_stream = fixedBufferStream(&output_buf).outStream();
    try exec(&intcode, in_stream, out_stream);
    assert(std.mem.eql(u8, "1\n", output_buf[0..2]));
}

test "test less than immediate" {
    var intcode = [_]i32{ 3, 3, 1107, -1, 8, 3, 4, 3, 99 };
    var output_buf: [32]u8 = undefined;
    var in_stream = fixedBufferStream("3\n").inStream();
    var out_stream = fixedBufferStream(&output_buf).outStream();
    try exec(&intcode, in_stream, out_stream);
    assert(std.mem.eql(u8, "1\n", output_buf[0..2]));
}

pub const Amp = []i32;

fn runAmp(intcode: Amp, phase: i32, input: i32) !i32 {
    var input_buf: [32]u8 = undefined;
    const input_slice = try std.fmt.bufPrint(&input_buf, "{}\n{}\n", .{ phase, input });
    var input_stream = fixedBufferStream(input_slice).inStream();

    var output_buf: [32]u8 = undefined;
    var output_stream_internal = fixedBufferStream(&output_buf).outStream();
    var output_stream = countingOutStream(output_stream_internal);

    try exec(intcode, input_stream, output_stream.outStream());

    return try std.fmt.parseInt(i32, output_buf[0 .. output_stream.bytes_written - 1], 10);
}

fn runAmps(amps: []Amp, phase_sequence: []i32) !i32 {
    var x: i32 = 0;
    for (amps) |amp, i| {
        x = try runAmp(amp, phase_sequence[i], x);
    }
    return x;
}

test "run amps" {
    const amp = [_]i32{ 3, 15, 3, 16, 1002, 16, 10, 16, 1, 16, 15, 15, 4, 15, 99, 0, 0 };
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var amps: [5]Amp = undefined;
    for (amps) |*a| {
        a.* = try std.mem.dupe(allocator, i32, &amp);
    }

    var phase_sequence = [_]i32{ 4, 3, 2, 1, 0 };
    assert((try runAmps(&amps, &phase_sequence)) == 43210);
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

fn findMaxOutput(alloc: *Allocator, amps_orig: []const Amp) !i32 {
    // Duplicate the amps
    var amps = try std.mem.dupe(alloc, Amp, amps_orig);
    for (amps) |*a, i| {
        a.* = try std.mem.dupe(alloc, i32, amps_orig[i]);
    }

    // free the duplicates later
    defer {
        for (amps) |a|
            alloc.free(a);
        alloc.free(amps);
    }

    // Iterate through permutations
    var phases = [_]i32{ 0, 1, 2, 3, 4 };
    var max_perm: ?[]i32 = null;
    var max_output: ?i32 = null;
    for ((try permutations(i32, alloc, &phases)).items) |perm| {
        // reset amps intcode
        for (amps) |*a, i| {
            std.mem.copy(i32, a.*, amps_orig[i]);
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
    const amp = [_]i32{ 3, 15, 3, 16, 1002, 16, 10, 16, 1, 16, 15, 15, 4, 15, 99, 0, 0 };
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var amps: [5]Amp = undefined;
    for (amps) |*a| {
        a.* = try std.mem.dupe(allocator, i32, &amp);
    }

    const output = try findMaxOutput(allocator, &amps);
    const expected_output: i32 = 43210;
    expect(output == expected_output);
}

test "max output 2" {
    const amp = [_]i32{
        3,   23, 3,  24, 1002, 24, 10, 24, 1002, 23, -1, 23,
        101, 5,  23, 23, 1,    24, 23, 23, 4,    23, 99, 0,
        0,
    };
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var amps: [5]Amp = undefined;
    for (amps) |*a| {
        a.* = try std.mem.dupe(allocator, i32, &amp);
    }

    const output = try findMaxOutput(allocator, &amps);
    const expected_output: i32 = 54321;
    expect(output == expected_output);
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
        try ints.append(std.fmt.parseInt(i32, item, 10) catch 0);
    }

    // duplicate amps 5 times
    var amps: [5]Amp = undefined;
    for (amps) |*a| {
        a.* = try std.mem.dupe(allocator, i32, ints.items);
    }

    // try combinations of phase sequences
    std.debug.warn("max achievable output: {}\n", .{try findMaxOutput(allocator, &amps)});
}
