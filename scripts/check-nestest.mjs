import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { nestest } from "../_build/js/release/build/lib/lib.js";

// Compare every instruction's address, CPU registers and PPU/CPU cycle counters.
// Disassembly text is intentionally separate: the emulator calls ISB "ISC",
// and its existing APU register reads differ in the final instructions.
const trace = [];
const log = console.log;
try {
  console.log = (line) => {
    if (/^[0-9A-F]{4}  /.test(line)) trace.push(line);
  };
  nestest(Array.from(readFileSync(new URL("../nestest/nestest.nes", import.meta.url))));
} finally {
  console.log = log;
}
const expected = readFileSync(new URL("../nestest/nestest.log", import.meta.url), "utf8")
  .trimEnd().split(/\r?\n/);
assert.equal(trace.length, 8991);
assert.equal(trace.length, expected.length);
const state = (line) => {
  const match = line.match(/^([0-9A-F]{4})  .*?(A:[0-9A-F]{2} X:.*)$/);
  assert.ok(match, `Invalid trace line: ${line}`);
  return `${match[1]} ${match[2]}`;
};
for (let i = 0; i < expected.length; i++) {
  assert.equal(state(trace[i]), state(expected[i]), `CPU state at instruction ${i + 1}`);
}
console.log(`Verified ${trace.length} CPU states and cycle counters against nestest.log.`);

// Exercise the same exported API and linear-memory transfer as the browser UI.
const wasmTrace = [];
let line = "";
const wasm = new WebAssembly.Module(readFileSync(
  new URL("../_build/wasm-gc/release/build/lib/lib.wasm", import.meta.url),
));
const instance = new WebAssembly.Instance(wasm, {
  nes: { write_audio_sample() {} },
  spectest: { print_char(ch) {
    if (ch === 10) {
      if (/^[0-9A-F]{4}  /.test(line)) wasmTrace.push(line);
      line = "";
    } else if (ch !== 13) {
      line += String.fromCharCode(ch);
    }
  } },
});
const rom = readFileSync(new URL("../nestest/nestest.nes", import.meta.url));
const memory = instance.exports["moonbit.memory"];
if (memory.buffer.byteLength < rom.length) {
  memory.grow(Math.ceil((rom.length - memory.buffer.byteLength) / 65536));
}
new Uint8Array(memory.buffer, 0, rom.length).set(rom);
instance.exports.nestest(rom.length);
assert.equal(wasmTrace.length, expected.length);
for (let i = 0; i < expected.length; i++) {
  assert.equal(state(wasmTrace[i]), state(expected[i]), `Wasm GC CPU state at instruction ${i + 1}`);
}
console.log(`Verified ${wasmTrace.length} Wasm GC CPU states and cycle counters.`);
