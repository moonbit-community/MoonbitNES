// SPDX-License-Identifier: MIT
// Copyright (c) 2015 Dennis Felsing
// Copyright (c) 2024 Liu Rujia, International Digital Economy Academy

///|
struct APU {
  mut nes : NES?
  // chan : FixedArray[Double] // len=4096. go: chan float32
  // mut chanPos : Int // used by nim
  sampleRate : Double
  pulse : FixedArray[Pulse] // len=2
  triangle : Triangle
  mut noise : Noise
  mut dmc : DMC
  mut cycle : Int64
  mut framePeriod : UInt8
  mut frameValue : UInt8
  mut frameIRQ : Bool
  //filterChain: FilterChain // used by go
}

///|
fn initAPU() -> APU {
  let pulse0 = Pulse::new()
  let pulse1 = Pulse::new()
  let result : APU = {
    nes: None,
    // chan: FixedArray::make(4096, 0.0),
    // chanPos: 0,
    sampleRate: cpuFrequency / 44100.0, // a constant in nim
    pulse: [pulse0, pulse1],
    triangle: Triangle::new(),
    noise: Noise::new(),
    dmc: DMC::new(),
    cycle: 0L,
    framePeriod: 4 |> to_u8,
    frameValue: 0 |> to_u8,
    frameIRQ: false,
  }
  result.noise.shiftRegister = 1 |> to_u16
  result.pulse[0].channel = 1 |> to_u8
  result.pulse[1].channel = 2 |> to_u8
  result
}

///|
let frameCounterRate : Double = cpuFrequency / 240.0

///|
let lengthTable : FixedArray[Int] = [
  10, 254, 20, 2, 40, 4, 80, 6, 160, 8, 60, 10, 14, 12, 26, 14, 12, 16, 24, 18, 48,
  20, 96, 22, 192, 24, 72, 26, 16, 28, 32, 30,
]

///|
let dutyTable : FixedArray[FixedArray[Int]] = [
  [0, 1, 0, 0, 0, 0, 0, 0],
  [0, 1, 1, 0, 0, 0, 0, 0],
  [0, 1, 1, 1, 1, 0, 0, 0],
  [1, 0, 0, 1, 1, 1, 1, 1],
]

///|
let triangleTable : FixedArray[Int] = [
  15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8,
  9, 10, 11, 12, 13, 14, 15,
]

// uint16

///|
let noiseTable : FixedArray[Int] = [
  4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068,
]

// uint8

///|
let dmcTable : FixedArray[Int] = [
  214, 190, 170, 160, 143, 127, 113, 107, 95, 80, 71, 64, 53, 42, 36, 27,
]

// float32

///|
let pulseTable : FixedArray[Double] = FixedArray::make(31, 0.0)

///|
let tndTable : FixedArray[Double] = FixedArray::make(203, 0.0)

///|
fn APU::step(self : APU, trace_log : Bool) -> Unit {
  let cycle1 = self.cycle
  self.cycle = self.cycle + 1L
  let cycle2 = self.cycle
  self.stepTimer()
  let f1 = (cycle1.to_double() / frameCounterRate).to_int()
  let f2 = (cycle2.to_double() / frameCounterRate).to_int()
  if f1 != f2 {
    self.stepFrameCounter()
  }
  let s1 = (cycle1.to_double() / self.sampleRate).to_int()
  let s2 = (cycle2.to_double() / self.sampleRate).to_int()
  if s1 != s2 {
    self.sendSample() // this is go's way
    // if self.chanPos < self.chan.length() {
    //   // nim's way
    //   self.chan[self.chanPos] = self.output()
    //   self.chanPos = self.chanPos + 1
    // }
  }
}

// we don't support filterChain for now

///|
fn APU::sendSample(self : APU) -> Unit {
  let output = self.output()
  nes_write_audio_sample(output) // call FFI!
  // output := apu.filterChain.Step(apu.output())
  // select {
  // case apu.channel <- output:
  // default:
  // }
}

// float32

