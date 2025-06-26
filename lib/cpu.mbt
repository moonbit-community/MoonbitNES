// SPDX-License-Identifier: MIT
// Copyright (c) 2015 Dennis Felsing
// Copyright (c) 2024 Liu Rujia, International Digital Economy Academy

let cpuFrequency = 1789773.0

struct CPUMemory {
  mut nes : NES? // Emulating "weakptr"
}

fn CPUMemory::new() -> CPUMemory {
  { nes: None }
}

enum Interrupt {
  None
  NMI
  IRQ
}

struct CPU {
  mem : CPUMemory
  mut cycles : Int64 // number of cycles
  // registers
  mut pc : UInt16 // program counter
  mut sp : UInt8 // stack pointer
  mut a : UInt8 // accumulator
  mut x : UInt8 // x register
  mut y : UInt8 // y register
  // flags
  mut c : Bool // carry flag
  mut z : Bool // zero flag
  mut i : Bool // interrupt disable flag
  mut d : Bool // decimal mode flag
  mut b : Bool // break command flag
  mut u : Bool // unused flag
  mut v : Bool // overflow flag
  mut n : Bool // negative flag
  // other
  mut interrupt : Interrupt // interrupt type to perform
  mut stall : Int // number of cycles to stall
}

// constructors must be capitalized
// jsnes vs here
// "Indirect absolute" -> Indirect (e.g. 0x4c JMP)
// Pre-indexed Indirect -> IndexedIndirect (e.g. 0x01 ORA)
// Post-indexed Indirect -> IndirectIndexed (e.g. 0x11 ORA)
enum AddressingMode {
  Absolute
  AbsoluteX
  AbsoluteY
  Accumulator
  Immediate
  Implied
  IndexedIndirect
  Indirect
  IndirectIndexed
  Relative
  ZeroPage
  ZeroPageX
  ZeroPageY
} derive(Eq)

impl Default for AddressingMode with default() -> AddressingMode {
  Absolute
}

fn addressingMode(mode : Int) -> AddressingMode {
  match mode {
    0 => Absolute
    1 => AbsoluteX
    2 => AbsoluteY
    3 => Accumulator
    4 => Immediate
    5 => Implied
    6 => IndexedIndirect
    7 => Indirect
    8 => IndirectIndexed
    9 => Relative
    10 => ZeroPage
    11 => ZeroPageX
    _ => ZeroPageY
  }
}

fn AddressingMode::to_int(self : AddressingMode) -> Int {
  match self {
    Absolute => 0
    AbsoluteX => 1
    AbsoluteY => 2
    Accumulator => 3
    Immediate => 4
    Implied => 5
    IndexedIndirect => 6
    Indirect => 7
    IndirectIndexed => 8
    Relative => 9
    ZeroPage => 10
    ZeroPageX => 11
    ZeroPageY => 12
  }
}

// StepInfo contains information that the instruction functions use
struct StepInfo {
  address : UInt16
  pc : UInt16
  mode : AddressingMode
} derive(Default)

fn CPUMemory::op_get(self : CPUMemory, adr : UInt16) -> UInt8 {
  let n = self.nes.unwrap()
  if adr._ >= 0x0000 && adr._ <= 0x1FFF {
    n.ram[adr._ % 0x0800]
  } else if adr >= (0x2000 |> to_u16) && adr <= (0x3FFF |> to_u16) {
    n.ppu.readRegister((0x2000 |> to_u16) + (adr._ % 8 |> to_u16))
  } else if adr._ == 0x4014 {
    n.ppu.readRegister(adr)
  } else if adr._ == 0x4015 {
    n.apu.readRegister(adr)
  } else if adr._ == 0x4016 {
    n.controllers[0].read()
  } else if adr._ == 0x4017 {
    n.controllers[1].read()
  } else if adr._ >= 0x6000 && adr._ <= 0xFFFF {
    let m = n.mapper.unwrap()
    m[adr]
  } else {
    0 |> to_u8()
  }
}

fn CPUMemory::op_set(self : CPUMemory, adr : UInt16, val : UInt8) -> Unit {
  let n = self.nes.unwrap()
  if adr._ >= 0x0000 && adr._ <= 0x1FFF {
    // let addr = adr._
    // let v = val.0
    // log_string("[CPUMemory] set \(addr) to \(v)")
    n.ram[adr._ % 0x0800] = val
  } else if adr._ >= 0x2000 && adr._ <= 0x3FFF {
    n.ppu.writeRegister((0x2000 |> to_u16) + (adr._ % 8 |> to_u16), val)
  } else if adr._ == 0x4014 {
    n.ppu.writeRegister(adr, val)
  } else if (adr._ >= 0x4000 && adr._ <= 0x4013) ||
    adr._ == 0x4015 ||
    adr._ == 0x4017 {
    n.apu.writeRegister(adr, val)
  } else if adr._ == 0x4016 {
    n.controllers[0].write(val)
    n.controllers[1].write(val)
  } else if adr._ >= 0x6000 && adr._ <= 0xFFFF {
    let m = n.mapper.unwrap()
    m[adr] = val
  }
}

fn CPUMemory::read16(self : CPUMemory, adr : UInt16) -> UInt16 {
  let lo = self[adr] |> to_u16
  let hi = self[adr + (1 |> to_u16)] |> to_u16
  (hi << 8) | lo
}

fn CPUMemory::read16bug(self : CPUMemory, adr : UInt16) -> UInt16 {
  // Low byte wraps without incrementing high byte
  let a = adr
  let b = (a & (0xFF00 |> to_u16)) |
    ((adr |> to_u8()) + (1 |> to_u8()) |> to_u16)
  let lo = self[a]
  let hi = self[b]
  ((hi |> to_u16) << 8) | (lo |> to_u16)
}

fn CPU::push(self : CPU, val : UInt8) -> Unit {
  self.mem[(self.sp |> to_u16) | (0x100 |> to_u16)] = val
  self.sp = self.sp - (1 |> to_u8())
}

fn CPU::pull(self : CPU) -> UInt8 {
  self.sp = self.sp + (1 |> to_u8())
  self.mem[(self.sp |> to_u16) | (0x100 |> to_u16)]
}

fn CPU::push16(self : CPU, val : UInt16) -> Unit {
  self.push(val >> 8 |> to_u8())
  self.push(val |> to_u8())
}

fn CPU::pull16(self : CPU) -> UInt16 {
  let v1 = self.pull() |> to_u16
  let v2 = (self.pull() |> to_u16) << 8
  v1 | v2
}

fn CPU::setZ(self : CPU, val : UInt8) -> Unit {
  self.z = val == (0 |> to_u8())
}

fn CPU::setN(self : CPU, val : UInt8) -> Unit {
  self.n = (val & (0x80 |> to_u8())) != (0 |> to_u8())
}

fn CPU::setZN(self : CPU, val : UInt8) -> Unit {
  self.setZ(val)
  self.setN(val)
}

fn CPU::flags(self : CPU) -> UInt8 {
  to_byte(self.c, self.z, self.i, self.d, self.b, self.u, self.v, self.n)
}

