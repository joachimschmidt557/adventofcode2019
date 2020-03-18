const std = @import("std");
const assert = std.debug.assert;
const expect = std.testing.expect;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const fixedBufferStream = std.io.fixedBufferStream;

const Pixel = u8;

const Layer = struct {
    pixels: []Pixel,

    const Self = @This();

    pub fn fromStream(alloc: *Allocator, stream: var, w: usize, h: usize) !Self {
        var pixels = try alloc.alloc(Pixel, w * h);
        for (pixels) |*p| {
            var buf: [1]u8 = undefined;
            if ((try stream.readAll(&buf)) == 0)
                return error.EndOfStream;
            p.* = try std.fmt.parseInt(u8, &buf, 10);
        }
        return Self{
            .pixels = pixels,
        };
    }

    pub fn countDigit(self: Self, digit: u8) usize {
        var result: usize = 0;

        for (self.pixels) |p| {
            if (p == digit)
                result += 1;
        }

        return result;
    }
};

test "read layer" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var in_stream = fixedBufferStream("001123").inStream();
    const lay = try Layer.fromStream(allocator, in_stream, 3, 2);

    expect(lay.countDigit(1) == 2);
    expect(lay.countDigit(0) == 2);
}

const Image = struct {
    layers: []Layer,

    const Self = @This();

    pub fn fromStream(alloc: *Allocator, stream: var, w: usize, h: usize) !Self {
        var layers = ArrayList(Layer).init(alloc);

        while (Layer.fromStream(alloc, stream, w, h)) |l| {
            try layers.append(l);
        } else |e| switch (e) {
            error.EndOfStream => {},
            error.InvalidCharacter => {},
            else => return e,
        }

        return Self{
            .layers = layers.toSlice(),
        };
    }
};

test "read image" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var in_stream = fixedBufferStream("123456789012").inStream();
    const img = try Image.fromStream(allocator, in_stream, 3, 2);

    expect(img.layers.len == 2);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    const input_file = try std.fs.cwd().openFile("input08.txt", .{});
    var input_stream = input_file.inStream();

    // read image
    const img = try Image.fromStream(allocator, input_stream, 25, 6);

    // find layer with fewest 0 digits
    var res: ?Layer = null;
    for (img.layers) |l| {
        if (res) |min_layer| {
            if (l.countDigit(0) < min_layer.countDigit(0)) {
                res = l;
            }
        } else {
            res = l;
        }
    }

    // calculate result
    const result = res.?.countDigit(1) * res.?.countDigit(2);
    std.debug.warn("result: {}\n", .{ result });
}
