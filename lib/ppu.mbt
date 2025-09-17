// SPDX-License-Identifier: MIT
// Copyright (c) 2015 Dennis Felsing
// Copyright (c) 2024 Liu Rujia, International Digital Economy Academy

///|
struct PPUMemory {
  mut nes : NES? // just like CPUMemory
}

///|
fn PPUMemory::new() -> PPUMemory {
  { nes: None }
}

///|
struct PPU {
  mem : PPUMemory
  mut nes : NES? // just like CPUMemory

  // Current state
  mut cycle : Int // 0-340 current "column"
  mut scanLine : Int // 0-261, current "row". 0-239=visible, 240=post, 241-260=vblank, 261=pre
  mut frame : Int64 // frame counter

  // storage variables
  paletteData : FixedArray[UInt8] // 32 bytes.
  nameTableData : FixedArray[UInt8] // 2048 bytes "VRAM"
  oamData : FixedArray[UInt8] // 256 bytes
  //mut front: Picture
  mut back : Picture // nim: ref Picture

  // Registers
  mut v : UInt16 // current vram address (15 bit)
  mut t : UInt16 // temporary vram address (15 bit)
  mut x : UInt8 // fine x scroll (3 bit)
  mut w : UInt8 // write toggle (1 bit)
  mut f : UInt8 // even/odd frame flag (1 bit)
  mut register : UInt8

  // NMI flags
  mut nmiOccured : Bool
  mut nmiOutput : Bool
  mut nmiPrevious : Bool
  mut nmiDelay : UInt8

  // background temporary variables
  mut nameTable : UInt8
  mut attributeTable : UInt8
  mut lowTile : UInt8
  mut highTile : UInt8
  mut tileData : Int64

  // sprites temporary variables
  mut spriteCount : Int
  mut spritePatterns : FixedArray[UInt32] // len=8
  mut spritePositions : FixedArray[UInt8] // len=8
  mut spritePriorities : FixedArray[UInt8] // len=8
  mut spriteIndices : FixedArray[UInt8] // len=8

  // $2000 PPUCTRL
  mut flagNameTable : UInt8 // 0: $2000; 1: $2400; 2: $2800; 3: $2C00  **NOT USED
  mut flagIncrement : Bool // 0: add 1; 1: add 32
  mut flagSpriteTable : Bool // 0: $0000; 1: $1000; ignored in 8x16 mode
  mut flagBackgroundTable : Bool // 0: $0000; 1: $1000
  mut flagSpriteSize : Bool // 0: 8x8; 1: 8x16
  mut flagMasterSlave : Bool // 0: read EXT; 1: write EXT  **NOT USED

  // $2001 PPUMASK
  mut flagGrayscale : Bool // 0: color; 1: grayscale
  mut flagShowLeftBackground : Bool // 0: hide; 1: show
  mut flagShowLeftSprites : Bool // 0: hide; 1: show
  mut flagShowBackground : Bool // 0: hide; 1: show
  mut flagShowSprites : Bool // 0: hide; 1: show
  mut flagRedTint : Bool // 0: normal; 1: emphasized
  mut flagGreenTint : Bool // 0: normal; 1: emphasized
  mut flagBlueTint : Bool // 0: normal; 1: emphasized

  // $2002 PPUSTATUS
  mut flagSpriteZeroHit : Bool
  mut flagSpriteOverflow : Bool

  // $2003 OAMADDR
  mut oamAddress : UInt8

  // $2007 PPUDATA
  mut bufferedData : UInt8 // for buffered reads
}

///|
struct Color(Int) // 0xrrggbb

// type alias will be better

///|
struct Picture {
  pixels : FixedArray[FixedArray[Color]] // [240][256]
}

///|
let resolution : (Int, Int) = (256, 240)

///|
fn Picture::new() -> Picture {
  {
    pixels: FixedArray::makei(resolution.1, fn(_i) {
      FixedArray::make(resolution.0, Color(0))
    }),
  }
}

// len=0x40

