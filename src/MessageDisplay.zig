const rl = @import("raylib");
const s2color = @import("raylib.zig").str2ColorComptime;

const Self = @This();
const message_time = 3.0;

message: [:0]const u8 = "",
message_timer: f32 = 0,

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

pub fn updateAndRender(self: *Self) void {
    if (self.message_timer > 0) {
        self.message_timer = @max(self.message_timer - rl.GetFrameTime(), 0);
        const point_size = 20;
        const x = @divFloor(rl.GetScreenWidth() - rl.MeasureText(self.message, point_size), 2);
        const y = @divFloor(rl.GetScreenHeight() - point_size, 2);
        const alpha = self.message_timer / message_time;
        rl.DrawRectangle(x - 5, y - 5, rl.MeasureText(self.message, point_size) + 10, point_size + 10, rl.ColorAlpha(rl.BLACK, alpha));
        rl.DrawText(self.message, x, y, point_size, rl.ColorAlpha(s2color("#ff6e6e"), alpha));
    }
}
