// SPDX-License-Identifier: MIT
// Copyright (c) 2015 Dennis Felsing
// Copyright (c) 2024 Liu Rujia, International Digital Economy Academy

///|
struct Controller {
  mut buttons : FixedArray[Bool]
  mut index : Int
  mut strobe : UInt8
}

///|
fn Controller::new() -> Controller {
  { buttons: FixedArray::make(8, false), index: 0, strobe: 0 }
}

// nim and go has different logic?

///|
fn Controller::read(self : Controller) -> UInt8 {
  if self.index >= 8 {
    return 1
  }
  let pressed = self.buttons[self.index]
  if (self.strobe & 1) == 0 {
    self.index = self.index + 1
  }
  pressed |> to_u8
}

///|
fn Controller::write(self : Controller, val : UInt8) -> Unit {
  self.strobe = val
  if (self.strobe & 1) == 1 {
    self.index = 0
  }
}