///|
fn initPalette() -> FixedArray[Color] {
  let cs : FixedArray[_] = [
    0x666666, 0x002A88, 0x1412A7, 0x3B00A4, 0x5C007E, 0x6E0040, 0x6C0600, 0x561D00,
    0x333500, 0x0B4800, 0x005200, 0x004F08, 0x00404D, 0x000000, 0x000000, 0x000000,
    0xADADAD, 0x155FD9, 0x4240FF, 0x7527FE, 0xA01ACC, 0xB71E7B, 0xB53120, 0x994E00,
    0x6B6D00, 0x388700, 0x0C9300, 0x008F32, 0x007C8D, 0x000000, 0x000000, 0x000000,
    0xFFFEFF, 0x64B0FF, 0x9290FF, 0xC676FF, 0xF36AFF, 0xFE6ECC, 0xFE8170, 0xEA9E22,
    0xBCBE00, 0x88D800, 0x5CE430, 0x45E082, 0x48CDDE, 0x4F4F4F, 0x000000, 0x000000,
    0xFFFEFF, 0xC0DFFF, 0xD3D2FF, 0xE8C8FF, 0xFBC2FF, 0xFEC4EA, 0xFECCC5, 0xF7D8A5,
    0xE4E594, 0xCFEF96, 0xBDF4AB, 0xB3F3CC, 0xB5EBF2, 0xB8B8B8, 0x000000, 0x000000,
  ]
  cs.map(Color(_))
}

///|
let palette : FixedArray[Color] = initPalette()

///|
fn PPU::reset(self : PPU) -> Unit {
  self.cycle = 340
  self.scanLine = 240
  //self.cycle = 25
  //self.scanLine = 0
  self.frame = 0L
  self.writeControl(0 |> to_u8)
  self.writeMask(0 |> to_u8)
  self.writeOAMAddress(0 |> to_u8)
}

///|
fn initPPU() -> PPU {
  let mem = PPUMemory::new()
  let result : PPU = {
    mem,
    nes: None,
    cycle: 0,
    scanLine: 0,
    frame: 0L,
    paletteData: FixedArray::make(32, 0 |> to_u8),
    nameTableData: FixedArray::make(2048, 0 |> to_u8),
    oamData: FixedArray::make(256, 0 |> to_u8),
    back: Picture::new(),
    //front: Picture::new(),
    // backbuffer
    v: 0 |> to_u16,
    t: 0 |> to_u16,
    x: 0 |> to_u8,
    w: 0 |> to_u8,
    f: 0 |> to_u8,
    register: 0 |> to_u8,
    nmiOccured: false,
    nmiOutput: false,
    nmiPrevious: false,
    nmiDelay: 0 |> to_u8,
    nameTable: 0 |> to_u8,
    attributeTable: 0 |> to_u8,
    lowTile: 0 |> to_u8,
    highTile: 0 |> to_u8,
    tileData: 0L,
    spriteCount: 0,
    spritePatterns: FixedArray::make(8, 0 |> to_u32),
    spritePositions: FixedArray::make(8, 0 |> to_u8),
    spritePriorities: FixedArray::make(8, 0 |> to_u8),
    spriteIndices: FixedArray::make(8, 0 |> to_u8),
    flagNameTable: 0 |> to_u8,
    flagIncrement: false,
    flagSpriteTable: false,
    flagBackgroundTable: false,
    flagSpriteSize: false,
    flagMasterSlave: false,
    flagGrayscale: false,
    flagShowLeftBackground: false,
    flagShowLeftSprites: false,
    flagShowBackground: false,
    flagShowSprites: false,
    flagRedTint: false,
    flagGreenTint: false,
    flagBlueTint: false,
    flagSpriteZeroHit: false,
    flagSpriteOverflow: false,
    oamAddress: 0 |> to_u8,
    bufferedData: 0 |> to_u8,
  }
  result.reset()
  result
}

// https://www.nesdev.org/wiki/Mirroring

///|
let mirrorLookup = [
  [0, 0, 1, 1],
  [0, 1, 0, 1],
  [0, 0, 0, 0],
  [1, 1, 1, 1],
  [0, 1, 2, 3],
]

///|
fn mirrorAddress(mode : UInt8, adr : UInt16) -> UInt16 {
  let adr = (adr - (0x2000 |> to_u16)).inner() % 0x1000
  let table = (adr / 0x0400) |> to_u8
  let offset = adr % 0x0400

  // TODO: do we need to do wrapped op every time?
  (mirrorLookup[mode.inner()][table.inner()] * 0x0400 + 0x2000 + offset)
  |> to_u16
}

///|
fn paletteAdr(adr : UInt16) -> Int {
  if adr >= (16 |> to_u16) && adr.inner() % 4 == 0 {
    adr.inner() - 16
  } else {
    adr.inner()
  }
}

