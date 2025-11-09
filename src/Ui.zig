const raylib = @import("raylib.zig");
const Editor = @import("Editor.zig");
const std = @import("std");
const rl = raylib.rl;
const vec3 = raylib.vec3;
const vec2 = raylib.vec2;
const rec = raylib.rec;
const cast = raylib.cast;
const s2color = raylib.str2ColorComptime;
const message_time  = 3.0;

const Self = @This();
camera: rl.Camera3D = .{
    .position = vec3(5, 5, 0),
    .target = rl.Vector3Zero(),
    .up = vec3(0, 1, 0),
    .fovy = 60,
    .projection = rl.CAMERA_PERSPECTIVE,
},
gui: rl.RenderTexture2D,
selector_pos: f32 = 0,

message: [:0]const u8,
message_timer: f32 = 0,

pub fn init() Self {
    return .{ .gui = rl.LoadRenderTexture(90, 90), .message = "" };
}

pub fn deinit(self: *Self) void {
    rl.UnloadRenderTexture(self.gui);
}

pub fn displayError(self: *Self, err: anyerror) void {
    self.message_timer = message_time;
    self.message = switch (err) {
        error.MissingArgument => "Missing argument!",
        error.NotACommand => "Not a command!",
        error.NotImplemented => "Not implemented!",
        error.WrongFormat => "Wrong argument format!",
        else => @errorName(err),
    };
}

pub fn render(self: *Self, editor: Editor, rotation: struct { ve: f32, ho: f32 }) void {
    rl.DrawRectangle(0, 0, @as(i32, @intCast(editor.buffers.items.len)) * self.gui.texture.width, self.gui.texture.height, rl.RAYWHITE);

    if (editor.buffer_selected) |idx_selected| {
        self.selector_pos = rl.Lerp(self.selector_pos, cast(f32, idx_selected) * cast(f32, self.gui.texture.width), 0.1);
        rl.DrawRectangle(@intFromFloat(self.selector_pos), 0, self.gui.texture.width, self.gui.texture.height, rl.GRAY);
    }

    for (editor.buffers.items, 0..) |buf, i| {
        {
            rl.BeginTextureMode(self.gui);
            defer rl.EndTextureMode();

            var begin = buf.items[0].pos;
            var end = buf.items[0].pos;
            for (buf.items) |vox| {
                begin = rl.Vector3Min(begin, vox.pos);
                end = rl.Vector3Max(end, vox.pos);
            }
            const middle = rl.Vector3Scale(rl.Vector3Add(end, begin), 0.5);

            self.camera.target = middle;
            const pos = &self.camera.position;
            const cameraDistance = calculateCameraDistance(self.camera.fovy, middle, end);

            pos.* = rl.Vector3Scale(vec3(1, 1, 0), cameraDistance);
            pos.* = rl.Vector3RotateByAxisAngle(pos.*, vec3(0, 0, 1), rotation.ve * rl.DEG2RAD);
            pos.* = rl.Vector3RotateByAxisAngle(pos.*, vec3(0, 1, 0), rotation.ho * rl.DEG2RAD);
            pos.* = rl.Vector3Add(pos.*, middle);
            rl.UpdateCamera(&self.camera, rl.CAMERA_CUSTOM);

            rl.BeginMode3D(self.camera);
            defer rl.EndMode3D();
            rl.ClearBackground(rl.BLANK);
            for (buf.items) |vox| {
                rl.DrawCube(vox.pos, 1, 1, 1, vox.color);
                rl.DrawCubeWires(vox.pos, 1, 1, 1, rl.RAYWHITE);
            }
        }

        const w: i32 = self.gui.texture.width;
        const h: i32 = self.gui.texture.height;
        const fw: f32 = @floatFromInt(w);
        const fh: f32 = @floatFromInt(h);
        rl.DrawTextureRec(self.gui.texture, rec(0, 0, fw, -fh), vec2(@as(f32, @floatFromInt(i)) * fw, 0), rl.RAYWHITE);
    }

    if (self.message_timer > 0) {
        self.message_timer = @max(self.message_timer - rl.GetFrameTime(), 0);
        const point_size = 20;
        const x = @divFloor(rl.GetScreenWidth() - rl.MeasureText(self.message, point_size), 2);
        const y = @divFloor(rl.GetScreenHeight() - point_size, 2);
        const alpha = self.message_timer / message_time;
        rl.DrawRectangle(x - 5, y - 5, rl.MeasureText(self.message, point_size) + 10, point_size + 10, rl.ColorAlpha(rl.BLACK, alpha));
        rl.DrawText(self.message, x, y, point_size, rl.ColorAlpha(s2color("#ff6e6e"), alpha));
    }

    const blocks_txt = rl.TextFormat("blocks: %i ", editor.blocks.items.len);
    rl.DrawRectangle(0, rl.GetScreenHeight() - 20, rl.MeasureText(blocks_txt, 10) + 20, 20, rl.RAYWHITE);
    rl.DrawText(blocks_txt, 10, rl.GetScreenHeight() - 15, 10, rl.BLACK);
}

fn calculateCameraDistance(fovy: f32, middle: rl.Vector3, edge: rl.Vector3) f32 {
    const margin = 1;
    const angle = fovy * 0.5;
    const radius = rl.Vector3Distance(middle, edge) + margin;
    return @floatCast((radius) / rl.tan(angle * rl.DEG2RAD));
}
