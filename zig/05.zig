const std = @import("std");
const assert = std.debug.assert;
const fixedBufferStream = std.io.fixedBufferStream;

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
                try output_stream.print("{}\n", .{ val_x });
                pos += 2;
            },
            else => {
                std.debug.warn("pos: {}, instr: {}\n", .{ pos, intcode[pos]});
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

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.direct_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    const input_file = try std.fs.cwd().openFile("input05.txt", .{});
    var input_stream = input_file.inStream();
    var buf: [1024]u8 = undefined;
    var ints = std.ArrayList(i32).init(allocator);

    // read everything into an int arraylist
    while (try input_stream.readUntilDelimiterOrEof(&buf, ',')) |item| {
        try ints.append(std.fmt.parseInt(i32, item, 10) catch 0);
    }

    // execute code
    try exec(ints.toSlice(), &std.io.getStdIn().inStream(), &std.io.getStdOut().outStream());
}