fn CPU::set_flags(self : CPU, flags : UInt8) -> Unit {
  self.c = flags.bit(0)
  self.z = flags.bit(1)
  self.i = flags.bit(2)
  self.d = flags.bit(3)
  self.b = flags.bit(4)
  self.u = flags.bit(5)
  self.v = flags.bit(6)
  self.n = flags.bit(7)
}

fn CPU::triggerNMI(self : CPU) -> Unit {
  self.interrupt = Interrupt::NMI
}

fn CPU::triggerIRQ(self : CPU) -> Unit {
  if not(self.i) {
    self.interrupt = Interrupt::IRQ
  }
}

// Reset resets the CPU to its initial powerup state
fn CPU::reset(self : CPU) -> Unit {
  self.cycles = 0L
  self.pc = self.mem.read16(0xFFFC |> to_u16)
  self.sp = 0xFD |> to_u8()
  self.set_flags(0x24 |> to_u8())
  // ???
  //self.sp = (0xFC) |> to_u8()
  //self.set_flags((0x04) |> to_u8())
}

// ref: nesbook ch6.2
// Implied -> NonAddressing??
// IndexedIndirect -> IndirectX
// IndirectIndexed -> IndirectY
// TODO:
// (line 3348) DBB5  6C FF 02  JMP ($02FF) = 0300              A:60 X:07 Y:00 P:65 SP:F9 PPU: 84,201 CYC:9615
// (line 8981) C68B  8D 15 40  STA $4015 = FF                  A:02 X:FF Y:15 P:25 SP:FB PPU:233,107 CYC:26520
fn CPU::formatAssemblySuffix(self : CPU) -> String {
  let opcode = self.mem[self.pc]
  let name = instructionNames[opcode._]
  let bytes = instructionSizes[opcode._]
  let mode = instructionModes[opcode._] |> addressingMode
  let modei = instructionModes[opcode._]
  //log_string("opcode addressing mode: \(modei)")

  let mem_addr = self.get_addr(mode)
  let mut stored_value = 0 |> to_u8()
  if mode.is_addressed() {
    stored_value = self.mem[mem_addr]
  }
  let (mem_addr_hex, stored_value_hex) = (
    mem_addr.to_hex(),
    stored_value.to_hex(),
  )
  let mem_addr8_hex = (mem_addr |> to_u8()).to_hex()
  match bytes {
    1 =>
      match opcode._ {
        0x0a | 0x4a | 0x2a | 0x6a => "A "
        _ => ""
      }
    2 => {
      let address = self.mem[self.pc + (1 |> to_u16)]
      let address_hex = address.to_hex()
      match mode {
        Immediate => "#$\{address_hex}"
        ZeroPage => "$\{mem_addr8_hex} = \{stored_value_hex}"
        ZeroPageX =>
          "$\{address_hex},X @ \{mem_addr8_hex} = \{stored_value_hex}"
        ZeroPageY =>
          "$\{address_hex},Y @ \{mem_addr8_hex} = \{stored_value_hex}"
        // Indirect_X
        IndexedIndirect => {
          let new_addr_hex = (address + self.x).to_hex()
          "($\{address_hex},X) @ \{new_addr_hex} = \{mem_addr_hex} = \{stored_value_hex}"
        }
        // Indirect_Y
        IndirectIndexed => {
          // sub???
          let new_addr_hex = (mem_addr - (self.y |> to_u16)).to_hex() // 16-bit
          "($\{address_hex}),Y = \{new_addr_hex} @ \{mem_addr_hex} = \{stored_value_hex}"
        }
        Relative =>
          // assuming local jumps: BNE, BVS, etc....
          "$\{mem_addr_hex}"
        //_ => abort("unexpected addressing mode {:?} has ops-len 2. code {:02x}")
        _ => ""
      }
    }
    3 => {
      // let address_lo = cpu.mem_read(begin + 1);
      // let address_hi = cpu.mem_read(begin + 2);

      let address = self.mem.read16(self.pc + (1 |> to_u16))
      let address_hex = address.to_hex()
      match mode {
        Indirect => "($\{address_hex}) = \{mem_addr_hex}"
        Relative =>
          // if opcode._ == 0x6c {
          //     //jmp indirect
          //     let jmp_addr = if address & 0x00FF == 0x00FF {
          //         let lo = cpu.mem_read(address);
          //         let hi = cpu.mem_read(address & 0xFF00);
          //         (hi as u16) << 8 | (lo as u16)
          //     } else {
          //         cpu.mem_read_u16(address)
          //     };

          //     // let jmp_addr = cpu.mem_read_u16(address);
          //     format!("(${:04x}) = {:04x}", address, jmp_addr)
          // } else {
          //     format!("${:04x}", address)
          // }
          "$\{address_hex}"
        Absolute =>
          if name == "JMP" || name == "JSR" {
            "$\{address_hex}"
          } else {
            "$\{mem_addr_hex} = \{stored_value_hex}"
          }
        AbsoluteX => "$\{address_hex},X @ \{mem_addr_hex} = \{stored_value_hex}"
        AbsoluteY => "$\{address_hex},Y @ \{mem_addr_hex} = \{stored_value_hex}"
        //_ => abort("unexpected addressing mode {:?} has ops-len 3. code {:02x}",
        _ => ""
      }
    }
    _ => ""
  }
}

fn CPU::formatAssembly(self : CPU) -> String {
  let opcode = self.mem[self.pc]
  let name = instructionNames[opcode._]
  loop name + " " + self.formatAssemblySuffix() {
    s => if s.length() < 32 { continue s + " " } else { s }
  }
}

fn isSpecialOpcode(op : Int) -> Bool {
  instructionUnofficial[op] == 1
}

// PrintInstruction prints the current CPU state (next instruction)
fn CPU::formatInstruction(self : CPU) -> String {
  let opcode = self.mem[self.pc]
  let bytes = instructionSizes[opcode._]
  let name = instructionNames[opcode._]
  let w0 = self.mem[self.pc + (0 |> to_u16)].to_hex()
  let mut w1 = self.mem[self.pc + (1 |> to_u16)].to_hex()
  let mut w2 = self.mem[self.pc + (2 |> to_u16)].to_hex()
  if bytes < 2 {
    w1 = "  "
  }
  if bytes < 3 {
    w2 = "  "
  }
  let uf = if isSpecialOpcode(opcode._) { "*" } else { " " }
  let asm = self.formatAssembly()
  let pc = self.pc.to_hex()
  let a = self.a.to_hex()
  let x = self.x.to_hex()
  let y = self.y.to_hex()
  let p = self.flags().to_hex()
  let sp = self.sp.to_hex()
  "\{pc}  \{w0} \{w1} \{w2} \{uf}\{asm}A:\{a} X:\{x} Y:\{y} P:\{p} SP:\{sp}"
}

