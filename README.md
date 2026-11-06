# eider-postgres

A PostgreSQL client written in Eider (package `postgres`). Wire protocol v3 over `std/net`, no C library.

```eider
import postgres
import postgres.client
import postgres.codec
import std.time

fn main() uses net, io, clock, fs {
    var cfg = postgres.config("127.0.0.1", "eider", "eiderdb")
    cfg.password = Some(String.from("secret"))
    let dl = time.after_ms(5000)
    let mut c = client.connect(cfg, dl).unwrap()
    let rs = c.query("SELECT $1::int8 + 1 AS n", List[postgres.Int(41)], dl).unwrap()
    print(codec.value(rs, 0, 0).unwrap())
    c.close()
}
```

What it does: cleartext, MD5 and SCRAM-SHA-256 authentication; simple and extended queries with a statement
cache; text and binary results; typed errors with all fields; transactions and savepoints; COPY; cancel and
deadlines; LISTEN/NOTIFY; a connection pool (`postgres.pool`); typed queries from records (`postgres.typed`);
TLS through eider-tls (`postgres.secure`, `sslmode=require` or `verify-full`). See docs/postgres.md.

Limits: no Kerberos/GSS/SSPI; passwords are not SASLprep'd; results are read whole (bounded by
`max_result_bytes`); arrays decode from text form only; interval, time, inet and similar come back as `Raw`.
Use it as a git dependency (`[deps.postgres]`, `git = "https://github.com/klxdev/eider-postgres.git"`) together with
`[deps.crypto]` set to `toolchain = true` (crypto comes with Eider 0.7.6 and later; eider-tls is fetched from its
repository). An installed toolchain is enough to build and test it; `ASAN=1 sh scripts/test.sh` needs an eider-lang
checkout (it builds the crypto backend sanitized).

Scripts: `scripts/test.sh` (codec and hostile-server tests always; server tests when podman and a postgres
image are present; `PG_VERSIONS="16 17 18"`), `scripts/bench.sh`, `scripts/pg-up.sh`, `scripts/pg-down.sh`.
