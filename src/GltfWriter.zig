const std = @import("std");

const Array3d = @import("raylib.zig").Array3d;
const cast = @import("raylib.zig").cast;
const rl = @import("raylib.zig").rl;

const Self = @This();

const Voxel = struct {
    position: rl.Vector3,
    color_idx: usize,
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

    const Scene = struct { nodes: []const i32 };
    const Node = struct { mesh: i32 };
    const Primitive = struct { attributes: struct { POSITION: i32 }, indices: i32 };
    const Mesh = struct { primitives: []const Primitive };
    const Buffer = struct { uri: []const u8, byteLength: usize };
    const BufferView = struct { buffer: i32, byteOffset: usize, byteLength: usize, target: i32 };
    const Accessor = struct {
        bufferView: i32,
        byteOffset: i32,
        componentType: i32,
        count: i32,
        type: []const u8,
        max: []const f32,
        min: []const f32,
    };

    const indices, const vertices = try self.buildIndicesAndVerticesMock();
    defer indices.deinit();
    defer vertices.deinit();

    var indices_max: u32 = 0;
    var indices_min: u32 = std.math.maxInt(u32);
    for (indices.items) |i| {
        indices_max = @max(indices_max, i[0], i[1], i[2]);
        indices_min = @min(indices_min, i[0], i[1], i[2]);
    }
    var vertices_max = [3]f32{ 0, 0, 0 };
    for (vertices.items) |i| {
        vertices_max[0] = @max(vertices_max[0], i[0]);
        vertices_max[1] = @max(vertices_max[1], i[1]);
        vertices_max[2] = @max(vertices_max[2], i[2]);
    }

    const indices_u8 = @as([]u8, @ptrCast(indices.items));
    const vertices_u8 = @as([]u8, @ptrCast(vertices.items));
    const vertices_extra_offset = @mod(indices_u8.len, @sizeOf(f32));
    const buffer = try self.gpa.alloc(u8, indices_u8.len + vertices_extra_offset + vertices_u8.len);
    defer self.gpa.free(buffer);

    for (buffer) |*v| v.* = 0;
    @memcpy(buffer[0..indices_u8.len], indices_u8);
    @memcpy(buffer[indices_u8.len + vertices_extra_offset ..  indices_u8.len + vertices_extra_offset + vertices_u8.len], vertices_u8);

    var buffer_b64_writer = std.Io.Writer.Allocating.init(self.gpa);
    defer buffer_b64_writer.deinit();

    try buffer_b64_writer.writer.print("data:application/octet-stream;base64,", .{});
    try std.base64.standard.Encoder.encodeWriter(&buffer_b64_writer.writer, buffer);

    var buffer_b64 = buffer_b64_writer.toArrayList();
    defer buffer_b64.deinit(self.gpa);
    std.debug.print("{s}\n", .{buffer_b64.items});

    const gltf = .{
        .asset = .{ .version = "2.0" },
        .scene = 0,
        .scenes = [_]Scene{.{ .nodes = &[_]i32{0} }},
        .nodes = [_]Node{.{ .mesh = 0 }},
        .meshes = [_]Mesh{
            .{
                .primitives = &[_]Primitive{
                    .{
                        .attributes = .{ .POSITION = 1 },
                        .indices = 0,
                    },
                },
            },
        },
        .buffers = [_]Buffer{.{
            .uri = buffer_b64.items,
            .byteLength = buffer.len,
        }},
        .bufferViews = [_]BufferView{
            .{
                .buffer = 0,
                .byteOffset = 0,
                .byteLength = indices_u8.len,
                .target = 34963,
            },
            .{
                .buffer = 0,
                .byteOffset = indices_u8.len + vertices_extra_offset,
                .byteLength = vertices_u8.len,
                .target = 34962,
            },
        },
        .accessors = [_]Accessor{
            .{
                .bufferView = 0,
                .byteOffset = 0,
                .componentType = 5123, //unsigned short 16
                .count = 3,
                .type = "SCALAR",
                .max = &[_]f32{@floatFromInt(indices_max)},
                .min = &[_]f32{@floatFromInt(indices_min)},
            },
            .{
                .bufferView = 1,
                .byteOffset = 0,
                .componentType = 5126, //signed float 32
                .count = 3,
                .type = "VEC3",
                .max = &vertices_max,
                .min = &[_]f32{ 0.0, 0.0, 0.0 },
            },
        },
    };

    var buffer2: [0x1000]u8 = undefined;
    const json = try std.fmt.bufPrint(&buffer2, "{f}", .{std.json.fmt(gltf, .{ .whitespace = .indent_2 })});
    try file.writeAll(json);
}

