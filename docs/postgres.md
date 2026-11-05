# postgres

Modules: `postgres` (Config, Value, Rows, Error, `parse_url`), `postgres.client` (Conn, `connect`, `query`,
`exec`, `simple`, `transaction`, `cancel`), `postgres.codec` (`codec.value(rows, row, col)`), `postgres.pool`,
`postgres.typed`, `postgres.secure` (TLS upgrade).

Connect with `postgres.config(host, user, db)` or
`postgres.parse_url("postgres://u:p@h:5432/db?sslmode=verify-full")`. Every call takes a `time.Deadline`; when
it passes, the client sends a CancelRequest on a second socket and drains the connection, so it stays usable.

Parameters are `postgres.Value`s sent as text with type oid 0 (bytea in binary), so the server infers types.
Fixed-size results arrive in binary, the rest as text; `codec.value` decodes both to `Value`.

Transactions: `client.transaction(c, dl, |tx| ...)` commits on Ok and rolls back on Err or trap. Savepoints
are on Conn. Errors are `postgres.Error` with `kind`, `sqlstate`, `message` and the other fields.

Pool: `pool.new(cfg, pool.pool_config(), dl)`; `pool.with`, `pool.query`, `pool.exec`; min/max, idle timeout,
lifetime, health check on checkout, FIFO fairness; safe across tasks.

Typed: `@[derive(Deserialize)] type Item = {...}`, then `typed.query[Item](c, sql, params, dl)`;
`typed.query_with` takes a Serialize record as parameters. Column and field mismatches are errors.

Performance (PostgreSQL 17 in podman, loopback): about 21k simple round trips/s, 20k with a parameter,
17k autocommit INSERTs/s, 1.7M rows/s fetched, 1.0M rows/s decoded into records, 37k queries/s through a
pool of 4 from 16 tasks.
