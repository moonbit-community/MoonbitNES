///|
pub extern "wasm" fn malloc(size : Int32) -> Int32 =
  #|(func (param i32) (result i32) local.get 0 call $moonbit.malloc)

///|
pub extern "wasm" fn free(position : Int32) =
  #|(func (param i32) local.get 0 call $moonbit.decref)

///|
let offset : Ref[Int32] = { val: 0, }

///|
pub fn set_offset(i : Int32) -> Unit {
  offset.val = i
}
