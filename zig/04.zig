const std = @import("std");
const assert = std.debug.assert;

const Digit = usize;

fn valid(pw: usize) bool {
    var digits: [6]Digit = undefined;
    digits[5] = pw % 10;
    digits[4] = (pw / 10) % 10;
    digits[3] = (pw / 100) % 10;
    digits[2] = (pw / 1000) % 10;
    digits[1] = (pw / 10000) % 10;
    digits[0] = (pw / 100000) % 10;

    var i: usize = 0;
    var found_double = false;
    while (i < 5) : (i += 1) {
        // check for non-descending
        if (digits[i + 1] < digits[i]) {
            return false;
        }

        // check for double digit
        if (digits[i] == digits[i + 1]) {
            found_double = true;
        }
    }
    return found_double;
}

test "tests from website" {
    assert(valid(111111));
    assert(!valid(223450));
    assert(!valid(123789));
}

pub fn main() void {
    const min = 272091;
    const max = 815432;

    var x: usize = min;
    var count: usize = 0;
    while (x <= max) : (x += 1) {
        if (valid(x)) count += 1;
    }

    std.debug.warn("Count: {}\n", count);
}
