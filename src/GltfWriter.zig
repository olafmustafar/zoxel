const std = @import("std");
const rl = @import("raylib.zig").rl;
const cast = @import("raylib.zig").cast;
const Array3d = @import("raylib.zig").Array3d;

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
    _ = self; // autofix
    const file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();

    const Scene = struct { nodes: []const i32 };
    const Node = struct { mesh: i32 };
    const Primitive = struct { attributes: struct { POSITION: i32 }, indices: i32 };
    const Mesh = struct { primitives: []const Primitive };
    const Buffer = struct { uri: []const u8, byteLength: i32 };
    const BufferView = struct { buffer: i32, byteOffset: i32, byteLength: i32, target: i32 };
    const Accessor = struct {
        bufferView: i32,
        byteOffset: i32,
        componentType: i32,
        count: i32,
        type: []const u8,
        max: []const i32,
        min: []const i32,
    };

    const indices, const vertices = buildIndicesAndVertices();
    defer indices.deinit();
    defer vertices.deinit();

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
            .uri = "data:application/octet-stream;base64,AAABAAIAAAAAAAAAAAAAAAAAAAAAAIA/AAAAAAAAAAAAAAAAAACAPwAAAAA=",
            .byteLength = 44,
        }},
        .bufferViews = [_]BufferView{
            .{
                .buffer = 0,
                .byteOffset = 0,
                .byteLength = 6,
                .target = 34963,
            },
            .{
                .buffer = 0,
                .byteOffset = 8,
                .byteLength = 36,
                .target = 34962,
            },
        },
        .accessors = [_]Accessor{ .{
            .bufferView = 0,
            .byteOffset = 0,
            .componentType = 5123,
            .count = 3,
            .type = "SCALAR",
            .max = &[_]i32{2},
            .min = &[_]i32{0},
        }, .{
            .bufferView = 1,
            .byteOffset = 0,
            .componentType = 5126,
            .count = 3,
            .type = "VEC3",
            .max = &[_]i32{ 1.0, 1.0, 0.0 },
            .min = &[_]i32{ 0.0, 0.0, 0.0 },
        } },
    };

    var buffer: [0x1000]u8 = undefined;
    const json = try std.fmt.bufPrint(&buffer, "{f}", .{std.json.fmt(gltf, .{ .whitespace = .indent_2 })});
    try file.writeAll(json);
}

fn buildIndicesAndVertices(self: Self) !struct { std.array_list.Managed([3]u32), std.array_list.Managed([3]f32) } {
    const box = voxBoundingBox(self.voxels.items);
    const size = [3]u32{
        @intFromFloat(@abs(box[0].x - box[1].x)),
        @intFromFloat(@abs(box[0].y - box[1].y)),
        @intFromFloat(@abs(box[0].z - box[1].z)),
    };

    const voxels = try Array3d(bool).init(self.gpa, size, false);
    defer voxels.deinit();
    const vertexes = try Array3d(?u32).init(self.gpa, rl.Vector3Sum(size, rl.Vector3One()), null);
    defer vertexes.deinit();

    for (self.voxels.items) |vox|
        voxels.set(vox.position.x, vox.position.y, vox.position.z, true);

    var vert_idx = 0;
    for (0..vertexes.size[2].len) |z| {
        for (0..vertexes.size[1].len) |y| {
            for (0..vertexes.size[0].len) |x| {
                if (canPlaceVertex(voxels, x, y, z)) {
                    vertexes.set(x, y, z, vert_idx);
                    vert_idx += 1;
                }
            }
        }
    }

    const indices = std.array_list.Managed([4]u32).init(self.gpa); //quad indices
    for (0..voxels.size[2].len) |z| {
        for (0..voxels.size[1].len) |y| {
            for (0..voxels.size[0].len) |x| {
                const conditions = [_]struct { condition: [3]u8, face: [4][3]u8 }{
                    .{ .condition = .{ -1, 0, 0 }, .face = .{ .{ -1, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 1, 0 }, .{ 0, 0, 1 }, .{ 0, 1, 1 } } },
                    .{ .condition = .{ 0, -1, 0 }, .face = .{ .{ 0, -1, 0 }, .{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 0, 0, 1 }, .{ 1, 0, 1 } } },
                    .{ .condition = .{ 0, 0, -1 }, .face = .{ .{ 0, 0, -1 }, .{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 1, 1, 0 } } },
                    .{ .condition = .{ 1, 0, 0 }, .face = .{ .{ 1, 0, 0 }, .{ 1, 0, 0 }, .{ 1, 1, 0 }, .{ 1, 0, 1 }, .{ 1, 1, 1 } } },
                    .{ .condition = .{ 0, 1, 0 }, .face = .{ .{ 0, 1, 0 }, .{ 0, 1, 0 }, .{ 1, 1, 0 }, .{ 0, 1, 1 }, .{ 1, 1, 1 } } },
                    .{ .condition = .{ 0, 0, 1 }, .face = .{ .{ 0, 0, 1 }, .{ 0, 0, 1 }, .{ 1, 0, 1 }, .{ 0, 1, 1 }, .{ 1, 1, 1 } } },
                };

                for (conditions) |cond| {
                    const condition = cond.condition;
                    const face = cond.face;
                    if (voxels.get(x + condition[0], y + condition[1], z + condition[2]) == null) {
                        indices.append(.{
                            vertexes.get(x + face[0][0], y + face[0][1], z + face[0][2]),
                            vertexes.get(x + face[1][0], y + face[1][1], z + face[1][2]),
                            vertexes.get(x + face[2][0], y + face[2][1], z + face[2][2]),
                            vertexes.get(x + face[3][0], y + face[3][1], z + face[3][2]),
                        });
                    }
                }
            }
        }
    }

    const vertex = std.array_list.Managed([3]f32).init(self.gpa); //vertex xyz
    return .{ indices, vertex };
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

fn canPlaceVertex(voxels: Array3d(bool), x: usize, y: usize, z: usize) bool {
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
