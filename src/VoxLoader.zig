const std = @import("std");
const Voxel = @import("Voxel.zig");
const rl = @import("raylib");
const vec3 = @import("raylib_components").utils.vec3;
const readSliceShort = std.Io.Reader.readSliceShort;

pub fn load(gpa: std.mem.Allocator, io: std.Io, filename: []const u8) !std.array_list.Managed(Voxel) {
    var buff: [0x10000]u8 = undefined;
    var file = try std.Io.Dir.cwd().openFile(io, filename, .{ .mode = .read_only });
    defer file.close(io);

    var reader = file.reader(io, &buff);
    const ioreader = &reader.interface;

    const header = try read([4]u8, ioreader);
    if (!std.mem.eql(u8, &header, "VOX ")) {
        return error.NotAVoxFile;
    }

    const version = try read(u32, ioreader);
    if (version != 200 and version != 150) {
        return error.IncompatibleVersion;
    }

    var xyzis = std.array_list.Managed([4]u8).init(gpa);
    defer xyzis.deinit();
    var rgbas = std.array_list.Managed([4]u8).init(gpa);
    defer rgbas.deinit();

    var s: usize = 0;
    while (true) {
        const tag = buff[0..4];
        s = try readSliceShort(ioreader, tag);
        if (s == 0) break;

        if (std.mem.eql(u8, tag, "MAIN")) {
            _ = try read([2]u32, ioreader);
        } else if (std.mem.eql(u8, tag, "PACK")) {
            _ = try read([2]u32, ioreader);
            const model_count = try read(u32, ioreader);
            if (model_count < 1) {
                return error.VoxNoModelsFound;
            }
            if (model_count > 1) {
                std.debug.print("Multiple models found {}, loading the first only.\n", .{model_count});
            }
        } else if (std.mem.eql(u8, tag, "SIZE")) {
            _ = try read([5]u32, ioreader);
        } else if (std.mem.eql(u8, tag, "XYZI")) {
            _ = try read([2]u32, ioreader);
            s = try read(u32, ioreader);
            for (0..s) |_| try xyzis.append(try read([4]u8, ioreader));
        } else if (std.mem.eql(u8, tag, "RGBA")) {
            _ = try read([2]u32, ioreader);
            for (0..256) |_| try rgbas.append(try read([4]u8, ioreader));
        } else {
            std.debug.print("Ignoreing unkwnown tag {s}\n", .{tag});
            const data_size = try read(u32, ioreader);
            const children_size = try read(u32, ioreader);
            const chars = buff[0 .. data_size + children_size];
            _ = try readSliceShort(ioreader, chars);
        }

        if (xyzis.items.len > 0 and rgbas.items.len > 0) break;
    }

    var voxels = std.array_list.Managed(Voxel).init(gpa);
    for (xyzis.items) |xyzi| {
        const rgba = rgbas.items[xyzi[3] - 1];
        try voxels.append(.{
            .pos = vec3(
                @floatFromInt(xyzi[0]),
                @floatFromInt(xyzi[1]),
                @floatFromInt(xyzi[2]),
            ),
            .color = .{ .r = rgba[0], .g = rgba[1], .b = rgba[2], .a = rgba[3] },
        });
    }

    return voxels;
}

fn read(comptime T: type, reader: *std.Io.Reader) !T {
    var t: T = undefined;
    _ = try readSliceShort(reader, @ptrCast(@alignCast(&t)));
    return t;
}