// Mesen2's trace logger format：everything except "use labels" and "indent based on stack pointer"
// format string:
// [Disassembly][EffectiveAddress] [MemoryValue,h][Align,38] A:[A,2h] X:[X,2h] Y:[Y,2h] S:[SP,2h] P:[P,h] V:[Scanline,3] H:[Cycle,3] Fr:[FrameCount] Cycle:[CycleCount] BC:[ByteCode]
// eg.
// AEB5   LDA $0300,X [$030E] = $00              A:00 X:0E Y:3F S:F6 P:04 V:-1  H:310 Fr:51 Cycle:1489016 BC:BD 00 03
fn CPU::formatInstructionWithMesen2Extended(self : CPU) -> String {
  let opcode = self.mem[self.pc]
  let bytes = instructionSizes[opcode._]
  let name = instructionNames[opcode._]
  let w0 = self.mem[self.pc + (0 |> to_u16)].to_hex()
  let mut w1 = self.mem[self.pc + (1 |> to_u16)].to_hex()
  let mut w2 = self.mem[self.pc + (2 |> to_u16)].to_hex()
  if bytes < 2 {
    w1 = "  "
  }
  if bytes < 3 {
    w2 = "  "
  }
  let uf = if isSpecialOpcode(opcode._) { "*" } else { " " }
  let asm = self.formatAssembly()
  let pc = self.pc.to_hex()
  let a = self.a.to_hex()
  let x = self.x.to_hex()
  let y = self.y.to_hex()
  let p = self.flags().to_hex()
  let sp = self.sp.to_hex()
  "\{pc}  \{w0} \{w1} \{w2} \{uf}\{asm}A:\{a} X:\{x} Y:\{y} P:\{p} SP:\{sp}"
}

fn CPU::formatMemoryDump(self : CPU, base : UInt16, cnt : Int) -> String {
  for i = 0, ret = ""
      i < cnt
      i = i + 1, ret = ret + self.mem[base + (i |> to_u16)].to_hex() + " " {

  } else {
    ret
  }
}

// I'm keeping the original function name. The original code takes NES as a paramter which cannot be implemented for now
fn initCPU() -> CPU {
  let mem = CPUMemory::new()
  let result : CPU = {
    mem,
    cycles: 0L,
    pc: 0 |> to_u16,
    sp: 0 |> to_u8(),
    a: 0 |> to_u8(),
    x: 0 |> to_u8(),
    y: 0 |> to_u8(),
    c: false,
    z: false,
    i: false,
    d: false,
    b: false,
    u: false,
    v: false,
    n: false,
    interrupt: None,
    stall: 0,
  }
  // cannot reset here! would unwrap none
  //result.reset()
  result
}

// pagesDiffer returns true if the two addresses reference different pages
fn pagesDiffer(a : UInt16, b : UInt16) -> Bool {
  (a & (0xFF00 |> to_u16)) != (b & (0xFF00 |> to_u16))
}

// branch, then adds a cycle for taking a branch and adds another cycle
// if the branch jumps to a new page
fn CPU::branch(self : CPU, info : StepInfo) -> Unit {
  self.pc = info.address
  self.cycles += 1L
  if pagesDiffer(info.pc, info.address) {
    self.cycles += 1L
  }
}

fn CPU::compare(self : CPU, a : UInt8, b : UInt8) -> Unit {
  self.setZN(a - b)
  self.c = a >= b
}

// opcodes

// ADC - Add with carry
fn CPU::opADC(self : CPU, info : StepInfo) -> Unit {
  let a = self.a
  let b = self.mem[info.address]
  let c = self.c |> to_u8()
  self.a = a + b + c
  self.setZN(self.a)
  self.c = a._ + b._ + c._ > 0xFF
  // (a^b)&0x80 == 0 && (a^self.a)&0x80 != 0
  self.v = ((a ^ b) & (0x80 |> to_u8())) == (0 |> to_u8()) &&
    ((a ^ self.a) & (0x80 |> to_u8())) != (0 |> to_u8())
}

// AND - Logical and
// ** opcode name changed
fn CPU::opAND(self : CPU, info : StepInfo) -> Unit {
  self.a = self.a & self.mem[info.address] // self.a & self.mem[info.address]
  self.setZN(self.a)
}

// ASL - Arithmetic shift left
fn CPU::opASL(self : CPU, info : StepInfo) -> Unit {
  match info.mode {
    Accumulator => {
      self.c = ((self.a >> 7) & (1 |> to_u8())) != (0 |> to_u8()) // (self.a >> 7) & 1
      self.a = self.a << 1
      self.setZN(self.a)
    }
    _ => {
      let mut val = self.mem[info.address]
      self.c = ((val >> 7) & (1 |> to_u8())) != (0 |> to_u8()) // (val >> 7) & 1
      val = val << 1
      self.mem[info.address] = val
      self.setZN(val)
    }
  }
}

// BCC - Branch if carry clear
fn CPU::opBCC(self : CPU, info : StepInfo) -> Unit {
  if not(self.c) {
    self.branch(info)
  }
}

// BCS - Branch if carry set
fn CPU::opBCS(self : CPU, info : StepInfo) -> Unit {
  if self.c {
    self.branch(info)
  }
}

// BEQ - Branch if equal
fn CPU::opBEQ(self : CPU, info : StepInfo) -> Unit {
  if self.z {
    self.branch(info)
  }
}

// BIT - Bit test
fn CPU::opBIT(self : CPU, info : StepInfo) -> Unit {
  let val = self.mem[info.address] // :- same as go!
  self.v = ((val >> 6) & (1 |> to_u8())) != (0 |> to_u8()) // (val >> 6) & 1
  self.setZ(val & self.a) // val & self.A
  self.setN(val)
}

// BMI - Branch if minus
fn CPU::opBMI(self : CPU, info : StepInfo) -> Unit {
  if self.n {
    self.branch(info)
  }
}

// BNE - Branch if minus
fn CPU::opBNE(self : CPU, info : StepInfo) -> Unit {
  if not(self.z) {
    self.branch(info)
  }
}

// BPL - Branch if positive
fn CPU::opBPL(self : CPU, info : StepInfo) -> Unit {
  if not(self.n) {
    self.branch(info)
  }
}

// BRK - Force interrupt
fn CPU::opBRK(self : CPU, info : StepInfo) -> Unit {
  self.push16(self.pc)
  self.opPHP(info)
  self.opSEI(info)
  self.pc = self.mem.read16(0xFFFE |> to_u16)
}

// BVC - Branch if overflow clear
fn CPU::opBVC(self : CPU, info : StepInfo) -> Unit {
  if not(self.v) {
    self.branch(info)
  }
}

// BVS - Branch if overflow set
fn CPU::opBVS(self : CPU, info : StepInfo) -> Unit {
  if self.v {
    self.branch(info)
  }
}

// CLC - Clear carry flag
fn CPU::opCLC(self : CPU, _info : StepInfo) -> Unit {
  self.c = false
}

// CLD - Clear decimal mode
fn CPU::opCLD(self : CPU, _info : StepInfo) -> Unit {
  self.d = false
}

// CLI - Clear interrupt disable
fn CPU::opCLI(self : CPU, _info : StepInfo) -> Unit {
  self.i = false
}

// CLV - Clear overflow flag
fn CPU::opCLV(self : CPU, _info : StepInfo) -> Unit {
  self.v = false
}

