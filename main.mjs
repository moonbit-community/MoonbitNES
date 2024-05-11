// SPDX-License-Identifier: MIT
// Copyright (c) 2024 Liu Rujia, International Digital Economy Academy

/// Configurations
const speed_multiplier = 1;
const do_nestest = false; // execute nestest and generate a log to be compared with nestest/nestest.log
const do_benchmark = false; // run the emulator for 10 seconds and print audio stats
const do_run_with_logging = false; // run the emulator for 10 seconds and print logs
const backend = "wasm-gc" // wasm-gc or js

/// Canvas
const SCREEN_WIDTH = 256;
const SCREEN_HEIGHT = 240;
const FRAMEBUFFER_SIZE = SCREEN_WIDTH * SCREEN_HEIGHT;

let canvas_ctx, image;

function nes_draw_frame() {
    canvas_ctx.putImageData(image, 0, 0);
}

/// Audio
let audio_ctx, audio_processor
let _audio_sample_cnt = 0
let _audio_sample_total = 0
function nes_write_audio_sample(sample) {
    _audio_sample_cnt++;
    _audio_sample_total += sample;
    if (audio_processor) {
        audio_processor.port.postMessage(sample);
    }

}

/// Keyboard events
const BUTTON_A = 0;
const BUTTON_B = 1;
const BUTTON_SELECT = 2;
const BUTTON_START = 3;
const BUTTON_UP = 4;
const BUTTON_DOWN = 5;
const BUTTON_LEFT = 6;
const BUTTON_RIGHT = 7;

// WASD for directions, JK for Button B/A, LI for select/start
function nes_keyboard(callback, event) {
    const player = 1;
    switch (event.code) {
        case "ArrowUp": // UP
        case "KeyW": // 'W'
            callback(player, BUTTON_UP); break;
        case "ArrowDown": // Down
        case "KeyS": // 'S'
            callback(player, BUTTON_DOWN); break;
        case "ArrowLeft": // Left
        case "KeyA": // 'A'
            callback(player, BUTTON_LEFT); break;
        case "ArrowRight": // Right
        case "KeyD": // 'D'
            callback(player, BUTTON_RIGHT); break;
        case "KeyK": // 'K' - my favorite
            callback(player, BUTTON_A); break;
        case "KeyJ": // 'J' - my favorite
            callback(player, BUTTON_B); break;
        case "Tab": // Tab
            event.preventDefault();
        case "KeyL": // 'L' - my favorite
            callback(player, BUTTON_SELECT); break;
        case "Enter": // Return
        case "KeyI": // 'I' - my favorite
            callback(player, BUTTON_START); break;
        default: break;
    }
}

/// NES API

function nes_init(canvas_id) {
    const canvas = document.getElementById(canvas_id);
    canvas_ctx = canvas.getContext("2d");

    canvas_ctx.fillStyle = "black";
    canvas_ctx.fillRect(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT);
    // Setup audio.
    audio_ctx = new window.AudioContext();
    audio_ctx.audioWorklet.addModule('./audio.mjs').then(() => {
        audio_processor = new AudioWorkletNode(audio_ctx, 'audio-processor', { outputChannelCount: [2] });
        audio_processor.connect(audio_ctx.destination);
    })
}

function nes_load_url(canvas_id, path, callback) {
    nes_init(canvas_id);
    fetch(path).then(response => response.arrayBuffer()).then(buffer => callback(new Uint8Array(buffer)))
}

function nes_load_file(canvas_id, file, callback) {
    nes_init(canvas_id);
    file.arrayBuffer().then(buffer => callback(new Uint8Array(buffer)))
}

///////////////////////////////// WASM API


const [log, flush] = (() => {
    let buffer = [];
    function flush() {
        if (buffer.length > 0) {
            console.log(new TextDecoder("utf-16").decode(new Uint16Array(buffer)));
            buffer = [];
        }
    }
    function log(ch) {
        if (ch == '\n'.charCodeAt(0)) { flush(); }
        else if (ch == '\r'.charCodeAt(0)) { /* noop */ }
        else { buffer.push(ch); }
    }
    return [log, flush]
})();

