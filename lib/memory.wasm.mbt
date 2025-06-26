///|
pub extern "wasm" fn malloc(size : Int) -> Int =
  #|(func (param i32) (result i32) local.get 0 call $moonbit.malloc)

///|
pub extern "wasm" fn free(position : Int) =
  #|(func (param i32) local.get 0 call $moonbit.free)

///|
let offset : Ref[Int] = { val: 0 }

///|
pub fn set_offset(i : Int) -> Unit {
  offset.val = i
}