// CMP - Compare
fn CPU::opCMP(self : CPU, info : StepInfo) -> Unit {
  self.compare(self.a, self.mem[info.address])
}

// CPX - Compare x register
fn CPU::opCPX(self : CPU, info : StepInfo) -> Unit {
  self.compare(self.x, self.mem[info.address])
}

// CPY - Compare y register
fn CPU::opCPY(self : CPU, info : StepInfo) -> Unit {
  self.compare(self.y, self.mem[info.address])
}

// DEC - Decrement memory
// **opcode name
fn CPU::opDEC(self : CPU, info : StepInfo) -> Unit {
  let val = self.mem[info.address] - (1 |> to_u8())
  self.mem[info.address] = val
  self.setZN(val)
}

// DEX - Decrement x register
fn CPU::opDEX(self : CPU, _info : StepInfo) -> Unit {
  self.x = self.x - (1 |> to_u8()) // self.x--
  self.setZN(self.x)
}

// DEY - Decrement y register
fn CPU::opDEY(self : CPU, _info : StepInfo) -> Unit {
  self.y = self.y - (1 |> to_u8()) // self.y--
  self.setZN(self.y)
}

// EOR - Exclusive or
fn CPU::opEOR(self : CPU, info : StepInfo) -> Unit {
  self.a = self.a ^ self.mem[info.address]
  self.setZN(self.a)
}

// INC - Increment memory
// **opcode name
fn CPU::opINC(self : CPU, info : StepInfo) -> Unit {
  let val = self.mem[info.address] + (1 |> to_u8())
  self.mem[info.address] = val
  self.setZN(val)
}

// INX - Increment x register
fn CPU::opINX(self : CPU, _info : StepInfo) -> Unit {
  self.x = self.x + (1 |> to_u8()) //self.x++
  self.setZN(self.x)
}

// INY - Increment y register
fn CPU::opINY(self : CPU, _info : StepInfo) -> Unit {
  self.y = self.y + (1 |> to_u8()) // self.y++
  self.setZN(self.y)
}

// JMP - Jump
fn CPU::opJMP(self : CPU, info : StepInfo) -> Unit {
  self.pc = info.address
  // addr_hex := self.pc.to_hex()
  // log_string("JMP \(addr_hex)")
}

// JSR - Jump to subroutine
fn CPU::opJSR(self : CPU, info : StepInfo) -> Unit {
  self.push16(self.pc - (1 |> to_u16))
  self.pc = info.address
}

// LDA - Load accumulator
fn CPU::opLDA(self : CPU, info : StepInfo) -> Unit {
  self.a = self.mem[info.address]
  self.setZN(self.a)
}

// LDX - Load x register
fn CPU::opLDX(self : CPU, info : StepInfo) -> Unit {
  self.x = self.mem[info.address]
  self.setZN(self.x)
}

// LDY - Load y register
fn CPU::opLDY(self : CPU, info : StepInfo) -> Unit {
  self.y = self.mem[info.address]
  self.setZN(self.y)
}

// LSR - Logical shift right
fn CPU::opLSR(self : CPU, info : StepInfo) -> Unit {
  match info.mode {
    Accumulator => {
      self.c = (self.a & (1 |> to_u8())) != (0 |> to_u8()) // self.A & 1
      self.a = self.a >> 1 // self.A >>= 1
      self.setZN(self.a)
    }
    _ => {
      let mut val = self.mem[info.address]
      self.c = (val & (1 |> to_u8())) != (0 |> to_u8()) // value & 1
      val = val >> 1 // val >>= 1
      self.mem[info.address] = val
      self.setZN(val)
    }
  }
}

// NOP - No operation
fn CPU::opNOP(self : CPU, info : StepInfo) -> Unit {

}

// ORA - Logical inclusive or
fn CPU::opORA(self : CPU, info : StepInfo) -> Unit {
  self.a = self.a | self.mem[info.address]
  self.setZN(self.a)
}

// PHA - Push accumulator
fn CPU::opPHA(self : CPU, _info : StepInfo) -> Unit {
  self.push(self.a)
}

// PHP - Push processor status
fn CPU::opPHP(self : CPU, _info : StepInfo) -> Unit {
  self.push(self.flags() | (0x10 |> to_u8()))
}

// PLA - Pull accumulator
fn CPU::opPLA(self : CPU, _info : StepInfo) -> Unit {
  self.a = self.pull()
  self.setZN(self.a)
}

// PLP - Pull processor status
fn CPU::opPLP(self : CPU, _info : StepInfo) -> Unit {
  self.set_flags((self.pull() & (0xEF |> to_u8())) | (0x20 |> to_u8())) // pull() & 0xEF | 0x20
}

// ROL - Rotate left
fn CPU::opROL(self : CPU, info : StepInfo) -> Unit {
  let c = self.c |> to_u8()
  match info.mode {
    Accumulator => {
      self.c = ((self.a >> 7) & (1 |> to_u8())) != (0 |> to_u8()) // (self.A >> 7) & 1
      self.a = (self.a << 1) | c // (self.A << 1) | c
      self.setZN(self.a)
    }
    _ => {
      let mut val = self.mem[info.address]
      self.c = ((val >> 7) & (1 |> to_u8())) != (0 |> to_u8()) // (val >> 7) & 1
      val = (val << 1) | c // (val << 1) | c
      self.mem[info.address] = val
      self.setZN(val)
    }
  }
}

// ROR - Rotate right
fn CPU::opROR(self : CPU, info : StepInfo) -> Unit {
  let c = self.c |> to_u8()
  match info.mode {
    Accumulator => {
      self.c = (self.a & (1 |> to_u8())) != (0 |> to_u8()) // self.A & 1
      self.a = (self.a >> 1) | (c << 7) // (self.A >> 1) | (c << 7)
      self.setZN(self.a)
    }
    _ => {
      let mut val = self.mem[info.address]
      self.c = (val & (1 |> to_u8())) != (0 |> to_u8()) // val & 1
      val = (val >> 1) | (c << 7) // (val >> 1) | (c << 7)
      self.mem[info.address] = val
      self.setZN(val)
    }
  }
}

// RTI - Return from interrupt
fn CPU::opRTI(self : CPU, info : StepInfo) -> Unit {
  self.set_flags((self.pull() & (0xEF |> to_u8())) | (0x20 |> to_u8())) // pull() & 0xEF | 0x20
  self.pc = self.pull16()
}

// RTS - Return from subrouting
fn CPU::opRTS(self : CPU, info : StepInfo) -> Unit {
  self.pc = self.pull16() + (1 |> to_u16)
}

// SBC - Subtract with carry
fn CPU::opSBC(self : CPU, info : StepInfo) -> Unit {
  let a = self.a
  let b = self.mem[info.address]
  let c = self.c |> to_u8()
  self.a = a - b - ((1 |> to_u8()) - c)
  self.setZN(self.a)
  self.c = a._ - b._ - ((1 |> to_u8()) - c)._ >= 0
  self.v = ((a ^ b) & (0x80 |> to_u8())) != (0 |> to_u8()) &&
    ((a ^ self.a) & (0x80 |> to_u8())) != (0 |> to_u8())
}

