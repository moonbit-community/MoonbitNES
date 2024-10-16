// SPDX-License-Identifier: MIT
// Copyright (c) 2015 Dennis Felsing
// Copyright (c) 2024 Liu Rujia, International Digital Economy Academy

// TODO: use interface
struct MemoryReader {
  data : FixedArray[Int]
  mut pos : Int
}

fn MemoryReader::new(data : FixedArray[Int]) -> MemoryReader {
  { data, pos: 0 }
}

// copied from official example `bytes-buffer`
fn bytes_to_int_be(bytes : FixedArray[Int], start : Int) -> Int {
  ((bytes[start] & 0xff) << 24) |
  ((bytes[start + 1] & 0xff) << 16) |
  ((bytes[start + 2] & 0xff) << 8) |
  (bytes[start + 3] & 0xff)
}

fn bytes_to_int_le(bytes : FixedArray[Int], start : Int) -> Int {
  ((bytes[start + 3] & 0xff) << 24) |
  ((bytes[start + 2] & 0xff) << 16) |
  ((bytes[start + 1] & 0xff) << 8) |
  (bytes[start + 0] & 0xff)
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
