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

pub fn str2Color(rgb: []const u8) !rl.Color {
    if (rgb.len != 6) return error.WrongFormat;

    return rl.Color{
        .r = try std.fmt.parseInt(u8, rgb[0..2], 16),
        .g = try std.fmt.parseInt(u8, rgb[2..4], 16),
        .b = try std.fmt.parseInt(u8, rgb[4..6], 16),
        .a = 0xff,
    };
}

pub fn vec3BoundingBox(haystack: []const rl.Vector3) [2]rl.Vector3 {
    var begin = haystack[0].pos;
    var end = haystack[0].pos;
    for (haystack) |vox| {
        begin = rl.Vector3Min(begin, vox.pos);
        end = rl.Vector3Max(end, vox.pos);
    }
    return .{begin, end};
}
