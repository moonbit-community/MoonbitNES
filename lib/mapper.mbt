// SPDX-License-Identifier: MIT
// Copyright (c) 2015 Dennis Felsing
// Copyright (c) 2024 Liu Rujia, International Digital Economy Academy

///|
struct Mapper {
  _step : () -> Unit
  _idx : (UInt16) -> UInt8
  _idxSet : (UInt16, UInt8) -> Unit
}

// wrapper methods

///|
fn Mapper::step(self : Mapper) -> Unit {
  (self._step)()
}

///|
fn Mapper::op_get(self : Mapper, adr : UInt16) -> UInt8 {
  (self._idx)(adr)
}

///|
fn Mapper::op_set(self : Mapper, adr : UInt16, val : UInt8) -> Unit {
  (self._idxSet)(adr, val)
}

///|
trait IMapper {
  step(Self) -> Unit
  idx(Self, UInt16) -> UInt8
  idxSet(Self, UInt16, UInt8) -> Unit
}

// can't write `self: T`

///|
fn[T : IMapper] to_mapper(m : T) -> Mapper {
  {
    _step: fn() { m.step() },
    _idx: fn(adr) { m.idx(adr) },
    _idxSet: fn(adr, val) { m.idxSet(adr, val) },
  }
}

// Mapper 0(NROM)
// https://www.nesdev.org/wiki/NROM
// The generic designation NROM refers to the Nintendo cartridge boards NES-NROM-128, NES-NROM-256, their HVC counterparts, and clone boards.
// he suffixes 128 and 256 refer to kilobits by Nintendo's own designation; not kilobytes
// [Overview]
// PRG ROM size: 16 KiB for NROM-128, 32 KiB for NROM-256 (DIP-28 standard pinout)
// PRG ROM bank size: Not bankswitched
// PRG RAM: 2 or 4 KiB, not bankswitched, only in Family Basic (but most emulators provide 8)
// CHR capacity: 8 KiB ROM (DIP-28 standard pinout) but most emulators support RAM
// CHR bank size: Not bankswitched, see CNROM
// Nametable mirroring: Solder pads select vertical or horizontal mirroring
// Subject to bus conflicts: Yes, but irrelevant
// [Banks]
// All Banks are fixed,
// CPU $6000-$7FFF: Family Basic only: PRG RAM, mirrored as necessary to fill entire 8 KiB window, write protectable with an external switch
// CPU $8000-$BFFF: First 16 KB of ROM.
// CPU $C000-$FFFF: Last 16 KB of ROM (NROM-256) or mirror of $8000-$BFFF (NROM-128).

// Mapper 2(UNROM)
// https://www.nesdev.org/wiki/UxROM
// Example games: Mega Man, Castlevania, Contra, Duck Tales, Metal Gear
// iNES Mapper 002 is the implementation of the most common usage of UxROM compatible boards
// [Banks]
// CPU $8000-$BFFF: 16 KB switchable PRG ROM bank
// CPU $C000-$FFFF: 16 KB PRG ROM bank, fixed to the last bank
// [Registers]
// Bank select ($8000-$FFFF)
// 7  bit  0
// ---- ----
// xxxx pPPP
//      ||||
//      ++++- Select 16 KB PRG ROM bank for CPU $8000-$BFFF
//           (UNROM uses bits 2-0; UOROM uses bits 3-0)

// Note:
// 1. CHR ROM space is always 8KiB, though in Mapper 2 there is no CHR at all.
// 2. Attention to PRG RAM mirroring

///|
struct Mapper2 {
  cartridge : Cartridge
  prgBanks : Int
  mut prgBank1 : Int
  prgBank2 : Int
}

///|
impl IMapper for Mapper2 with step(self : Mapper2) -> Unit {

}

///|
impl IMapper for Mapper2 with idx(self : Mapper2, adr : UInt16) -> UInt8 {
  if adr >= (0x0000 |> to_u16) && adr <= (0x1FFF |> to_u16) {
    return self.cartridge.chr[adr.inner()]
  } else if adr >= (0x6000 |> to_u16) && adr <= (0x7FFF |> to_u16) {
    return self.cartridge.sram[adr.inner() - 0x6000]
  } else if adr >= (0x8000 |> to_u16) && adr <= (0xBFFF |> to_u16) {
    let offset = self.prgBank1 * 0x4000 + (adr.inner() - 0x8000)
    return self.cartridge.prg[offset]
  } else if adr >= (0xC000 |> to_u16) && adr <= (0xFFFF |> to_u16) {
    let offset = self.prgBank2 * 0x4000 + (adr.inner() - 0xC000)
    return self.cartridge.prg[offset]
  } else {
    0 |> to_u8
  }
} // should raise exception