// SEC - Set carry flag
fn CPU::opSEC(self : CPU, _info : StepInfo) -> Unit {
  self.c = true
}

// SED - Set decimal flag
fn CPU::opSED(self : CPU, _info : StepInfo) -> Unit {
  self.d = true
}

// SEI - Set interrupt disable
fn CPU::opSEI(self : CPU, _info : StepInfo) -> Unit {
  self.i = true
}

// STA - Store accumulator
fn CPU::opSTA(self : CPU, info : StepInfo) -> Unit {
  self.mem[info.address] = self.a
}

// STX - Store x register
fn CPU::opSTX(self : CPU, info : StepInfo) -> Unit {
  self.mem[info.address] = self.x
}

// STY - Store y register
fn CPU::opSTY(self : CPU, info : StepInfo) -> Unit {
  self.mem[info.address] = self.y
}

// TAX - Transfer accumulator to x
fn CPU::opTAX(self : CPU, _info : StepInfo) -> Unit {
  self.x = self.a
  self.setZN(self.x)
}

// TAY - Transfer accumulator to y
fn CPU::opTAY(self : CPU, _info : StepInfo) -> Unit {
  self.y = self.a
  self.setZN(self.y)
}

// TSX - Transfer stack pointer to x
fn CPU::opTSX(self : CPU, _info : StepInfo) -> Unit {
  self.x = self.sp
  self.setZN(self.x)
}

// TXA - Transfer x to accumulator
fn CPU::opTXA(self : CPU, _info : StepInfo) -> Unit {
  self.a = self.x
  self.setZN(self.a)
}

// TXS - Transfer x to stack pointer
fn CPU::opTXS(self : CPU, _info : StepInfo) -> Unit {
  self.sp = self.x
}

// TYA - Transfer y to accumulator
fn CPU::opTYA(self : CPU, _info : StepInfo) -> Unit {
  self.a = self.y
  self.setZN(self.a)
}

// # Illegal opcodes
// https://www.nesdev.org/wiki/CPU_unofficial_opcodes
// https://www.nesdev.org/wiki/Programming_with_unofficial_opcodes
fn CPU::opAHX(self : CPU, info : StepInfo) -> Unit {
  println("unimplemented: AHX")
  //abort("AHX")
}

fn CPU::opALR(self : CPU, info : StepInfo) -> Unit {
  println("unimplemented: ALR")
  //abort("ALR")
}

fn CPU::opANC(self : CPU, info : StepInfo) -> Unit {
  println("unimplemented: ANC")
  //abort("ANC")
}

fn CPU::opARR(self : CPU, info : StepInfo) -> Unit {
  println("unimplemented: ARR")
  //abort("ARR")
}

fn CPU::opAXS(self : CPU, info : StepInfo) -> Unit {
  println("unimplemented: AXS")
  //abort("AXS")
}

fn CPU::opDCP(self : CPU, info : StepInfo) -> Unit {
  // Equivalent to DEC value then CMP value, except supporting more addressing modes.
  // LDA #$FF followed by DCP can be used to check if the decrement underflows, which is useful for multi-byte decrements.
  self.opDEC(info)
  self.opCMP(info)
}

fn CPU::opISC(self : CPU, info : StepInfo) -> Unit {
  // Equivalent to INC value then SBC value, except supporting more addressing modes.
  self.opINC(info)
  self.opSBC(info)
}

fn CPU::opKIL(self : CPU, info : StepInfo) -> Unit {
  println("unimplemented: KIL")
  //abort("KIL")
}

fn CPU::opLAS(self : CPU, info : StepInfo) -> Unit {
  println("unimplemented: LAS")
  //abort("LAS")
}

fn CPU::opLAX(self : CPU, info : StepInfo) -> Unit {
  // Shortcut for LDA value then TAX. Saves a byte and two cycles and allows use of the X register with the (d),Y addressing mode.
  // Notice that the immediate is missing; the opcode that would have been LAX is affected by line noise on the data bus.
  // MOS 6502: even the bugs have bugs.
  self.opLDA(info)
  self.opTAX(info)
}

fn CPU::opRLA(self : CPU, info : StepInfo) -> Unit {
  // Equivalent to ROL value then AND value, except supporting more addressing modes.
  // LDA #$FF followed by RLA is an efficient way to rotate a variable while also loading it in A.
  self.opROL(info)
  self.opAND(info)
}

fn CPU::opRRA(self : CPU, info : StepInfo) -> Unit {
  // Equivalent to ROR value then ADC value, except supporting more addressing modes.
  // Essentially this computes A + value / 2, where value is 9-bit and the division is rounded up.
  self.opROR(info)
  self.opADC(info)
}

fn CPU::opSAX(self : CPU, info : StepInfo) -> Unit {
  // Stores the bitwise AND of A and X. As with STA and STX, no flags are affected.
  self.mem[info.address] = self.a & self.x
}

fn CPU::opSHX(self : CPU, info : StepInfo) -> Unit {
  println("unimplemented: SHX")
  //abort("SHX")
}

fn CPU::opSHY(self : CPU, info : StepInfo) -> Unit {
  println("unimplemented: SHY")
  //abort("SHY")
}

fn CPU::opSLO(self : CPU, info : StepInfo) -> Unit {
  // Equivalent to ASL value then ORA value, except supporting more addressing modes.
  // LDA #0 followed by SLO is an efficient way to shift a variable while also loading it in A.
  self.opASL(info)
  self.opORA(info)
}

fn CPU::opSRE(self : CPU, info : StepInfo) -> Unit {
  // Equivalent to LSR value then EOR value, except supporting more addressing modes.
  // LDA #0 followed by SRE is an efficient way to shift a variable while also loading it in A.
  self.opLSR(info)
  self.opEOR(info)
}

fn CPU::opTAS(self : CPU, info : StepInfo) -> Unit {
  println("unimplemented: TAS")
  //abort("TAS")
}

fn CPU::opXAA(self : CPU, info : StepInfo) -> Unit {
  println("unimplemented: XAA")
  //abort("XAA")
}

