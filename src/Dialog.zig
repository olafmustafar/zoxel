const std = @import("std");
const rl = @import("raylib.zig").rl;
const vec2 = @import("raylib.zig").vec2;
const cast = @import("raylib.zig").cast;
const rec = @import("raylib.zig").rec;

const Self = @This();

const Mode = enum { text, color_picker };

const ResultTag = enum { more, cancelled, finished };

const Result = union(ResultTag) {
    more: void,
    cancelled: void,
    finished: [:0]const u8,
};

const border = 5;
const color_picker_w = 420;
const color_picker_h = 400;
const canvas_padding = 25;
const canvas_w = color_picker_h - (canvas_padding * 2);
const canvas_h = color_picker_h - (canvas_padding * 2);

buffer: [255:0]u8 = std.mem.zeroes([255:0]u8),
buffer_i: usize = 0,
frame: usize = 0,
mode: Mode = Mode.text,

cp_hue_slider: f32 = 0,
cp_hue_slider_target: f32 = 0,
cp_cursor: rl.Vector2 = vec2(0, 0),
cp_cursor_target: rl.Vector2 = vec2(0, 0),
cp_canvas: rl.RenderTexture2D,

pub fn init() Self {
    const canvas = rl.LoadRenderTexture(canvas_w, canvas_h);
    return Self{ .cp_canvas = canvas };
}

pub fn deinit(self: Self) void {
    rl.UnloadRenderTexture(self.cp_canvas);
}

pub fn startTextDialog(self: *Self) void {
    self.mode = .text;
    self.buffer = std.mem.zeroes(@TypeOf(self.buffer));
    self.buffer_i = 0;
}

pub fn startColorPicker(self: *Self, color: rl.Color) void {
    self.mode = .color_picker;
    self.buffer = std.mem.zeroes(@TypeOf(self.buffer));
    self.buffer_i = 0;

    const hsv = rl.ColorToHSV(color);
    self.cp_hue_slider_target = hsv.x / 360;
    self.cp_hue_slider = self.cp_hue_slider_target;
    self.cp_cursor_target = vec2(hsv.y * canvas_h, (1 - hsv.z) * canvas_w);
    self.cp_cursor = self.cp_cursor_target;
    self.updateCanvas();
}

pub fn processInput(self: *Self) Result {
    switch (self.mode) {
        .text => return self.processTextInput(),
        .color_picker => return self.processColorPickerInput(),
    }
}

pub fn processTextInput(self: *Self) Result {
    self.frame += 1;
    var key = rl.GetCharPressed();
    while (key > 0) {
        if (key == ':') {
            return .cancelled;
        }

        const allowed = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ .";
        if (std.mem.findScalar(u8, allowed, @intCast(key)) != null) {
            self.buffer[self.buffer_i] = @intCast(key);
            self.buffer[self.buffer_i + 1] = 0;
            self.buffer_i += 1;
        }

        key = rl.GetCharPressed();
    }
    if (rl.IsKeyPressed(rl.KEY_BACKSPACE)) {
        if (self.buffer_i == 0) {
            return .cancelled;
        } else {
            self.buffer[self.buffer_i - 1] = 0;
            self.buffer_i -= 1;
        }
    } else if (rl.IsKeyPressed(rl.KEY_ENTER)) {
        return if (self.buffer_i == 0) .cancelled else .{ .finished = self.buffer[0..self.buffer_i :0] };
    } else if (rl.IsKeyPressed(rl.KEY_LEFT_BRACKET)) {
        return .cancelled;
    }
    return .more;
}

pub fn processColorPickerInput(self: *Self) Result {
    const speed: f32 = if (rl.IsKeyDown(rl.KEY_LEFT_SHIFT) or rl.IsKeyDown(rl.KEY_RIGHT_SHIFT)) 10 else 2;
    if (rl.IsKeyDown(rl.KEY_H)) self.cp_cursor_target = rl.Vector2Add(self.cp_cursor_target, vec2(-speed, 0));
    if (rl.IsKeyDown(rl.KEY_J)) self.cp_cursor_target = rl.Vector2Add(self.cp_cursor_target, vec2(0, speed));
    if (rl.IsKeyDown(rl.KEY_K)) self.cp_cursor_target = rl.Vector2Add(self.cp_cursor_target, vec2(0, -speed));
    if (rl.IsKeyDown(rl.KEY_L)) self.cp_cursor_target = rl.Vector2Add(self.cp_cursor_target, vec2(speed, 0));
    self.cp_cursor_target = rl.Vector2Clamp(self.cp_cursor_target, rl.Vector2Zero(), vec2(canvas_w, canvas_h));
    self.cp_cursor = rl.Vector2Lerp(self.cp_cursor, self.cp_cursor_target, 6 * rl.GetFrameTime());

    if (rl.IsKeyDown(rl.KEY_I)) self.cp_hue_slider_target += speed * 0.01;
    if (rl.IsKeyDown(rl.KEY_U)) self.cp_hue_slider_target -= speed * 0.01;
    self.cp_hue_slider_target = rl.Clamp(self.cp_hue_slider_target, 0, 1);
    if (self.cp_hue_slider != self.cp_hue_slider_target) {
        if (@abs(self.cp_hue_slider - self.cp_hue_slider_target) < 0.01) {
            self.cp_hue_slider = self.cp_hue_slider_target;
        } else {
            self.cp_hue_slider = rl.Lerp(self.cp_hue_slider, self.cp_hue_slider_target, 6 * rl.GetFrameTime());
        }
        self.updateCanvas();
    }

    if (rl.IsKeyPressed(rl.KEY_ENTER)) {
        const color = self.getCurrentColor();
        const slice = std.fmt.bufPrintSentinel(&self.buffer, "color {x:0>2}{x:0>2}{x:0>2}", .{ color.r, color.g, color.b }, 0) catch {
            return .cancelled;
        };
        self.buffer_i = slice.len;
        return .{ .finished = self.buffer[0..self.buffer_i :0] };
    } else if (rl.IsKeyPressed(rl.KEY_LEFT_BRACKET)) {
        return .cancelled;
    }
    return .more;
}

