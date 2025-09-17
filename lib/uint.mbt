// SPDX-License-Identifier: MIT
// Copyright (c) 2015 Dennis Felsing
// Copyright (c) 2024 Liu Rujia, International Digital Economy Academy

// try to get some type safety by wrapper UInt8 and UInt16

///|
struct UInt8(Int) derive(Eq, Compare)

///|
struct UInt16(Int) derive(Eq, Compare, Default)

///|
struct UInt32(Int)

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
  UInt8(i & 0xFF)
}

///|
impl U16 for Int with u16(i : Int) -> UInt16 {
  UInt16(i & 0xFFFF)
}

///|
impl U32 for Int with u32(i : Int) -> UInt32 {
  UInt32(i)
}

///|
impl U64 for Int64 with u64(i : Int64) -> UInt64 {
  i.reinterpret_as_uint64()
}

///|
impl Show for UInt8 with output(self, logger) -> Unit {
  self.inner().output(logger)
}

///|
impl Show for UInt16 with output(self, logger) -> Unit {
  self.inner().output(logger)
}

// TODO: test u8 arithmetic

///|
impl Add for UInt8 with add(self : UInt8, rhs : UInt8) -> UInt8 {
  (self.inner() + rhs.inner()) |> to_u8
}

///|
impl Sub for UInt8 with sub(self : UInt8, rhs : UInt8) -> UInt8 {
  (self.inner() - rhs.inner()) |> to_u8
}

///|
impl Add for UInt16 with add(self : UInt16, rhs : UInt16) -> UInt16 {
  (self.inner() + rhs.inner()) |> to_u16
}

///|
impl Sub for UInt16 with sub(self : UInt16, rhs : UInt16) -> UInt16 {
  (self.inner() - rhs.inner()) |> to_u16
}

///|
impl Mod for UInt16 with mod(self : UInt16, rhs : UInt16) -> UInt16 {
  (self.inner() % rhs.inner()) |> to_u16
}

///|
impl U8 for Bool with u8(self : Bool) -> UInt8 {
  if self {
    UInt8(1)
  } else {
    UInt8(0)
  }
}

// TODO

///|
fn UInt8::formatHex(self : UInt8) -> String {
  ""
}

///|
impl U8 for UInt16 with u8(self : UInt16) -> UInt8 {
  self.inner() |> to_u8
}

///|
impl U8 for UInt32 with u8(self : UInt32) -> UInt8 {
  self.inner() |> to_u8
}

///|
impl U16 for UInt8 with u16(self : UInt8) -> UInt16 {
  self.inner() |> to_u16
}

///|
impl U32 for UInt64 with u32(self : UInt64) -> UInt32 {
  self.to_int() |> to_u32
}

///|
impl U64 for UInt32 with u64(self : UInt32) -> UInt64 {
  self.inner().to_int64() |> to_u64
}

///|
impl U64 for UInt8 with u64(self : UInt8) -> UInt64 {
  self.inner().to_int64() |> to_u64
}

// `bit` is usually a constant, so `Int` is easier to use

///|
impl Shl for UInt8 with shl(self : UInt8, bit : Int) -> UInt8 {
  (self.inner() << bit) |> to_u8
}

///|
impl Shl for UInt16 with shl(self : UInt16, bit : Int) -> UInt16 {
  (self.inner() << bit) |> to_u16
}

///|
impl Shr for UInt8 with shr(self : UInt8, bit : Int) -> UInt8 {
  (self.inner().reinterpret_as_uint() >> bit)
  |> UInt::reinterpret_as_int
  |> to_u8
}

///|
impl Shr for UInt16 with shr(self : UInt16, bit : Int) -> UInt16 {
  (self.inner().reinterpret_as_uint() >> bit)
  |> UInt::reinterpret_as_int
  |> to_u16
}

///|
impl Shr for UInt32 with shr(self : UInt32, bit : Int) -> UInt32 {
  (self.inner() >> bit) |> to_u32
}

///|
impl BitOr for UInt8 with lor(self : UInt8, bit : UInt8) -> UInt8 {
  (self.inner() | bit.inner()) |> to_u8
}

///|
impl BitOr for UInt16 with lor(self : UInt16, bit : UInt16) -> UInt16 {
  (self.inner() | bit.inner()) |> to_u16
}

///|
impl BitAnd for UInt8 with land(self : UInt8, rhs : UInt8) -> UInt8 {
  (self.inner() & rhs.inner()) |> to_u8
}

///|
impl BitAnd for UInt16 with land(self : UInt16, rhs : UInt16) -> UInt16 {
  (self.inner() & rhs.inner()) |> to_u16
}

///|
impl BitAnd for UInt32 with land(self : UInt32, rhs : UInt32) -> UInt32 {
  (self.inner() & rhs.inner()) |> to_u32
}

///|
impl BitXOr for UInt8 with lxor(self : UInt8, rhs : UInt8) -> UInt8 {
  (self.inner() ^ rhs.inner()) |> to_u8
}

///|
impl BitXOr for UInt16 with lxor(self : UInt16, rhs : UInt16) -> UInt16 {
  (self.inner() ^ rhs.inner()) |> to_u16
}

///|
fn UInt8::bit(self : UInt8, bit : Int) -> Bool {
  ((self >> bit) & (1 |> to_u8)).inner() == 1
}

///|
fn to_hex_digit(i : Int) -> String {
  let s = "0123456789ABCDEF"
  s[i].to_string()
}

///|
fn UInt8::to_hex(self : UInt8) -> String {
  ((self.inner() >> 4) |> to_hex_digit) +
  ((self.inner() & 0xf) |> to_hex_digit())
}

///|
fn UInt16::to_hex(self : UInt16) -> String {
  ((self.inner() >> 8) |> to_u8).to_hex() +
  ((self.inner() & 0xff) |> to_u8).to_hex()
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
