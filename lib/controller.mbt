// SPDX-License-Identifier: MIT
// Copyright (c) 2015 Dennis Felsing
// Copyright (c) 2024 Liu Rujia, International Digital Economy Academy

struct Controller {
  mut buttons : Array[Bool]
  mut index : Int
  mut strobe : UInt8
}

fn Controller::new() -> Controller {
  { buttons: Array::make(8, false), index: 0, strobe: 0 |> to_u8 }
}

// nim and go has different logic?
fn read(self : Controller) -> UInt8 {
  if self.index >= 8 {
    return 1 |> to_u8
  }
  let pressed = self.buttons[self.index]
  if self.strobe.land(1 |> to_u8) == (0 |> to_u8) {
    self.index = self.index + 1
  }
  pressed |> to_u8
}

fn write(self : Controller, val : UInt8) -> Unit {
  self.strobe = val
  if self.strobe.land(1 |> to_u8) == (1 |> to_u8) {
    self.index = 0
  }
}
