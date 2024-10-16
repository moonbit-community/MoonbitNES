// SPDX-License-Identifier: MIT
// Copyright (c) 2015 Dennis Felsing
// Copyright (c) 2024 Liu Rujia, International Digital Economy Academy

// try to get some type safety by wrapper UInt8 and UInt16
type UInt8 Int derive(Eq, Compare)

type UInt16 Int derive(Eq, Compare, Default)

type UInt32 Int

trait U8 {
  u8(Self) -> UInt8
}

fn to_u8[T : U8](t : T) -> UInt8 {
  t.u8()
}

trait U16 {
  u16(Self) -> UInt16
}

fn to_u16[T : U16](t : T) -> UInt16 {
  t.u16()
}

trait U32 {
  u32(Self) -> UInt32
}

fn to_u32[T : U32](t : T) -> UInt32 {
  t.u32()
}

trait U64 {
  u64(Self) -> UInt64
}

fn to_u64[T : U64](t : T) -> UInt64 {
  t.u64()
}

impl U8 for Int with u8(i : Int) -> UInt8 { UInt8(i & 0xFF) }

impl U16 for Int with u16(i : Int) -> UInt16 { UInt16(i & 0xFFFF) }

impl U32 for Int with u32(i : Int) -> UInt32 { UInt32(i) }

impl U64 for Int64 with u64(i : Int64) -> UInt64 { i.reinterpret_as_uint64() }

fn to_string(self : UInt8) -> String {
  self._.to_string()
}

fn to_string(self : UInt16) -> String {
  self._.to_string()
}

// TODO: test u8 arithmetic
fn op_add(self : UInt8, rhs : UInt8) -> UInt8 {
  self._ + rhs._ |> to_u8
}

fn op_sub(self : UInt8, rhs : UInt8) -> UInt8 {
  self._ - rhs._ |> to_u8
}

fn op_add(self : UInt16, rhs : UInt16) -> UInt16 {
  self._ + rhs._ |> to_u16
}

fn op_sub(self : UInt16, rhs : UInt16) -> UInt16 {
  self._ - rhs._ |> to_u16
}

fn op_mod(self : UInt16, rhs : UInt16) -> UInt16 {
  self._ % rhs._ |> to_u16
}

impl U8 for Bool with u8(self : Bool) -> UInt8 {
  if self {
    UInt8(1)
  } else {
    UInt8(0)
  }
}

// TODO
fn formatHex(self : UInt8) -> String {
  ""
}

fn u8(self : UInt16) -> UInt8 {
  self._ |> to_u8
}

fn u8(self : UInt32) -> UInt8 {
  self._ |> to_u8
}

fn u16(self : UInt8) -> UInt16 {
  self._ |> to_u16
}

impl U32 for UInt64 with u32(self : UInt64) -> UInt32 {
  self.to_int() |> to_u32
}

fn u64(self : UInt32) -> UInt64 {
  self._.to_int64() |> to_u64
}

fn u64(self : UInt8) -> UInt64 {
  self._.to_int64() |> to_u64
}

// `bit` is usually a constant, so `Int` is easier to use
fn op_shl(self : UInt8, bit : Int) -> UInt8 {
  self._ << bit |> to_u8
}

fn op_shl(self : UInt16, bit : Int) -> UInt16 {
  self._ << bit |> to_u16
}

fn op_shr(self : UInt8, bit : Int) -> UInt8 {
  self._.reinterpret_as_uint() >> bit |> UInt::reinterpret_as_int |> to_u8
}

fn op_shr(self : UInt16, bit : Int) -> UInt16 {
  self._.reinterpret_as_uint() >> bit |> UInt::reinterpret_as_int |> to_u16
}

fn op_shr(self : UInt32, bit : Int) -> UInt32 {
  self._ >> bit |> to_u32
}

fn lor(self : UInt8, bit : UInt8) -> UInt8 {
  self._ | bit._ |> to_u8
}

fn lor(self : UInt16, bit : UInt16) -> UInt16 {
  self._ | bit._ |> to_u16
}

fn land(self : UInt8, rhs : UInt8) -> UInt8 {
  self._ & rhs._ |> to_u8
}

fn land(self : UInt16, rhs : UInt16) -> UInt16 {
  self._ & rhs._ |> to_u16
}

fn land(self : UInt32, rhs : UInt32) -> UInt32 {
  self._ & rhs._ |> to_u32
}

fn lxor(self : UInt8, rhs : UInt8) -> UInt8 {
  self._ ^ rhs._ |> to_u8
}

fn lxor(self : UInt16, rhs : UInt16) -> UInt16 {
  self._ ^ rhs._ |> to_u16
}

fn bit(self : UInt8, bit : Int) -> Bool {
  ((self >> bit) & (1 |> to_u8))._ == 1
}

fn to_hex_digit(i : Int) -> String {
  let s = "0123456789ABCDEF"
  s[i].to_string()
}

fn to_hex(self : UInt8) -> String {
  (self._ >> 4 |> to_hex_digit) + (self._ & 0xf |> to_hex_digit())
}

fn to_hex(self : UInt16) -> String {
  (self._ >> 8 |> to_u8).to_hex() + (self._ & 0xff |> to_u8).to_hex()
}

fn to_byte(
  b0 : Bool,
  b1 : Bool,
  b2 : Bool,
  b3 : Bool,
  b4 : Bool,
  b5 : Bool,
  b6 : Bool,
  b7 : Bool
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

fn readUInt8(self : MemoryReader) -> UInt8 {
  self.pos = self.pos + 1
  self.data[self.pos - 1] |> to_u8
}

fn readUInt8Array(self : MemoryReader, cnt : Int) -> FixedArray[UInt8] {
  let result = FixedArray::makei(
    cnt,
    fn { index => self.data[self.pos + index] |> to_u8 },
  )
  self.pos = self.pos + cnt
  result
}