///|
fn APU::output(self : APU) -> Double {
  let p1 = self.pulse[0].output()
  let p2 = self.pulse[1].output()
  let t = self.triangle.output()
  let n = self.noise.output()
  let d = self.dmc.output()
  let pulseOut = pulseTable[p1.inner() + p2.inner()]
  let tndOut = tndTable[3 * t.inner() + 2 * n.inner() + d.inner()]
  return pulseOut + tndOut
}

// mode 0:    mode 1:       function
// ---------  -----------  -----------------------------
//  - - - f    - - - - -    IRQ (if bit 6 is clear)
//  - l - l    l - l - -    Length counter and sweep
//  e e e e    e e e e -    Envelope and linear counter

///|
fn APU::stepFrameCounter(self : APU) -> Unit {
  match self.framePeriod.inner() {
    4 => {
      self.frameValue = ((self.frameValue.inner() + 1) % 4) |> to_u8
      match self.frameValue.inner() {
        0 | 2 => self.stepEnvelope()
        1 => {
          self.stepEnvelope()
          self.stepSweep()
          self.stepLength()
        }
        3 => {
          self.stepEnvelope()
          self.stepSweep()
          self.stepLength()
          self.fireIRQ()
        }
        _ => println("stepFrameCounter match failure 1")
      }
    }
    5 => {
      self.frameValue = ((self.frameValue.inner() + 1) % 5) |> to_u8
      match self.frameValue.inner() {
        0 | 2 => self.stepEnvelope()
        1 | 3 => {
          self.stepEnvelope()
          self.stepSweep()
          self.stepLength()
        }
        _ => println("stepFrameCounter match failure 2")
      }
    }
    _ => println("stepFrameCounter match failure 3")
  }
}

///|
fn APU::stepTimer(self : APU) -> Unit {
  if self.cycle % 2L == 0L {
    self.pulse[0].stepTimer()
    self.pulse[1].stepTimer()
    self.noise.stepTimer()
    self.dmc.stepTimer()
  }
  self.triangle.stepTimer()
}

///|
fn APU::stepEnvelope(self : APU) -> Unit {
  self.pulse[0].stepEnvelope()
  self.pulse[1].stepEnvelope()
  self.triangle.stepCounter()
  self.noise.stepEnvelope()
}

///|
fn APU::stepSweep(self : APU) -> Unit {
  self.pulse[0].stepSweep()
  self.pulse[1].stepSweep()
}

///|
fn APU::stepLength(self : APU) -> Unit {
  self.pulse[0].stepLength()
  self.pulse[1].stepLength()
  self.triangle.stepLength()
  self.noise.stepLength()
}

///|
fn APU::fireIRQ(self : APU) -> Unit {
  let console = self.nes.unwrap()
  if self.frameIRQ {
    console.cpu.triggerIRQ()
  }
}

///|
fn APU::readRegister(self : APU, adr : UInt16) -> UInt8 {
  let address = adr.inner()
  match address {
    0x4015 => return self.readStatus()
    _ => abort("unhandled apu register read")
  }
  // default:
  // 	log.Fatalf("unhandled apu register read at address: 0x%04X", address)
  return 0 |> to_u8
}

///|
fn APU::writeRegister(self : APU, adr : UInt16, val : UInt8) -> Unit {
  let address = adr.inner()
  match address {
    0x4000 => self.pulse[0].writeControl(val)
    0x4001 => self.pulse[0].writeSweep(val)
    0x4002 => self.pulse[0].writeTimerLow(val)
    0x4003 => self.pulse[0].writeTimerHigh(val)
    0x4004 => self.pulse[1].writeControl(val)
    0x4005 => self.pulse[1].writeSweep(val)
    0x4006 => self.pulse[1].writeTimerLow(val)
    0x4007 => self.pulse[1].writeTimerHigh(val)
    0x4008 => self.triangle.writeControl(val)
    0x4009 | 0x4010 => self.dmc.writeControl(val)
    0x4011 => self.dmc.writeValue(val)
    0x4012 => self.dmc.writeAddress(val)
    0x4013 => self.dmc.writeLength(val)
    0x400A => self.triangle.writeTimerLow(val)
    0x400B => self.triangle.writeTimerHigh(val)
    0x400C => self.noise.writeControl(val)
    0x400D | 0x400E => self.noise.writePeriod(val)
    0x400F => self.noise.writeLength(val)
    0x4015 => self.writeControl(val)
    0x4017 => self.writeFrameCounter(val)
    _ => abort("unhandled apu register write")
  }
}