///|
fn PPU::readPalette(self : PPU, adr : UInt16) -> UInt8 {
  self.paletteData[paletteAdr(adr)]
}

///|
fn PPU::writePalette(self : PPU, adr : UInt16, val : UInt8) -> Unit {
  self.paletteData[paletteAdr(adr)] = val
}

// https://www.nesdev.org/wiki/PPU_memory_map
// PPU memory map
// The PPU addresses a 14-bit (16kB) address space, $0000-3FFF, completely separate from the CPU's address bus. It is either directly accessed by the PPU itself, or via the CPU with memory mapped registers at $2006 and $2007.

// The NES has 2kB of RAM dedicated to the PPU, normally mapped to the nametable address space from $2000-2FFF, but this can be rerouted through custom cartridge wiring.

// Address range	Size	Description
// $0000-$0FFF	$1000	Pattern table 0
// $1000-$1FFF	$1000	Pattern table 1
// $2000-$23FF	$0400	Nametable 0
// $2400-$27FF	$0400	Nametable 1
// $2800-$2BFF	$0400	Nametable 2
// $2C00-$2FFF	$0400	Nametable 3
// $3000-$3EFF	$0F00	Mirrors of $2000-$2EFF
// $3F00-$3F1F	$0020	Palette RAM indexes
// $3F20-$3FFF	$00E0	Mirrors of $3F00-$3F1F

// In addition, the PPU internally contains 256 bytes of memory known as Object Attribute Memory which determines how sprites are rendered. The CPU can manipulate this memory through memory mapped registers at OAMADDR ($2003), OAMDATA ($2004), and OAMDMA ($4014). OAM can be viewed as an array with 64 entries. Each entry has 4 bytes: the sprite Y coordinate, the sprite tile number, the sprite attribute, and the sprite X coordinate.

// Address Low Nibble	Description
// $00, $04, $08, $0C	Sprite Y coordinate
// $01, $05, $09, $0D	Sprite tile #
// $02, $06, $0A, $0E	Sprite attribute
// $03, $07, $0B, $0F	Sprite X coordinate

// Hardware mapping
// The mappings above are the fixed addresses from which the PPU uses to fetch data during rendering. The actual device that the PPU fetches data from, however, may be configured by the cartridge.

// $0000-1FFF is normally mapped by the cartridge to a CHR-ROM or CHR-RAM, often with a bank switching mechanism.
// $2000-2FFF is normally mapped to the 2kB NES internal VRAM, providing 2 nametables with a mirroring configuration controlled by the cartridge, but it can be partly or fully remapped to RAM on the cartridge, allowing up to 4 simultaneous nametables.
// $3000-3EFF is usually a mirror of the 2kB region from $2000-2EFF. The PPU does not render from this address range, so this space has negligible utility.
// $3F00-3FFF is not configurable, always mapped to the internal palette control.

///|
fn PPUMemory::op_get(self : PPUMemory, adr : UInt16) -> UInt8 {
  let adr = adr % (0x4000 |> to_u16)
  let nes = self.nes.unwrap()
  if adr.inner() >= 0x0000 && adr.inner() <= 0x1FFF {
    let m = nes.mapper.unwrap()
    m[adr]
  } else if adr.inner() >= 0x2000 && adr.inner() <= 0x3EFF {
    let mode = nes.cartridge.mirror
    nes.ppu.nameTableData[(mirrorAddress(mode, adr) % (2048 |> to_u16)).inner()]
  } else if adr.inner() >= 0x3F00 && adr.inner() <= 0x3FFF {
    nes.ppu.readPalette(adr % (32 |> to_u16))
  } else {
    0 |> to_u8
  }
}

///|
fn PPUMemory::op_set(self : PPUMemory, adr : UInt16, val : UInt8) -> Unit {
  let adr = adr % (0x4000 |> to_u16)
  let nes = self.nes.unwrap()
  if adr.inner() >= 0x0000 && adr.inner() <= 0x1FFF {
    let m = nes.mapper.unwrap()
    m[adr] = val
  } else if adr.inner() >= 0x2000 && adr.inner() <= 0x3EFF {
    let mode = nes.cartridge.mirror
    nes.ppu.nameTableData[(mirrorAddress(mode, adr) % (2048 |> to_u16)).inner()] = val
  } else if adr.inner() >= 0x3F00 && adr.inner() <= 0x3FFF {
    nes.ppu.writePalette(adr % (32 |> to_u16), val)
  }
}

