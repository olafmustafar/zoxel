const std = @import("std");
const lib = @import("zig_shipdesigner_lib");
const rl = @import("raylib");
const keydown = rl.IsKeyDown;
const keypress = rl.IsKeyPressed;
const Editor = @import("Editor.zig");
const Ui = @import("Ui.zig");

const components = @import("raylib_components");
const Dialog = components.Dialog;
const MessageDisplay = components.MessageDisplay;

const utils = components.utils;
const rec = utils.rec;
const vec3 = utils.vec3;
const vec3val = utils.vec3val;
const vec2 = utils.vec2;

const window_w = 720;
const window_h = 720;
var buffer: [0xffff]u8 = undefined;

pub fn main() !void {
    const alloc = std.heap.page_allocator;

    rl.SetConfigFlags(rl.FLAG_MSAA_4X_HINT);
    rl.InitWindow(window_w, window_h, "raylib [core] example - basic window");
    rl.SetTargetFPS(60);
    defer rl.CloseWindow();

    var camera = rl.Camera3D{
        .position = vec3(5, 5, 0),
        .target = rl.Vector3Zero(),
        .up = vec3(0, 1, 0),
        .fovy = 60,
        .projection = rl.CAMERA_PERSPECTIVE,
    };

    const mesh = rl.GenMeshCube(1, 1, 1);
    const model = rl.LoadModelFromMesh(mesh);
    defer rl.UnloadModel(model);

    var editor = try Editor.init(alloc);
    defer editor.deinit();

    var ve_rotation: f32 = 0;
    var ve_rotation_target: f32 = 0;
    var ho_rotation: f32 = 0;
    var ho_rotation_target: f32 = 0;
    var zoom: f32 = 1;
    var zoom_target: f32 = 1;
    var mode: enum { normal, dialog, extra } = .normal;

    var ui = Ui.init();
    var display = MessageDisplay{};
    var dialog = Dialog.init();
    defer dialog.deinit();

    while (!rl.WindowShouldClose()) {
        switch (mode) {
            .normal => {
                const isShiftDown = keydown(rl.KEY_LEFT_SHIFT) or keydown(rl.KEY_RIGHT_SHIFT);

                if (keydown(rl.KEY_SPACE) or keydown(rl.KEY_F)) try editor.place();
                if (keydown(rl.KEY_R)) try editor.replace();
                if (keydown(rl.KEY_D) or keydown(rl.KEY_X)) try editor.remove();
                if ((keypress(rl.KEY_H) or keypress(rl.KEY_LEFT)) and !isShiftDown) editor.moveCursor(vec3(0, 0, 1));
                if ((keypress(rl.KEY_J) or keypress(rl.KEY_DOWN)) and !isShiftDown) editor.moveCursor(vec3(1, 0, 0));
                if ((keypress(rl.KEY_K) or keypress(rl.KEY_UP)) and !isShiftDown) editor.moveCursor(vec3(-1, 0, 0));
                if ((keypress(rl.KEY_L) or keypress(rl.KEY_RIGHT)) and !isShiftDown) editor.moveCursor(vec3(0, 0, -1));
                if ((keypress(rl.KEY_U) or keypress(rl.KEY_PAGE_DOWN)) and !isShiftDown) editor.moveCursor(vec3(0, -1, 0));
                if ((keypress(rl.KEY_I) or keypress(rl.KEY_PAGE_UP)) and !isShiftDown) editor.moveCursor(vec3(0, 1, 0));
                if ((keydown(rl.KEY_H) or keydown(rl.KEY_LEFT)) and isShiftDown) ho_rotation_target -= 2;
                if ((keydown(rl.KEY_J) or keydown(rl.KEY_DOWN)) and isShiftDown) ve_rotation_target -= 2;
                if ((keydown(rl.KEY_K) or keydown(rl.KEY_UP)) and isShiftDown) ve_rotation_target += 2;
                if ((keydown(rl.KEY_L) or keydown(rl.KEY_RIGHT)) and isShiftDown) ho_rotation_target += 2;
                if ((keydown(rl.KEY_U) or keydown(rl.KEY_PAGE_DOWN)) and isShiftDown) zoom_target += 0.2;
                if ((keydown(rl.KEY_I) or keydown(rl.KEY_PAGE_UP)) and isShiftDown) zoom_target -= 0.2;
                editor.rotation = ho_rotation_target;
                if (keypress(rl.KEY_N) and !isShiftDown) try editor.nextBuffer();
                if (keypress(rl.KEY_N) and isShiftDown) try editor.prevBuffer();
                if (keypress(rl.KEY_Y)) try editor.copyHovering();
                if (keypress(rl.KEY_V)) try editor.switchVisualMode();
                if (keypress(rl.KEY_LEFT_BRACKET)) try editor.clearMode();
                if (keypress(rl.KEY_G)) mode = .extra;

                if (keypress(rl.KEY_SEMICOLON) and isShiftDown) {
                    dialog.startTextDialog();
                    mode = .dialog;
                }

                if (keypress(rl.KEY_C)) {
                    dialog.startColorPicker(editor.color);
                    mode = .dialog;
                }
            },
            .extra => {
                if (keypress(rl.KEY_H)) editor.rotate(vec3(1, 0, 0));
                if (keypress(rl.KEY_J)) editor.rotate(vec3(0, 0, -1));
                if (keypress(rl.KEY_K)) editor.rotate(vec3(0, 0, 1));
                if (keypress(rl.KEY_L)) editor.rotate(vec3(-1, 0, 0));
                if (rl.GetKeyPressed() != 0) mode = .normal;
            },
            .dialog => {
                switch (dialog.processInput()) {
                    .more => {},
                    .cancelled => mode = .normal,
                    .finished => |command| {
                        mode = .normal;
                        editor.command(@ptrCast(command)) catch |e| display.displayError(e);
                    },
                }
            },
        }

        camera.target = rl.Vector3Lerp(camera.target, editor.cursor, 6 * rl.GetFrameTime());
        ve_rotation = rl.Lerp(ve_rotation, ve_rotation_target, 6 * rl.GetFrameTime());
        ho_rotation = rl.Lerp(ho_rotation, ho_rotation_target, 6 * rl.GetFrameTime());
        zoom = rl.Lerp(zoom, zoom_target, 6 * rl.GetFrameTime());
        camera.position = rl.Vector3Add(vec3(5, 5, 0), vec3(zoom, zoom, 0));
        camera.position = rl.Vector3RotateByAxisAngle(camera.position, vec3(0, 0, 1), ve_rotation * rl.DEG2RAD);
        camera.position = rl.Vector3RotateByAxisAngle(camera.position, vec3(0, 1, 0), ho_rotation * rl.DEG2RAD);
        camera.position = rl.Vector3Add(camera.target, camera.position);

        {
            rl.BeginDrawing();
            defer rl.EndDrawing();

            rl.ClearBackground(rl.RAYWHITE);

            {
                rl.BeginMode3D(camera);
                defer rl.EndMode3D();
                rl.rlClearScreenBuffers();

                rl.UpdateCamera(&camera, rl.CAMERA_CUSTOM);
                for (editor.blocks.items) |block| {
                    rl.DrawCubeWires(block.pos, 1, 1, 1, rl.WHITE);
                    rl.DrawModel(model, block.pos, 1, block.color);
                }

                if (editor.visual_mode) {
                    const begin = rl.Vector3AddValue(rl.Vector3Min(editor.visual_begin, editor.cursor), -0.5);
                    const end = rl.Vector3AddValue(rl.Vector3Max(editor.visual_begin, editor.cursor), 0.5);
                    const size = rl.Vector3Subtract(end, begin);
                    const pos = rl.Vector3Add(begin, rl.Vector3Divide(size, vec3val(2)));
                    rl.DrawCubeWiresV(pos, size, rl.RED);
                }

                rl.DrawGrid(10, 1);
                rl.DrawCubeWires(editor.cursor, 1.1, 1.1, 1.1, rl.BLACK);

                for (editor.place_buffer.items) |b| {
                    rl.rlDisableDepthMask();
                    defer rl.rlEnableDepthMask();
                    rl.DrawModel(model, rl.Vector3Add(editor.cursor, b.pos), 1, rl.ColorAlpha(b.color, 0.2));
                }
            }

            if (mode == .dialog) {
                dialog.render(window_w, window_h);
            }
            display.updateAndRender();

            ui.render(editor, .{ .ve = ve_rotation, .ho = ho_rotation });
            rl.DrawFPS(0, 0);
        }
    }
}