pub fn render(self: Self, window_w: comptime_int, window_h: comptime_int) void {
    switch (self.mode) {
        .text => self.renderTextDialog(window_w, window_h),
        .color_picker => self.renderColorPicker(window_w, window_h),
    }
}

fn renderTextDialog(self: Self, window_w: comptime_int, window_h: comptime_int) void {
    const w = 400;
    const h = 50;
    const x = (window_w - w) / 2;
    const y = (window_h - h) / 2;
    const padding = 15;
    const font = h - (padding * 2);
    rl.DrawRectangle(x, y, w, h, rl.WHITE);
    rl.DrawRectangle(x + border, y + border, w - (border * 2), h - (border * 2), rl.BLACK);
    rl.DrawText(&self.buffer, x + padding, y + padding, font, rl.WHITE);
    if (@mod(self.frame / 20, 2) == 0) {
        rl.DrawText("_", x + padding + 1 + rl.MeasureText(&self.buffer, font), y + padding, font, rl.WHITE);
    }
}

pub fn renderColorPicker(self: Self, window_w: comptime_int, window_h: comptime_int) void {
    const x = (window_w - color_picker_w) / 2;
    const y = (window_h - color_picker_h) / 2;

    rl.DrawRectangle(x, y, color_picker_w, color_picker_h, rl.WHITE);
    rl.DrawRectangle(x + border, y + border, color_picker_w - (border * 2), color_picker_h - (border * 2), rl.BLACK);

    for (0..canvas_h) |yy| {
        const color = rl.ColorFromHSV((cast(f32, yy) / canvas_h) * 360, 1, 1);
        rl.DrawRectangle(@intCast(x + canvas_padding), @intCast(y + yy + canvas_padding), 10, 1, color);
    }

    rl.DrawTextureRec(
        self.cp_canvas.texture,
        rec(0, 0, canvas_w, -canvas_h),
        vec2(20 + x + canvas_padding, y + canvas_padding),
        rl.WHITE,
    );

    const color = self.getCurrentColor();
    const cursor = rl.Vector2Add(self.cp_cursor, vec2(20 + x + canvas_padding, y + canvas_padding));
    rl.DrawCircleV(cursor, 9, rl.WHITE);
    rl.DrawCircleV(cursor, 7, rl.BLACK);
    rl.DrawCircleV(cursor, 5, color);

    const slider_x = x + canvas_padding;
    const slider_y = y + canvas_padding + (self.cp_hue_slider * canvas_h);
    rl.DrawTriangle(
        vec2(slider_x, slider_y),
        vec2(slider_x - 10, slider_y - 5),
        vec2(slider_x - 10, slider_y + 5),
        rl.ColorFromHSV(self.cp_hue_slider * 360, 1, 1),
    );
}

fn updateCanvas(self: Self) void {
    rl.BeginTextureMode(self.cp_canvas);
    defer rl.EndTextureMode();
    const hue = self.cp_hue_slider * 360;
    for (0..canvas_h) |y| {
        const colorL = rl.ColorFromHSV(hue, 0, 1 - cast(f32, y) / canvas_h);
        const colorR = rl.ColorFromHSV(hue, 1, 1 - cast(f32, y) / canvas_h);
        rl.DrawRectangleGradientH(0, @intCast(y), canvas_w, 1, colorL, colorR);
    }
}

fn getCurrentColor(self: Self) rl.Color {
    return rl.ColorFromHSV(
        self.cp_hue_slider * 360,
        self.cp_cursor.x / canvas_w,
        1 - self.cp_cursor.y / canvas_w,
    );
}
