import gleam/result
import sqlight.{type Connection}

pub fn with_connection(
  uri: String,
  run: fn(Connection) -> Result(a, String),
) -> Result(a, String) {
  use conn <- result.try(
    sqlight.open(uri) |> result.map_error(fn(_) { "Database unavailable" }),
  )
  with_open_connection(conn, fn() {
    use _ <- result.try(
      sqlight.exec("PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000", conn)
      |> result.map_error(fn(_) { "Database configuration failed" }),
    )
    run(conn)
  })
}

@external(erlang, "rebstock_mcp_db_ffi", "with_open_connection")
fn with_open_connection(
  conn: Connection,
  run: fn() -> Result(a, String),
) -> Result(a, String)

@external(erlang, "rebstock_mcp_db_ffi", "transaction")
pub fn transaction(
  conn: Connection,
  run: fn() -> Result(a, String),
) -> Result(a, String)
