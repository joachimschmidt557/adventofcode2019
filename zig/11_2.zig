const std = @import("std");
const assert = std.debug.assert;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const AutoHashMap = std.AutoHashMap;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const ExecError = error{
    InvalidOpcode,
    InvalidParamMode,
};

fn opcode(ins: Instr) Instr {
    return @rem(ins, 100);
}

test "opcode extraction" {
    expectEqual(opcode(1002), 2);
}

fn paramMode(ins: Instr, pos: Instr) Instr {
    var div: Instr = 100; // Mode of parameter 0 is in digit 3
    var i: Instr = 0;
    while (i < pos) : (i += 1) {
        div *= 10;
    }
    return @rem(@divTrunc(ins, div), 10);
}

test "param mode extraction" {
    expectEqual(paramMode(1002, 0), 0);
    expectEqual(paramMode(1002, 1), 1);
    expectEqual(paramMode(1002, 2), 0);
}

pub const Instr = i64;
pub const Intcode = []Instr;

pub const Mem = struct {
    backend: ArrayList(Instr),

    const Self = @This();

    pub fn init(intcode: Intcode, alloc: *Allocator) Self {
        return Self{
            .backend = ArrayList(Instr).fromOwnedSlice(alloc, intcode),
        };
    }

    pub fn get(self: Self, pos: usize) Instr {
        return if (pos < self.backend.items.len) self.backend.items[pos] else 0;
    }

    pub fn set(self: *Self, pos: usize, val: Instr) !void {
        if (pos < self.backend.items.len) {
            self.backend.items[pos] = val;
        } else {
            const old_len = self.backend.items.len;
            try self.backend.resize(pos + 1);

            var i: usize = old_len;
            while (i < self.backend.items.len) : (i += 1) {
                self.backend.items[i] = 0;
            }

            self.backend.items[pos] = val;
        }
    }
};

