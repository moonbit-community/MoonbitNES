// SPDX-License-Identifier: MIT
// Copyright (c) 2015 Dennis Felsing
// Copyright (c) 2024 Liu Rujia, International Digital Economy Academy

///|
extern "wasm" fn store32(offset : Int, value : Int) =
  #|(func (param i32) (param i32) (i32.store (local.get 0) (local.get 1)))

///|
fn nes_write_color(offset : Int, red~ : Int, green~ : Int, blue~ : Int) -> Unit {
  store32(offset * 4, 0xFF000000 | (blue << 16) | (green << 8) | red)
}
