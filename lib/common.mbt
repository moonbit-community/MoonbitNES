// SPDX-License-Identifier: MIT
// Copyright (c) 2015 Dennis Felsing
// Copyright (c) 2024 Liu Rujia, International Digital Economy Academy

// TODO: use interface

///|
struct MemoryReader {
  data : FixedArray[Int32]
  mut pos : Int32
}

///|
fn MemoryReader::new(data : FixedArray[Int32]) -> MemoryReader {
  { data, pos: 0, }
}

// copied from official example `bytes-buffer`

///|
fn bytes_to_int_be(bytes : FixedArray[Int32], start : Int32) -> Int32 {
  ((bytes[start] & 0xff) << 24) |
  ((bytes[start + 1] & 0xff) << 16) |
  ((bytes[start + 2] & 0xff) << 8) |
  (bytes[start + 3] & 0xff)
}

///|
fn bytes_to_int_le(bytes : FixedArray[Int32], start : Int32) -> Int32 {
  ((bytes[start + 3] & 0xff) << 24) |
  ((bytes[start + 2] & 0xff) << 16) |
  ((bytes[start + 1] & 0xff) << 8) |
  (bytes[start + 0] & 0xff)
}

// big endian

///|
fn MemoryReader::readIntBE(self : MemoryReader) -> Int32 {
  self.pos = self.pos + 4
  bytes_to_int_be(self.data, self.pos - 4)
}

// little endian

///|
fn MemoryReader::readIntLE(self : MemoryReader) -> Int32 {
  self.pos = self.pos + 4
  bytes_to_int_le(self.data, self.pos - 4)
}