const importObject = {
    nes: {
        write_audio_sample: (s) => nes_write_audio_sample(s),
    },
    spectest: {
        print_char: log,
    }
};

let moonbitnes = {

}

let requestAnimationFrameId = null
let lastTime = 0

function buttonDown(player, btn) {
    if (!requestAnimationFrameId || !moonbitnes.buttonDown) return;
    moonbitnes.buttonDown(player, btn);
}

function buttonUp(player, btn) {
    if (!requestAnimationFrameId || !moonbitnes.buttonUp) return;
    moonbitnes.buttonUp(player, btn);
}

// In theory: when lost focus, do not simulate (otherwise when you come back, the simulator will "hang" because it tries to simulate too many cycles)
// In practice: just limit each simulation time to 200ms :-D
function update(time = 0) {
    flush();
    const deltaTime = time - lastTime;
    var simuTime = deltaTime * speed_multiplier;
    if (simuTime > 200) simuTime = 200;
    const st = performance.now();
    moonbitnes.run(simuTime / 1000.0); // deltaTime is in ms
    const ed = performance.now();
    console.log("simulated " + simuTime + " msec, used ", ed - st, " msec. speed =", simuTime / (ed - st));
    nes_draw_frame();
    lastTime = time;
    requestAnimationFrameId = requestAnimationFrame(update);
}

function run_timed(sec) {
    const st = performance.now()
    moonbitnes.run(sec)
    const ed = performance.now()
    console.log("simulated " + sec + " sec, took " + (ed - st) / 1000.0 + " sec\n");
}

function run_benchmark() {
    run_timed(10)
    nes_draw_frame()
    console.log("audio stats: count=" + _audio_sample_cnt + " total=" + _audio_sample_total + "\n");
}

function run_with_logging() {
    moonbitnes.run_with_logging(10000)
}

document.addEventListener('keydown', (event) => { nes_keyboard(buttonDown, event) });
document.addEventListener('keyup', (event) => { nes_keyboard(buttonUp, event) });