// 6502/6510/8500/8502 Opcode matrix:
// http://www.oxyron.de/html/opcodes02.html
let instructions: FixedArray[(CPU, StepInfo) -> Unit] = [ // All 6502 instructions
	CPU::opBRK, CPU::opORA, CPU::opKIL, CPU::opSLO, CPU::opNOP, CPU::opORA, CPU::opASL, CPU::opSLO,//0
	CPU::opPHP, CPU::opORA, CPU::opASL, CPU::opANC, CPU::opNOP, CPU::opORA, CPU::opASL, CPU::opSLO,
	CPU::opBPL, CPU::opORA, CPU::opKIL, CPU::opSLO, CPU::opNOP, CPU::opORA, CPU::opASL, CPU::opSLO,//1
	CPU::opCLC, CPU::opORA, CPU::opNOP, CPU::opSLO, CPU::opNOP, CPU::opORA, CPU::opASL, CPU::opSLO,
	CPU::opJSR, CPU::opAND, CPU::opKIL, CPU::opRLA, CPU::opBIT, CPU::opAND, CPU::opROL, CPU::opRLA,//2
	CPU::opPLP, CPU::opAND, CPU::opROL, CPU::opANC, CPU::opBIT, CPU::opAND, CPU::opROL, CPU::opRLA,
	CPU::opBMI, CPU::opAND, CPU::opKIL, CPU::opRLA, CPU::opNOP, CPU::opAND, CPU::opROL, CPU::opRLA,//3
	CPU::opSEC, CPU::opAND, CPU::opNOP, CPU::opRLA, CPU::opNOP, CPU::opAND, CPU::opROL, CPU::opRLA,
	CPU::opRTI, CPU::opEOR, CPU::opKIL, CPU::opSRE, CPU::opNOP, CPU::opEOR, CPU::opLSR, CPU::opSRE,//4
	CPU::opPHA, CPU::opEOR, CPU::opLSR, CPU::opALR, CPU::opJMP, CPU::opEOR, CPU::opLSR, CPU::opSRE,
	CPU::opBVC, CPU::opEOR, CPU::opKIL, CPU::opSRE, CPU::opNOP, CPU::opEOR, CPU::opLSR, CPU::opSRE,//5
	CPU::opCLI, CPU::opEOR, CPU::opNOP, CPU::opSRE, CPU::opNOP, CPU::opEOR, CPU::opLSR, CPU::opSRE,
	CPU::opRTS, CPU::opADC, CPU::opKIL, CPU::opRRA, CPU::opNOP, CPU::opADC, CPU::opROR, CPU::opRRA,//6
	CPU::opPLA, CPU::opADC, CPU::opROR, CPU::opARR, CPU::opJMP, CPU::opADC, CPU::opROR, CPU::opRRA,
	CPU::opBVS, CPU::opADC, CPU::opKIL, CPU::opRRA, CPU::opNOP, CPU::opADC, CPU::opROR, CPU::opRRA,//7
	CPU::opSEI, CPU::opADC, CPU::opNOP, CPU::opRRA, CPU::opNOP, CPU::opADC, CPU::opROR, CPU::opRRA,
	CPU::opNOP, CPU::opSTA, CPU::opNOP, CPU::opSAX, CPU::opSTY, CPU::opSTA, CPU::opSTX, CPU::opSAX,//8
	CPU::opDEY, CPU::opNOP, CPU::opTXA, CPU::opXAA, CPU::opSTY, CPU::opSTA, CPU::opSTX, CPU::opSAX,
	CPU::opBCC, CPU::opSTA, CPU::opKIL, CPU::opAHX, CPU::opSTY, CPU::opSTA, CPU::opSTX, CPU::opSAX,//9
	CPU::opTYA, CPU::opSTA, CPU::opTXS, CPU::opTAS, CPU::opSHY, CPU::opSTA, CPU::opSHX, CPU::opAHX,
	CPU::opLDY, CPU::opLDA, CPU::opLDX, CPU::opLAX, CPU::opLDY, CPU::opLDA, CPU::opLDX, CPU::opLAX,//A
	CPU::opTAY, CPU::opLDA, CPU::opTAX, CPU::opLAX, CPU::opLDY, CPU::opLDA, CPU::opLDX, CPU::opLAX,
	CPU::opBCS, CPU::opLDA, CPU::opKIL, CPU::opLAX, CPU::opLDY, CPU::opLDA, CPU::opLDX, CPU::opLAX,//B
	CPU::opCLV, CPU::opLDA, CPU::opTSX, CPU::opLAS, CPU::opLDY, CPU::opLDA, CPU::opLDX, CPU::opLAX,
	CPU::opCPY, CPU::opCMP, CPU::opNOP, CPU::opDCP, CPU::opCPY, CPU::opCMP, CPU::opDEC, CPU::opDCP,//C
	CPU::opINY, CPU::opCMP, CPU::opDEX, CPU::opAXS, CPU::opCPY, CPU::opCMP, CPU::opDEC, CPU::opDCP,
	CPU::opBNE, CPU::opCMP, CPU::opKIL, CPU::opDCP, CPU::opNOP, CPU::opCMP, CPU::opDEC, CPU::opDCP,//D
	CPU::opCLD, CPU::opCMP, CPU::opNOP, CPU::opDCP, CPU::opNOP, CPU::opCMP, CPU::opDEC, CPU::opDCP,
	CPU::opCPX, CPU::opSBC, CPU::opNOP, CPU::opISC, CPU::opCPX, CPU::opSBC, CPU::opINC, CPU::opISC,//E
	CPU::opINX, CPU::opSBC, CPU::opNOP, CPU::opSBC, CPU::opCPX, CPU::opSBC, CPU::opINC, CPU::opISC,
	CPU::opBEQ, CPU::opSBC, CPU::opKIL, CPU::opISC, CPU::opNOP, CPU::opSBC, CPU::opINC, CPU::opISC,//F
  CPU::opSED, CPU::opSBC, CPU::opNOP, CPU::opISC, CPU::opNOP, CPU::opSBC, CPU::opINC, CPU::opISC,
]

// instructionNames indicates the name of each instruction
let instructionNames: FixedArray[String] = [
	"BRK", "ORA", "KIL", "SLO", "NOP", "ORA", "ASL", "SLO",
	"PHP", "ORA", "ASL", "ANC", "NOP", "ORA", "ASL", "SLO",
	"BPL", "ORA", "KIL", "SLO", "NOP", "ORA", "ASL", "SLO",
	"CLC", "ORA", "NOP", "SLO", "NOP", "ORA", "ASL", "SLO",
	"JSR", "AND", "KIL", "RLA", "BIT", "AND", "ROL", "RLA",
	"PLP", "AND", "ROL", "ANC", "BIT", "AND", "ROL", "RLA",
	"BMI", "AND", "KIL", "RLA", "NOP", "AND", "ROL", "RLA",
	"SEC", "AND", "NOP", "RLA", "NOP", "AND", "ROL", "RLA",
	"RTI", "EOR", "KIL", "SRE", "NOP", "EOR", "LSR", "SRE",
	"PHA", "EOR", "LSR", "ALR", "JMP", "EOR", "LSR", "SRE",
	"BVC", "EOR", "KIL", "SRE", "NOP", "EOR", "LSR", "SRE",
	"CLI", "EOR", "NOP", "SRE", "NOP", "EOR", "LSR", "SRE",
	"RTS", "ADC", "KIL", "RRA", "NOP", "ADC", "ROR", "RRA",
	"PLA", "ADC", "ROR", "ARR", "JMP", "ADC", "ROR", "RRA",
	"BVS", "ADC", "KIL", "RRA", "NOP", "ADC", "ROR", "RRA",
	"SEI", "ADC", "NOP", "RRA", "NOP", "ADC", "ROR", "RRA",
	"NOP", "STA", "NOP", "SAX", "STY", "STA", "STX", "SAX",
	"DEY", "NOP", "TXA", "XAA", "STY", "STA", "STX", "SAX",
	"BCC", "STA", "KIL", "AHX", "STY", "STA", "STX", "SAX",
	"TYA", "STA", "TXS", "TAS", "SHY", "STA", "SHX", "AHX",
	"LDY", "LDA", "LDX", "LAX", "LDY", "LDA", "LDX", "LAX",
	"TAY", "LDA", "TAX", "LAX", "LDY", "LDA", "LDX", "LAX",
	"BCS", "LDA", "KIL", "LAX", "LDY", "LDA", "LDX", "LAX",
	"CLV", "LDA", "TSX", "LAS", "LDY", "LDA", "LDX", "LAX",
	"CPY", "CMP", "NOP", "DCP", "CPY", "CMP", "DEC", "DCP",
	"INY", "CMP", "DEX", "AXS", "CPY", "CMP", "DEC", "DCP",
	"BNE", "CMP", "KIL", "DCP", "NOP", "CMP", "DEC", "DCP",
	"CLD", "CMP", "NOP", "DCP", "NOP", "CMP", "DEC", "DCP",
	"CPX", "SBC", "NOP", "ISC", "CPX", "SBC", "INC", "ISC",
	"INX", "SBC", "NOP", "SBC", "CPX", "SBC", "INC", "ISC",
	"BEQ", "SBC", "KIL", "ISC", "NOP", "SBC", "INC", "ISC",
	"SED", "SBC", "NOP", "ISC", "NOP", "SBC", "INC", "ISC",
]

