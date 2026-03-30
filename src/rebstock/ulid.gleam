import gleam/crypto
import gleam/string

const crockford = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

@external(erlang, "rebstock_ffi", "timestamp_ms")
fn timestamp_ms() -> Int

pub fn generate() -> String {
  let ts = timestamp_ms()
  let random = crypto.strong_random_bytes(10)
  let rand_int = case random {
    <<n:size(80)>> -> n
    _ -> 0
  }
  encode_int(ts, 10, "") <> encode_int(rand_int, 16, "")
}

fn encode_int(value: Int, remaining: Int, acc: String) -> String {
  case remaining {
    0 -> acc
    _ -> {
      let char = string.slice(crockford, value % 32, 1)
      encode_int(value / 32, remaining - 1, char <> acc)
    }
  }
}