///|
impl IMapper for Mapper2 with idxSet(self : Mapper2, adr : UInt16, val : UInt8) -> Unit {
  if adr >= (0x0000 |> to_u16) && adr <= (0x1FFF |> to_u16) {
    self.cartridge.chr[adr.inner()] = val // "but most emulators support RAM"
  } else if adr >= (0x6000 |> to_u16) && adr <= (0x7FFF |> to_u16) {
    self.cartridge.sram[adr.inner() - 0x6000] = val
  } else if adr >= (0x8000 |> to_u16) {
    self.prgBank1 = val.inner() % self.prgBanks
  }
}

///|
fn Mapper2::new(cartridge : Cartridge) -> Mapper2 {
  let prg_len = cartridge.prg.length()
  let prgBanks = prg_len / 0x4000
  println("Mapper2::new: \{prg_len} \{prgBanks}")
  { cartridge, prgBanks, prgBank1: 0, prgBank2: prgBanks - 1 }
}

///|
fn Mapper2::to_string(self : Mapper2) -> String {
  let prg_len = self.cartridge.prg.length()
  let prgBanks = self.prgBanks
  let prgBank1 = self.prgBank1
  let prgBank2 = self.prgBank2
  "\{prg_len} \{prgBanks} \{prgBank1} \{prgBank2}"
}

///|
impl Show for Mapper2 with output(self, logger) -> Unit {
  logger.write_string(self.to_string())
}

///|
fn newMapper2(self : NES) -> Mapper {
  let mapper = Mapper2::new(self.cartridge)
  println("mapper: \{mapper}")
  to_mapper(mapper)
}

// Mapper 1 (Nitendo MMC1)
// https://www.nesdev.org/wiki/MMC1

///|
struct Mapper1 {
  cartridge : Cartridge
  mut shiftRegister : UInt8
  mut control : UInt8
  mut prgMode : UInt8
  mut chrMode : UInt8
  mut prgBank : UInt8
  mut chrBank0 : UInt8
  mut chrBank1 : UInt8
  prgOffsets : FixedArray[Int] // cnt=2
  chrOffsets : FixedArray[Int] // cnt=2
}

///|
impl IMapper for Mapper1 with step(self : Mapper1) -> Unit {

}

///|
impl IMapper for Mapper1 with idx(self : Mapper1, adr : UInt16) -> UInt8 {
  let mut address = adr.inner()
  if address < 0x2000 {
    let bank = address / 0x1000
    let offset = address % 0x1000
    return self.cartridge.chr[self.chrOffsets[bank] + offset]
  } else if address >= 0x8000 {
    address = address - 0x8000
    let bank = address / 0x4000
    let offset = address % 0x4000
    return self.cartridge.prg[self.prgOffsets[bank] + offset]
  } else if address >= 0x6000 {
    return self.cartridge.sram[address - 0x6000]
  } else {
    abort("unhandled mapper1 read")
  }
}

///|
impl IMapper for Mapper1 with idxSet(self : Mapper1, adr : UInt16, val : UInt8) -> Unit {
  let address = adr.inner()
  if address < 0x2000 {
    let bank = address / 0x1000
    let offset = address % 0x1000
    self.cartridge.chr[self.chrOffsets[bank] + offset] = val
  } else if address >= 0x8000 {
    self.loadRegister(adr, val)
  } else if address >= 0x6000 {
    self.cartridge.sram[address - 0x6000] = val
  } else {
    abort("unhandled mapper1 write")
  }
}

///|
fn Mapper1::loadRegister(self : Mapper1, adr : UInt16, value : UInt8) -> Unit {
  if (value & (0x80 |> to_u8)) == (0x80 |> to_u8) {
    self.shiftRegister = 0x10 |> to_u8
    self.writeControl(self.control | (0x0C |> to_u8))
  } else {
    let complete = (self.shiftRegister & (1 |> to_u8)) == (1 |> to_u8)
    self.shiftRegister = self.shiftRegister >> 1
    self.shiftRegister = self.shiftRegister | ((value & (1 |> to_u8)) << 4)
    if complete {
      self.writeRegister(adr, self.shiftRegister)
      self.shiftRegister = 0x10 |> to_u8
    }
  }
}