let
  instructionModes: FixedArray[Int] = [ // Addressing modes
     5,   6,   5,   6,  10,  10,  10,  10,   5,   4,   3,   4,   0,   0,   0,   0,
     9,   8,   5,   8,  11,  11,  11,  11,   5,   2,   5,   2,   1,   1,   1,   1,
     0,   6,   5,   6,  10,  10,  10,  10,   5,   4,   3,   4,   0,   0,   0,   0,
     9,   8,   5,   8,  11,  11,  11,  11,   5,   2,   5,   2,   1,   1,   1,   1,
     5,   6,   5,   6,  10,  10,  10,  10,   5,   4,   3,   4,   0,   0,   0,   0,
     9,   8,   5,   8,  11,  11,  11,  11,   5,   2,   5,   2,   1,   1,   1,   1,
     5,   6,   5,   6,  10,  10,  10,  10,   5,   4,   3,   4,   7,   0,   0,   0,
     9,   8,   5,   8,  11,  11,  11,  11,   5,   2,   5,   2,   1,   1,   1,   1,
     4,   6,   4,   6,  10,  10,  10,  10,   5,   4,   5,   4,   0,   0,   0,   0,
     9,   8,   5,   8,  11,  11,  12,  12,   5,   2,   5,   2,   1,   1,   2,   2,
     4,   6,   4,   6,  10,  10,  10,  10,   5,   4,   5,   4,   0,   0,   0,   0,
     9,   8,   5,   8,  11,  11,  12,  12,   5,   2,   5,   2,   1,   1,   2,   2,
     4,   6,   4,   6,  10,  10,  10,  10,   5,   4,   5,   4,   0,   0,   0,   0,
     9,   8,   5,   8,  11,  11,  11,  11,   5,   2,   5,   2,   1,   1,   1,   1,
     4,   6,   4,   6,  10,  10,  10,  10,   5,   4,   5,   4,   0,   0,   0,   0,
     9,   8,   5,   8,  11,  11,  11,  11,   5,   2,   5,   2,   1,   1,   1,   1,
]

let
  instructionSizes: FixedArray[Int] = [ // Size in bytes
     1,   2,   0,   2,   2,   2,   2,   2,   1,   2,   1,   0,   3,   3,   3,   3,
     2,   2,   0,   2,   2,   2,   2,   2,   1,   3,   1,   3,   3,   3,   3,   3,
     3,   2,   0,   2,   2,   2,   2,   2,   1,   2,   1,   0,   3,   3,   3,   3,
     2,   2,   0,   2,   2,   2,   2,   2,   1,   3,   1,   3,   3,   3,   3,   3,
     1,   2,   0,   2,   2,   2,   2,   2,   1,   2,   1,   0,   3,   3,   3,   3,
     2,   2,   0,   2,   2,   2,   2,   2,   1,   3,   1,   3,   3,   3,   3,   3,
     1,   2,   0,   2,   2,   2,   2,   2,   1,   2,   1,   0,   3,   3,   3,   3,
     2,   2,   0,   2,   2,   2,   2,   2,   1,   3,   1,   3,   3,   3,   3,   3,
     2,   2,   0,   2,   2,   2,   2,   2,   1,   0,   1,   0,   3,   3,   3,   3,
     2,   2,   0,   0,   2,   2,   2,   2,   1,   3,   1,   0,   0,   3,   0,   0,
     2,   2,   2,   2,   2,   2,   2,   2,   1,   2,   1,   0,   3,   3,   3,   3,
     2,   2,   0,   2,   2,   2,   2,   2,   1,   3,   1,   0,   3,   3,   3,   3,
     2,   2,   0,   2,   2,   2,   2,   2,   1,   2,   1,   0,   3,   3,   3,   3,
     2,   2,   0,   2,   2,   2,   2,   2,   1,   3,   1,   3,   3,   3,   3,   3,
     2,   2,   0,   2,   2,   2,   2,   2,   1,   2,   1,   2,   3,   3,   3,   3,
     2,   2,   0,   2,   2,   2,   2,   2,   1,   3,   1,   3,   3,   3,   3,   3,
]

let
  instructionCycles: FixedArray[Int] = [ // Number of cycles used
     7,   6,   2,   8,   3,   3,   5,   5,   3,   2,   2,   2,   4,   4,   6,   6,
     2,   5,   2,   8,   4,   4,   6,   6,   2,   4,   2,   7,   4,   4,   7,   7,
     6,   6,   2,   8,   3,   3,   5,   5,   4,   2,   2,   2,   4,   4,   6,   6,
     2,   5,   2,   8,   4,   4,   6,   6,   2,   4,   2,   7,   4,   4,   7,   7,
     6,   6,   2,   8,   3,   3,   5,   5,   3,   2,   2,   2,   3,   4,   6,   6,
     2,   5,   2,   8,   4,   4,   6,   6,   2,   4,   2,   7,   4,   4,   7,   7,
     6,   6,   2,   8,   3,   3,   5,   5,   4,   2,   2,   2,   5,   4,   6,   6,
     2,   5,   2,   8,   4,   4,   6,   6,   2,   4,   2,   7,   4,   4,   7,   7,
     2,   6,   2,   6,   3,   3,   3,   3,   2,   2,   2,   2,   4,   4,   4,   4,
     2,   6,   2,   6,   4,   4,   4,   4,   2,   5,   2,   5,   5,   5,   5,   5,
     2,   6,   2,   6,   3,   3,   3,   3,   2,   2,   2,   2,   4,   4,   4,   4,
     2,   5,   2,   5,   4,   4,   4,   4,   2,   4,   2,   4,   4,   4,   4,   4,
     2,   6,   2,   8,   3,   3,   5,   5,   2,   2,   2,   2,   4,   4,   6,   6,
     2,   5,   2,   8,   4,   4,   6,   6,   2,   4,   2,   7,   4,   4,   7,   7,
     2,   6,   2,   8,   3,   3,   5,   5,   2,   2,   2,   2,   4,   4,   6,   6,
     2,   5,   2,   8,   4,   4,   6,   6,   2,   4,   2,   7,   4,   4,   7,   7,
]