///|
fn PPU::readRegister(self : PPU, adr : UInt16) -> UInt8 {
  match adr.inner() {
    0x2002 => self.readStatus()
    0x2004 => self.readOAMData()
    0x2007 => self.readData()
    _ => 0 |> to_u8
  }
}

///|
fn PPU::writeRegister(self : PPU, adr : UInt16, val : UInt8) -> Unit {
  self.register = val
  match adr.inner() {
    0x2000 => self.writeControl(val)
    0x2001 => self.writeMask(val)
    0x2003 => self.writeOAMAddress(val)
    0x2004 => self.writeOAMData(val)
    0x2005 => self.writeScroll(val)
    0x2006 => self.writeAddress(val)
    0x2007 => self.writeData(val)
    0x4014 => self.writeDMA(val)
    _ => ()
  }
}

// $2000: PPUCTRL

///|
fn PPU::writeControl(self : PPU, val : UInt8) -> Unit {
  self.flagNameTable = val & (3 |> to_u8)
  self.flagIncrement = val.bit(2)
  self.flagSpriteTable = val.bit(3)
  self.flagBackgroundTable = val.bit(4)
  self.flagSpriteSize = val.bit(5)
  self.flagMasterSlave = val.bit(6)
  self.nmiOutput = val.bit(7)
  self.nmiChange()
  // t: ....BA.. ........ = d: ......BA
  //ppu.t = (ppu.t & 0xF3FF) | ((uint16(value) & 0x03) << 10)
  self.t = (self.t & (0xF3FF |> to_u16)) |
    ((val.u16() & (0x03 |> to_u16)) << 10)
}

// $2001: PPUMASK

///|
fn PPU::writeMask(self : PPU, val : UInt8) -> Unit {
  self.flagGrayscale = val.bit(0)
  self.flagShowLeftBackground = val.bit(1)
  self.flagShowLeftSprites = val.bit(2)
  self.flagShowBackground = val.bit(3)
  self.flagShowSprites = val.bit(4)
  self.flagRedTint = val.bit(5)
  self.flagGreenTint = val.bit(6)
  self.flagBlueTint = val.bit(7)
}

// $2002: PPUSTATUS

///|
fn PPU::readStatus(self : PPU) -> UInt8 {
  // TODO: wait for bitwise operators
  let mut result = self.register & (0x1F |> to_u8)
  result = result | ((self.flagSpriteOverflow |> to_u8()) << 5)
  result = result | ((self.flagSpriteZeroHit |> to_u8()) << 6)
  if self.nmiOccured {
    result = result | ((1 |> to_u8) << 7)
  }
  self.nmiOccured = false
  self.nmiChange()
  self.w = 0 |> to_u8
  result
}

// $2003: OAMADDR

///|
fn PPU::writeOAMAddress(self : PPU, val : UInt8) -> Unit {
  self.oamAddress = val
}

// $2004: OAMDATA (read)

///|
fn PPU::readOAMData(self : PPU) -> UInt8 {
  let mut data = self.oamData[self.oamAddress.inner()]
  if (self.oamAddress & (0x03 |> to_u8)) == (0x02 |> to_u8) {
    data = data & (0xE3 |> to_u8)
  }
  return data
}

// $2004: OAMDATA (write)

///|
fn PPU::writeOAMData(self : PPU, val : UInt8) -> Unit {
  self.oamData[self.oamAddress.inner()] = val
  self.oamAddress = self.oamAddress + (1 |> to_u8)
}

// $2005: PPUSCROLL

///|
fn PPU::writeScroll(self : PPU, val : UInt8) -> Unit {
  if self.w == (0 |> to_u8) {
    // t: ........ ...HGFED = d: HGFED...
    // x:               CBA = d: .....CBA
    // w:                   = 1
    //ppu.t = (ppu.t & 0xFFE0) | (uint16(value) >> 3)
    //ppu.x = value & 0x07
    self.t = (self.t & (0xFFE0 |> to_u16)) | (val.u16() >> 3)
    self.x = val & (0x07 |> to_u8)
    self.w = 1 |> to_u8
  } else {
    // t: .CBA..HG FED..... = d: HGFEDCBA
    // w:                   = 0
    //ppu.t = (ppu.t & 0x8FFF) | ((uint16(value) & 0x07) << 12)
    //ppu.t = (ppu.t & 0xFC1F) | ((uint16(value) & 0xF8) << 2)
    self.t = (self.t & (0x8FFF |> to_u16)) |
      ((val.u16() & (0x07 |> to_u16)) << 12)
    self.t = (self.t & (0xFC1F |> to_u16)) |
      ((val.u16() & (0xF8 |> to_u16)) << 2)
    self.w = 0 |> to_u8
  }
}