///|
fn APU::readStatus(self : APU) -> UInt8 {
  let mut result = 0
  if self.pulse[0].lengthValue.inner() > 0 {
    result = result | 1
  }
  if self.pulse[1].lengthValue.inner() > 0 {
    result = result | 2
  }
  if self.triangle.lengthValue.inner() > 0 {
    result = result | 4
  }
  if self.noise.lengthValue.inner() > 0 {
    result = result | 8
  }
  if self.dmc.currentLength.inner() > 0 {
    result = result | 16
  }
  result |> to_u8
}

///|
fn APU::writeControl(self : APU, val : UInt8) -> Unit {
  let value = val.inner()
  self.pulse[0].enabled = (value & 1) == 1
  self.pulse[1].enabled = (value & 2) == 2
  self.triangle.enabled = (value & 4) == 4
  self.noise.enabled = (value & 8) == 8
  self.dmc.enabled = (value & 16) == 16
  if not(self.pulse[0].enabled) {
    self.pulse[0].lengthValue = 0 |> to_u8
  }
  if not(self.pulse[1].enabled) {
    self.pulse[1].lengthValue = 0 |> to_u8
  }
  if not(self.triangle.enabled) {
    self.triangle.lengthValue = 0 |> to_u8
  }
  if not(self.noise.enabled) {
    self.noise.lengthValue = 0 |> to_u8
  }
  if not(self.dmc.enabled) {
    self.dmc.currentLength = 0 |> to_u16
  } else if self.dmc.currentLength == (0 |> to_u16) {
    self.dmc.restart()
  }
}

///|
fn APU::writeFrameCounter(self : APU, val : UInt8) -> Unit {
  let value = val.inner() & 0xFF
  self.framePeriod = (4 + ((value >> 7) & 1)) |> to_u8
  self.frameIRQ = ((value >> 6) & 1) == 0
  // self.frameValue = 0
  if self.framePeriod == (5 |> to_u8) {
    self.stepEnvelope()
    self.stepSweep()
    self.stepLength()
  }
}

///| Pulse
struct Pulse {
  mut enabled : Bool
  mut channel : UInt8
  mut lengthEnabled : Bool
  mut lengthValue : UInt8
  mut timerPeriod : UInt16
  mut timerValue : UInt16
  mut dutyMode : UInt8
  mut dutyValue : UInt8
  mut sweepReload : Bool
  mut sweepEnabled : Bool
  mut sweepNegate : Bool
  mut sweepShift : UInt8
  mut sweepPeriod : UInt8
  mut sweepValue : UInt8
  mut envelopeEnabled : Bool
  mut envelopeLoop : Bool
  mut envelopeStart : Bool
  mut envelopePeriod : UInt8
  mut envelopeValue : UInt8
  mut envelopeVolume : UInt8
  mut constantVolume : UInt8
}

///|
fn Pulse::new() -> Pulse {
  {
    enabled: false,
    channel: 0 |> to_u8,
    lengthEnabled: false,
    lengthValue: 0 |> to_u8,
    timerPeriod: 0 |> to_u16,
    timerValue: 0 |> to_u16,
    dutyMode: 0 |> to_u8,
    dutyValue: 0 |> to_u8,
    sweepReload: false,
    sweepEnabled: false,
    sweepNegate: false,
    sweepShift: 0 |> to_u8,
    sweepPeriod: 0 |> to_u8,
    sweepValue: 0 |> to_u8,
    envelopeEnabled: false,
    envelopeLoop: false,
    envelopeStart: false,
    envelopePeriod: 0 |> to_u8,
    envelopeValue: 0 |> to_u8,
    envelopeVolume: 0 |> to_u8,
    constantVolume: 0 |> to_u8,
  }
}

