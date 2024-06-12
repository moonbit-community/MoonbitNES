// SPDX-License-Identifier: MIT
// Copyright (c) 2015 Dennis Felsing
// Copyright (c) 2024 Liu Rujia, International Digital Economy Academy

let cpuFrequency = 1789773.0

struct CPUMemory {
  mut nes : Option[NES] // Emulating "weakptr"
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

fn AddressingMode::default() -> AddressingMode {
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

fn to_int(self : AddressingMode) -> Int {
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

fn op_get(self : CPUMemory, adr : UInt16) -> UInt8 {
  let n = self.nes.unwrap()
  if adr.0 >= 0x0000 && adr.0 <= 0x1FFF {
    n.ram[adr.0 % 0x0800]
  } else if adr >= (0x2000 |> to_u16) && adr <= (0x3FFF |> to_u16) {
    n.ppu.readRegister((0x2000 |> to_u16) + (adr.0 % 8 |> to_u16))
  } else if adr.0 == 0x4014 {
    n.ppu.readRegister(adr)
  } else if adr.0 == 0x4015 {
    n.apu.readRegister(adr)
  } else if adr.0 == 0x4016 {
    n.controllers[0].read()
  } else if adr.0 == 0x4017 {
    n.controllers[1].read()
  } else if adr.0 >= 0x6000 && adr.0 <= 0xFFFF {
    let m = n.mapper.unwrap()
    m[adr]
  } else {
    0 |> to_u8()
  }
}

fn op_set(self : CPUMemory, adr : UInt16, val : UInt8) -> Unit {
  let n = self.nes.unwrap()
  if adr.0 >= 0x0000 && adr.0 <= 0x1FFF {
    // let addr = adr.0
    // let v = val.0
    // log_string("[CPUMemory] set \(addr) to \(v)")
    n.ram[adr.0 % 0x0800] = val
  } else if adr.0 >= 0x2000 && adr.0 <= 0x3FFF {
    n.ppu.writeRegister((0x2000 |> to_u16) + (adr.0 % 8 |> to_u16), val)
  } else if adr.0 == 0x4014 {
    n.ppu.writeRegister(adr, val)
  } else if adr.0 >= 0x4000 && adr.0 <= 0x4013 || adr.0 == 0x4015 || adr.0 == 0x4017 {
    n.apu.writeRegister(adr, val)
  } else if adr.0 == 0x4016 {
    n.controllers[0].write(val)
    n.controllers[1].write(val)
  } else if adr.0 >= 0x6000 && adr.0 <= 0xFFFF {
    let m = n.mapper.unwrap()
    m[adr] = val
  }
}

fn read16(self : CPUMemory, adr : UInt16) -> UInt16 {
  let lo = self[adr] |> to_u16
  let hi = self[adr + (1 |> to_u16)] |> to_u16
  hi.lsl(8).lor(lo)
}

fn read16bug(self : CPUMemory, adr : UInt16) -> UInt16 {
  // Low byte wraps without incrementing high byte
  let a = adr
  let b = a.land(0xFF00 |> to_u16).lor(
    (adr |> to_u8()) + (1 |> to_u8()) |> to_u16,
  )
  let lo = self[a]
  let hi = self[b]
  (hi |> to_u16).lsl(8).lor(lo |> to_u16)
}

fn push(self : CPU, val : UInt8) -> Unit {
  self.mem[(self.sp |> to_u16).lor(0x100 |> to_u16)] = val
  self.sp = self.sp - (1 |> to_u8())
}

fn pull(self : CPU) -> UInt8 {
  self.sp = self.sp + (1 |> to_u8())
  self.mem[(self.sp |> to_u16).lor(0x100 |> to_u16)]
}

fn push16(self : CPU, val : UInt16) -> Unit {
  self.push(val.lsr(8) |> to_u8())
  self.push(val |> to_u8())
}

fn pull16(self : CPU) -> UInt16 {
  let v1 = self.pull() |> to_u16
  let v2 = (self.pull() |> to_u16).lsl(8)
  v1.lor(v2)
}

fn setZ(self : CPU, val : UInt8) -> Unit {
  self.z = val == (0 |> to_u8())
}

fn setN(self : CPU, val : UInt8) -> Unit {
  self.n = val.land(0x80 |> to_u8()) != (0 |> to_u8())
}

fn setZN(self : CPU, val : UInt8) -> Unit {
  self.setZ(val)
  self.setN(val)
}

fn flags(self : CPU) -> UInt8 {
  to_byte(self.c, self.z, self.i, self.d, self.b, self.u, self.v, self.n)
}

fn set_flags(self : CPU, flags : UInt8) -> Unit {
  self.c = flags.bit(0)
  self.z = flags.bit(1)
  self.i = flags.bit(2)
  self.d = flags.bit(3)
  self.b = flags.bit(4)
  self.u = flags.bit(5)
  self.v = flags.bit(6)
  self.n = flags.bit(7)
}

fn triggerNMI(self : CPU) -> Unit {
  self.interrupt = Interrupt::NMI
}

fn triggerIRQ(self : CPU) -> Unit {
  if not(self.i) {
    self.interrupt = Interrupt::IRQ
  }
}

// Reset resets the CPU to its initial powerup state
fn reset(self : CPU) -> Unit {
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
fn formatAssemblySuffix(self : CPU) -> String {
  let opcode = self.mem[self.pc]
  let name = instructionNames[opcode.0]
  let bytes = instructionSizes[opcode.0]
  let mode = instructionModes[opcode.0] |> addressingMode
  let modei = instructionModes[opcode.0]
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
      match opcode.0 {
        0x0a | 0x4a | 0x2a | 0x6a => "A "
        _ => ""
      }
    2 => {
      let address = self.mem[self.pc + (1 |> to_u16)]
      let address_hex = address.to_hex()
      match mode {
        Immediate => "#$\(address_hex)"
        ZeroPage => "$\(mem_addr8_hex) = \(stored_value_hex)"
        ZeroPageX =>
          "$\(address_hex),X @ \(mem_addr8_hex) = \(stored_value_hex)"
        ZeroPageY =>
          "$\(address_hex),Y @ \(mem_addr8_hex) = \(stored_value_hex)"
        // Indirect_X
        IndexedIndirect => {
          let new_addr_hex = (address + self.x).to_hex()
          "($\(address_hex),X) @ \(new_addr_hex) = \(mem_addr_hex) = \(stored_value_hex)"
        }
        // Indirect_Y
        IndirectIndexed => {
          // sub???
          let new_addr_hex = (mem_addr - (self.y |> to_u16)).to_hex() // 16-bit
          "($\(address_hex)),Y = \(new_addr_hex) @ \(mem_addr_hex) = \(stored_value_hex)"
        }
        Relative =>
          // assuming local jumps: BNE, BVS, etc....
          "$\(mem_addr_hex)"
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
        Indirect => "($\(address_hex)) = \(mem_addr_hex)"
        Relative =>
          // if opcode.0 == 0x6c {
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
          "$\(address_hex)"
        Absolute =>
          if name == "JMP" || name == "JSR" {
            "$\(address_hex)"
          } else {
            "$\(mem_addr_hex) = \(stored_value_hex)"
          }
        AbsoluteX => "$\(address_hex),X @ \(mem_addr_hex) = \(stored_value_hex)"
        AbsoluteY => "$\(address_hex),Y @ \(mem_addr_hex) = \(stored_value_hex)"
        //_ => abort("unexpected addressing mode {:?} has ops-len 3. code {:02x}",
        _ => ""
      }
    }
    _ => ""
  }
}

fn formatAssembly(self : CPU) -> String {
  let opcode = self.mem[self.pc]
  let name = instructionNames[opcode.0]
  loop name + " " + self.formatAssemblySuffix() {
    s => if s.length() < 32 { continue s + " " } else { s }
  }
}

fn isSpecialOpcode(op : Int) -> Bool {
  instructionUnofficial[op] == 1
}

// PrintInstruction prints the current CPU state (next instruction)
fn formatInstruction(self : CPU) -> String {
  let opcode = self.mem[self.pc]
  let bytes = instructionSizes[opcode.0]
  let name = instructionNames[opcode.0]
  let w0 = self.mem[self.pc + (0 |> to_u16)].to_hex()
  let mut w1 = self.mem[self.pc + (1 |> to_u16)].to_hex()
  let mut w2 = self.mem[self.pc + (2 |> to_u16)].to_hex()
  if bytes < 2 {
    w1 = "  "
  }
  if bytes < 3 {
    w2 = "  "
  }
  let uf = if isSpecialOpcode(opcode.0) { "*" } else { " " }
  let asm = self.formatAssembly()
  let pc = self.pc.to_hex()
  let a = self.a.to_hex()
  let x = self.x.to_hex()
  let y = self.y.to_hex()
  let p = self.flags().to_hex()
  let sp = self.sp.to_hex()
  "\(pc)  \(w0) \(w1) \(w2) \(uf)\(asm)A:\(a) X:\(x) Y:\(y) P:\(p) SP:\(sp)"
}

// Mesen2's trace logger format：everything except "use labels" and "indent based on stack pointer"
// format string:
// [Disassembly][EffectiveAddress] [MemoryValue,h][Align,38] A:[A,2h] X:[X,2h] Y:[Y,2h] S:[SP,2h] P:[P,h] V:[Scanline,3] H:[Cycle,3] Fr:[FrameCount] Cycle:[CycleCount] BC:[ByteCode]
// eg.
// AEB5   LDA $0300,X [$030E] = $00              A:00 X:0E Y:3F S:F6 P:04 V:-1  H:310 Fr:51 Cycle:1489016 BC:BD 00 03
fn formatInstructionWithMesen2Extended(self : CPU) -> String {
  let opcode = self.mem[self.pc]
  let bytes = instructionSizes[opcode.0]
  let name = instructionNames[opcode.0]
  let w0 = self.mem[self.pc + (0 |> to_u16)].to_hex()
  let mut w1 = self.mem[self.pc + (1 |> to_u16)].to_hex()
  let mut w2 = self.mem[self.pc + (2 |> to_u16)].to_hex()
  if bytes < 2 {
    w1 = "  "
  }
  if bytes < 3 {
    w2 = "  "
  }
  let uf = if isSpecialOpcode(opcode.0) { "*" } else { " " }
  let asm = self.formatAssembly()
  let pc = self.pc.to_hex()
  let a = self.a.to_hex()
  let x = self.x.to_hex()
  let y = self.y.to_hex()
  let p = self.flags().to_hex()
  let sp = self.sp.to_hex()
  "\(pc)  \(w0) \(w1) \(w2) \(uf)\(asm)A:\(a) X:\(x) Y:\(y) P:\(p) SP:\(sp)"
}

fn formatMemoryDump(self : CPU, base : UInt16, cnt : Int) -> String {
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
  a.land(0xFF00 |> to_u16) != b.land(0xFF00 |> to_u16)
}

// branch, then adds a cycle for taking a branch and adds another cycle
// if the branch jumps to a new page
fn branch(self : CPU, info : StepInfo) -> Unit {
  self.pc = info.address
  self.cycles += 1L
  if pagesDiffer(info.pc, info.address) {
    self.cycles += 1L
  }
}

fn compare(self : CPU, a : UInt8, b : UInt8) -> Unit {
  self.setZN(a - b)
  self.c = a >= b
}

// opcodes

// ADC - Add with carry
fn opADC(self : CPU, info : StepInfo) -> Unit {
  let a = self.a
  let b = self.mem[info.address]
  let c = self.c |> to_u8()
  self.a = a + b + c
  self.setZN(self.a)
  self.c = a.0 + b.0 + c.0 > 0xFF
  // (a^b)&0x80 == 0 && (a^self.a)&0x80 != 0
  self.v = a.lxor(b).land(0x80 |> to_u8()) == (0 |> to_u8()) && a.lxor(self.a).land(
      0x80 |> to_u8(),
    ) != (0 |> to_u8())
}

// AND - Logical and
// ** opcode name changed
fn opAND(self : CPU, info : StepInfo) -> Unit {
  self.a = self.a.land(self.mem[info.address]) // self.a & self.mem[info.address]
  self.setZN(self.a)
}

// ASL - Arithmetic shift left
fn opASL(self : CPU, info : StepInfo) -> Unit {
  match info.mode {
    Accumulator => {
      self.c = self.a.lsr(7).land(1 |> to_u8()) != (0 |> to_u8()) // (self.a >> 7) & 1
      self.a = self.a.lsl(1)
      self.setZN(self.a)
    }
    _ => {
      let mut val = self.mem[info.address]
      self.c = val.lsr(7).land(1 |> to_u8()) != (0 |> to_u8()) // (val >> 7) & 1
      val = val.lsl(1)
      self.mem[info.address] = val
      self.setZN(val)
    }
  }
}

// BCC - Branch if carry clear
fn opBCC(self : CPU, info : StepInfo) -> Unit {
  if self.c.not() {
    self.branch(info)
  }
}

// BCS - Branch if carry set
fn opBCS(self : CPU, info : StepInfo) -> Unit {
  if self.c {
    self.branch(info)
  }
}

// BEQ - Branch if equal
fn opBEQ(self : CPU, info : StepInfo) -> Unit {
  if self.z {
    self.branch(info)
  }
}

// BIT - Bit test
fn opBIT(self : CPU, info : StepInfo) -> Unit {
  let val = self.mem[info.address] // :- same as go!
  self.v = val.lsr(6).land(1 |> to_u8()) != (0 |> to_u8()) // (val >> 6) & 1
  self.setZ(val.land(self.a)) // val & self.A
  self.setN(val)
}

// BMI - Branch if minus
fn opBMI(self : CPU, info : StepInfo) -> Unit {
  if self.n {
    self.branch(info)
  }
}

// BNE - Branch if minus
fn opBNE(self : CPU, info : StepInfo) -> Unit {
  if not(self.z) {
    self.branch(info)
  }
}

// BPL - Branch if positive
fn opBPL(self : CPU, info : StepInfo) -> Unit {
  if not(self.n) {
    self.branch(info)
  }
}

// BRK - Force interrupt
fn opBRK(self : CPU, info : StepInfo) -> Unit {
  self.push16(self.pc)
  self.opPHP(info)
  self.opSEI(info)
  self.pc = self.mem.read16(0xFFFE |> to_u16)
}

// BVC - Branch if overflow clear
fn opBVC(self : CPU, info : StepInfo) -> Unit {
  if not(self.v) {
    self.branch(info)
  }
}

// BVS - Branch if overflow set
fn opBVS(self : CPU, info : StepInfo) -> Unit {
  if self.v {
    self.branch(info)
  }
}

// CLC - Clear carry flag
fn opCLC(self : CPU, _info : StepInfo) -> Unit {
  self.c = false
}

// CLD - Clear decimal mode
fn opCLD(self : CPU, _info : StepInfo) -> Unit {
  self.d = false
}

// CLI - Clear interrupt disable
fn opCLI(self : CPU, _info : StepInfo) -> Unit {
  self.i = false
}

// CLV - Clear overflow flag
fn opCLV(self : CPU, _info : StepInfo) -> Unit {
  self.v = false
}

// CMP - Compare
fn opCMP(self : CPU, info : StepInfo) -> Unit {
  self.compare(self.a, self.mem[info.address])
}

// CPX - Compare x register
fn opCPX(self : CPU, info : StepInfo) -> Unit {
  self.compare(self.x, self.mem[info.address])
}

// CPY - Compare y register
fn opCPY(self : CPU, info : StepInfo) -> Unit {
  self.compare(self.y, self.mem[info.address])
}

// DEC - Decrement memory
// **opcode name
fn opDEC(self : CPU, info : StepInfo) -> Unit {
  let val = self.mem[info.address] - (1 |> to_u8())
  self.mem[info.address] = val
  self.setZN(val)
}

// DEX - Decrement x register
fn opDEX(self : CPU, _info : StepInfo) -> Unit {
  self.x = self.x - (1 |> to_u8()) // self.x--
  self.setZN(self.x)
}

// DEY - Decrement y register
fn opDEY(self : CPU, _info : StepInfo) -> Unit {
  self.y = self.y - (1 |> to_u8()) // self.y--
  self.setZN(self.y)
}

// EOR - Exclusive or
fn opEOR(self : CPU, info : StepInfo) -> Unit {
  self.a = self.a.lxor(self.mem[info.address])
  self.setZN(self.a)
}

// INC - Increment memory
// **opcode name
fn opINC(self : CPU, info : StepInfo) -> Unit {
  let val = self.mem[info.address] + (1 |> to_u8())
  self.mem[info.address] = val
  self.setZN(val)
}

// INX - Increment x register
fn opINX(self : CPU, _info : StepInfo) -> Unit {
  self.x = self.x + (1 |> to_u8()) //self.x++
  self.setZN(self.x)
}

// INY - Increment y register
fn opINY(self : CPU, _info : StepInfo) -> Unit {
  self.y = self.y + (1 |> to_u8()) // self.y++
  self.setZN(self.y)
}

// JMP - Jump
fn opJMP(self : CPU, info : StepInfo) -> Unit {
  self.pc = info.address
  // addr_hex := self.pc.to_hex()
  // log_string("JMP \(addr_hex)")
}

// JSR - Jump to subroutine
fn opJSR(self : CPU, info : StepInfo) -> Unit {
  self.push16(self.pc - (1 |> to_u16))
  self.pc = info.address
}

// LDA - Load accumulator
fn opLDA(self : CPU, info : StepInfo) -> Unit {
  self.a = self.mem[info.address]
  self.setZN(self.a)
}

// LDX - Load x register
fn opLDX(self : CPU, info : StepInfo) -> Unit {
  self.x = self.mem[info.address]
  self.setZN(self.x)
}

// LDY - Load y register
fn opLDY(self : CPU, info : StepInfo) -> Unit {
  self.y = self.mem[info.address]
  self.setZN(self.y)
}

// LSR - Logical shift right
fn opLSR(self : CPU, info : StepInfo) -> Unit {
  match info.mode {
    Accumulator => {
      self.c = self.a.land(1 |> to_u8()) != (0 |> to_u8()) // self.A & 1
      self.a = self.a.lsr(1) // self.A >>= 1
      self.setZN(self.a)
    }
    _ => {
      let mut val = self.mem[info.address]
      self.c = val.land(1 |> to_u8()) != (0 |> to_u8()) // value & 1
      val = val.lsr(1) // val >>= 1
      self.mem[info.address] = val
      self.setZN(val)
    }
  }
}

// NOP - No operation
fn opNOP(self : CPU, info : StepInfo) -> Unit {

}

// ORA - Logical inclusive or
fn opORA(self : CPU, info : StepInfo) -> Unit {
  self.a = self.a.lor(self.mem[info.address])
  self.setZN(self.a)
}

// PHA - Push accumulator
fn opPHA(self : CPU, _info : StepInfo) -> Unit {
  self.push(self.a)
}

// PHP - Push processor status
fn opPHP(self : CPU, _info : StepInfo) -> Unit {
  self.push(self.flags().lor(0x10 |> to_u8()))
}

// PLA - Pull accumulator
fn opPLA(self : CPU, _info : StepInfo) -> Unit {
  self.a = self.pull()
  self.setZN(self.a)
}

// PLP - Pull processor status
fn opPLP(self : CPU, _info : StepInfo) -> Unit {
  self.set_flags(self.pull().land(0xEF |> to_u8()).lor(0x20 |> to_u8())) // pull() & 0xEF | 0x20
}

// ROL - Rotate left
fn opROL(self : CPU, info : StepInfo) -> Unit {
  let c = self.c |> to_u8()
  match info.mode {
    Accumulator => {
      self.c = self.a.lsr(7).land(1 |> to_u8()) != (0 |> to_u8()) // (self.A >> 7) & 1
      self.a = self.a.lsl(1).lor(c) // (self.A << 1) | c
      self.setZN(self.a)
    }
    _ => {
      let mut val = self.mem[info.address]
      self.c = val.lsr(7).land(1 |> to_u8()) != (0 |> to_u8()) // (val >> 7) & 1
      val = val.lsl(1).lor(c) // (val << 1) | c
      self.mem[info.address] = val
      self.setZN(val)
    }
  }
}

// ROR - Rotate right
fn opROR(self : CPU, info : StepInfo) -> Unit {
  let c = self.c |> to_u8()
  match info.mode {
    Accumulator => {
      self.c = self.a.land(1 |> to_u8()) != (0 |> to_u8()) // self.A & 1
      self.a = self.a.lsr(1).lor(c.lsl(7)) // (self.A >> 1) | (c << 7)
      self.setZN(self.a)
    }
    _ => {
      let mut val = self.mem[info.address]
      self.c = val.land(1 |> to_u8()) != (0 |> to_u8()) // val & 1
      val = val.lsr(1).lor(c.lsl(7)) // (val >> 1) | (c << 7)
      self.mem[info.address] = val
      self.setZN(val)
    }
  }
}

// RTI - Return from interrupt
fn opRTI(self : CPU, info : StepInfo) -> Unit {
  self.set_flags(self.pull().land(0xEF |> to_u8()).lor(0x20 |> to_u8())) // pull() & 0xEF | 0x20
  self.pc = self.pull16()
}

// RTS - Return from subrouting
fn opRTS(self : CPU, info : StepInfo) -> Unit {
  self.pc = self.pull16() + (1 |> to_u16)
}

// SBC - Subtract with carry
fn opSBC(self : CPU, info : StepInfo) -> Unit {
  let a = self.a
  let b = self.mem[info.address]
  let c = self.c |> to_u8()
  self.a = a - b - ((1 |> to_u8()) - c)
  self.setZN(self.a)
  self.c = a.0 - b.0 - ((1 |> to_u8()) - c).0 >= 0
  self.v = a.lxor(b).land(0x80 |> to_u8()) != (0 |> to_u8()) && a.lxor(self.a).land(
      0x80 |> to_u8(),
    ) != (0 |> to_u8())
}

// SEC - Set carry flag
fn opSEC(self : CPU, _info : StepInfo) -> Unit {
  self.c = true
}

// SED - Set decimal flag
fn opSED(self : CPU, _info : StepInfo) -> Unit {
  self.d = true
}

// SEI - Set interrupt disable
fn opSEI(self : CPU, _info : StepInfo) -> Unit {
  self.i = true
}

// STA - Store accumulator
fn opSTA(self : CPU, info : StepInfo) -> Unit {
  self.mem[info.address] = self.a
}

// STX - Store x register
fn opSTX(self : CPU, info : StepInfo) -> Unit {
  self.mem[info.address] = self.x
}

// STY - Store y register
fn opSTY(self : CPU, info : StepInfo) -> Unit {
  self.mem[info.address] = self.y
}

// TAX - Transfer accumulator to x
fn opTAX(self : CPU, _info : StepInfo) -> Unit {
  self.x = self.a
  self.setZN(self.x)
}

// TAY - Transfer accumulator to y
fn opTAY(self : CPU, _info : StepInfo) -> Unit {
  self.y = self.a
  self.setZN(self.y)
}

// TSX - Transfer stack pointer to x
fn opTSX(self : CPU, _info : StepInfo) -> Unit {
  self.x = self.sp
  self.setZN(self.x)
}

// TXA - Transfer x to accumulator
fn opTXA(self : CPU, _info : StepInfo) -> Unit {
  self.a = self.x
  self.setZN(self.a)
}

// TXS - Transfer x to stack pointer
fn opTXS(self : CPU, _info : StepInfo) -> Unit {
  self.sp = self.x
}

// TYA - Transfer y to accumulator
fn opTYA(self : CPU, _info : StepInfo) -> Unit {
  self.a = self.y
  self.setZN(self.a)
}

// # Illegal opcodes
// https://www.nesdev.org/wiki/CPU_unofficial_opcodes
// https://www.nesdev.org/wiki/Programming_with_unofficial_opcodes
fn opAHX(self : CPU, info : StepInfo) -> Unit {
  println("unimplemented: AHX")
  //abort("AHX")
}

fn opALR(self : CPU, info : StepInfo) -> Unit {
  println("unimplemented: ALR")
  //abort("ALR")
}

fn opANC(self : CPU, info : StepInfo) -> Unit {
  println("unimplemented: ANC")
  //abort("ANC")
}

fn opARR(self : CPU, info : StepInfo) -> Unit {
  println("unimplemented: ARR")
  //abort("ARR")
}

fn opAXS(self : CPU, info : StepInfo) -> Unit {
  println("unimplemented: AXS")
  //abort("AXS")
}

fn opDCP(self : CPU, info : StepInfo) -> Unit {
  // Equivalent to DEC value then CMP value, except supporting more addressing modes.
  // LDA #$FF followed by DCP can be used to check if the decrement underflows, which is useful for multi-byte decrements.
  self.opDEC(info)
  self.opCMP(info)
}

fn opISC(self : CPU, info : StepInfo) -> Unit {
  // Equivalent to INC value then SBC value, except supporting more addressing modes.
  self.opINC(info)
  self.opSBC(info)
}

fn opKIL(self : CPU, info : StepInfo) -> Unit {
  println("unimplemented: KIL")
  //abort("KIL")
}

fn opLAS(self : CPU, info : StepInfo) -> Unit {
  println("unimplemented: LAS")
  //abort("LAS")
}

fn opLAX(self : CPU, info : StepInfo) -> Unit {
  // Shortcut for LDA value then TAX. Saves a byte and two cycles and allows use of the X register with the (d),Y addressing mode.
  // Notice that the immediate is missing; the opcode that would have been LAX is affected by line noise on the data bus.
  // MOS 6502: even the bugs have bugs.
  self.opLDA(info)
  self.opTAX(info)
}

fn opRLA(self : CPU, info : StepInfo) -> Unit {
  // Equivalent to ROL value then AND value, except supporting more addressing modes.
  // LDA #$FF followed by RLA is an efficient way to rotate a variable while also loading it in A.
  self.opROL(info)
  self.opAND(info)
}

fn opRRA(self : CPU, info : StepInfo) -> Unit {
  // Equivalent to ROR value then ADC value, except supporting more addressing modes.
  // Essentially this computes A + value / 2, where value is 9-bit and the division is rounded up.
  self.opROR(info)
  self.opADC(info)
}

fn opSAX(self : CPU, info : StepInfo) -> Unit {
  // Stores the bitwise AND of A and X. As with STA and STX, no flags are affected.
  self.mem[info.address] = self.a.land(self.x)
}

fn opSHX(self : CPU, info : StepInfo) -> Unit {
  println("unimplemented: SHX")
  //abort("SHX")
}

fn opSHY(self : CPU, info : StepInfo) -> Unit {
  println("unimplemented: SHY")
  //abort("SHY")
}

fn opSLO(self : CPU, info : StepInfo) -> Unit {
  // Equivalent to ASL value then ORA value, except supporting more addressing modes.
  // LDA #0 followed by SLO is an efficient way to shift a variable while also loading it in A.
  self.opASL(info)
  self.opORA(info)
}

fn opSRE(self : CPU, info : StepInfo) -> Unit {
  // Equivalent to LSR value then EOR value, except supporting more addressing modes.
  // LDA #0 followed by SRE is an efficient way to shift a variable while also loading it in A.
  self.opLSR(info)
  self.opEOR(info)
}

fn opTAS(self : CPU, info : StepInfo) -> Unit {
  println("unimplemented: TAS")
  //abort("TAS")
}

fn opXAA(self : CPU, info : StepInfo) -> Unit {
  println("unimplemented: XAA")
  //abort("XAA")
}

// 6502/6510/8500/8502 Opcode matrix:
// http://www.oxyron.de/html/opcodes02.html
let instructions: FixedArray[(CPU, StepInfo) -> Unit] = [ // All 6502 instructions
	opBRK, opORA, opKIL, opSLO, opNOP, opORA, opASL, opSLO,//0
	opPHP, opORA, opASL, opANC, opNOP, opORA, opASL, opSLO,
	opBPL, opORA, opKIL, opSLO, opNOP, opORA, opASL, opSLO,//1
	opCLC, opORA, opNOP, opSLO, opNOP, opORA, opASL, opSLO,
	opJSR, opAND, opKIL, opRLA, opBIT, opAND, opROL, opRLA,//2
	opPLP, opAND, opROL, opANC, opBIT, opAND, opROL, opRLA,
	opBMI, opAND, opKIL, opRLA, opNOP, opAND, opROL, opRLA,//3
	opSEC, opAND, opNOP, opRLA, opNOP, opAND, opROL, opRLA,
	opRTI, opEOR, opKIL, opSRE, opNOP, opEOR, opLSR, opSRE,//4
	opPHA, opEOR, opLSR, opALR, opJMP, opEOR, opLSR, opSRE,
	opBVC, opEOR, opKIL, opSRE, opNOP, opEOR, opLSR, opSRE,//5
	opCLI, opEOR, opNOP, opSRE, opNOP, opEOR, opLSR, opSRE,
	opRTS, opADC, opKIL, opRRA, opNOP, opADC, opROR, opRRA,//6
	opPLA, opADC, opROR, opARR, opJMP, opADC, opROR, opRRA,
	opBVS, opADC, opKIL, opRRA, opNOP, opADC, opROR, opRRA,//7
	opSEI, opADC, opNOP, opRRA, opNOP, opADC, opROR, opRRA,
	opNOP, opSTA, opNOP, opSAX, opSTY, opSTA, opSTX, opSAX,//8
	opDEY, opNOP, opTXA, opXAA, opSTY, opSTA, opSTX, opSAX,
	opBCC, opSTA, opKIL, opAHX, opSTY, opSTA, opSTX, opSAX,//9
	opTYA, opSTA, opTXS, opTAS, opSHY, opSTA, opSHX, opAHX,
	opLDY, opLDA, opLDX, opLAX, opLDY, opLDA, opLDX, opLAX,//A
	opTAY, opLDA, opTAX, opLAX, opLDY, opLDA, opLDX, opLAX,
	opBCS, opLDA, opKIL, opLAX, opLDY, opLDA, opLDX, opLAX,//B
	opCLV, opLDA, opTSX, opLAS, opLDY, opLDA, opLDX, opLAX,
	opCPY, opCMP, opNOP, opDCP, opCPY, opCMP, opDEC, opDCP,//C
	opINY, opCMP, opDEX, opAXS, opCPY, opCMP, opDEC, opDCP,
	opBNE, opCMP, opKIL, opDCP, opNOP, opCMP, opDEC, opDCP,//D
	opCLD, opCMP, opNOP, opDCP, opNOP, opCMP, opDEC, opDCP,
	opCPX, opSBC, opNOP, opISC, opCPX, opSBC, opINC, opISC,//E
	opINX, opSBC, opNOP, opSBC, opCPX, opSBC, opINC, opISC,
	opBEQ, opSBC, opKIL, opISC, opNOP, opSBC, opINC, opISC,//F
	opSED, opSBC, opNOP, opISC, opNOP, opSBC, opINC, opISC,
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
fn nmi(self : CPU) -> Unit {
  self.push16(self.pc)
  self.opPHP(StepInfo::default())
  self.pc = self.mem.read16(0xFFFA |> to_u16)
  self.i = true
  self.cycles += 7L
}

// IRQ interrupt
fn irq(self : CPU) -> Unit {
  self.push16(self.pc)
  self.opPHP(StepInfo::default())
  self.pc = self.mem.read16(0xFFFE |> to_u16)
  self.i = true
  self.cycles += 7L
}

fn is_addressed(self : AddressingMode) -> Bool {
  match self {
    Accumulator | Implied => false
    _ => true
  }
}

fn get_addr(self : CPU, mode : AddressingMode) -> UInt16 {
  match mode {
    Absolute => self.mem.read16(self.pc + (1 |> to_u16))
    AbsoluteX => self.mem.read16(self.pc + (1 |> to_u16)) + (self.x |> to_u16)
    AbsoluteY => self.mem.read16(self.pc + (1 |> to_u16)) + (self.y |> to_u16)
    IndexedIndirect =>
      self.mem.read16bug(self.mem[self.pc + (1 |> to_u16)] + self.x |> to_u16)
    Indirect => self.mem.read16bug(self.mem.read16(self.pc + (1 |> to_u16)))
    IndirectIndexed =>
      self.mem.read16bug(self.mem[self.pc + (1 |> to_u16)] |> to_u16) + (self.y
      |> to_u16)
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

fn step(self : CPU, trace_log : Bool) -> Int {
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
  let mode = instructionModes[opcode.0] |> addressingMode()
  let adr = self.get_addr(mode)

  // CHECKME: AbsoluteX can cross page too!
  if mode == AbsoluteX && pagesDiffer(adr - (self.x |> to_u16), adr) || (
    [AbsoluteY, IndirectIndexed] : FixedArray[AddressingMode]).contains(mode) && pagesDiffer(
    adr - (self.y |> to_u16),
    adr,
  ) {
    self.cycles += instructionPageCycles[opcode.0].to_int64()
  }
  self.pc += instructionSizes[opcode.0] |> to_u16
  self.cycles += instructionCycles[opcode.0].to_int64()
  let info : StepInfo = { address: adr, pc: self.pc, mode }
  instructions[opcode.0](self, info)
  (self.cycles - cycles).to_int()
}
