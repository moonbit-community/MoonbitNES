// SPDX-License-Identifier: MIT
// Copyright (c) 2015 Dennis Felsing
// Copyright (c) 2024 Liu Rujia, International Digital Economy Academy

struct NES {
  cpu : CPU
  apu : APU
  ppu : PPU
  cartridge : Cartridge
  controllers : FixedArray[Controller]
  mut mapper : Option[Mapper]
  ram : FixedArray[UInt8] // 2048 bytes
  mut step_cnt : Int
}

fn NES::new(data : FixedArray[Int]) -> NES {
  let controllers: FixedArray[_] = [Controller::new(), Controller::new()]
  let nes : NES = {
    cpu: initCPU(),
    ppu: initPPU(),
    apu: initAPU(),
    cartridge: newCartridge(data),
    controllers,
    mapper: None,
    ram: FixedArray::make(2048, 0 |> to_u8),
    step_cnt: 0,
  }
  nes.mapper = Some(Mapper::new(nes))
  nes.cpu.mem.nes = Some(nes)
  nes.ppu.nes = Some(nes)
  nes.ppu.mem.nes = Some(nes)
  nes.apu.nes = Some(nes)
  nes.apu.dmc.cpu = Some(nes.cpu)
  nes.cpu.reset()
  nes
}

fn NES::reset(self : NES) -> Unit {
  self.cpu.reset()
  self.ppu.reset()
  let prefix = self.cpu.formatInstruction()
  let suffix = self.formatCycleInfo()
  println("Initial instruction after reset: " + prefix + " " + suffix)
}

fn NES::step(self : NES, trace_log : Bool) -> Int {
  let step_cnt = self.step_cnt
  //log_trace("step: \(step_cnt)")
  let cpuCycles = self.cpu.step(trace_log)
  let ppuCycles = cpuCycles * 3

  //for i in 1 .. result*3:
  let mapper = self.mapper.unwrap()
  for i = 0; i < ppuCycles; i = i + 1 {
    self.ppu.step(trace_log)
    mapper.step()
  }
  for i = 0; i < cpuCycles; i = i + 1 {
    // comment out this if you don't need sound/music
    self.apu.step(trace_log)
  }
  self.step_cnt = self.step_cnt + 1
  cpuCycles
}

fn NES::run_a_while(self : NES, seconds : Double) -> Unit {
  loop (cpuFrequency * seconds).to_int() {
    cycles => if cycles > 0 { continue cycles - self.step(false) }
  }
}
