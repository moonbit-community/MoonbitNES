# MoonbitNES: NES emulator and playground in Moonbit

This projects started as a personal experiment for the Moonbit language in Oct. 2023 and luckily became a showcase in IDEA conference in Nov. 2023.

Based on Dennis Felsing's Exellent [nimes](https://github.com/def-/nimes), which itself is based on fogleman's excellent [NES emulator in
Go](https://github.com/fogleman/nes).

Compared to the nim/go versions, this version implements enough [unofficial opcodes](https://www.nesdev.org/wiki/CPU_unofficial_opcodes) to pass the `nestest` suggested in [nesdev wiki](https://www.nesdev.org/wiki/Emulator_tests).

This version is very different (changed ~800 lines) from the original version because Moonbit has evolved a loooot since then. At that time, there was no `for` loops, no pipes, and we can define methods for built-in types etc.

We make it open-source to encourage people mess with it. PRs are welcome!

## Usage

To build the project, one will need

```bash
moon build --target wasm-gc # for the wasm-gc backend
# or
moon build --target js # for the js backend
```

To run the project, one will need

```bash
python3 -m http.server 8080 # or other ways to start a static server
```

Notice that the wasm-gc backend uses GC proposal of WebAssembly, thus requiring Chrome 119 and later, Firefox 120 and later. One may check if it's available with [feature extensions](https://webassembly.org/features/). One may configure the backend at the beginning of `main.mjs`.

## Known issues & future work:

* Refactor to more idiomatic moonbit (remember that most codes are written in Oct. 2023 and they're better described as *ported* than *written*!)
* Fix broken audio for some games (e.g. Kage, Batman)
* More mappers beyond 0,1,2,3,4,7
* Cycle-accurate CPU emulation
* Debugger GUI (the current instruction formatter is already close to Mesen2's trace logger)

## Contributors

* [Rujia Liu](https://github.com/rujialiu)
* [hackwaly](https://github.com/hackwaly)
* [peter-jerry-ye](https://github.com/peter-jerry-ye)

## Thanks

* [Bob Zhang](https://github.com/bobzhang)
* [Yu Zhang](https://github.com/Yu-zh)
* The rest of moonbit community not mentioned above.