if (backend == "wasm-gc") {
    const wasm_binary = "target/wasm-gc/release/build/lib/lib.wasm";
    const module = await WebAssembly.compileStreaming(fetch(wasm_binary));

    if (do_nestest) {
        document.getElementById("upload").style.display = "none";
        document.getElementById("canvas").style.display = "none";
        document.getElementById("keys").style.display = "none";
        document.getElementById("download").style.display = "inherit";
        let buffer = []
        const instance = await WebAssembly.instantiate(module, {
            ...importObject,
            "spectest": {
                print_char: (ch) => {
                    buffer.push(ch)
                }
            },
        });

        instance.exports._start();
        moonbitnes = {
            nestest: instance.exports["nestest"],
            load_rom: instance.exports["load_rom"],
            run: instance.exports["run"],
            buttonDown: instance.exports["buttonDown"],
            buttonUp: instance.exports["buttonUp"],
            run_with_logging: instance.exports["run_with_logging"],
        }
        const memory = instance.exports["moonbit.memory"];
        nes_load_url("nes-canvas", "nestest/nestest.nes", function (rom_data) {
            // Allocate memory for the ROM
            memory.grow(rom_data.length / 65536);
            // Put the ROM data into the memory
            new Uint8Array(memory.buffer, 0).set(rom_data, 0);
            moonbitnes.nestest(rom_data.length);
            const blob = new Blob([new TextDecoder("utf-16").decode(new Uint16Array(buffer))]);
            const url = URL.createObjectURL(blob);
            document.getElementById("download").href = url;
            document.getElementById("download").textContent = "Log"
        });
    } else {
        document.getElementById("upload").addEventListener("change", async function () {
            const file = this.files[0];
            if (requestAnimationFrameId) {
                cancelAnimationFrame(requestAnimationFrameId);
                audio_ctx.close();
                audio_ctx = new window.AudioContext();
                audio_ctx.audioWorklet.addModule('./audio.mjs').then(() => {
                    audio_processor = new AudioWorkletNode(audio_ctx, 'audio-processor', { outputChannelCount: [2] });
                    audio_processor.connect(audio_ctx.destination);
                })
            }

            const instance = await WebAssembly.instantiate(module, importObject);

            instance.exports._start();
            moonbitnes = {
                nestest: instance.exports["nestest"],
                load_rom: instance.exports["load_rom"],
                run: instance.exports["run"],
                buttonDown: instance.exports["buttonDown"],
                buttonUp: instance.exports["buttonUp"],
                run_with_logging: instance.exports["run_with_logging"],
            }
            const memory = instance.exports["moonbit.memory"];

            nes_load_file("nes-canvas", file, function (rom_data) {
                // Allocate memory for the ROM
                memory.grow(rom_data.length / 65536);
                // Put the ROM data into the memory
                new Uint8Array(memory.buffer, 0).set(rom_data, 0);
                moonbitnes.load_rom(rom_data.length);

                // Allocate framebuffer
                memory.grow(Math.max(0, (FRAMEBUFFER_SIZE * 4 - memory.buffer.byteLength) / 65536 + 1));
                // Create an ImageData object with the framebuffer memory
                image = new ImageData(new Uint8ClampedArray(memory.buffer, 0, FRAMEBUFFER_SIZE * 4), SCREEN_WIDTH, SCREEN_HEIGHT);
                if (do_benchmark) {
                    run_benchmark();
                }
                else if (do_run_with_logging) {
                    run_with_logging();
                }
                else {
                    requestAnimationFrameId = requestAnimationFrame(update);
                }
            });
        });
    }
} else {
    const { nestest, load_rom, run, buttonDown, buttonUp, run_with_logging, set_image_data, set_callback } = await import("./target/js/release/build/lib/lib.js");
    image = new ImageData(new Uint8ClampedArray(SCREEN_WIDTH * SCREEN_HEIGHT * 4), SCREEN_WIDTH, SCREEN_HEIGHT);
    set_image_data(image.data)
    set_callback(nes_write_audio_sample)
    moonbitnes = {
        nestest,
        load_rom,
        run,
        buttonDown,
        buttonUp,
        run_with_logging,
    }
    if (do_nestest) {
        document.getElementById("upload").style.display = "none";
        document.getElementById("canvas").style.display = "none";
        document.getElementById("keys").style.display = "none";
        document.getElementById("download").style.display = "inherit";
        let buffer = []
        console.log = (str) => {
            buffer.push(str + "\n");
        }
        nes_load_url("nes-canvas", "nestest/nestest.nes", function (rom_data) {
            moonbitnes.nestest(rom_data);
            const blob = new Blob([buffer]);
            const url = URL.createObjectURL(blob);
            document.getElementById("download").href = url;
            document.getElementById("download").textContent = "Log"
        });
    } else {
        document.getElementById("upload").addEventListener("change", async function () {
            const file = this.files[0];
            if (requestAnimationFrameId) {
                cancelAnimationFrame(requestAnimationFrameId);
                audio_ctx.close();
                audio_ctx = new window.AudioContext();
                audio_ctx.audioWorklet.addModule('./audio.mjs').then(() => {
                    audio_processor = new AudioWorkletNode(audio_ctx, 'audio-processor', { outputChannelCount: [2] });
                    audio_processor.connect(audio_ctx.destination);
                })
            }
            nes_load_file("nes-canvas", file, function (rom_data) {
                moonbitnes.load_rom(rom_data);
                if (do_benchmark) {
                    run_benchmark();
                }
                else if (do_run_with_logging) {
                    run_with_logging();
                }
                else {
                    requestAnimationFrameId = requestAnimationFrame(update);
                }
            });
        });
    }
}