let
  instructionPageCycles: FixedArray[Int] = [ // Cycles used on a page cross
     0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
     1,   1,   0,   0,   0,   0,   0,   0,   0,   1,   0,   0,   1,   1,   0,   0,
     0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
     1,   1,   0,   0,   0,   0,   0,   0,   0,   1,   0,   0,   1,   1,   0,   0,
     0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
     1,   1,   0,   0,   0,   0,   0,   0,   0,   1,   0,   0,   1,   1,   0,   0,
     0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
     1,   1,   0,   0,   0,   0,   0,   0,   0,   1,   0,   0,   1,   1,   0,   0,
     0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
     1,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
     0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
     1,   1,   0,   1,   0,   0,   0,   0,   0,   1,   0,   1,   1,   1,   1,   1,
     0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
     1,   1,   0,   0,   0,   0,   0,   0,   0,   1,   0,   0,   1,   1,   0,   0,
     0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
     1,   1,   0,   0,   0,   0,   0,   0,   0,   1,   0,   0,   1,   1,   0,   0,
]

let
  instructionUnofficial: FixedArray[Int] = [ // 1 if official
  // 0    1    2    3    4    5    6    7    8    9    A    B    C    D    E    F
     0,   0,   1,   1,   1,   0,   0,   1,   0,   0,   0,   1,   1,   0,   0,   1,//0
     0,   0,   1,   1,   1,   0,   0,   1,   0,   0,   1,   1,   1,   0,   0,   1,//1
     0,   0,   1,   1,   0,   0,   0,   1,   0,   0,   0,   1,   0,   0,   0,   1,//2
     0,   0,   1,   1,   1,   0,   0,   1,   0,   0,   1,   1,   1,   0,   0,   1,//3
     0,   0,   1,   1,   1,   0,   0,   1,   0,   0,   0,   1,   0,   0,   0,   1,//4
     0,   0,   1,   1,   1,   0,   0,   1,   0,   0,   1,   1,   1,   0,   0,   1,//5
     0,   0,   1,   1,   1,   0,   0,   1,   0,   0,   0,   1,   0,   0,   0,   1,//6
     0,   0,   1,   1,   1,   0,   0,   1,   0,   0,   1,   1,   1,   0,   0,   1,//7
     1,   0,   1,   1,   0,   0,   0,   1,   0,   1,   0,   1,   0,   0,   0,   1,//8
     0,   0,   1,   1,   0,   0,   0,   1,   0,   0,   0,   1,   1,   0,   1,   1,//9
     0,   0,   0,   1,   0,   0,   0,   1,   0,   0,   0,   1,   0,   0,   0,   1,//A
     0,   0,   1,   1,   0,   0,   0,   1,   0,   0,   0,   1,   0,   0,   0,   1,//B
     0,   0,   1,   1,   0,   0,   0,   1,   0,   0,   0,   1,   0,   0,   0,   1,//C
     0,   0,   1,   1,   1,   0,   0,   1,   0,   0,   1,   1,   1,   0,   0,   1,//D
     0,   0,   1,   1,   0,   0,   0,   1,   0,   0,   0,   1,   0,   0,   0,   1,//E
     0,   0,   1,   1,   1,   0,   0,   1,   0,   0,   1,   1,   1,   0,   0,   1,//F
]


// Non-maskable interrupt
fn CPU::nmi(self : CPU) -> Unit {
  self.push16(self.pc)
  self.opPHP(StepInfo::default())
  self.pc = self.mem.read16(0xFFFA |> to_u16)
  self.i = true
  self.cycles += 7L
}

// IRQ interrupt
fn CPU::irq(self : CPU) -> Unit {
  self.push16(self.pc)
  self.opPHP(StepInfo::default())
  self.pc = self.mem.read16(0xFFFE |> to_u16)
  self.i = true
  self.cycles += 7L
}

fn AddressingMode::is_addressed(self : AddressingMode) -> Bool {
  match self {
    Accumulator | Implied => false
    _ => true
  }
}

fn CPU::get_addr(self : CPU, mode : AddressingMode) -> UInt16 {
  match mode {
    Absolute => self.mem.read16(self.pc + (1 |> to_u16))
    AbsoluteX => self.mem.read16(self.pc + (1 |> to_u16)) + (self.x |> to_u16)
    AbsoluteY => self.mem.read16(self.pc + (1 |> to_u16)) + (self.y |> to_u16)
    IndexedIndirect =>
      self.mem.read16bug(self.mem[self.pc + (1 |> to_u16)] + self.x |> to_u16)
    Indirect => self.mem.read16bug(self.mem.read16(self.pc + (1 |> to_u16)))
    IndirectIndexed =>
      self.mem.read16bug(self.mem[self.pc + (1 |> to_u16)] |> to_u16) +
      (self.y |> to_u16)
    ZeroPage => self.mem[self.pc + (1 |> to_u16)] |> to_u16
    ZeroPageX => self.mem[self.pc + (1 |> to_u16)] + self.x |> to_u16 // CHECKME
    ZeroPageY => self.mem[self.pc + (1 |> to_u16)] + self.y |> to_u16
    Immediate => self.pc + (1 |> to_u16)
    Accumulator | Implied => 0 |> to_u16
    Relative => {
      let offset = self.mem[self.pc + (1 |> to_u16)] |> to_u16
      if offset < (0x80 |> to_u16) {
        self.pc + (2 |> to_u16) + offset
      } else {
        self.pc + (2 |> to_u16) + offset - (0x100 |> to_u16)
      }
    }
  }
}

fn CPU::step(self : CPU, trace_log : Bool) -> Int {
  if self.stall > 0 {
    if trace_log {
      println("wait for stall" + self.stall.to_string())
    }
    self.stall = self.stall - 1
    return 1
  }
  let cycles = self.cycles
  match self.interrupt {
    NMI => {
      if trace_log {
        println("Do NMI")
      }
      self.nmi()
    }
    IRQ => {
      if trace_log {
        println("Do IRQ")
      }
      self.irq()
    }
    None => ()
  }
  self.interrupt = None
  let opcode = self.mem[self.pc]
  let mode = instructionModes[opcode._] |> addressingMode()
  let adr = self.get_addr(mode)

  // CHECKME: AbsoluteX can cross page too!
  if (mode == AbsoluteX && pagesDiffer(adr - (self.x |> to_u16), adr)) ||
    (
      ([AbsoluteY, IndirectIndexed] : FixedArray[AddressingMode]).contains(mode) &&
      pagesDiffer(adr - (self.y |> to_u16), adr)
    ) {
    self.cycles += instructionPageCycles[opcode._].to_int64()
  }
  self.pc += instructionSizes[opcode._] |> to_u16
  self.cycles += instructionCycles[opcode._].to_int64()
  let info : StepInfo = { address: adr, pc: self.pc, mode }
  instructions[opcode._](self, info)
  (self.cycles - cycles).to_int()
}