pub const IntcodeComputer = struct {
    mem: Mem,
    pc: usize,
    relative_base: Instr,
    state: State,
    input: ?Instr,
    output: ?Instr,

    const Self = @This();

    pub const State = enum {
        Stopped,
        Running,
        AwaitingInput,
        AwaitingOutput,
    };

    pub fn init(intcode: Intcode, alloc: *Allocator) Self {
        return Self{
            .mem = Mem.init(intcode, alloc),
            .pc = 0,
            .relative_base = 0,
            .state = State.Running,
            .input = null,
            .output = null,
        };
    }

    fn getParam(self: Self, n: usize, mode: Instr) !Instr {
        const val = self.mem.get(self.pc + 1 + n);
        return switch (mode) {
            0 => self.mem.get(@intCast(usize, val)),
            1 => val,
            2 => self.mem.get(@intCast(usize, self.relative_base + val)),
            else => return error.InvalidParamMode,
        };
    }

    fn getPos(self: Self, n: usize, mode: Instr) !usize {
        const val = self.mem.get(self.pc + 1 + n);
        return switch (mode) {
            0 => @intCast(usize, val),
            1 => return error.OutputParameterImmediateMode,
            2 => @intCast(usize, self.relative_base + val),
            else => return error.InvalidParamMode,
        };
    }

    pub fn exec(self: *Self) !void {
        const instr = self.mem.get(self.pc);
        switch (opcode(instr)) {
            99 => self.state = State.Stopped,
            1 => {
                const val_x = try self.getParam(0, paramMode(instr, 0));
                const val_y = try self.getParam(1, paramMode(instr, 1));
                const pos_result = try self.getPos(2, paramMode(instr, 2));
                try self.mem.set(pos_result, val_x + val_y);
                self.pc += 4;
            },
            2 => {
                const val_x = try self.getParam(0, paramMode(instr, 0));
                const val_y = try self.getParam(1, paramMode(instr, 1));
                const pos_result = try self.getPos(2, paramMode(instr, 2));
                try self.mem.set(pos_result, val_x * val_y);
                self.pc += 4;
            },
            3 => {
                const pos_x = try self.getPos(0, paramMode(instr, 0));
                if (self.input) |val| {
                    try self.mem.set(pos_x, val);
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
                const pos_result = try self.getPos(2, paramMode(instr, 2));
                try self.mem.set(pos_result, if (val_x < val_y) 1 else 0);
                self.pc += 4;
            },
            8 => {
                const val_x = try self.getParam(0, paramMode(instr, 0));
                const val_y = try self.getParam(1, paramMode(instr, 1));
                const pos_result = try self.getPos(2, paramMode(instr, 2));
                try self.mem.set(pos_result, if (val_x == val_y) 1 else 0);
                self.pc += 4;
            },
            9 => {
                const val_x = try self.getParam(0, paramMode(instr, 0));
                self.relative_base += val_x;
                self.pc += 2;
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
    var intcode = [_]Instr{ 1, 0, 0, 0, 99 };
    var comp = IntcodeComputer.init(&intcode, std.testing.failing_allocator);
    try comp.execUntilHalt();
    expectEqual(intcode[0], 2);
}

test "test exec 2" {
    var intcode = [_]Instr{ 2, 3, 0, 3, 99 };
    var comp = IntcodeComputer.init(&intcode, std.testing.failing_allocator);
    try comp.execUntilHalt();
    expectEqual(intcode[3], 6);
}

test "test exec 3" {
    var intcode = [_]Instr{ 2, 4, 4, 5, 99, 0 };
    var comp = IntcodeComputer.init(&intcode, std.testing.failing_allocator);
    try comp.execUntilHalt();
    expectEqual(intcode[5], 9801);
}

test "test exec with different param mode" {
    var intcode = [_]Instr{ 1002, 4, 3, 4, 33 };
    var comp = IntcodeComputer.init(&intcode, std.testing.failing_allocator);
    try comp.execUntilHalt();
    expectEqual(intcode[4], 99);
}

test "test exec with negative integers" {
    var intcode = [_]Instr{ 1101, 100, -1, 4, 0 };
    var comp = IntcodeComputer.init(&intcode, std.testing.failing_allocator);
    try comp.execUntilHalt();
    expectEqual(intcode[4], 99);
}

test "test equal 1" {
    var intcode = [_]Instr{ 3, 9, 8, 9, 10, 9, 4, 9, 99, -1, 8 };
    var comp = IntcodeComputer.init(&intcode, std.testing.failing_allocator);
    comp.input = 8;
    try comp.execUntilHalt();
    expectEqual(comp.output.?, 1);
}

test "test equal 2" {
    var intcode = [_]Instr{ 3, 9, 8, 9, 10, 9, 4, 9, 99, -1, 8 };
    var comp = IntcodeComputer.init(&intcode, std.testing.failing_allocator);
    comp.input = 13;
    try comp.execUntilHalt();
    expectEqual(comp.output.?, 0);
}

test "test less than 1" {
    var intcode = [_]Instr{ 3, 9, 7, 9, 10, 9, 4, 9, 99, -1, 8 };
    var comp = IntcodeComputer.init(&intcode, std.testing.failing_allocator);
    comp.input = 5;
    try comp.execUntilHalt();
    expectEqual(comp.output.?, 1);
}

test "test less than 2" {
    var intcode = [_]Instr{ 3, 9, 7, 9, 10, 9, 4, 9, 99, -1, 8 };
    var comp = IntcodeComputer.init(&intcode, std.testing.failing_allocator);
    comp.input = 20;
    try comp.execUntilHalt();
    expectEqual(comp.output.?, 0);
}

test "test equal immediate" {
    var intcode = [_]Instr{ 3, 3, 1108, -1, 8, 3, 4, 3, 99 };
    var comp = IntcodeComputer.init(&intcode, std.testing.failing_allocator);
    comp.input = 8;
    try comp.execUntilHalt();
    expectEqual(comp.output.?, 1);
}

test "test less than immediate" {
    var intcode = [_]Instr{ 3, 3, 1107, -1, 8, 3, 4, 3, 99 };
    var comp = IntcodeComputer.init(&intcode, std.testing.failing_allocator);
    comp.input = 3;
    try comp.execUntilHalt();
    expectEqual(comp.output.?, 1);
}

test "quine" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var intcode = [_]Instr{ 109, 1, 204, -1, 1001, 100, 1, 100, 1008, 100, 16, 101, 1006, 101, 0, 99 };
    var comp = IntcodeComputer.init(&intcode, allocator);
    try comp.execUntilHalt();
}

test "big number" {
    var intcode = [_]Instr{ 1102, 34915192, 34915192, 7, 4, 7, 99, 0 };
    var comp = IntcodeComputer.init(&intcode, std.testing.failing_allocator);
    try comp.execUntilHalt();
}

test "big number 2" {
    var intcode = [_]Instr{ 104, 1125899906842624, 99 };
    var comp = IntcodeComputer.init(&intcode, std.testing.failing_allocator);
    try comp.execUntilHalt();

    expectEqual(comp.output.?, 1125899906842624);
}

pub const Color = enum {
    White,
    Black,

    const Self = @This();

    pub fn fromInstr(val: Instr) !Self {
        return switch (val) {
            0 => .Black,
            1 => .White,
            else => return error.InvalidColor,
        };
    }

    pub fn toInstr(self: Self) Instr {
        return switch (self) {
            .Black => 0,
            .White => 1,
        };
    }

    pub fn toStr(self: Self) []const u8 {
        return switch (self) {
            .Black => ".",
            .White => "#",
        };
    }
};

test "color" {
    expectEqual(Color.Black, try Color.fromInstr(0));
    expectEqual(@intCast(Instr, 0), Color.Black.toInstr());
}

pub const Panel = struct {
    pos_map: AutoHashMap(Pos, Color),

    const Self = @This();

    pub fn init(alloc: *Allocator) Self {
        return Self{
            .pos_map = AutoHashMap(Pos, Color).init(alloc),
        };
    }

    pub fn isPainted(self: Self, p: Pos) bool {
        return self.pos_map.get(p) != null;
    }

    pub fn getColor(self: Self, p: Pos) Color {
        if (self.pos_map.get(p)) |kv| {
            return kv.value;
        } else {
            return Color.Black;
        }
    }

    pub fn paint(self: *Self, p: Pos, col: Color) !void {
        _ = try self.pos_map.put(p, col);
    }

    pub fn print(self: Self) void {
        // find out boundaries
        var max_x: ?isize = null;
        var min_x: ?isize = null;
        var max_y: ?isize = null;
        var min_y: ?isize = null;

        var iter = self.pos_map.iterator();
        while (iter.next()) |kv| {
            const pos = kv.key;

            if (max_x) |max| {
                if (pos.x > max)
                    max_x = pos.x;
            } else {
                max_x = pos.x;
            }

            if (min_x) |max| {
                if (pos.x < max)
                    min_x = pos.x;
            } else {
                min_x = pos.x;
            }

            if (max_y) |max| {
                if (pos.y > max)
                    max_y = pos.y;
            } else {
                max_y = pos.y;
            }

            if (min_y) |max| {
                if (pos.y < max)
                    min_y = pos.y;
            } else {
                min_y = pos.y;
            }
        }

        self.printArea(Pos.p(min_x.?, max_y.?), Pos.p(max_x.?, min_y.?));
    }

    pub fn printArea(self: Self, start: Pos, end: Pos) void {
        var i: isize = start.y;
        while (i >= end.y) : (i -= 1) {
            var j: isize = start.x;
            while (j <= end.x) : (j += 1) {
                std.debug.warn("{}", .{self.getColor(Pos.p(start.x + j, start.y + i)).toStr()});
            }
            std.debug.warn("\n", .{});
        }
    }
};

test "panel" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    var panel = Panel.init(allocator);
    expectEqual(Color.Black, panel.getColor(Pos.p(0, 0)));
    expectEqual(false, panel.isPainted(Pos.p(0, 0)));

    try panel.paint(Pos.p(0, 0), Color.Black);
    expectEqual(Color.Black, panel.getColor(Pos.p(0, 0)));
    expectEqual(true, panel.isPainted(Pos.p(0, 0)));
}

pub const Pos = struct {
    x: isize,
    y: isize,

    const Self = @This();

    fn p(x: isize, y: isize) Self {
        return Self{
            .x = x,
            .y = y,
        };
    }
};

pub const Direction = enum {
    North,
    South,
    West,
    East,
};

pub const PaintRobot = struct {
    comp: IntcodeComputer,
    pos: Pos,
    dir: Direction,
    panel: Panel,

    const Self = @This();

    pub fn init(alloc: *Allocator, comp: IntcodeComputer) Self {
        return Self{
            .comp = comp,
            .pos = Pos.p(0, 0),
            .dir = .North,
            .panel = Panel.init(alloc),
        };
    }

    pub fn moveOne(self: *Self) void {
        switch (self.dir) {
            .North => self.pos.y += 1,
            .South => self.pos.y -= 1,
            .West => self.pos.x -= 1,
            .East => self.pos.x += 1,
        }
    }

    pub fn turnLeft(self: *Self) void {
        self.dir = switch (self.dir) {
            .North => .West,
            .South => .East,
            .West => .South,
            .East => .North,
        };
    }

    pub fn turnRight(self: *Self) void {
        self.dir = switch (self.dir) {
            .North => .East,
            .South => .West,
            .West => .North,
            .East => .South,
        };
    }

    pub fn paint(self: *Self) !void {
        try self.panel.paint(Pos.p(0, 0), Color.White);

        while (self.comp.state != .Stopped) {
            const col = self.panel.getColor(self.pos).toInstr();
            self.comp.input = col;

            try self.comp.execUntilHalt();
            const new_col = self.comp.output orelse return error.NoOutput;
            self.comp.output = null;
            const new_col_as_color = try Color.fromInstr(new_col);
            try self.panel.paint(self.pos, new_col_as_color);

            try self.comp.execUntilHalt();
            const new_dir = self.comp.output orelse return error.NoOutput;
            self.comp.output = null;

            switch (new_dir) {
                0 => self.turnLeft(),
                1 => self.turnRight(),
                else => return error.InvalidDirection,
            }
            self.moveOne();
        }
    }
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    const input_file = try std.fs.cwd().openFile("input11.txt", .{});
    var input_stream = input_file.reader();
    var buf: [1024]u8 = undefined;
    var ints = std.ArrayList(Instr).init(allocator);

    // read amp intcode into an int arraylist
    while (try input_stream.readUntilDelimiterOrEof(&buf, ',')) |item| {
        // add an empty element to the input file because I don't want to modify
        // this to discard newlines
        try ints.append(std.fmt.parseInt(Instr, item, 10) catch -1);
    }

    // run
    var comp = IntcodeComputer.init(ints.items, allocator);
    var robot = PaintRobot.init(allocator, comp);

    const painted_panels = try robot.paint();
    robot.panel.print();
}