///|
fn Mapper1::writeRegister(self : Mapper1, adr : UInt16, value : UInt8) -> Unit {
  let address = adr.inner()
  if address <= 0x9FFF {
    self.writeControl(value)
  } else if address <= 0xBFFF {
    self.writeCHRBank0(value)
  } else if address <= 0xDFFF {
    self.writeCHRBank1(value)
  } else if address <= 0xFFFF {
    self.writePRGBank(value)
  }
}

// Control (internal, $8000-$9FFF)

///|
fn Mapper1::writeControl(self : Mapper1, value : UInt8) -> Unit {
  self.control = value
  self.chrMode = (value >> 4) & (1 |> to_u8)
  self.prgMode = (value >> 2) & (3 |> to_u8)
  let mirror = value & (3 |> to_u8)
  match mirror.inner() {
    0 => self.cartridge.mirror = mirrorSingle0
    1 => self.cartridge.mirror = mirrorSingle1
    2 => self.cartridge.mirror = mirrorVertical
    3 => self.cartridge.mirror = mirrorHorizontal
  }
  self.updateOffsets()
}

// CHR bank 0 (internal, $A000-$BFFF)

///|
fn Mapper1::writeCHRBank0(self : Mapper1, value : UInt8) -> Unit {
  self.chrBank0 = value
  self.updateOffsets()
}

// CHR bank 1 (internal, $C000-$DFFF)

///|
fn Mapper1::writeCHRBank1(self : Mapper1, value : UInt8) -> Unit {
  self.chrBank1 = value
  self.updateOffsets()
}

// PRG bank (internal, $E000-$FFFF)

///|
fn Mapper1::writePRGBank(self : Mapper1, value : UInt8) -> Unit {
  self.prgBank = value & (0x0F |> to_u8)
  self.updateOffsets()
}

///|
fn Mapper1::prgBankOffset(self : Mapper1, index : Int) -> Int {
  let index = (if index >= 0x80 { index - 0x100 } else { index }) %
    (self.cartridge.prg.length() / 0x4000)
  let offset = index * 0x4000
  if offset < 0 {
    offset + self.cartridge.prg.length()
  } else {
    offset
  }
}

///|
fn Mapper1::chrBankOffset(self : Mapper1, index : Int) -> Int {
  let index = (if index >= 0x80 { index - 0x100 } else { index }) %
    (self.cartridge.chr.length() / 0x1000)
  let offset = index * 0x1000
  if offset < 0 {
    offset + self.cartridge.chr.length()
  } else {
    offset
  }
}

// PRG ROM bank mode (0, 1: switch 32 KB at $8000, ignoring low bit of bank number;
//                    2: fix first bank at $8000 and switch 16 KB bank at $C000;
//                    3: fix last bank at $C000 and switch 16 KB bank at $8000)
// CHR ROM bank mode (0: switch 8 KB at a time; 1: switch two separate 4 KB banks)

///|
fn Mapper1::updateOffsets(self : Mapper1) -> Unit {
  match self.prgMode.inner() {
    0 | 1 => {
      self.prgOffsets[0] = self.prgBankOffset(self.prgBank.inner() & 0xFE)
      self.prgOffsets[1] = self.prgBankOffset(self.prgBank.inner() | 0x01)
    }
    2 => {
      self.prgOffsets[0] = 0
      self.prgOffsets[1] = self.prgBankOffset(self.prgBank.inner())
    }
    3 => {
      self.prgOffsets[0] = self.prgBankOffset(self.prgBank.inner())
      self.prgOffsets[1] = self.prgBankOffset(-1)
    }
  }
  match self.chrMode.inner() {
    0 => {
      self.chrOffsets[0] = self.chrBankOffset(self.chrBank0.inner() & 0xFE)
      self.chrOffsets[1] = self.chrBankOffset(self.chrBank0.inner() | 0x01)
    }
    1 => {
      self.chrOffsets[0] = self.chrBankOffset(self.chrBank0.inner())
      self.chrOffsets[1] = self.chrBankOffset(self.chrBank1.inner())
    }
  }
}