fn buildIndicesAndVertices(self: Self) !struct { std.array_list.Managed([3]u32), std.array_list.Managed([3]f32) } {
    const box = voxBoundingBox(self.voxels.items);
    const size = [3]usize{
        @intFromFloat(@abs(box[1].x - box[0].x)),
        @intFromFloat(@abs(box[1].y - box[0].y)),
        @intFromFloat(@abs(box[1].z - box[0].z)),
    };

    const voxels = try Array3d(bool).init(self.gpa, size, false);
    defer voxels.deinit();
    const vertexes = try Array3d(?u32).init(self.gpa, .{ size[0] + 1, size[1] + 1, size[2] + 1 }, null);
    defer vertexes.deinit();

    for (self.voxels.items) |vox| {
        voxels.set(cast(usize, vox.position.x - box[0].x), @intFromFloat(vox.position.y - box[0].y), @intFromFloat(vox.position.z - box[0].z), true);
    }

    var vert_idx: u32 = 0;
    for (0..vertexes.size[2]) |z| {
        for (0..vertexes.size[1]) |y| {
            for (0..vertexes.size[0]) |x| {
                const xi = @as(i32, @intCast(x));
                const yi = @as(i32, @intCast(y));
                const zi = @as(i32, @intCast(z));
                if (canPlaceVertex(voxels, xi, yi, zi)) {
                    vertexes.set(x, y, z, vert_idx);
                    vert_idx += 1;
                }
            }
        }
    }

    var indices = std.array_list.Managed([3]u32).init(self.gpa); //triangle indices
    for (0..voxels.size[2]) |z| {
        for (0..voxels.size[1]) |y| {
            for (0..voxels.size[0]) |x| {
                const xi = @as(i32, @intCast(x));
                const yi = @as(i32, @intCast(y));
                const zi = @as(i32, @intCast(z));

                const face_conditions = [_]struct { cond: [3]i32, face: [4][3]i32 }{
                    .{ .cond = .{ -1, 0, 0 }, .face = .{ .{ 0, 0, 0 }, .{ 0, 1, 0 }, .{ 0, 0, 1 }, .{ 0, 1, 1 } } },
                    .{ .cond = .{ 0, -1, 0 }, .face = .{ .{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 0, 0, 1 }, .{ 1, 0, 1 } } },
                    .{ .cond = .{ 0, 0, -1 }, .face = .{ .{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 1, 1, 0 } } },
                    .{ .cond = .{ 1, 0, 0 }, .face = .{ .{ 1, 0, 0 }, .{ 1, 1, 0 }, .{ 1, 0, 1 }, .{ 1, 1, 1 } } },
                    .{ .cond = .{ 0, 1, 0 }, .face = .{ .{ 0, 1, 0 }, .{ 1, 1, 0 }, .{ 0, 1, 1 }, .{ 1, 1, 1 } } },
                    .{ .cond = .{ 0, 0, 1 }, .face = .{ .{ 0, 0, 1 }, .{ 1, 0, 1 }, .{ 0, 1, 1 }, .{ 1, 1, 1 } } },
                };

                for (face_conditions) |face_condition| {
                    const cond = face_condition.cond;
                    const face = face_condition.face;
                    if (voxels.get(xi + cond[0], yi + cond[1], zi + cond[2]) == null) {
                        try indices.append(.{
                            vertexes.get(xi + face[0][0], yi + face[0][1], zi + face[0][2]).?.?,
                            vertexes.get(xi + face[1][0], yi + face[1][1], zi + face[1][2]).?.?,
                            vertexes.get(xi + face[2][0], yi + face[2][1], zi + face[2][2]).?.?,
                        });
                        try indices.append(.{
                            vertexes.get(xi + face[1][0], yi + face[1][1], zi + face[1][2]).?.?,
                            vertexes.get(xi + face[2][0], yi + face[2][1], zi + face[2][2]).?.?,
                            vertexes.get(xi + face[3][0], yi + face[3][1], zi + face[3][2]).?.?,
                        });
                    }
                }
            }
        }
    }

    var vertex = std.array_list.Managed([3]f32).init(self.gpa); //vertex xyz
    for (0..vertexes.size[2]) |z| {
        for (0..vertexes.size[1]) |y| {
            for (0..vertexes.size[0]) |x| {
                if (vertexes.get(@intCast(x), @intCast(y), @intCast(z))) |_| {
                    try vertex.append(.{ @floatFromInt(x), @floatFromInt(y), @floatFromInt(z) });
                }
            }
        }
    }

    return .{ indices, vertex };
}

fn buildIndicesAndVerticesMock(self: Self) !struct { std.array_list.Managed([3]u16), std.array_list.Managed([3]f32) } {
    var indices = std.array_list.Managed([3]u16).init(self.gpa); //triangle indices
    var vertices = std.array_list.Managed([3]f32).init(self.gpa); //vertex xyz
    try indices.append(.{ 0, 1, 2 });
    try vertices.append(.{ 0.0, 0.0, 0.0 });
    try vertices.append(.{ 0.0, 1.0, 0.0 });
    try vertices.append(.{ 1.0, 0.0, 0.0 });
    return .{ indices, vertices };
}

fn voxBoundingBox(haystack: []const Voxel) [2]rl.Vector3 {
    var begin = haystack[0].position;
    var end = rl.Vector3Add(haystack[0].position, rl.Vector3One());
    for (haystack) |vox| {
        begin = rl.Vector3Min(begin, vox.position);
        end = rl.Vector3Max(end, rl.Vector3Add(vox.position, rl.Vector3One()));
    }
    return .{ begin, end };
}

fn canPlaceVertex(voxels: Array3d(bool), x: i32, y: i32, z: i32) bool {
    const neighbors = [_][3]i32{
        .{ 0, 0, 0 },   .{ -1, 0, 0 },  .{ 0, -1, 0 },  .{ 0, 0, -1 },
        .{ -1, -1, 0 }, .{ 0, -1, -1 }, .{ -1, 0, -1 }, .{ -1, -1, -1 },
    };
    var hasAtLeastOne = false;
    var isSurrounded = true;
    for (neighbors) |pos| {
        if (voxels.get(x + pos[0], y + pos[1], z + pos[2]) == true) {
            hasAtLeastOne = true;
        } else {
            isSurrounded = false;
        }
    }

    return hasAtLeastOne and !isSurrounded;
}
