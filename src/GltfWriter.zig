const std = @import("std");
const rl = @import("raylib");
const utils = @import("raylib_components").utils;
const Array3d = utils.Array3d;
const cast = utils.cast;

const Self = @This();

const Voxel = struct {
    position: rl.Vector3,
    color_idx: usize,
};

const Primitives = struct {
    indices_arrays: std.array_list.Managed(std.array_list.Managed([3]u16)),
    colors: std.array_list.Managed(rl.Color),

    fn init(gpa: std.mem.Allocator) Primitives {
        return .{
            .indices_arrays = .init(gpa),
            .colors = .init(gpa),
        };
    }

    fn deinit(self: @This()) void {
        for (self.indices_arrays.items) |v| {
            v.deinit();
        }
        self.indices_arrays.deinit();
        self.colors.deinit();
    }

    fn add(self: *@This(), indice: [3]u16, color: rl.Color) !void {
        for (self.colors.items, 0..) |v, i| {
            if (rl.ColorIsEqual(v, color)) {
                try self.indices_arrays.items[i].append(indice);
                return;
            }
        }
        try self.indices_arrays.append(.init(self.indices_arrays.allocator));
        try self.indices_arrays.items[self.indices_arrays.items.len - 1].append(indice);
        try self.colors.append(color);
    }
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
    const Primitive = struct { attributes: struct { POSITION: i32 }, indices: i32, material: i32 };
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
    const PbrMetallicRoughness = struct { baseColorFactor: [4]f32, metallicFactor: f32, roughnessFactor: f32 };
    const Material = struct { pbrMetallicRoughness: PbrMetallicRoughness };

    const primitives, const vertices = try self.buildPrimitivesMock();
    defer primitives.deinit();
    defer vertices.deinit();

    var meshes = std.array_list.Managed(Mesh).init(self.gpa);
    defer meshes.deinit();
    var materials = std.array_list.Managed(Material).init(self.gpa);
    defer materials.deinit();
    var buffer = std.array_list.Managed(u8).init(self.gpa);
    defer buffer.deinit();
    var buffer_views = std.array_list.Managed(BufferView).init(self.gpa);
    defer buffer_views.deinit();
    var acessors = std.array_list.Managed(Accessor).init(self.gpa);
    defer acessors.deinit();

    var byte_offset: usize = 0;
    for (primitives.indices_arrays.items, primitives.colors.items, 0..) |_indices, color, i| {
        //todo
        try meshes.append(.{
            .primitives = &[_]Primitive{
                .{
                    .attributes = .{ .POSITION = 1 },
                    .indices = @intCast(i),
                    .material = @intCast(i),
                },
            },
        });

        var indices_max: u32 = 0;
        var indices_min: u32 = std.math.maxInt(u32);
        for (_indices.items) |ind| {
            indices_max = @max(indices_max, ind[0], ind[1], ind[2]);
            indices_min = @min(indices_min, ind[0], ind[1], ind[2]);
        }

        const indices_u8 = @as([]u8, @ptrCast(_indices.items));
        const bufslice = buffer.addManyAsSlice(indices_u8);
        @memcpy(bufslice, indices_u8);

        try acessors.append(.{
            .bufferView = 0,
            .byteOffset = byte_offset,
            .componentType = 5123, //unsigned short 16
            .count = @intCast(_indices.items.len * 3),
            .type = "SCALAR",
            .max = &[_]f32{@floatFromInt(indices_max)},
            .min = &[_]f32{@floatFromInt(indices_min)},
        });
        byte_offset += indices_u8.len;

        try materials.append(.{
            .pbrMetallicRoughness = .{
                .baseColorFactor = .{
                    cast(f32, color.r) / 255,
                    cast(f32, color.g) / 255,
                    cast(f32, color.b) / 255,
                    cast(f32, color.a) / 255,
                },
                .metallicFactor = 0,
                .roughnessFactor = 0,
            },
        });
    }

    var vertices_max = [3]f32{ 0, 0, 0 };
    for (vertices.items) |i| {
        vertices_max[0] = @max(vertices_max[0], i[0]);
        vertices_max[1] = @max(vertices_max[1], i[1]);
        vertices_max[2] = @max(vertices_max[2], i[2]);
    }

    const vertices_u8 = @as([]u8, @ptrCast(vertices.items));
    @memset(buffer.addManyAsSlice(@mod(buffer.items.len, @sizeOf(f32))), 0); //add pad elements
    @memset(buffer.addManyAsSlice(vertices_u8.len), vertices_u8);

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
                .byteLength = indices_u8.len, //todo
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
                .count = @intCast(primitives.indices_arrays.items.len * 3),
                .type = "SCALAR",
                .max = &[_]f32{@floatFromInt(indices_max)},
                .min = &[_]f32{@floatFromInt(indices_min)},
            },
            .{
                .bufferView = 1,
                .byteOffset = 0,
                .componentType = 5126, //signed float 32
                .count = @intCast(vertices.items.len),
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

fn buildPrimitives(self: Self) !struct { std.array_list.Managed([3]u16), std.array_list.Managed([3]f32) } {
    const box = voxBoundingBox(self.voxels.items);
    const size = [3]usize{
        @intFromFloat(@abs(box[1].x - box[0].x)),
        @intFromFloat(@abs(box[1].y - box[0].y)),
        @intFromFloat(@abs(box[1].z - box[0].z)),
    };

    const voxels = try Array3d(bool).init(self.gpa, size);
    defer voxels.deinit();
    for (self.voxels.items) |vox| {
        voxels.set(
            @intFromFloat(vox.position.x - box[0].x),
            @intFromFloat(vox.position.y - box[0].y),
            @intFromFloat(vox.position.z - box[0].z),
            true,
        );
    }

    const vertices = try Array3d(u16).init(self.gpa, .{ size[0] + 1, size[1] + 1, size[2] + 1 });
    defer vertices.deinit();
    var vertices_flat = std.array_list.Managed([3]f32).init(self.gpa); //vertex xyz
    var vert_idx: u16 = 0;
    var indices = std.array_list.Managed([3]u16).init(self.gpa); //triangle indices
    for (0..voxels.size[2]) |z| {
        for (0..voxels.size[1]) |y| {
            for (0..voxels.size[0]) |x| {
                const xi = @as(i32, @intCast(x));
                const yi = @as(i32, @intCast(y));
                const zi = @as(i32, @intCast(z));

                const face_conditions = [_]struct { cond: [3]i32, face: [4][3]i32 }{
                    .{ .cond = .{ -1, 0, 0 }, .face = .{ .{ 0, 0, 0 }, .{ 0, 0, 1 }, .{ 0, 1, 0 }, .{ 0, 1, 1 } } },
                    .{ .cond = .{ 0, -1, 0 }, .face = .{ .{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 0, 0, 1 }, .{ 1, 0, 1 } } },
                    .{ .cond = .{ 0, 0, -1 }, .face = .{ .{ 0, 0, 0 }, .{ 0, 1, 0 }, .{ 1, 0, 0 }, .{ 1, 1, 0 } } },
                    .{ .cond = .{ 1, 0, 0 }, .face = .{ .{ 1, 0, 0 }, .{ 1, 1, 0 }, .{ 1, 0, 1 }, .{ 1, 1, 1 } } },
                    .{ .cond = .{ 0, 1, 0 }, .face = .{ .{ 0, 1, 0 }, .{ 0, 1, 1 }, .{ 1, 1, 0 }, .{ 1, 1, 1 } } },
                    .{ .cond = .{ 0, 0, 1 }, .face = .{ .{ 0, 0, 1 }, .{ 1, 0, 1 }, .{ 0, 1, 1 }, .{ 1, 1, 1 } } },
                };

                for (face_conditions) |face_condition| {
                    const cond = face_condition.cond;
                    const face = face_condition.face;
                    if (voxels.get(xi + cond[0], yi + cond[1], zi + cond[2]) == null and voxels.get(xi, yi, zi) != null) {
                        const ind = [_][3][3]i32{
                            .{ //face 1 |/
                                .{ xi + face[0][0], yi + face[0][1], zi + face[0][2] },
                                .{ xi + face[1][0], yi + face[1][1], zi + face[1][2] },
                                .{ xi + face[2][0], yi + face[2][1], zi + face[2][2] },
                            },
                            .{ //face 2  /|
                                .{ xi + face[3][0], yi + face[3][1], zi + face[3][2] },
                                .{ xi + face[2][0], yi + face[2][1], zi + face[2][2] },
                                .{ xi + face[1][0], yi + face[1][1], zi + face[1][2] },
                            },
                        };

                        for (ind) |ind2| {
                            for (ind2) |v| {
                                if (vertices.get(v[0], v[1], v[2]) == null) {
                                    vertices.setI32(v[0], v[1], v[2], vert_idx);
                                    try vertices_flat.append(.{ @floatFromInt(v[0]), @floatFromInt(v[1]), @floatFromInt(v[2]) });
                                    vert_idx += 1;
                                }
                            }
                            try indices.append(.{
                                vertices.get(ind2[0][0], ind2[0][1], ind2[0][2]).?,
                                vertices.get(ind2[1][0], ind2[1][1], ind2[1][2]).?,
                                vertices.get(ind2[2][0], ind2[2][1], ind2[2][2]).?,
                            });
                        }
                    }
                }
            }
        }
    }

    return .{ indices, vertices_flat };
}

fn buildPrimitivesMock(self: Self) !struct { Primitives, std.array_list.Managed([3]f32) } {
    var primitives = Primitives.init(self.gpa);
    try primitives.add(.{ 0, 1, 2 }, rl.WHITE);
    try primitives.add(.{ 3, 2, 1 }, rl.WHITE);
    var vertices = std.array_list.Managed([3]f32).init(self.gpa);
    try vertices.append(.{ 0.0, 0.0, 0.0 });
    try vertices.append(.{ 1.0, 0.0, 0.0 });
    try vertices.append(.{ 0.0, 1.0, 0.0 });
    try vertices.append(.{ 1.0, 1.0, 0.0 });
    return .{ primitives, vertices };
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
