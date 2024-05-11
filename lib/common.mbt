// SPDX-License-Identifier: MIT
// Copyright (c) 2015 Dennis Felsing
// Copyright (c) 2024 Liu Rujia, International Digital Economy Academy

// TODO: use interface
struct MemoryReader {
  data : Array[Int]
  mut pos : Int
}

fn MemoryReader::new(data : Array[Int]) -> MemoryReader {
  { data, pos: 0 }
}

// copied from official example `bytes-buffer`
fn bytes_to_int_be(bytes : Array[Int], start : Int) -> Int {
  bytes[start].land(0xff).lsl(24).lor(
    bytes[start + 1].land(0xff).lsl(16).lor(
      bytes[start + 2].land(0xff).lsl(8).lor(bytes[start + 3].land(0xff)),
    ),
  )
}

fn bytes_to_int_le(bytes : Array[Int], start : Int) -> Int {
  bytes[start + 3].land(0xff).lsl(24).lor(
    bytes[start + 2].land(0xff).lsl(16).lor(
      bytes[start + 1].land(0xff).lsl(8).lor(bytes[start + 0].land(0xff)),
    ),
  )
}

// big endian
fn readIntBE(self : MemoryReader) -> Int {
  self.pos = self.pos + 4
  bytes_to_int_be(self.data, self.pos - 4)
}

// little endian
fn readIntLE(self : MemoryReader) -> Int {
  self.pos = self.pos + 4
  bytes_to_int_le(self.data, self.pos - 4)
}
