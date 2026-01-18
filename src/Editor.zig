const std = @import("std");
const VoxWriter = @import("VoxWriter.zig");
const GltfWriter = @import("GltfWriter.zig");
const VoxLoader = @import("VoxLoader.zig");
const rl = @import("raylib");
const utils = @import("raylib_components").utils;
const vec3 = utils.vec3;
const str2Color = utils.str2Color;
const Voxel = @import("Voxel.zig");

const CommandError = error{
    NotACommand,
    MissingArgument,
    WrongFormat,
    NotImplemented,
};

const Self = @This();

place_buffer: std.array_list.Managed(Voxel),
blocks: std.array_list.Managed(Voxel),

buffers: std.array_list.Managed(std.array_list.Managed(Voxel)),
buffer_selected: ?usize = null,

cursor: rl.Vector3 = vec3(0, 0, 0),
color: rl.Color = rl.BLACK,
rotation: f32 = 0,

visual_mode: bool = false,
visual_begin: rl.Vector3 = undefined,

gpa: std.mem.Allocator,

pub fn init(alloc: std.mem.Allocator) !Self {
    var self = Self{
        .blocks = .init(alloc),
        .buffers = .init(alloc),
        .place_buffer = .init(alloc),
        .gpa = alloc,
    };

    try self.buffers.append(.init(alloc));
    try self.buffers.items[0].append(.{ .pos = vec3(0, 0, 0), .color = self.color });
    try self.selectBuffer(0);
    return self;
}

pub fn deinit(self: *Self) void {
    self.blocks.deinit();
    self.place_buffer.deinit();
    for (self.buffers.items) |i| {
        i.deinit();
    }
    self.buffers.deinit();
}

pub fn replace(self: *Self) !void {
    if (self.visual_mode) {
        try self.applyOnVisualBlock(replaceVoxel);
        try self.switchVisualMode();
    } else {
        for (self.place_buffer.items) |vox| {
            try self.replaceVoxel(.{ .pos = rl.Vector3Add(vox.pos, self.cursor), .color = vox.color });
        }
    }
}

pub fn place(self: *Self) !void {
    if (self.visual_mode) {
        try self.applyOnVisualBlock(placeVoxel);
        try self.switchVisualMode();
    } else {
        for (self.place_buffer.items) |vox| {
            try self.placeVoxel(.{ .pos = rl.Vector3Add(vox.pos, self.cursor), .color = vox.color });
        }
    }
}

pub fn remove(self: *Self) !void {
    if (self.visual_mode) {
        try self.applyOnVisualBlockPos(removePos);
        try self.switchVisualMode();
    } else {
        for (self.place_buffer.items) |vox| {
            try self.removePos(rl.Vector3Add(vox.pos, self.cursor));
        }
    }
}

pub fn moveCursor(self: *Self, vec: rl.Vector3) void {
    const rotation = @round(self.rotation / 90) * 90;
    var position = rl.Vector3RotateByAxisAngle(vec, vec3(0, 1, 0), rl.DEG2RAD * rotation);
    position = vec3(@round(position.x), @round(position.y), @round(position.z));
    self.cursor = rl.Vector3Add(self.cursor, position);
}

pub fn rotate(self: *Self, vec: rl.Vector3) void {
    for (self.place_buffer.items) |*vox| {
        vox.pos = rl.Vector3RotateByAxisAngle(vox.pos, vec, rl.DEG2RAD * 90);
    }
}

pub fn switchVisualMode(self: *Self) !void {
    if (!self.visual_mode) {
        self.visual_begin = self.cursor;
    } else {
        self.cursor = self.visual_begin;
    }
    self.visual_mode = !self.visual_mode;
}

//go back to single block, non visual mode
pub fn clearMode(self: *Self) !void {
    if (self.visual_mode) {
        try self.switchVisualMode();
    }
    try self.selectBuffer(0);
}

pub fn copyHovering(self: *Self) !void {
    self.buffer_selected = null;
    if (self.visual_mode) {
        self.place_buffer.clearAndFree();
        const begin = rl.Vector3Min(self.visual_begin, self.cursor);
        const end = rl.Vector3Max(self.visual_begin, self.cursor);
        for (self.blocks.items) |block| {
            if (rl.Vector3Equals(rl.Vector3Clamp(block.pos, begin, end), block.pos) == 1) {
                var copy = block;
                copy.pos = rl.Vector3Subtract(copy.pos, self.visual_begin);
                try self.place_buffer.append(copy);
            }
        }
        try self.switchVisualMode();
    } else {
        for (self.blocks.items) |block| {
            if (rl.Vector3Equals(block.pos, self.cursor) == 1) {
                self.setColor(block.color);
                return;
            }
        }
    }
}

pub fn prevBuffer(self: *Self) !void {
    if (self.buffer_selected) |i| {
        try self.selectBuffer(@mod(self.buffers.items.len + i - 1, self.buffers.items.len));
    } else {
        try self.selectBuffer(self.buffers.items.len - 1);
    }
}

