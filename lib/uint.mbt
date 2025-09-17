// SPDX-License-Identifier: MIT
// Copyright (c) 2015 Dennis Felsing
// Copyright (c) 2024 Liu Rujia, International Digital Economy Academy

// try to get some type safety by wrapper UInt8 and UInt16

///|
typealias Byte as UInt8

///|
typealias UInt as UInt32

///|
trait U8 {
  u8(Self) -> UInt8
}

///|
fn[T : U8] to_u8(t : T) -> UInt8 {
  t.u8()
}

///|
trait U16 {
  u16(Self) -> UInt16
}

///|
fn[T : U16] to_u16(t : T) -> UInt16 {
  t.u16()
}

///|
trait U32 {
  u32(Self) -> UInt32
}

///|
fn[T : U32] to_u32(t : T) -> UInt32 {
  t.u32()
}

///|
trait U64 {
  u64(Self) -> UInt64
}

///|
fn[T : U64] to_u64(t : T) -> UInt64 {
  t.u64()
}

///|
impl U8 for Int with u8(i : Int) -> UInt8 {
  i.to_byte()
}

///|
impl U16 for Int with u16(i : Int) -> UInt16 {
  i.to_uint16()
}

///|
impl U32 for Int with u32(i : Int) -> UInt32 {
  i.reinterpret_as_uint()
}

///|
impl U64 for Int64 with u64(i : Int64) -> UInt64 {
  i.reinterpret_as_uint64()
}

///|
impl U8 for Bool with u8(self : Bool) -> UInt8 {
  if self {
    1
  } else {
    0
  }
}

// TODO

///|
fn UInt8::formatHex(self : UInt8) -> String {
  ""
}

///|
impl U8 for UInt16 with u8(self : UInt16) -> UInt8 {
  self.to_byte()
}

///|
impl U8 for UInt32 with u8(self : UInt32) -> UInt8 {
  self.to_byte()
}

///|
impl U16 for UInt8 with u16(self : UInt8) -> UInt16 {
  self.to_uint16()
}

///|
impl U32 for UInt64 with u32(self : UInt64) -> UInt32 {
  self.to_uint()
}

///|
impl U64 for UInt32 with u64(self : UInt32) -> UInt64 {
  self.to_uint64()
}

///|
impl U64 for UInt8 with u64(self : UInt8) -> UInt64 {
  self.to_uint64()
}

///|
fn UInt8::bit(self : UInt8, bit : Int) -> Bool {
  ((self >> bit) & 1) == 1
}

///|
fn to_hex_digit(i : Int) -> String {
  let s = "0123456789ABCDEF"
  s[i].unsafe_to_char().to_string()
}

///|
fn UInt8::to_hex(self : UInt8) -> String {
  ((self >> 4).to_int() |> to_hex_digit) +
  ((self & 0xf).to_int() |> to_hex_digit())
}

///|
fn UInt16::to_hex(self : UInt16) -> String {
  ((self >> 8) |> to_u8 |> UInt8::to_hex) +
  ((self & 0xff) |> to_u8 |> UInt8::to_hex)
}

///|
fn to_byte(
  b0 : Bool,
  b1 : Bool,
  b2 : Bool,
  b3 : Bool,
  b4 : Bool,
  b5 : Bool,
  b6 : Bool,
  b7 : Bool,
) -> UInt8 {
  (b0 |> to_u8) |
  ((b1 |> to_u8) << 1) |
  ((b2 |> to_u8) << 2) |
  ((b3 |> to_u8) << 3) |
  ((b4 |> to_u8) << 4) |
  ((b5 |> to_u8) << 5) |
  ((b6 |> to_u8) << 6) |
  ((b7 |> to_u8) << 7)
}

///|
fn MemoryReader::readUInt8(self : MemoryReader) -> UInt8 {
  self.pos = self.pos + 1
  self.data[self.pos - 1] |> to_u8
}

///|
fn MemoryReader::readUInt8Array(
  self : MemoryReader,
  cnt : Int,
) -> FixedArray[UInt8] {
  let result = FixedArray::makei(cnt, index => self.data[self.pos + index]
    |> to_u8)
  self.pos = self.pos + cnt
  result
}
