# mpzig

mpzig is an implementation of [MessagePack](https://msgpack.org/) for Zig.


## Type conversion

### Serialization

source types  | output format
--------------|------------------------------------------------------
void          | nil
u8/u16/u32/u64| int(positive fixint, uint 8/16/32/64)
i8/i16/i32/i64| int(positive fixint, negative fixint, int 8/16/32/64)
bool          | bool
[]const u8    | str or bin
struct        | array or map

### Deserialization

source format                        | output type
-------------------------------------|------------
nil                                  | void
int(positive fixint, uint 8/16/32/64)| uint
int(negative fixint, int 8/16/32/64) | int
bool                                 | bool
str                                  | [] u8
bin                                  | [] u8
array                                | struct
map                                  | struct