// $2006: PPUADDR

///|
fn PPU::writeAddress(self : PPU, val : UInt8) -> Unit {
  if self.w == (0 |> to_u8) {
    // t: ..FEDCBA ........ = d: ..FEDCBA
    // t: .X...... ........ = 0
    // w:                   = 1
    //ppu.t = (ppu.t & 0x80FF) | ((uint16(value) & 0x3F) << 8)
    self.t = (self.t & (0x80FF |> to_u16)) |
      ((val.u16() & (0x3F |> to_u16)) << 8)
    self.w = 1 |> to_u8
  } else {
    // t: ........ HGFEDCBA = d: HGFEDCBA
    // v                    = t
    // w:                   = 0
    //ppu.t = (ppu.t & 0xFF00) | uint16(value)
    self.t = (self.t & (0xFF00 |> to_u16)) | val.u16()
    self.v = self.t
    self.w = 0 |> to_u8
  }
}

// $2007: PPUDATA (read)

///|
fn PPU::readData(self : PPU) -> UInt8 {
  let mut val = self.mem[self.v]

  // emulate buffered reads
  if self.v.inner() % 0x4000 < 0x3F00 {
    // (self.bufferedData, result) = (result, self.bufferedData)
    let buffered = self.bufferedData
    self.bufferedData = val
    val = buffered
  } else {
    self.bufferedData = self.mem[self.v - (0x1000 |> to_u16)]
  }
  if not(self.flagIncrement) {
    self.v = self.v + (1 |> to_u16)
  } else {
    self.v = self.v + (32 |> to_u16)
  }
  val
}

// $2007: PPUDATA (write)

///|
fn PPU::writeData(self : PPU, val : UInt8) -> Unit {
  self.mem[self.v] = val
  if not(self.flagIncrement) {
    self.v = self.v + (1 |> to_u16)
  } else {
    self.v = self.v + (32 |> to_u16)
  }
}

// $4014: OAMDMA

///|
fn PPU::writeDMA(self : PPU, val : UInt8) -> Unit {
  let nes = self.nes.unwrap()
  let cpu = nes.cpu
  for i = 0, adr = val.u16() << 8
      i <= 255
      i = i + 1, adr = adr + (1 |> to_u16) {
    self.oamData[self.oamAddress.inner()] = cpu.mem[adr]
    self.oamAddress = self.oamAddress + (1 |> to_u8)
  }
  cpu.stall = cpu.stall + 513
  if cpu.cycles % 2L == 1L {
    cpu.stall = cpu.stall + 1
  }
}

// NTSC Timing Helper Functions

///|
fn PPU::incrementX(self : PPU) -> Unit {
  // increment hori(v)
  // if coarse X == 31
  if (self.v & (0x001F |> to_u16)) == (31 |> to_u16) {
    // coarse X = 0
    self.v = self.v & (0xFFE0 |> to_u16)
    // switch horizontal nametable
    self.v = self.v ^ (0x0400 |> to_u16)
  } else {
    // increment coarse X
    self.v = self.v + (1 |> to_u16)
  }
}

///|
fn PPU::incrementY(self : PPU) -> Unit {
  // increment vert(v)
  // if fine Y < 7
  if (self.v & (0x7000 |> to_u16)) != (0x7000 |> to_u16) {
    // increment fine Y
    self.v = self.v + (0x1000 |> to_u16)
  } else {
    // fine Y = 0
    self.v = self.v & (0x8FFF |> to_u16)
    // let y = coarse Y
    let mut y = (self.v & (0x03E0 |> to_u16)) >> 5
    if y == (29 |> to_u16) {
      // coarse Y = 0
      y = 0 |> to_u16
      // switch vertical nametable
      self.v = self.v ^ (0x0800 |> to_u16)
    } else if y == (31 |> to_u16) {
      // coarse Y = 0, nametable not switched
      y = 0 |> to_u16
    } else {
      // increment coarse Y
      y = y + (1 |> to_u16)
    }
    // put coarse Y back into v
    //ppu.v = (ppu.v & 0xFC1F) | (y << 5)
    self.v = (self.v & (0xFC1F |> to_u16)) | (y << 5)
  }
}

