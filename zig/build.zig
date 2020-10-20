const Builder = @import("std").build.Builder;

const days = [_][]const u8{
    "01",
    "01_2",
    "02",
    "02_2",
    "03",
    "03_2",
    "04",
    "04_2",
    "05",
    "05_2",
    "06",
    "06_2",
    "07",
    "07_2",
    "08",
    "08_2",
    "09",
    "09_2",
    "10",
    "10_2",
    "11",
    "11_2",
    "12",
    "13",
    "13_2",
    "14",
    "16",
    "17",
    "19",
    "19_2",
};

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();

    inline for (days) |day| {
        const exe = b.addExecutable(day, day ++ ".zig");
        exe.setBuildMode(mode);

        const run_cmd = exe.run();

        const run_step = b.step(day, "Run " ++ day);
        run_step.dependOn(&run_cmd.step);
    }
}
