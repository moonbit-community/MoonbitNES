// SPDX-License-Identifier: MIT
// Copyright (c) 2015 Dennis Felsing
// Copyright (c) 2024 Liu Rujia, International Digital Economy Academy

struct Cartridge {
  prg : FixedArray[UInt8] // PRG-ROM banks
  chr : FixedArray[UInt8] // CHR-ROM banks
  sram : FixedArray[UInt8] // Save RAM
  mapper : UInt8 // mapper type
  mut mirror : UInt8 // mirroring mode
  battery : Bool // battery present
}

let mirrorHorizontal : UInt8 = 0 |> to_u8()

let mirrorVertical : UInt8 = 1 |> to_u8()

let mirrorSingle0 : UInt8 = 2 |> to_u8()

let mirrorSingle1 : UInt8 = 3 |> to_u8()

let mirrorFour : UInt8 = 4 |> to_u8()

let iNESMagic = 0x1A53454E

// I don't want to capitalize but the format is called `iNES`
struct iNESHeader {
  magic : Int // iNES magic number
  numPRG : UInt8 // number of PRG-ROM banks (16KB each)
  numCHR : UInt8 // number of CHR-ROM banks (8KB each)
  control1 : UInt8 // control bits
  control2 : UInt8 // control bits
  numRAM : UInt8 // PRG-RAM size (x 8KB)
  padding : FixedArray[UInt8] // 7 bytes, unused padding
}

fn readiNESHeader(self : MemoryReader) -> iNESHeader {
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

fn newCartridge(data : FixedArray[Int]) -> Cartridge {
  let reader = MemoryReader::new(data)
  let header = reader.readiNESHeader()
  if header.magic != iNESMagic {
    abort("header not conforming to iNES format")
  }
  println("iNESMagic matched!!!")

  // mapper type
  let mapper1 = header.control1.lsr(4)
  let mapper2 = header.control2.lsr(4)
  let mapper = mapper1.lor(mapper2.lsl(4))
  println("mapper: \{mapper})")

  // mirroring type
  let mirror1 = header.control1.land(1 |> to_u8)
  let mirror2 = header.control1.lsr(3).land(1 |> to_u8)
  let mirror = mirror1.lor(mirror2.lsl(1))

  // battery-backed RAM
  let battery = header.control1.lsr(1).land(1 |> to_u8) != (0 |> to_u8)
  let prg_len = header.numPRG._ * 16384
  let chr_len = header.numCHR._ * 8192

  // read trainer if present (unused)
  if header.control1.land(4 |> to_u8) == (4 |> to_u8) {
    // read trainer. It's not used, but must read it
    let _ = reader.readUInt8Array(512)
    println("has trainer")
  }

  // read prg-rom bank(s)
  let prg = reader.readUInt8Array(prg_len)
  println("read \{prg_len} bytes of prg-rom")

  // read chr-rom bank(s)
  // provide chr-rom/ram if not in file
  let chr = if header.numCHR == (0 |> to_u8) {
    FixedArray::make(8192, 0 |> to_u8)
  } else {
    println("read \{chr_len} bytes of chr-rom")
    reader.readUInt8Array(chr_len)
  }
  let sram = FixedArray::make(0x2000, 0 |> to_u8)
  { prg, chr, sram, mapper, mirror, battery }
}