///|
fn PPU::copyX(self : PPU) -> Unit {
  // hori(v) = hori(t)
  // v: .....F.. ...EDCBA = t: .....F.. ...EDCBA
  self.v = (self.v & (0xFBE0 |> to_u16)) | (self.t & (0x041F |> to_u16))
}

///|
fn PPU::copyY(self : PPU) -> Unit {
  // vert(v) = vert(t)
  // v: .IHGF.ED CBA..... = t: .IHGF.ED CBA.....
  self.v = (self.v & (0x841F |> to_u16)) | (self.t & (0x7BE0 |> to_u16))
}

///|
fn PPU::nmiChange(self : PPU) -> Unit {
  let nmi = self.nmiOutput && self.nmiOccured
  if nmi && not(self.nmiPrevious) {
    // TODO: this fixes some games but the delay shouldn't have to be so
    // long, so the timings are off somewhere
    self.nmiDelay = 15 |> to_u8
  }
  self.nmiPrevious = nmi
}

///|
fn PPU::setVerticalBlank(self : PPU) -> Unit {
  //swap ppu.front, ppu.back[]
  //tmp := self.front
  //self.front = self.back
  //self.back = tmp

  // transfer a frame image to host
  for row = 0; row < resolution.1; row = row + 1 {
    for col = 0; col < resolution.0; col = col + 1 {
      let color = self.back.pixels[row][col].inner()
      nes_write_color(
        row * resolution.0 + col,
        red=(color.land(0xFF0000).reinterpret_as_uint() >> 16)
          |> UInt::reinterpret_as_int,
        green=(color.land(0xFF00).reinterpret_as_uint() >> 8)
          |> UInt::reinterpret_as_int,
        blue=color & 0xFF,
      )
    }
  }
  self.nmiOccured = true
  self.nmiChange()
}

///|
fn PPU::clearVerticalBlank(self : PPU) -> Unit {
  self.nmiOccured = false
  self.nmiChange()
}

///|
fn PPU::fetchNameTableByte(self : PPU) -> Unit {
  let v = self.v
  let adr = (0x2000 |> to_u16) | (v & (0x0FFF |> to_u16))
  self.nameTable = self.mem[adr]
}

///|
fn PPU::fetchAttributeTableByte(self : PPU) -> Unit {
  let v = self.v
  // CHECKME
  // address := 0x23C0 | (v & 0x0C00) | ((v >> 4) & 0x38) | ((v >> 2) & 0x07)
  let adr = (0x23C0 |> to_u16) |
    (v & (0x0C00 |> to_u16)) |
    ((v >> 4) & (0x38 |> to_u16)) |
    ((v >> 2) & (0x07 |> to_u16))
  // CHECKME
  // shift := ((v >> 4) & 4) | (v & 2)
  let shift = (((v >> 4) & (4 |> to_u16)) | (v & (2 |> to_u16))) |> to_u8
  // ppu.attributeTableByte = ((ppu.Read(address) >> shift) & 3) << 2
  self.attributeTable = ((self.mem[adr] >> shift.inner()) & (3 |> to_u8)) << 2
}

// fineY := (ppu.v >> 12) & 7
// table := ppu.flagBackgroundTable
// tile := ppu.nameTableByte
// address := 0x1000*uint16(table) + uint16(tile)*16 + fineY

///|
fn PPU::tileAdr(self : PPU) -> Int {
  let fineY = (self.v >> 12) & (7 |> to_u16)
  let table = self.flagBackgroundTable
  let tile = self.nameTable
  0x1000 * (table |> to_u8).inner() + tile.inner() * 16 + fineY.inner()
}

///|
fn PPU::fetchLowTileByte(self : PPU) -> Unit {
  self.lowTile = self.mem[self.tileAdr() |> to_u16]
}

///|
fn PPU::fetchHighTileByte(self : PPU) -> Unit {
  self.highTile = self.mem[(self.tileAdr() + 8) |> to_u16]
}

// Attention to coersions!

///|
fn PPU::storeTileData(self : PPU) -> Unit {
  let data = for i = 0, data = 0L; i < 8; {
    let a = self.attributeTable
    let p1 = (self.lowTile & (0x80 |> to_u8)) >> 7
    let p2 = (self.highTile & (0x80 |> to_u8)) >> 6
    self.lowTile = self.lowTile << 1
    self.highTile = self.highTile << 1
    continue i + 1,
      (data << 4) |
      a.inner().to_int64() |
      p1.inner().to_int64() |
      p2.inner().to_int64()
  } else { // data |= uint32(a | p1 | p2)
    data
  }
  self.tileData = self.tileData | data
}

