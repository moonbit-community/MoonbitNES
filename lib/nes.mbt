// SPDX-License-Identifier: MIT
// Copyright (c) 2015 Dennis Felsing
// Copyright (c) 2024 Liu Rujia, International Digital Economy Academy

// Main Loop

///|
struct GlobalState {
  mut nes : NES?
}

///|
let gs : GlobalState = { nes: None }

///|
fn formatInt3(i : Int) -> String {
  let d1 = if i > 99 { (i / 100).to_string() } else { " " }
  let d2 = if i > 9 { (i / 10 % 10).to_string() } else { " " }
  d1 + d2 + (i % 10).to_string()
}

//PPU:  0, 21 CYC:7
// note that this should be called AFTER the instruction is executed

///|
fn NES::formatCycleInfo(self : NES) -> String {
  let ppu_x = self.ppu.scanLine |> formatInt3()
  let ppu_y = self.ppu.cycle |> formatInt3()
  let cyc = self.cpu.cycles
  "PPU:\{ppu_x},\{ppu_y} CYC:\{cyc}"
}

///|
pub fn nestest(rom : FixedArray[Int]) -> Unit {
  println("nestest")
  //cart := newCartridge(rom)
  let nes = NES::new(rom)
  nes.reset()
  //log_string("Next instructions:")
  //log_string(nes.cpu.formatMemoryDump(nesConsole.cpu.pc, 8))
  nes.cpu.pc = 0xC000 // nestest automated test address
  nes.cpu.interrupt = None // clear interrupt before auto test
  nes.ppu.scanLine = 0
  nes.ppu.cycle = 21
  nes.cpu.cycles = 7L

  // first mismatch should be line 8981:
  // C68B  8D 15 40  STA $4015 = FF                  A:02 X:FF Y:15 P:25 SP:FB PPU:233,107 CYC:26520
  for i = 0; i < 8991; i = i + 1 {
    let prefix = nes.cpu.formatInstruction()
    let suffix = nes.formatCycleInfo()
    println(prefix + " " + suffix)
    nes.step(false) |> ignore
  }
}

// get ready for playing!

///|
pub fn load_rom(rom : FixedArray[Int]) -> Unit {
  let nes = NES::new(rom)
  nes.reset()
  gs.nes = Some(nes)
  println("rom loaded")
}

///|
pub fn run(deltaTime : Double) -> Unit {
  let nes = gs.nes.unwrap()
  nes.run_a_while(deltaTime)
}

///|
pub fn run_with_logging(num_instructions : Int) -> Unit {
  let nes = gs.nes.unwrap()
  for i = 0; i < num_instructions; i = i + 1 {
    let line = nes.cpu.formatInstructionWithMesen2Extended()
    println(line)
    nes.step(true) |> ignore
  }
}

// player: 1, 2

///|
fn button(player : Int, btn : Int, state : Bool) -> Unit {
  let nes = gs.nes.unwrap()
  nes.controllers[player - 1].buttons[btn] = state
}

///|
pub fn buttonDown(player : Int, btn : Int) -> Unit {
  button(player, btn, true)
}

///|
pub fn buttonUp(player : Int, btn : Int) -> Unit {
  button(player, btn, false)
}
