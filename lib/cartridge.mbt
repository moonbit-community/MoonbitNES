// SPDX-License-Identifier: MIT
// Copyright (c) 2015 Dennis Felsing
// Copyright (c) 2024 Liu Rujia, International Digital Economy Academy

///|
struct Cartridge {
  prg : FixedArray[UInt8] // PRG-ROM banks
  chr : FixedArray[UInt8] // CHR-ROM banks
  sram : FixedArray[UInt8] // Save RAM
  mapper : UInt8 // mapper type
  mut mirror : UInt8 // mirroring mode
  battery : Bool // battery present
}

///|
let mirrorHorizontal : UInt8 = 0

///|
let mirrorVertical : UInt8 = 1

///|
let mirrorSingle0 : UInt8 = 2

///|
let mirrorSingle1 : UInt8 = 3

///|
let mirrorFour : UInt8 = 4

///|
let iNESMagic = 0x1A53454E

// I don't want to capitalize but the format is called `iNES`

///|
struct INESHeader {
  magic : Int // iNES magic number
  numPRG : UInt8 // number of PRG-ROM banks (16KB each)
  numCHR : UInt8 // number of CHR-ROM banks (8KB each)
  control1 : UInt8 // control bits
  control2 : UInt8 // control bits
  numRAM : UInt8 // PRG-RAM size (x 8KB)
  padding : FixedArray[UInt8] // 7 bytes, unused padding
}

///|
fn MemoryReader::readINESHeader(self : MemoryReader) -> INESHeader {
  let magic = self.readIntLE()
  println("magic: \{magic})")
  let numPRG = self.readUInt8()
  let numCHR = self.readUInt8()
  println("numPRG: \{numPRG})")
  println("numCHR: \{numCHR})")
  let control1 = self.readUInt8()
  let control2 = self.readUInt8()
  let numRAM = self.readUInt8()
  println("control1: \{control1})")
  println("control2: \{control2})")
  println("numRAM: \{numRAM})")
  let padding = self.readUInt8Array(7)
  { magic, numPRG, numCHR, control1, control2, numRAM, padding }
}

// http://wiki.nesdev.com/w/index.php/INES
// http://nesdev.com/NESDoc.pdf (page 28)
// TODO: report error if we cannot read data properly. Exception?
// https://www.nesdev.org/wiki/INES
// Flags 6
// 76543210
// ||||||||
// |||||||+- Mirroring: 0: horizontal (vertical arrangement) (CIRAM A10 = PPU A11)
// |||||||              1: vertical (horizontal arrangement) (CIRAM A10 = PPU A10)
// ||||||+-- 1: Cartridge contains battery-backed PRG RAM ($6000-7FFF) or other persistent memory
// |||||+--- 1: 512-byte trainer at $7000-$71FF (stored before PRG data)
// ||||+---- 1: Ignore mirroring control or above mirroring bit; instead provide four-screen VRAM
// ++++----- Lower nybble of mapper number

///|
fn newCartridge(data : FixedArray[Int]) -> Cartridge {
  let reader = MemoryReader::new(data)
  let header = reader.readINESHeader()
  if header.magic != iNESMagic {
    abort("header not conforming to iNES format")
  }
  println("iNESMagic matched!!!")

  // mapper type
  let mapper1 = header.control1 >> 4
  let mapper2 = header.control2 >> 4
  let mapper = mapper1 | (mapper2 << 4)
  println("mapper: \{mapper})")

  // mirroring type
  let mirror1 = header.control1 & 1
  let mirror2 = (header.control1 >> 3) & 1
  let mirror = mirror1 | (mirror2 << 1)
  let battery = (
      (

      // battery-backed RAM
        header.control1 >> 1
      ) &
      1
    ) !=
    0
  let prg_len = header.numPRG.to_int() * 16384
  let chr_len = header.numCHR.to_int() * 8192

  // read trainer if present (unused)
  if (header.control1 & 4) == 4 {
    // read trainer. It's not used, but must read it
    let _ = reader.readUInt8Array(512)
    println("has trainer")
  }

  // read prg-rom bank(s)
  let prg = reader.readUInt8Array(prg_len)
  println("read \{prg_len} bytes of prg-rom")

  // read chr-rom bank(s)
  // provide chr-rom/ram if not in file
  let chr : FixedArray[UInt8] = if header.numCHR == 0 {
    FixedArray::make(8192, 0)
  } else {
    println("read \{chr_len} bytes of chr-rom")
    reader.readUInt8Array(chr_len)
  }
  let sram : FixedArray[UInt8] = FixedArray::make(0x2000, 0)
  { prg, chr, sram, mapper, mirror, battery }
}
