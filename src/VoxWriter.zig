const std = @import("std");
const rl = @import("raylib");

const Self = @This();

const Voxel = struct {
    position: rl.Vector3,
    color_idx: usize,
};

const Chunk = struct {
    tag: []const u8,
    data: []const u8,
    children: []const Chunk = &.{},
};

voxels: std.array_list.Managed(Voxel),
colors: std.array_list.Managed(rl.Color),
gpa: std.mem.Allocator,

pub fn init(gpa: std.mem.Allocator) Self {
    return .{ .voxels = .init(gpa), .colors = .init(gpa), .gpa = gpa };
}

pub fn deinit(self: Self) void {
    self.voxels.deinit();
    self.colors.deinit();
}

pub fn addVox(self: *Self, position: rl.Vector3, color: rl.Color) !void {
    var colorfound: ?usize = null;
    for (self.colors.items, 0..) |v, i| {
        if (rl.ColorIsEqual(v, color)) {
            colorfound = i;
            break;
        }
    }

    if (colorfound) |color_idx| {
        try self.voxels.append(.{ .position = position, .color_idx = color_idx + 1 });
    } else {
        try self.colors.append(color);
        try self.voxels.append(.{ .position = position, .color_idx = self.colors.items.len });
    }
}

pub fn writeFile(self: Self, filename: []const u8) !void {
    const file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();

    _ = try file.write("VOX ");
    try writeInt(file, 150);

    const box = voxBoundingBox(self.voxels.items);
    const size = [3]u32{
        @intFromFloat(@abs(box[0].x - box[1].x)),
        @intFromFloat(@abs(box[0].y - box[1].y)),
        @intFromFloat(@abs(box[0].z - box[1].z)),
    };

    var xyzi = std.array_list.Managed(u32).init(self.gpa);
    try xyzi.append(@intCast(self.voxels.items.len));
    for (self.voxels.items) |vox| {
        try xyzi.append(@bitCast([4]u8{
            @intFromFloat(vox.position.x - box[0].x),
            @intFromFloat(vox.position.y - box[0].y),
            @intFromFloat(vox.position.z - box[0].z),
            @intCast(vox.color_idx),
        }));
    }

    var rgba = std.mem.zeroes([256]u32);
    for (self.colors.items, 0..) |color, i| {
        rgba[i] = @bitCast([4]u8{
            @intCast(color.r),
            @intCast(color.g),
            @intCast(color.b),
            @intCast(color.a),
        });
    }

    const mainchunk = Chunk{
        .tag = "MAIN",
        .data = "",
        .children = &[_]Chunk{
            // Chunk{
            //     .tag = "PACK",
            //     .data = toCharArray(&[_]i32{1}),
            // },
            Chunk{
                .tag = "SIZE",
                .data = toCharArray(&size),
            },
            Chunk{
                .tag = "XYZI",
                .data = toCharArray(xyzi.items),
            },
            Chunk{
                .tag = "RGBA",
                .data = toCharArray(&rgba),
            },
        },
    };
    try writeChunk(file, mainchunk);
}

fn writeInt(file: std.fs.File, val: u32) !void {
    _ = try file.write(&@as([4]u8, @bitCast(val)));
}

fn toCharArray(intarr: []const u32) []const u8 {
    return @as([]const u8, @ptrCast(intarr));
}

fn writeChunk(file: std.fs.File, chunk: Chunk) !void {
    std.debug.assert(chunk.tag.len == 4);
    _ = try file.write(chunk.tag);
    try writeInt(file, @intCast(chunk.data.len));

    var children_size: usize = 0;
    for (chunk.children) |child| children_size += measureChunk(child);
    try writeInt(file, @intCast(children_size));

    _ = try file.write(chunk.data);
    for (chunk.children) |child| try writeChunk(file, child);
}

fn measureChunk(chunk: Chunk) usize {
    var children_size: usize = 0;
    for (chunk.children) |child| children_size += measureChunk(child);
    return 12 + chunk.data.len + children_size;
}

pub fn voxBoundingBox(haystack: []const Voxel) [2]rl.Vector3 {
    var begin = haystack[0].position;
    var end = rl.Vector3Add(haystack[0].position, rl.Vector3One());
    for (haystack) |vox| {
        begin = rl.Vector3Min(begin, vox.position);
        end = rl.Vector3Max(end, rl.Vector3Add(vox.position, rl.Vector3One()));
    }
    return .{ begin, end };
}