///|
fn Pulse::writeControl(self : Pulse, val : UInt8) -> Unit {
  let value = val.inner() & 0xFF
  self.dutyMode = ((value >> 6) & 3) |> to_u8
  self.lengthEnabled = ((value >> 5) & 1) == 0
  self.envelopeLoop = ((value >> 5) & 1) == 1
  self.envelopeEnabled = ((value >> 4) & 1) == 0
  self.envelopePeriod = (value & 15) |> to_u8
  self.constantVolume = (value & 15) |> to_u8
  self.envelopeStart = true
}

///|
fn Pulse::writeSweep(self : Pulse, val : UInt8) -> Unit {
  let value = val.inner() & 0xFF
  self.sweepEnabled = ((value >> 7) & 1) == 1
  self.sweepPeriod = (((value >> 4) & 7) + 1) |> to_u8
  self.sweepNegate = ((value >> 3) & 1) == 1
  self.sweepShift = (value & 7) |> to_u8
  self.sweepReload = true
}

///|
fn Pulse::writeTimerLow(self : Pulse, val : UInt8) -> Unit {
  let value = val.inner()
  self.timerPeriod = (self.timerPeriod & (0xFF00 |> to_u16)) | (value |> to_u16)
}

///|
fn Pulse::writeTimerHigh(self : Pulse, val : UInt8) -> Unit {
  let value = val.inner() & 0xFF
  self.lengthValue = lengthTable[value >> 3] |> to_u8
  self.timerPeriod = (self.timerPeriod & (0x00FF |> to_u16)) |
    (((value & 7) << 8) |> to_u16) // CHECKME
  self.envelopeStart = true
  self.dutyValue = 0 |> to_u8
}

///|
fn Pulse::stepTimer(self : Pulse) -> Unit {
  if self.timerValue.inner() == 0 {
    self.timerValue = self.timerPeriod
    self.dutyValue = ((self.dutyValue.inner() + 1) % 8) |> to_u8
  } else {
    self.timerValue = self.timerValue - (1 |> to_u16)
  }
}

///|
fn Pulse::stepEnvelope(self : Pulse) -> Unit {
  if self.envelopeStart {
    self.envelopeVolume = 15 |> to_u8
    self.envelopeValue = self.envelopePeriod
    self.envelopeStart = false
  } else if self.envelopeValue.inner() > 0 {
    self.envelopeValue = self.envelopeValue - (1 |> to_u8)
  } else {
    if self.envelopeVolume.inner() > 0 {
      self.envelopeVolume = self.envelopeVolume - (1 |> to_u8)
    } else if self.envelopeLoop {
      self.envelopeVolume = 15 |> to_u8
    }
    self.envelopeValue = self.envelopePeriod
  }
}

///|
fn Pulse::stepSweep(self : Pulse) -> Unit {
  if self.sweepReload {
    if self.sweepEnabled && self.sweepValue.inner() == 0 {
      self.sweep()
    }
    self.sweepValue = self.sweepPeriod
    self.sweepReload = false
  } else if self.sweepValue.inner() > 0 {
    self.sweepValue = self.sweepValue - (1 |> to_u8)
  } else {
    if self.sweepEnabled {
      self.sweep()
    }
    self.sweepValue = self.sweepPeriod
  }
}

///|
fn Pulse::stepLength(self : Pulse) -> Unit {
  if self.lengthEnabled && self.lengthValue.inner() > 0 {
    self.lengthValue = self.lengthValue - (1 |> to_u8)
  }
}

///|
fn Pulse::sweep(self : Pulse) -> Unit {
  let delta = self.timerPeriod >> self.sweepShift.inner()
  if self.sweepNegate {
    self.timerPeriod = self.timerPeriod - delta
    if self.channel.inner() == 1 {
      self.timerPeriod = self.timerPeriod - (1 |> to_u16)
    }
  } else {
    self.timerPeriod = self.timerPeriod + delta
  }
}