///|
fn Mapper1::new(cartridge : Cartridge) -> Mapper1 {
  let result : Mapper1 = {
    cartridge,
    shiftRegister: 0x10 |> to_u8,
    control: 0 |> to_u8,
    prgMode: 0 |> to_u8,
    chrMode: 0 |> to_u8,
    prgBank: 0 |> to_u8,
    chrBank0: 0 |> to_u8,
    chrBank1: 0 |> to_u8,
    prgOffsets: FixedArray::make(2, 0),
    chrOffsets: FixedArray::make(2, 0),
  }
  result.prgOffsets[1] = result.prgBankOffset(-1)
  result
}

///|
fn newMapper1(self : NES) -> Mapper {
  let mapper = Mapper1::new(self.cartridge)
  println("mapper1 initialized")
  to_mapper(mapper)
}

// Mapper 3 (CNROM)
// https://www.nesdev.org/wiki/INES_Mapper_003
// Example games: Solomon's Key, Arkanoid, Arkista's Ring, Bump 'n' Jump, Cybernoid

///|
struct Mapper3 {
  cartridge : Cartridge
  mut chrBank : Int
  mut prgBank1 : Int
  mut prgBank2 : Int
}

///|
impl IMapper for Mapper3 with step(self : Mapper3) -> Unit {

}

///|
impl IMapper for Mapper3 with idx(self : Mapper3, adr : UInt16) -> UInt8 {
  if adr < (0x2000 |> to_u16) {
    let index = self.chrBank * 0x2000 + adr.inner()
    self.cartridge.chr[index]
  } else if adr >= (0xC000 |> to_u16) {
    let index = self.prgBank2 * 0x4000 + (adr.inner() - 0xC000)
    self.cartridge.prg[index]
  } else if adr >= (0x8000 |> to_u16) {
    let index = self.prgBank1 * 0x4000 + (adr.inner() - 0x8000)
    self.cartridge.prg[index]
  } else if adr >= (0x6000 |> to_u16) {
    let index = adr.inner() - 0x6000
    self.cartridge.sram[index]
  } else {
    abort("unhandled mapper3 read")
  }
}

///|
impl IMapper for Mapper3 with idxSet(self : Mapper3, adr : UInt16, val : UInt8) -> Unit {
  if adr < (0x2000 |> to_u16) {
    let index = self.chrBank * 0x2000 + adr.inner()
    self.cartridge.chr[index] = val
  } else if adr >= (0x8000 |> to_u16) {
    self.chrBank = val.inner() & 3
  } else if adr >= (0x6000 |> to_u16) {
    let index = adr.inner() - 0x6000
    self.cartridge.sram[index] = val
  } else {
    abort("unhandled mapper3 write")
  }
}

///|
fn Mapper3::new(cartridge : Cartridge) -> Mapper3 {
  let prgBanks = cartridge.prg.length() / 0x4000
  { cartridge, chrBank: 0, prgBank1: 0, prgBank2: prgBanks - 1 }
}

///|
fn newMapper3(self : NES) -> Mapper {
  let mapper = Mapper3::new(self.cartridge)
  to_mapper(mapper)
}

// Mapper 4 (Nintendo MMC3)
// https://www.nesdev.org/wiki/MMC3
// Many good games
//https://nesdir.github.io/mapper4.html

///|
struct Mapper4 {
  cartridge : Cartridge
  console : NES
  mut register : UInt8
  registers : FixedArray[UInt8] // len=8
  mut prgMode : UInt8
  mut chrMode : UInt8
  prgOffsets : FixedArray[Int] // len=4
  chrOffsets : FixedArray[Int] // len=8
  mut reload : UInt8
  mut counter : UInt8
  mut irqEnable : Bool
}

///|
impl IMapper for Mapper4 with step(self : Mapper4) -> Unit {
  let ppu = self.console.ppu
  if ppu.cycle != 280 { // TODO: this *should* be 260
    return
  }
  if ppu.scanLine > 239 && ppu.scanLine < 261 {
    return
  }
  if ppu.flagShowBackground == false && ppu.flagShowSprites == false {
    return
  }
  self.handleScanLine()
}

///|
impl IMapper for Mapper4 with idx(self : Mapper4, adr : UInt16) -> UInt8 {
  let mut address = adr.inner()
  if address < 0x2000 {
    let bank = address / 0x0400
    let offset = address % 0x0400
    return self.cartridge.chr[self.chrOffsets[bank] + offset]
  } else if address >= 0x8000 {
    address = address - 0x8000
    let bank = address / 0x2000
    let offset = address % 0x2000
    return self.cartridge.prg[self.prgOffsets[bank] + offset]
  } else if address >= 0x6000 {
    return self.cartridge.sram[address - 0x6000]
  } else {
    abort("unhandled mapper4 read")
  }
  return 0 |> to_u8
}