///|
fn PPU::fetchTileData(self : PPU) -> UInt32 {
  (self.tileData >> 32) |> Int64::to_int |> to_u32
}

///|
fn PPU::backgroundPixel(self : PPU) -> UInt8 {
  if not(self.flagShowBackground) {
    return 0 |> to_u8
  }
  let data = self.fetchTileData() >> ((7 - self.x.inner()) * 4)
  (data.inner() & 0x0F) |> to_u8
}

///|
fn PPU::spritePixel(self : PPU) -> (UInt8, UInt8) {
  if not(self.flagShowSprites) {
    return (0 |> to_u8, 0 |> to_u8)
  }

  //for i in 0 ..< ppu.spriteCount:
  for i = 0; i < self.spriteCount; {
    let mut offset = self.cycle - 1 - self.spritePositions[i].inner()
    //if offset notin 0..7:
    // TODO: change to for ... in
    if offset < 0 || offset > 7 {
      continue i + 1
    }
    offset = 7 - offset
    // CHECKME
    let color = ((self.spritePatterns[i] >> (offset * 4)) & (0x0F |> to_u32))
      |> to_u8()
    if color.inner() % 4 == 0 {
      continue i + 1
    }
    return (i |> to_u8(), color)
  }
  return (0 |> to_u8, 0 |> to_u8)
}

///|
fn PPU::renderPixel(self : PPU) -> Unit {
  let x = self.cycle - 1
  let y = self.scanLine
  let mut background = self.backgroundPixel()
  let (i, sprite) = self.spritePixel()
  let mut sprite = sprite
  if x < 8 {
    if not(self.flagShowLeftBackground) {
      background = 0 |> to_u8
    }
    if not(self.flagShowLeftSprites) {
      sprite = 0 |> to_u8
    }
  }
  let b = background.inner() % 4 != 0
  let s = sprite.inner() % 4 != 0
  let mut color = 0 |> to_u8
  if not(b) && not(s) {
    color = 0 |> to_u8
  } else if not(b) && s {
    color = sprite | (0x10 |> to_u8)
  } else if b && not(s) {
    color = background
  } else {
    if self.spriteIndices[i.inner()] == (0 |> to_u8) && x < 255 {
      self.flagSpriteZeroHit = true
    }
    if self.spritePriorities[i.inner()] == (0 |> to_u8) {
      color = sprite | (0x10 |> to_u8)
    } else {
      color = background
    }
  }
  let c = palette[self.readPalette(color.u16()).inner() % 64]
  self.back.pixels[y][x] = c
}

///|
fn PPU::fetchSpritePattern(self : PPU, i : Int, row : Int) -> UInt32 {
  let mut row = row
  let mut tile = self.oamData[i * 4 + 1]
  let attributes = self.oamData[i * 4 + 2]
  let mut adr = 0 |> to_u16
  let mut table = 0 |> to_u8
  if not(self.flagSpriteSize) {
    if (attributes & (0x80 |> to_u8)) == (0x80 |> to_u8) {
      row = 7 - row
    }
    table = self.flagSpriteTable |> to_u8
  } else {
    if (attributes & (0x80 |> to_u8)) == (0x80 |> to_u8) {
      row = 15 - row
    }
    table = tile & (1 |> to_u8)
    tile = tile & (0xFE |> to_u8)
    if row > 7 {
      tile = tile + (1 |> to_u8)
      row = row - 8
    }
  }

  // CHECK the coercion points
  adr = ((table.inner() * 0x1000) |> to_u16) +
    ((tile.inner() * 16) |> to_u16) +
    (row |> to_u16())
  let a = (attributes & (3 |> to_u8)) << 2
  let mut lowTileByte = self.mem[adr]
  let mut highTileByte = self.mem[adr + (8 |> to_u16)]
  for i = 0, data = (0L |> to_u64()); i < 8; {
    //for i in 0..7:
    let mut p1 = 0 |> to_u8
    let mut p2 = 0 |> to_u8
    if (attributes & (0x40 |> to_u8)) == (0x40 |> to_u8) {
      p1 = lowTileByte & (1 |> to_u8)
      p2 = (highTileByte & (1 |> to_u8)) << 1
      lowTileByte = lowTileByte >> 1
      highTileByte = highTileByte >> 1
    } else {
      p1 = (lowTileByte & (0x80 |> to_u8)) >> 7
      p2 = (highTileByte & (0x80 |> to_u8)) >> 6
      lowTileByte = lowTileByte << 1
      highTileByte = highTileByte << 1
    }
    continue i + 1, (data << 4) | a.u64() | p1.u64() | p2.u64()
  } else {
    data |> to_u32()
  }
}