///|
fn Pulse::output(self : Pulse) -> UInt8 {
  if not(self.enabled) {
    return 0 |> to_u8
  }
  if self.lengthValue.inner() == 0 {
    return 0 |> to_u8
  }
  if dutyTable[self.dutyMode.inner()][self.dutyValue.inner()] == 0 {
    return 0 |> to_u8
  }
  if self.timerPeriod.inner() < 8 || self.timerPeriod.inner() > 0x7FF {
    return 0 |> to_u8
  }
  // if !self.sweepNegate && self.timerPeriod+(self.timerPeriod>>self.sweepShift) > 0x7FF {
  // 	return 0
  // }
  if self.envelopeEnabled {
    return self.envelopeVolume
  } else {
    return self.constantVolume
  }
}

///| Triangle
struct Triangle {
  mut enabled : Bool
  mut lengthEnabled : Bool
  mut lengthValue : UInt8
  mut timerPeriod : UInt16
  mut timerValue : UInt16
  mut dutyValue : UInt8
  mut counterPeriod : UInt8
  mut counterValue : UInt8
  mut counterReload : Bool
}

///|
fn Triangle::new() -> Triangle {
  {
    enabled: false,
    lengthEnabled: false,
    lengthValue: 0 |> to_u8,
    timerPeriod: 0 |> to_u16,
    timerValue: 0 |> to_u16,
    dutyValue: 0 |> to_u8,
    counterPeriod: 0 |> to_u8,
    counterValue: 0 |> to_u8,
    counterReload: false,
  }
}

///|
fn Triangle::writeControl(self : Triangle, val : UInt8) -> Unit {
  let value = val.inner()
  self.lengthEnabled = (((value & 0xFF) >> 7) & 1) == 0
  self.counterPeriod = (value & 0x7F) |> to_u8
}

///|
fn Triangle::writeTimerLow(self : Triangle, val : UInt8) -> Unit {
  let value = val.inner()
  self.timerPeriod = (self.timerPeriod & (0xFF00 |> to_u16)) | (value |> to_u16) // CHECKME
}

///|
fn Triangle::writeTimerHigh(self : Triangle, val : UInt8) -> Unit {
  let value = val.inner()
  self.lengthValue = lengthTable[(value & 0xFF) >> 3] |> to_u8
  self.timerPeriod = (self.timerPeriod & (0x00FF |> to_u16)) |
    (((value & 7) << 8) |> to_u16) // CHECKME
  self.timerValue = self.timerPeriod
  self.counterReload = true
}

///|
fn Triangle::stepTimer(self : Triangle) -> Unit {
  if self.timerValue.inner() == 0 {
    self.timerValue = self.timerPeriod
    if self.lengthValue.inner() > 0 && self.counterValue.inner() > 0 {
      self.dutyValue = ((self.dutyValue.inner() + 1) % 32) |> to_u8
    }
  } else {
    self.timerValue = self.timerValue - (1 |> to_u16)
  }
}

///|
fn Triangle::stepLength(self : Triangle) -> Unit {
  if self.lengthEnabled && self.lengthValue.inner() > 0 {
    self.lengthValue = self.lengthValue - (1 |> to_u8)
  }
}

///|
fn Triangle::stepCounter(self : Triangle) -> Unit {
  if self.counterReload {
    self.counterValue = self.counterPeriod
  } else if self.counterValue.inner() > 0 {
    self.counterValue = self.counterValue - (1 |> to_u8)
  }
  if self.lengthEnabled {
    self.counterReload = false
  }
}

///|
fn Triangle::output(self : Triangle) -> UInt8 {
  if not(self.enabled) {
    return 0 |> to_u8
  }
  if self.timerPeriod.inner() < 3 {
    return 0 |> to_u8
  }
  if self.lengthValue.inner() == 0 {
    return 0 |> to_u8
  }
  if self.counterValue.inner() == 0 {
    return 0 |> to_u8
  }
  return triangleTable[self.dutyValue.inner()] |> to_u8
}