///|
impl IMapper for Mapper4 with idxSet(self : Mapper4, adr : UInt16, val : UInt8) -> Unit {
  let address = adr.inner()
  if address < 0x2000 {
    let bank = address / 0x0400
    let offset = address % 0x0400
    self.cartridge.chr[self.chrOffsets[bank] + offset] = val
  } else if address >= 0x8000 {
    self.writeRegister(adr, val)
  } else if address >= 0x6000 {
    self.cartridge.sram[address - 0x6000] = val
  } else {
    abort("unhandled mapper4 write")
  }
}

///|
fn Mapper4::handleScanLine(self : Mapper4) -> Unit {
  if self.counter == (0 |> to_u8) {
    self.counter = self.reload
  } else {
    self.counter = self.counter - (1 |> to_u8)
    if self.counter == (0 |> to_u8) && self.irqEnable {
      self.console.cpu.triggerIRQ()
    }
  }
}

///|
fn Mapper4::writeRegister(self : Mapper4, adr : UInt16, value : UInt8) -> Unit {
  let address = adr.inner()
  if address <= 0x9FFF && address % 2 == 0 {
    self.writeBankSelect(value)
  } else if address <= 0x9FFF && address % 2 == 1 {
    self.writeBankData(value)
  } else if address <= 0xBFFF && address % 2 == 0 {
    self.writeMirror(value)
  } else if address <= 0xBFFF && address % 2 == 1 {
    self.writeProtect(value)
  } else if address <= 0xDFFF && address % 2 == 0 {
    self.writeIRQLatch(value)
  } else if address <= 0xDFFF && address % 2 == 1 {
    self.writeIRQReload(value)
  } else if address <= 0xFFFF && address % 2 == 0 {
    self.writeIRQDisable(value)
  } else if address <= 0xFFFF && address % 2 == 1 {
    self.writeIRQEnable(value)
  }
}

///|
fn Mapper4::writeBankSelect(self : Mapper4, value : UInt8) -> Unit {
  self.prgMode = (value >> 6) & (1 |> to_u8)
  self.chrMode = (value >> 7) & (1 |> to_u8)
  self.register = value & (7 |> to_u8)
  self.updateOffsets()
}

///|
fn Mapper4::writeBankData(self : Mapper4, value : UInt8) -> Unit {
  self.registers[self.register.inner()] = value
  self.updateOffsets()
}

///|
fn Mapper4::writeMirror(self : Mapper4, value : UInt8) -> Unit {
  match value.inner() & 1 {
    0 => self.cartridge.mirror = mirrorVertical
    1 => self.cartridge.mirror = mirrorHorizontal
  }
}

///|
fn Mapper4::writeProtect(self : Mapper4, value : UInt8) -> Unit {

}

///|
fn Mapper4::writeIRQLatch(self : Mapper4, value : UInt8) -> Unit {
  self.reload = value
}

///|
fn Mapper4::writeIRQReload(self : Mapper4, value : UInt8) -> Unit {
  self.counter = 0 |> to_u8
}

///|
fn Mapper4::writeIRQDisable(self : Mapper4, value : UInt8) -> Unit {
  self.irqEnable = false
}

///|
fn Mapper4::writeIRQEnable(self : Mapper4, value : UInt8) -> Unit {
  self.irqEnable = true
}

///|
fn Mapper4::prgBankOffset(self : Mapper4, index : Int) -> Int {
  let index = (if index >= 0x80 { index - 0x100 } else { index }) %
    (self.cartridge.prg.length() / 0x2000)
  let offset = index * 0x2000
  if offset < 0 {
    offset + self.cartridge.prg.length()
  } else {
    offset
  }
}

///|
fn Mapper4::chrBankOffset(self : Mapper4, index : Int) -> Int {
  let index = (if index >= 0x80 { index - 0x100 } else { index }) %
    (self.cartridge.chr.length() / 0x0400)
  let offset = index * 0x0400
  if offset < 0 {
    offset + self.cartridge.chr.length()
  } else {
    offset
  }
}

