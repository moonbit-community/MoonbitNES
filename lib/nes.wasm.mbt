// SPDX-License-Identifier: MIT
// Copyright (c) 2015 Dennis Felsing
// Copyright (c) 2024 Liu Rujia, International Digital Economy Academy

///|
extern "wasm" fn load8_u(offset : Int32) -> Int32 =
  #|(func (param i32) (result i32) (i32.load8_u (local.get 0)))

///|
pub fn nestest_extern(length : Int32) -> Unit {
  nestest(FixedArray::makei(length, fn(i) { load8_u(offset.val + i) }))
}

///|
pub fn load_rom_extern(length : Int32) -> Unit {
  load_rom(FixedArray::makei(length, fn(i) { load8_u(offset.val + i) }))
}

// ffi

///|
fn nes_write_audio_sample(s : Double) = "nes" "write_audio_sample"
