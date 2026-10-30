// SPDX-License-Identifier: MIT
// Copyright (c) 2015 Dennis Felsing
// Copyright (c) 2024 Liu Rujia, International Digital Economy Academy

///|
let canvas : Ref[FixedArray[Int32]] = { val: FixedArray::make(0, 0), }

///|
pub fn set_image_data(image_data : FixedArray[Int32]) -> Unit {
  canvas.val = image_data
}

///|
fn nes_write_color(
  offset : Int32,
  red~ : Int32,
  green~ : Int32,
  blue~ : Int32,
) -> Unit {
  canvas.val[offset * 4] = red
  canvas.val[offset * 4 + 1] = green
  canvas.val[offset * 4 + 2] = blue
  canvas.val[offset * 4 + 3] = 0xFF
}
