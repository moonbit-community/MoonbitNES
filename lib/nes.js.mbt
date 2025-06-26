// SPDX-License-Identifier: MIT
// Copyright (c) 2015 Dennis Felsing
// Copyright (c) 2024 Liu Rujia, International Digital Economy Academy

///|
let callback : Ref[(Double) -> Unit] = { val: fn(_d) {  } }

///|
pub fn set_callback(nes_write_audio_sample : (Double) -> Unit) -> Unit {
  callback.val = nes_write_audio_sample
}

///|
fn nes_write_audio_sample(s : Double) -> Unit {
  (callback.val)(s)
}
