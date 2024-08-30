// SPDX-License-Identifier: MIT
// Copyright (c) 2015 Dennis Felsing
// Copyright (c) 2024 Liu Rujia, International Digital Economy Academy

struct Mapper {
  _step : () -> Unit
  _idx : (UInt16) -> UInt8
  _idxSet : (UInt16, UInt8) -> Unit
}

// wrapper methods
fn step(self : Mapper) -> Unit {
  (self._step)()
}

fn op_get(self : Mapper, adr : UInt16) -> UInt8 {
  (self._idx)(adr)
}

fn op_set(self : Mapper, adr : UInt16, val : UInt8) -> Unit {
  (self._idxSet)(adr, val)
}

trait IMapper {
  step(Self) -> Unit
  idx(Self, UInt16) -> UInt8
  idxSet(Self, UInt16, UInt8) -> Unit
}

// can't write `self: T`
fn to_mapper[T : IMapper](m : T) -> Mapper {
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

struct Mapper2 {
  cartridge : Cartridge
  prgBanks : Int
  mut prgBank1 : Int
  prgBank2 : Int
}

fn step(self : Mapper2) -> Unit {

}

fn idx(self : Mapper2, adr : UInt16) -> UInt8 {
  if adr >= (0x0000 |> to_u16) && adr <= (0x1FFF |> to_u16) {
    return self.cartridge.chr[adr.0]
  } else if adr >= (0x6000 |> to_u16) && adr <= (0x7FFF |> to_u16) {
    return self.cartridge.sram[adr.0 - 0x6000]
  } else if adr >= (0x8000 |> to_u16) && adr <= (0xBFFF |> to_u16) {
    let offset = self.prgBank1 * 0x4000 + (adr.0 - 0x8000)
    return self.cartridge.prg[offset]
  } else if adr >= (0xC000 |> to_u16) && adr <= (0xFFFF |> to_u16) {
    let offset = self.prgBank2 * 0x4000 + (adr.0 - 0xC000)
    return self.cartridge.prg[offset]
  } else {
    0 |> to_u8
  }
} // should raise exception

fn idxSet(self : Mapper2, adr : UInt16, val : UInt8) -> Unit {
  if adr >= (0x0000 |> to_u16) && adr <= (0x1FFF |> to_u16) {
    self.cartridge.chr[adr.0] = val // "but most emulators support RAM"
  } else if adr >= (0x6000 |> to_u16) && adr <= (0x7FFF |> to_u16) {
    self.cartridge.sram[adr.0 - 0x6000] = val
  } else if adr >= (0x8000 |> to_u16) {
    self.prgBank1 = val.0 % self.prgBanks
  }
}

fn Mapper2::new(cartridge : Cartridge) -> Mapper2 {
  let prg_len = cartridge.prg.length()
  let prgBanks = prg_len / 0x4000
  println("Mapper2::new: \{prg_len} \{prgBanks}")
  { cartridge, prgBanks, prgBank1: 0, prgBank2: prgBanks - 1 }
}

fn to_string(self : Mapper2) -> String {
  let prg_len = self.cartridge.prg.length()
  let prgBanks = self.prgBanks
  let prgBank1 = self.prgBank1
  let prgBank2 = self.prgBank2
  "\{prg_len} \{prgBanks} \{prgBank1} \{prgBank2}"
}

fn newMapper2(self : NES) -> Mapper {
  let mapper = Mapper2::new(self.cartridge)
  println("mapper: \{mapper}")
  to_mapper(mapper)
}

// Mapper 1 (Nitendo MMC1)
// https://www.nesdev.org/wiki/MMC1
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

fn step(self : Mapper1) -> Unit {

}

fn idx(self : Mapper1, adr : UInt16) -> UInt8 {
  let mut address = adr.0
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

fn idxSet(self : Mapper1, adr : UInt16, val : UInt8) -> Unit {
  let address = adr.0
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

fn loadRegister(self : Mapper1, adr : UInt16, value : UInt8) -> Unit {
  if value.land(0x80 |> to_u8) == (0x80 |> to_u8) {
    self.shiftRegister = 0x10 |> to_u8
    self.writeControl(self.control.lor(0x0C |> to_u8))
  } else {
    let complete = self.shiftRegister.land(1 |> to_u8) == (1 |> to_u8)
    self.shiftRegister = self.shiftRegister.lsr(1)
    self.shiftRegister = self.shiftRegister.lor(value.land(1 |> to_u8).lsl(4))
    if complete {
      self.writeRegister(adr, self.shiftRegister)
      self.shiftRegister = 0x10 |> to_u8
    }
  }
}

fn writeRegister(self : Mapper1, adr : UInt16, value : UInt8) -> Unit {
  let address = adr.0
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
fn writeControl(self : Mapper1, value : UInt8) -> Unit {
  self.control = value
  self.chrMode = value.lsr(4).land(1 |> to_u8)
  self.prgMode = value.lsr(2).land(3 |> to_u8)
  let mirror = value.land(3 |> to_u8)
  match mirror.0 {
    0 => self.cartridge.mirror = mirrorSingle0
    1 => self.cartridge.mirror = mirrorSingle1
    2 => self.cartridge.mirror = mirrorVertical
    3 => self.cartridge.mirror = mirrorHorizontal
  }
  self.updateOffsets()
}

// CHR bank 0 (internal, $A000-$BFFF)
fn writeCHRBank0(self : Mapper1, value : UInt8) -> Unit {
  self.chrBank0 = value
  self.updateOffsets()
}

// CHR bank 1 (internal, $C000-$DFFF)
fn writeCHRBank1(self : Mapper1, value : UInt8) -> Unit {
  self.chrBank1 = value
  self.updateOffsets()
}

// PRG bank (internal, $E000-$FFFF)
fn writePRGBank(self : Mapper1, value : UInt8) -> Unit {
  self.prgBank = value.land(0x0F |> to_u8)
  self.updateOffsets()
}

fn prgBankOffset(self : Mapper1, index : Int) -> Int {
  let index = if index >= 0x80 { index - 0x100 } else { index } %
    (self.cartridge.prg.length() / 0x4000)
  let offset = index * 0x4000
  if offset < 0 {
    offset + self.cartridge.prg.length()
  } else {
    offset
  }
}

fn chrBankOffset(self : Mapper1, index : Int) -> Int {
  let index = if index >= 0x80 { index - 0x100 } else { index } %
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
fn updateOffsets(self : Mapper1) -> Unit {
  match self.prgMode.0 {
    0 | 1 => {
      self.prgOffsets[0] = self.prgBankOffset(self.prgBank.0.land(0xFE))
      self.prgOffsets[1] = self.prgBankOffset(self.prgBank.0.lor(0x01))
    }
    2 => {
      self.prgOffsets[0] = 0
      self.prgOffsets[1] = self.prgBankOffset(self.prgBank.0)
    }
    3 => {
      self.prgOffsets[0] = self.prgBankOffset(self.prgBank.0)
      self.prgOffsets[1] = self.prgBankOffset(-1)
    }
  }
  match self.chrMode.0 {
    0 => {
      self.chrOffsets[0] = self.chrBankOffset(self.chrBank0.0.land(0xFE))
      self.chrOffsets[1] = self.chrBankOffset(self.chrBank0.0.lor(0x01))
    }
    1 => {
      self.chrOffsets[0] = self.chrBankOffset(self.chrBank0.0)
      self.chrOffsets[1] = self.chrBankOffset(self.chrBank1.0)
    }
  }
}

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

fn newMapper1(self : NES) -> Mapper {
  let mapper = Mapper1::new(self.cartridge)
  println("mapper1 initialized")
  to_mapper(mapper)
}

// Mapper 3 (CNROM)
// https://www.nesdev.org/wiki/INES_Mapper_003
// Example games: Solomon's Key, Arkanoid, Arkista's Ring, Bump 'n' Jump, Cybernoid

struct Mapper3 {
  cartridge : Cartridge
  mut chrBank : Int
  mut prgBank1 : Int
  mut prgBank2 : Int
}

fn step(self : Mapper3) -> Unit {

}

fn idx(self : Mapper3, adr : UInt16) -> UInt8 {
  if adr < (0x2000 |> to_u16) {
    let index = self.chrBank * 0x2000 + adr.0
    self.cartridge.chr[index]
  } else if adr >= (0xC000 |> to_u16) {
    let index = self.prgBank2 * 0x4000 + (adr.0 - 0xC000)
    self.cartridge.prg[index]
  } else if adr >= (0x8000 |> to_u16) {
    let index = self.prgBank1 * 0x4000 + (adr.0 - 0x8000)
    self.cartridge.prg[index]
  } else if adr >= (0x6000 |> to_u16) {
    let index = adr.0 - 0x6000
    self.cartridge.sram[index]
  } else {
    abort("unhandled mapper3 read")
  }
}

fn idxSet(self : Mapper3, adr : UInt16, val : UInt8) -> Unit {
  if adr < (0x2000 |> to_u16) {
    let index = self.chrBank * 0x2000 + adr.0
    self.cartridge.chr[index] = val
  } else if adr >= (0x8000 |> to_u16) {
    self.chrBank = val.0.land(3)
  } else if adr >= (0x6000 |> to_u16) {
    let index = adr.0 - 0x6000
    self.cartridge.sram[index] = val
  } else {
    abort("unhandled mapper3 write")
  }
}

fn Mapper3::new(cartridge : Cartridge) -> Mapper3 {
  let prgBanks = cartridge.prg.length() / 0x4000
  { cartridge, chrBank: 0, prgBank1: 0, prgBank2: prgBanks - 1 }
}

fn newMapper3(self : NES) -> Mapper {
  let mapper = Mapper3::new(self.cartridge)
  to_mapper(mapper)
}

// Mapper 4 (Nintendo MMC3)
// https://www.nesdev.org/wiki/MMC3
// Many good games
//https://nesdir.github.io/mapper4.html

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

fn step(self : Mapper4) -> Unit {
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

fn idx(self : Mapper4, adr : UInt16) -> UInt8 {
  let mut address = adr.0
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

fn idxSet(self : Mapper4, adr : UInt16, val : UInt8) -> Unit {
  let address = adr.0
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

fn handleScanLine(self : Mapper4) -> Unit {
  if self.counter == (0 |> to_u8) {
    self.counter = self.reload
  } else {
    self.counter = self.counter - (1 |> to_u8)
    if self.counter == (0 |> to_u8) && self.irqEnable {
      self.console.cpu.triggerIRQ()
    }
  }
}

fn writeRegister(self : Mapper4, adr : UInt16, value : UInt8) -> Unit {
  let address = adr.0
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

fn writeBankSelect(self : Mapper4, value : UInt8) -> Unit {
  self.prgMode = value.lsr(6).land(1 |> to_u8)
  self.chrMode = value.lsr(7).land(1 |> to_u8)
  self.register = value.land(7 |> to_u8)
  self.updateOffsets()
}

fn writeBankData(self : Mapper4, value : UInt8) -> Unit {
  self.registers[self.register.0] = value
  self.updateOffsets()
}

fn writeMirror(self : Mapper4, value : UInt8) -> Unit {
  match value.0.land(1) {
    0 => self.cartridge.mirror = mirrorVertical
    1 => self.cartridge.mirror = mirrorHorizontal
  }
}

fn writeProtect(self : Mapper4, value : UInt8) -> Unit {

}

fn writeIRQLatch(self : Mapper4, value : UInt8) -> Unit {
  self.reload = value
}

fn writeIRQReload(self : Mapper4, value : UInt8) -> Unit {
  self.counter = 0 |> to_u8
}

fn writeIRQDisable(self : Mapper4, value : UInt8) -> Unit {
  self.irqEnable = false
}

fn writeIRQEnable(self : Mapper4, value : UInt8) -> Unit {
  self.irqEnable = true
}

fn prgBankOffset(self : Mapper4, index : Int) -> Int {
  let index = if index >= 0x80 { index - 0x100 } else { index } %
    (self.cartridge.prg.length() / 0x2000)
  let offset = index * 0x2000
  if offset < 0 {
    offset + self.cartridge.prg.length()
  } else {
    offset
  }
}

fn chrBankOffset(self : Mapper4, index : Int) -> Int {
  let index = if index >= 0x80 { index - 0x100 } else { index } %
    (self.cartridge.chr.length() / 0x0400)
  let offset = index * 0x0400
  if offset < 0 {
    offset + self.cartridge.chr.length()
  } else {
    offset
  }
}

fn updateOffsets(self : Mapper4) -> Unit {
  match self.prgMode.0 {
    0 => {
      self.prgOffsets[0] = self.prgBankOffset(self.registers[6].0)
      self.prgOffsets[1] = self.prgBankOffset(self.registers[7].0)
      self.prgOffsets[2] = self.prgBankOffset(-2)
      self.prgOffsets[3] = self.prgBankOffset(-1)
    }
    1 => {
      self.prgOffsets[0] = self.prgBankOffset(-2)
      self.prgOffsets[1] = self.prgBankOffset(self.registers[7].0)
      self.prgOffsets[2] = self.prgBankOffset(self.registers[6].0)
      self.prgOffsets[3] = self.prgBankOffset(-1)
    }
  }
  match self.chrMode.0 {
    0 => {
      self.chrOffsets[0] = self.chrBankOffset(self.registers[0].0.land(0xFE))
      self.chrOffsets[1] = self.chrBankOffset(self.registers[0].0.lor(0x01))
      self.chrOffsets[2] = self.chrBankOffset(self.registers[1].0.land(0xFE))
      self.chrOffsets[3] = self.chrBankOffset(self.registers[1].0.lor(0x01))
      self.chrOffsets[4] = self.chrBankOffset(self.registers[2].0)
      self.chrOffsets[5] = self.chrBankOffset(self.registers[3].0)
      self.chrOffsets[6] = self.chrBankOffset(self.registers[4].0)
      self.chrOffsets[7] = self.chrBankOffset(self.registers[5].0)
    }
    1 => {
      self.chrOffsets[0] = self.chrBankOffset(self.registers[2].0)
      self.chrOffsets[1] = self.chrBankOffset(self.registers[3].0)
      self.chrOffsets[2] = self.chrBankOffset(self.registers[4].0)
      self.chrOffsets[3] = self.chrBankOffset(self.registers[5].0)
      self.chrOffsets[4] = self.chrBankOffset(self.registers[0].0.land(0xFE))
      self.chrOffsets[5] = self.chrBankOffset(self.registers[0].0.lor(0x01))
      self.chrOffsets[6] = self.chrBankOffset(self.registers[1].0.land(0xFE))
      self.chrOffsets[7] = self.chrBankOffset(self.registers[1].0.lor(0x01))
    }
  }
}

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

fn newMapper4(self : NES) -> Mapper {
  let mapper = Mapper4::new(self.cartridge, self)
  to_mapper(mapper)
}

// Mapper 7 (AOROM)
// https://www.nesdev.org/wiki/AxROM
// Example games: Battletoads

struct Mapper7 {
  cartridge : Cartridge
  prgBank : Int
}

fn step(self : Mapper7) -> Unit {

}

fn idx(self : Mapper7, adr : UInt16) -> UInt8 {
  0 |> to_u8
}

fn idxSet(self : Mapper7, adr : UInt16, val : UInt8) -> Unit {

}

fn Mapper7::new(cartridge : Cartridge) -> Mapper7 {
  { cartridge, prgBank: 0 }
}

fn newMapper7(self : NES) -> Mapper {
  let mapper = Mapper7::new(self.cartridge)
  to_mapper(mapper)
}

// a "factory" method
// why pass NES instead of Cartridge? Because Mapper4 needs it, so we'll need it in future
fn Mapper::new(nes : NES) -> Mapper {
  println("creating mapper")
  match nes.cartridge.mapper.0 {
    0 | 2 => newMapper2(nes)
    1 => newMapper1(nes)
    3 => newMapper3(nes)
    4 => newMapper4(nes)
    7 => newMapper7(nes)
    _ => newMapper2(nes) // TODO: error
  }
}
