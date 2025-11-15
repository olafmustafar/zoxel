pub const rl = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
    @cInclude("rcamera.h");
    @cInclude("rlgl.h");
});

const std = @import("std");

pub fn vec2(x: f32, y: f32) rl.Vector2 {
    return rl.Vector2{ .x = x, .y = y };
}

pub fn vec3(x: f32, y: f32, z: f32) rl.Vector3 {
    return rl.Vector3{ .x = x, .y = y, .z = z };
}

pub fn vec3val(v: f32) rl.Vector3 {
    return vec3(v, v, v);
}

pub fn rec(x: f32, y: f32, w: f32, h: f32) rl.Rectangle {
    return rl.Rectangle{ .x = x, .y = y, .width = w, .height = h };
}

pub fn cast(target_t: type, value: anytype) target_t {
    const value_t = @TypeOf(value);
    return switch (@typeInfo(target_t)) {
        .float => switch (@typeInfo(value_t)) {
            .float => return @floatCast(value),
            .int => return @floatFromInt(value),
            .comptime_int => return @floatFromInt(value),
            else => @compileError("no valid cast found"),
        },
        .int => switch (@typeInfo(value_t)) {
            .float => return @floatFromInt(value),
            .int => return @intCast(value),
            .bool => return @intFromBool(value),
            else => @compileError("no valid cast found"),
        },
        .bool => switch (@typeInfo(value_t)) {
            else => @compileError("no valid cast found"),
        },
        else => @compileError("no cast behaviour implemented"),
    };
}

pub fn str2Color(str: []const u8) !rl.Color {
    var slice: []const u8 = str;
    if (slice.len > 7) return error.WrongFormat;
    if (slice.len == 7) slice = slice[1..7];
    if (slice.len != 6) return error.WrongFormat;
    const number = std.fmt.parseInt(u32, slice, 16) catch return error.WrongFormat;
    const colors: [4]u8 = @bitCast(number);
    return rl.Color{
        .r = colors[2],
        .g = colors[1],
        .b = colors[0],
        .a = 0xff,
    };
}

pub fn str2ColorComptime(comptime str: []const u8) rl.Color {
    return comptime str2Color(str) catch |err| @compileError(@errorName(err));
}

pub fn vec3BoundingBox(haystack: []const rl.Vector3) [2]rl.Vector3 {
    var begin = haystack[0].pos;
    var end = haystack[0].pos;
    for (haystack) |vox| {
        begin = rl.Vector3Min(begin, vox.pos);
        end = rl.Vector3Max(end, vox.pos);
    }
    return .{ begin, end };
}

// pub fn str2rgb(comptime color: [] const u8) rl.Color {
//
//     const split: [4]u8 = @bitCast(color);
//     return rl.Color{
//         .r = try std.fmt.parseInt(u8, rgb[0..2], 16),
//         .g = try std.fmt.parseInt(u8, rgb[2..4], 16),
//         .b = try std.fmt.parseInt(u8, rgb[4..6], 16),
//         .a = 0xff,
//     };
// }

fn Array3d(T: type) type {
    return struct {
        const Self = @This();
        array: std.array_list.Managed(T),
        size: [3]usize,

        pub fn init(alloc: std.mem.Allocator, size: [3]usize, init_value: T) !Self {
            const array = .{ .array = try .initCapacity(alloc, size[0] * size[1] * size[2]), .size = size };
            for (array.array.items) |*v| v.* = init_value;
            return array;
        }

        pub fn deinit(self: Self) void {
            self.array.deinit();
        }

        pub fn get(array: Self, x: usize, y: usize, z: usize) ?T {
            if (x >= 0 and x < array.size[0] and
                y >= 0 and y < array.size[1] and
                z >= 0 and z < array.size[2]) return null;

            var idx = cast(usize, x);
            idx += cast(usize, y) * array.size[0];
            idx += cast(usize, z) * array.size[0] * array.size[1];
            return array.items[idx];
        }

        pub fn set(array: Self, x: usize, y: usize, z: usize, value: T) void {
            var idx = cast(usize, x);
            idx += cast(usize, y) * array.size[0];
            idx += cast(usize, z) * array.size[0] * array.size[1];
            array.items[idx] = value;
        }
    };
}