pub fn nextBuffer(self: *Self) !void {
    if (self.buffer_selected) |i| {
        try self.selectBuffer(@mod(self.buffers.items.len + i + 1, self.buffers.items.len));
    } else {
        try self.selectBuffer(0);
    }
}

pub fn command(self: *Self, line: []const u8) !void {
    var it = std.mem.tokenizeScalar(u8, line, ' ');
    const cmd = it.next() orelse return CommandError.NotACommand;
    if (std.mem.eql(u8, cmd, "color")) {
        const rgb = it.next() orelse return CommandError.MissingArgument;
        const color = str2Color(rgb) catch return CommandError.WrongFormat;
        self.setColor(color);
    } else if (std.mem.eql(u8, cmd, "store")) {
        try self.buffers.append(try self.place_buffer.clone());
        try self.selectBuffer(self.buffers.items.len - 1);
    } else if (std.mem.eql(u8, cmd, "export")) {
        const filename = it.next() orelse return CommandError.MissingArgument;
        const dot = std.mem.find(u8, filename, ".") orelse return CommandError.WrongFormat;

        if (std.mem.eql(u8, filename[dot..], ".vox")) {
            var writer = VoxWriter.init(self.gpa);
            defer writer.deinit();
            for (self.blocks.items) |vox| {
                try writer.addVox(vox.pos, vox.color);
            }
            try writer.writeFile(filename);
        } else if (std.mem.eql(u8, filename[dot..], ".gltf")) {
            var writer = GltfWriter.init(self.gpa);
            defer writer.deinit();
            for (self.blocks.items) |vox| {
                try writer.addVox(vox.pos, vox.color);
            }
            try writer.writeFile(filename);
        } else return CommandError.NotImplemented;
    } else if (std.mem.eql(u8, cmd, "load")) {
        const filename = it.next() orelse return CommandError.MissingArgument;
        const dot = std.mem.find(u8, filename, ".") orelse return CommandError.WrongFormat;

        if (!std.mem.eql(u8, filename[dot..], ".vox")) {
            return CommandError.NotImplemented;
        }

        var threaded = std.Io.Threaded.init_single_threaded;
        const voxels = try VoxLoader.load(self.gpa, threaded.io(), filename);
        defer voxels.deinit();

        for (voxels.items) |vox| {
            try self.placeVoxel(vox);
        }
    } else {
        return CommandError.NotACommand;
    }
}

fn selectBuffer(self: *Self, index: usize) !void {
    self.buffer_selected = index;
    self.place_buffer.clearAndFree();
    for (self.buffers.items[index].items) |vox| {
        try self.place_buffer.append(vox);
    }
}

fn setColor(self: *Self, color: rl.Color) void {
    self.color = color;
    for (self.buffers.items[0].items) |*vox| {
        vox.color = color;
    }

    for (self.place_buffer.items) |*vox| {
        vox.color = color;
    }
}

fn replaceVoxel(self: *Self, vox: Voxel) !void {
    for (self.blocks.items) |*block| {
        if (rl.Vector3Equals(block.pos, vox.pos) == 1) {
            block.* = vox;
        }
    }
}

fn placeVoxel(self: *Self, vox: Voxel) !void {
    for (self.blocks.items) |block| {
        if (rl.Vector3Equals(block.pos, vox.pos) == 1) {
            return;
        }
    }
    try self.blocks.append(vox);
}

fn removePos(self: *Self, pos: rl.Vector3) !void {
    for (self.blocks.items, 0..) |block, i| {
        if (rl.Vector3Equals(block.pos, pos) == 1) {
            _ = self.blocks.swapRemove(i);
            return;
        }
    }
}

fn applyOnVisualBlockPos(self: *Self, fun: fn (self: *Self, pos: rl.Vector3) anyerror!void) !void {
    const Gen = struct {
        fn gen(sself: *Self, vox: Voxel) anyerror!void {
            return fun(sself, vox.pos);
        }
    };
    try applyOnVisualBlock(self, Gen.gen);
}

fn applyOnVisualBlock(self: *Self, fun: fn (self: *Self, vox: Voxel) anyerror!void) !void {
    var curr = self.visual_begin;
    const step = vec3(
        if (self.cursor.x <= self.visual_begin.x) -1 else 1,
        if (self.cursor.y <= self.visual_begin.y) -1 else 1,
        if (self.cursor.z <= self.visual_begin.z) -1 else 1,
    );
    while (rl.Vector3Equals(curr, self.cursor) == 0) {
        try fun(self, Voxel{ .pos = curr, .color = self.color });
        if (curr.x != self.cursor.x) {
            curr.x += step.x;
            continue;
        }
        curr.x = self.visual_begin.x;

        if (curr.y != self.cursor.y) {
            curr.y += step.y;
            continue;
        }
        curr.y = self.visual_begin.y;

        if (curr.z != self.cursor.z) {
            curr.z += step.z;
            continue;
        }
    }
    try fun(self, Voxel{ .pos = curr, .color = self.color });
}