///| Noise
struct Noise {
  mut enabled : Bool
  mut mode : Bool
  mut shiftRegister : UInt16
  mut lengthEnabled : Bool
  mut lengthValue : UInt8
  mut timerPeriod : UInt16
  mut timerValue : UInt16
  mut envelopeEnabled : Bool
  mut envelopeLoop : Bool
  mut envelopeStart : Bool
  mut envelopePeriod : UInt8
  mut envelopeValue : UInt8
  mut envelopeVolume : UInt8
  mut constantVolume : UInt8
}

///|
fn Noise::new() -> Noise {
  {
    enabled: false,
    mode: false,
    shiftRegister: 0 |> to_u16,
    lengthEnabled: false,
    lengthValue: 0 |> to_u8,
    timerPeriod: 0 |> to_u16,
    timerValue: 0 |> to_u16,
    envelopeEnabled: false,
    envelopeLoop: false,
    envelopeStart: false,
    envelopePeriod: 0 |> to_u8,
    envelopeValue: 0 |> to_u8,
    envelopeVolume: 0 |> to_u8,
    constantVolume: 0 |> to_u8,
  }
}

///|
fn Noise::writeControl(self : Noise, val : UInt8) -> Unit {
  let value = val.inner() & 0xFF
  self.lengthEnabled = ((value >> 5) & 1) == 0
  self.envelopeLoop = ((value >> 5) & 1) == 1
  self.envelopeEnabled = ((value >> 4) & 1) == 0
  self.envelopePeriod = (value & 15) |> to_u8
  self.constantVolume = (value & 15) |> to_u8
  self.envelopeStart = true
}

///|
fn Noise::writePeriod(self : Noise, val : UInt8) -> Unit {
  let value = val.inner()
  self.mode = (value & 0x80) == 0x80
  self.timerPeriod = noiseTable[value & 0x0F] |> to_u16
}

///|
fn Noise::writeLength(self : Noise, val : UInt8) -> Unit {
  let value = val.inner() & 0xFF
  self.lengthValue = lengthTable[value >> 3] |> to_u8
  self.envelopeStart = true
}

///|
fn Noise::stepTimer(self : Noise) -> Unit {
  if self.timerValue.inner() == 0 {
    self.timerValue = self.timerPeriod
    let shift = if self.mode { 6 } else { 1 }
    let b1 = self.shiftRegister & (1 |> to_u16)
    let b2 = (self.shiftRegister >> shift) & (1 |> to_u16)
    self.shiftRegister = self.shiftRegister >> 1
    self.shiftRegister = self.shiftRegister | ((b1 ^ b2) >> 14)
  } else {
    self.timerValue = self.timerValue - (1 |> to_u16)
  }
}

///|
fn Noise::stepEnvelope(self : Noise) -> Unit {
  if self.envelopeStart {
    self.envelopeVolume = 15 |> to_u8
    self.envelopeValue = self.envelopePeriod
    self.envelopeStart = false
  } else if self.envelopeValue.inner() > 0 {
    self.envelopeValue = self.envelopeValue - (1 |> to_u8)
  } else {
    if self.envelopeVolume.inner() > 0 {
      self.envelopeVolume = self.envelopeVolume - (1 |> to_u8)
    } else if self.envelopeLoop {
      self.envelopeVolume = 15 |> to_u8
    }
    self.envelopeValue = self.envelopePeriod
  }
}

///|
fn Noise::stepLength(self : Noise) -> Unit {
  if self.lengthEnabled && self.lengthValue.inner() > 0 {
    self.lengthValue = self.lengthValue - (1 |> to_u8)
  }
}

///|
fn Noise::output(self : Noise) -> UInt8 {
  if not(self.enabled) {
    return 0 |> to_u8
  }
  if self.lengthValue.inner() == 0 {
    return 0 |> to_u8
  }
  if (self.shiftRegister.inner() & 1) == 1 {
    return 0 |> to_u8
  }
  if self.envelopeEnabled {
    return self.envelopeVolume
  } else {
    return self.constantVolume
  }
}

