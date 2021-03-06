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

    pub fn fromStream(alloc: *Allocator, stream: anytype, w: usize, h: usize) !Self {
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

    pub fn merge(self: *Self, other: Self) void {
        for (self.pixels) |*p, i| {
            if (p.* == 2)
                p.* = other.pixels[i];
        }
    }
};

test "read layer" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var reader = fixedBufferStream("001123").reader();
    const lay = try Layer.fromStream(allocator, reader, 3, 2);

    expect(lay.countDigit(1) == 2);
    expect(lay.countDigit(0) == 2);
}

const Image = struct {
    layers: []Layer,
    width: usize,

    const Self = @This();

    pub fn fromStream(alloc: *Allocator, stream: anytype, w: usize, h: usize) !Self {
        var layers = ArrayList(Layer).init(alloc);

        while (Layer.fromStream(alloc, stream, w, h)) |l| {
            try layers.append(l);
        } else |e| switch (e) {
            error.EndOfStream => {},
            error.InvalidCharacter => {},
            else => return e,
        }

        return Self{
            .layers = layers.items,
            .width = w,
        };
    }

    pub fn flatten(self: *Self) void {
        var i: usize = self.layers.len - 1;
        while (i > 0) : (i -= 1) {
            self.layers[i - 1].merge(self.layers[i]);
        }
    }

    pub fn print(self: Self) void {
        for (self.layers[0].pixels) |pix, i| {
            if (pix == 0) {
                std.debug.warn(" ", .{});
            } else {
                std.debug.warn("{}", .{pix});
            }
            if (i % self.width == self.width - 1)
                std.debug.warn("\n", .{});
        }
    }
};

test "read image" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var reader = fixedBufferStream("123456789012").reader();
    const img = try Image.fromStream(allocator, reader, 3, 2);

    expect(img.layers.len == 2);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    const input_file = try std.fs.cwd().openFile("input08.txt", .{});
    var input_stream = input_file.reader();

    // read image
    var img = try Image.fromStream(allocator, input_stream, 25, 6);

    // flatten
    img.flatten();

    // print
    img.print();
}