///|
fn Mapper4::updateOffsets(self : Mapper4) -> Unit {
  match self.prgMode.inner() {
    0 => {
      self.prgOffsets[0] = self.prgBankOffset(self.registers[6].inner())
      self.prgOffsets[1] = self.prgBankOffset(self.registers[7].inner())
      self.prgOffsets[2] = self.prgBankOffset(-2)
      self.prgOffsets[3] = self.prgBankOffset(-1)
    }
    1 => {
      self.prgOffsets[0] = self.prgBankOffset(-2)
      self.prgOffsets[1] = self.prgBankOffset(self.registers[7].inner())
      self.prgOffsets[2] = self.prgBankOffset(self.registers[6].inner())
      self.prgOffsets[3] = self.prgBankOffset(-1)
    }
  }
  match self.chrMode.inner() {
    0 => {
      self.chrOffsets[0] = self.chrBankOffset(self.registers[0].inner() & 0xFE)
      self.chrOffsets[1] = self.chrBankOffset(self.registers[0].inner() | 0x01)
      self.chrOffsets[2] = self.chrBankOffset(self.registers[1].inner() & 0xFE)
      self.chrOffsets[3] = self.chrBankOffset(self.registers[1].inner() | 0x01)
      self.chrOffsets[4] = self.chrBankOffset(self.registers[2].inner())
      self.chrOffsets[5] = self.chrBankOffset(self.registers[3].inner())
      self.chrOffsets[6] = self.chrBankOffset(self.registers[4].inner())
      self.chrOffsets[7] = self.chrBankOffset(self.registers[5].inner())
    }
    1 => {
      self.chrOffsets[0] = self.chrBankOffset(self.registers[2].inner())
      self.chrOffsets[1] = self.chrBankOffset(self.registers[3].inner())
      self.chrOffsets[2] = self.chrBankOffset(self.registers[4].inner())
      self.chrOffsets[3] = self.chrBankOffset(self.registers[5].inner())
      self.chrOffsets[4] = self.chrBankOffset(self.registers[0].inner() & 0xFE)
      self.chrOffsets[5] = self.chrBankOffset(self.registers[0].inner() | 0x01)
      self.chrOffsets[6] = self.chrBankOffset(self.registers[1].inner() & 0xFE)
      self.chrOffsets[7] = self.chrBankOffset(self.registers[1].inner() | 0x01)
    }
  }
}

///|
fn Mapper4::new(cartridge : Cartridge, nes : NES) -> Mapper4 {
  let result : Mapper4 = {
    cartridge,
    console: nes,
    register: 0 |> to_u8,
    registers: FixedArray::make(8, 0 |> to_u8),
    prgMode: 0 |> to_u8,
    chrMode: 0 |> to_u8,
    prgOffsets: FixedArray::make(4, 0),
    chrOffsets: FixedArray::make(8, 0),
    reload: 0 |> to_u8,
    counter: 0 |> to_u8,
    irqEnable: false,
  }
  result.prgOffsets[0] = result.prgBankOffset(0)
  result.prgOffsets[1] = result.prgBankOffset(1)
  result.prgOffsets[2] = result.prgBankOffset(-2)
  result.prgOffsets[3] = result.prgBankOffset(-1)
  result
}

///|
fn newMapper4(self : NES) -> Mapper {
  let mapper = Mapper4::new(self.cartridge, self)
  to_mapper(mapper)
}

// Mapper 7 (AOROM)
// https://www.nesdev.org/wiki/AxROM
// Example games: Battletoads

///|
struct Mapper7 {
  cartridge : Cartridge
  prgBank : Int
}

///|
impl IMapper for Mapper7 with step(self : Mapper7) -> Unit {

}

///|
impl IMapper for Mapper7 with idx(self : Mapper7, adr : UInt16) -> UInt8 {
  0 |> to_u8
}

///|
impl IMapper for Mapper7 with idxSet(self : Mapper7, adr : UInt16, val : UInt8) -> Unit {

}

///|
fn Mapper7::new(cartridge : Cartridge) -> Mapper7 {
  { cartridge, prgBank: 0 }
}

///|
fn newMapper7(self : NES) -> Mapper {
  let mapper = Mapper7::new(self.cartridge)
  to_mapper(mapper)
}

// a "factory" method
// why pass NES instead of Cartridge? Because Mapper4 needs it, so we'll need it in future

///|
fn Mapper::new(nes : NES) -> Mapper {
  println("creating mapper")
  match nes.cartridge.mapper.inner() {
    0 | 2 => nes.newMapper2()
    1 => nes.newMapper1()
    3 => nes.newMapper3()
    4 => nes.newMapper4()
    7 => nes.newMapper7()
    _ => nes.newMapper2() // TODO: error
  }
}
