const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

const base_pattern = [_]isize{ 0, 1, 0, -1 };

fn getPattern(output_pos: usize, pos: usize) isize {
    const real_pos = pos + 1;
    const multiplier = output_pos + 1;
    return base_pattern[(real_pos / multiplier) % base_pattern.len];
}

test "getPattern first output" {
    expectEqual(@as(isize, 1), getPattern(0, 0));
    expectEqual(@as(isize, 0), getPattern(0, 1));
    expectEqual(@as(isize, -1), getPattern(0, 2));
    expectEqual(@as(isize, 0), getPattern(0, 3));
    expectEqual(@as(isize, 1), getPattern(0, 4));
    expectEqual(@as(isize, 0), getPattern(0, 5));
}

test "getPattern second output" {
    expectEqual(@as(isize, 0), getPattern(1, 0));
    expectEqual(@as(isize, 1), getPattern(1, 1));
    expectEqual(@as(isize, 1), getPattern(1, 2));
    expectEqual(@as(isize, 0), getPattern(1, 3));
    expectEqual(@as(isize, 0), getPattern(1, 4));
    expectEqual(@as(isize, -1), getPattern(1, 5));
}

test "getPattern third output" {
    expectEqual(@as(isize, 0), getPattern(2, 0));
    expectEqual(@as(isize, 0), getPattern(2, 1));
    expectEqual(@as(isize, 1), getPattern(2, 2));
    expectEqual(@as(isize, 1), getPattern(2, 3));
    expectEqual(@as(isize, 1), getPattern(2, 4));
    expectEqual(@as(isize, 0), getPattern(2, 5));
    expectEqual(@as(isize, 0), getPattern(2, 6));
    expectEqual(@as(isize, 0), getPattern(2, 7));
    expectEqual(@as(isize, -1), getPattern(2, 8));
    expectEqual(@as(isize, -1), getPattern(2, 9));
    expectEqual(@as(isize, -1), getPattern(2, 10));
}

fn fftPhase(input: []const isize, output: []isize) void {
    for (input) |x, i| {
        const step_size = i + 1;
        var new_val: isize = 0;

        // Optimization: only iterate over fields that are non-null
        var j: usize = i;
        while (j < input.len) : (j += 2 * step_size) {
            var k: usize = 0;
            while (k < step_size and j + k < input.len) : (k += 1) {
                new_val += input[j + k] * getPattern(i, j + k);
            }
        }

        output[i] = @mod(std.math.absInt(new_val) catch 0, 10);
    }
}

test "first example" {
    var input: [8]isize = undefined;
    var output: [8]isize = undefined;

    var i: usize = 0;
    while (i < 8) : (i += 1) input[i] = @intCast(isize, i + 1);

    fftPhase(&input, &output);
    expectEqualSlices(isize, &[_]isize{ 4, 8, 2, 2, 6, 1, 5, 8 }, &output);
    std.mem.copy(isize, &input, &output);

    fftPhase(&input, &output);
    expectEqualSlices(isize, &[_]isize{ 3, 4, 0, 4, 0, 4, 3, 8 }, &output);
    std.mem.copy(isize, &input, &output);
}

test "large example 1" {
    const input_str = "80871224585914546619083218645595";
    var input: [input_str.len]isize = undefined;
    var output: [input_str.len]isize = undefined;

    for (input_str) |x, i| {
        input[i] = @intCast(isize, x - '0');
    }

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        fftPhase(&input, &output);
        std.mem.copy(isize, &input, &output);
    }

    expectEqualSlices(isize, &[_]isize{ 2, 4, 1, 7, 6, 1, 7, 6 }, output[0..8]);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = &arena.allocator;

    const input_file = try std.fs.cwd().openFile("input16.txt", .{});
    var input_stream = input_file.reader();
    var read = ArrayList(isize).init(allocator);

    while (input_stream.readByte()) |b| {
        if ('0' <= b and b <= '9') {
            try read.append(@intCast(isize, b - '0'));
        }
    } else |e| switch (e) {
        error.EndOfStream => {},
        else => return e,
    }

    var current = read.toOwnedSlice();
    var new = try allocator.alloc(isize, current.len);
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        fftPhase(current, new);
        std.mem.copy(isize, current, new);
    }

    var eight_digits: [8]u8 = undefined;
    for (eight_digits) |*x, j| {
        x.* = @intCast(u8, current[j] + '0');
    }
    std.debug.warn("first eight digits: {}\n", .{&eight_digits});
}