///|
fn PPU::evaluateSprites(self : PPU) -> Unit {
  let h = if not(self.flagSpriteSize) { 8 } else { 16 }
  let count = for i = 0, count = 0; i < 64; i = i + 1, count = count + 1 {
    let y = self.oamData[i * 4 + 0]
    let a = self.oamData[i * 4 + 2]
    let x = self.oamData[i * 4 + 3]
    let row = self.scanLine - y.inner()
    if row < 0 || row >= h {
      continue i + 1, count
    }
    if count < 8 {
      self.spritePatterns[count] = self.fetchSpritePattern(i, row)
      self.spritePositions[count] = x
      self.spritePriorities[count] = (a >> 5) & (1 |> to_u8)
      self.spriteIndices[count] = i |> to_u8
    }
  } else {
    count
  }
  if count > 8 {
    self.spriteCount = 8
    self.flagSpriteOverflow = true
  } else {
    self.spriteCount = count
  }
}

// tick updates Cycle, ScanLine and Frame counters

///|
fn PPU::tick(self : PPU, trace_log : Bool) -> Unit {
  let nes = self.nes.unwrap()
  if self.nmiDelay > (0 |> to_u8) {
    if trace_log {
      println("nmiDelay: " + self.nmiDelay.to_string())
    }
    self.nmiDelay = self.nmiDelay - (1 |> to_u8)
    if self.nmiDelay == (0 |> to_u8) && self.nmiOutput && self.nmiOccured {
      nes.cpu.triggerNMI()
    }
  }
  if self.flagShowBackground || self.flagShowSprites {
    if self.f == (1 |> to_u8) && self.scanLine == 261 && self.cycle == 339 {
      self.cycle = 0
      self.scanLine = 0
      self.frame = self.frame + 1L
      self.f = self.f ^ (1 |> to_u8)
      return
    }
  }
  self.cycle = self.cycle + 1
  if self.cycle > 340 {
    self.cycle = 0
    self.scanLine = self.scanLine + 1
    if self.scanLine > 261 {
      self.scanLine = 0
      self.frame = self.frame + 1L
      self.f = self.f ^ (1 |> to_u8)
    }
  }
}

// Step executes a single PPU cycle

///|
fn PPU::step(self : PPU, trace_log : Bool) -> Unit {
  self.tick(trace_log)
  let renderingEnabled = self.flagShowBackground || self.flagShowSprites
  let preLine = self.scanLine == 261
  let visibleLine = self.scanLine < 240
  let renderLine = preLine || visibleLine
  let preFetchCycle = self.cycle >= 321 && self.cycle <= 336
  let visibleCycle = self.cycle >= 1 && self.cycle <= 256
  let fetchCycle = preFetchCycle || visibleCycle

  // Background logic
  if renderingEnabled {
    if visibleLine && visibleCycle {
      self.renderPixel()
    }
    if renderLine && fetchCycle {
      self.tileData = self.tileData << 4
      match self.cycle % 8 {
        0 => self.storeTileData()
        1 => self.fetchNameTableByte()
        3 => self.fetchAttributeTableByte()
        5 => self.fetchLowTileByte()
        7 => self.fetchHighTileByte()
        _ => ()
      }
    }
    if preLine && self.cycle >= 280 && self.cycle <= 304 {
      self.copyY()
    }
    if renderLine {
      if fetchCycle && self.cycle % 8 == 0 {
        self.incrementX()
      }
      if self.cycle == 256 {
        self.incrementY()
      }
      if self.cycle == 257 {
        self.copyX()
      }
    }
  }

  // Sprite logic
  if renderingEnabled {
    if self.cycle == 257 {
      if visibleLine {
        self.evaluateSprites()
      } else {
        self.spriteCount = 0
      }
    }
  }

  // VBlank logic
  if self.scanLine == 241 && self.cycle == 1 {
    self.setVerticalBlank()
  }
  if preLine && self.cycle == 1 {
    self.clearVerticalBlank()
    self.flagSpriteZeroHit = false
    self.flagSpriteOverflow = false
  }
}
