// SPDX-License-Identifier: MIT
// Copyright (c) 2015 Dennis Felsing
// Copyright (c) 2024 Liu Rujia, International Digital Economy Academy

// try to get some type safety by wrapper UInt8 and UInt16
type UInt8 Int derive(Eq, Compare)

type UInt16 Int derive(Eq, Compare, Default)

type UInt32 Int

type UInt64 Int64

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

impl U8 for Int with u8(i : Int) -> UInt8 { UInt8(i.land(0xFF)) }

impl U16 for Int with u16(i : Int) -> UInt16 { UInt16(i.land(0xFFFF)) }

impl U32 for Int with u32(i : Int) -> UInt32 { UInt32(i) }

impl U64 for Int64 with u64(i : Int64) -> UInt64 { UInt64(i) }

fn to_string(self : UInt8) -> String {
  self.0.to_string()
}

fn to_string(self : UInt16) -> String {
  self.0.to_string()
}

// TODO: test u8 arithmetic
fn op_add(self : UInt8, rhs : UInt8) -> UInt8 {
  self.0 + rhs.0 |> to_u8
}

fn op_sub(self : UInt8, rhs : UInt8) -> UInt8 {
  self.0 - rhs.0 |> to_u8
}

fn op_add(self : UInt16, rhs : UInt16) -> UInt16 {
  self.0 + rhs.0 |> to_u16
}

fn op_sub(self : UInt16, rhs : UInt16) -> UInt16 {
  self.0 - rhs.0 |> to_u16
}

fn op_mod(self : UInt16, rhs : UInt16) -> UInt16 {
  self.0 % rhs.0 |> to_u16
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
  self.0 |> to_u8
}

fn u8(self : UInt32) -> UInt8 {
  self.0 |> to_u8
}

fn u16(self : UInt8) -> UInt16 {
  self.0 |> to_u16
}

fn u32(self : UInt64) -> UInt32 {
  self.0.to_int() |> to_u32
}

fn u64(self : UInt32) -> UInt64 {
  self.0.to_int64() |> to_u64
}

fn u64(self : UInt8) -> UInt64 {
  self.0.to_int64() |> to_u64
}

// `bit` is usually a constant, so `Int` is easier to use
fn lsl(self : UInt8, bit : Int) -> UInt8 {
  self.0.lsl(bit) |> to_u8
}

fn lsl(self : UInt16, bit : Int) -> UInt16 {
  self.0.lsl(bit) |> to_u16
}

fn lsl(self : UInt64, bit : Int) -> UInt64 {
  self.0.lsl(bit) |> to_u64
}

fn lsr(self : UInt8, bit : Int) -> UInt8 {
  self.0.lsr(bit) |> to_u8
}

fn lsr(self : UInt16, bit : Int) -> UInt16 {
  self.0.lsr(bit) |> to_u16
}

fn lsr(self : UInt32, bit : Int) -> UInt32 {
  self.0.lsr(bit) |> to_u32
}

fn lsr(self : UInt64, bit : Int) -> UInt64 {
  self.0.lsr(bit) |> to_u64
}

fn lor(self : UInt8, bit : UInt8) -> UInt8 {
  self.0.lor(bit.0) |> to_u8
}

fn lor(self : UInt16, bit : UInt16) -> UInt16 {
  self.0.lor(bit.0) |> to_u16
}

fn lor(self : UInt64, bit : UInt64) -> UInt64 {
  self.0.lor(bit.0) |> to_u64
}

fn land(self : UInt8, rhs : UInt8) -> UInt8 {
  self.0.land(rhs.0) |> to_u8
}

fn land(self : UInt16, rhs : UInt16) -> UInt16 {
  self.0.land(rhs.0) |> to_u16
}

fn land(self : UInt32, rhs : UInt32) -> UInt32 {
  self.0.land(rhs.0) |> to_u32
}

fn lxor(self : UInt8, rhs : UInt8) -> UInt8 {
  self.0.lxor(rhs.0) |> to_u8
}

fn lxor(self : UInt16, rhs : UInt16) -> UInt16 {
  self.0.lxor(rhs.0) |> to_u16
}

fn bit(self : UInt8, bit : Int) -> Bool {
  self.lsr(bit).land(1 |> to_u8).0 == 1
}

fn to_hex_digit(i : Int) -> String {
  let s = "0123456789ABCDEF"
  s[i].to_string()
}

fn to_hex(self : UInt8) -> String {
  (self.0.lsr(4) |> to_hex_digit) + (self.0.land(0xf) |> to_hex_digit())
}

fn to_hex(self : UInt16) -> String {
  (self.0.lsr(8) |> to_u8).to_hex() + (self.0.land(0xff) |> to_u8).to_hex()
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
  (b0 |> to_u8).lor((b1 |> to_u8).lsl(1)).lor((b2 |> to_u8).lsl(2)).lor(
    (b3 |> to_u8).lsl(3),
  ).lor((b4 |> to_u8).lsl(4)).lor((b5 |> to_u8).lsl(5)).lor(
    (b6 |> to_u8).lsl(6),
  ).lor((b7 |> to_u8).lsl(7))
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