///|
struct DMC {
  mut cpu : CPU? // sigh...
  mut enabled : Bool
  mut value : UInt8
  mut sampleAddress : UInt16
  mut sampleLength : UInt16
  mut currentAddress : UInt16
  mut currentLength : UInt16
  mut shiftRegister : UInt8
  mut bitCount : UInt8
  mut tickValue : UInt8
  mut tickPeriod : UInt8
  mut loop_ : Bool
  mut irq : Bool
}

///|
fn DMC::new() -> DMC {
  {
    cpu: None,
    enabled: false,
    value: 0 |> to_u8,
    sampleAddress: 0 |> to_u16,
    sampleLength: 0 |> to_u16,
    currentAddress: 0 |> to_u16,
    currentLength: 0 |> to_u16,
    shiftRegister: 0 |> to_u8,
    bitCount: 0 |> to_u8,
    tickValue: 0 |> to_u8,
    tickPeriod: 0 |> to_u8,
    loop_: false,
    irq: false,
  }
}

///|
fn DMC::writeControl(self : DMC, val : UInt8) -> Unit {
  let value = val.inner()
  self.irq = (value & 0x80) == 0x80
  self.loop_ = (value & 0x40) == 0x40
  self.tickPeriod = dmcTable[value & 0x0F] |> to_u8
}

///|
fn DMC::writeValue(self : DMC, val : UInt8) -> Unit {
  let value = val.inner()
  self.value = (value & 0x7F) |> to_u8
}

///|
fn DMC::writeAddress(self : DMC, val : UInt8) -> Unit {
  let value = val.inner()
  // Sample address = %11AAAAAA.AA000000
  self.sampleAddress = (0xC000 |> to_u16) | ((value |> to_u16) << 6) // CHECKME
}

///|
fn DMC::writeLength(self : DMC, val : UInt8) -> Unit {
  let value = val.inner()
  // Sample length = %0000LLLL.LLLL0001
  self.sampleLength = ((value |> to_u16) << 4) | (1 |> to_u16) // CHECKME
}

///|
fn DMC::restart(self : DMC) -> Unit {
  self.currentAddress = self.sampleAddress
  self.currentLength = self.sampleLength
}

///|
fn DMC::stepTimer(self : DMC) -> Unit {
  if not(self.enabled) {
    return
  }
  self.stepReader()
  if self.tickValue.inner() == 0 {
    self.tickValue = self.tickPeriod
    self.stepShifter()
  } else {
    self.tickValue = self.tickValue - (1 |> to_u8)
  }
}

///|
fn DMC::stepReader(self : DMC) -> Unit {
  let cpu = self.cpu.unwrap()
  if self.currentLength.inner() > 0 && self.bitCount.inner() == 0 {
    cpu.stall = cpu.stall + 4
    self.shiftRegister = cpu.mem[self.currentAddress]
    self.bitCount = 8 |> to_u8
    self.currentAddress = self.currentAddress + (1 |> to_u16)
    if self.currentAddress.inner() == 0 {
      self.currentAddress = 0x8000 |> to_u16
    }
    self.currentLength = self.currentLength - (1 |> to_u16)
    if self.currentLength.inner() == 0 && self.loop_ {
      self.restart()
    }
  }
}

///|
fn DMC::stepShifter(self : DMC) -> Unit {
  if self.bitCount.inner() == 0 {
    return
  }
  if (self.shiftRegister.inner() & 1) == 1 {
    if self.value.inner() <= 125 {
      self.value = self.value + (2 |> to_u8)
    }
  } else if self.value.inner() >= 2 {
    self.value = self.value - (2 |> to_u8)
  }
  self.shiftRegister = self.shiftRegister >> 1
  self.bitCount = self.bitCount - (1 |> to_u8)
}

///|
fn DMC::output(self : DMC) -> UInt8 {
  return self.value
}

///|
fn init {
  for i = 0; i < 31; i = i + 1 {
    pulseTable[i] = 95.52 / (8128.0 / i.to_double() + 100.0)
  }
  for i = 0; i < 203; i = i + 1 {
    tndTable[i] = 163.67 / (24329.0 / i.to_double() + 100.0)
  }
}
