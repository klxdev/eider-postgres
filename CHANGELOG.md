# Changelog

eider-postgres's versions (semver). Before 1.0 the MAJOR.MINOR is the Eider toolchain's it goes
with (`eider` in eider.toml), the PATCH its own.

## 0.7.2

- Consumable through git (eider-lang#222): crypto is the toolchain's own package (`[deps.crypto] toolchain = true`,
  Eider 0.7.6 and later) and eider-tls a git dependency, instead of path dependencies on links into `target/deps`.
  `scripts/env.sh` no longer makes those links (it takes eider-tls from `../eider-tls` or `$EIDER_TLS` through
  `EIDER_PKG_OVERRIDE`, like the other git dependencies). With an installed toolchain alone, `scripts/build.sh` and
  `scripts/test.sh` work. The `[deps.tls]` minimum must be raised to the eider-tls release that has the toolchain
  dependency (its 0.7.1 does not), and this release requires Eider 0.7.6.

## 0.7.1

- Use `let mut` instead of the removed `var` (eider-lang#2).

## 0.7.0

First version, for Eider 0.7: a PostgreSQL client in Eider. Protocol v3 with cleartext, MD5 and
SCRAM-SHA-256 authentication; simple and extended queries with a prepared-statement cache; text and binary
result formats for the common types; typed errors carrying every ErrorResponse field; transactions,
savepoints and `transaction(|tx| ...)`, which rolls back on Err or trap; COPY in and out; cancellation and
deadlines (a timeout sends a CancelRequest and drains the connection); LISTEN/NOTIFY; a bounded connection
pool; typed queries from records through std/serial; TLS through eider-tls (sslmode require and verify-full)
in the separate `postgres.secure` module. Every server message is parsed strictly and never traps.
Tested against PostgreSQL 16, 17 and 18 in a podman container. Not done: Kerberos/GSS/SSPI, SASLprep of
non-ASCII passwords, streaming rows (results are held in memory, bounded by `max_result_bytes`), binary
arrays, interval/inet and other rarer types (returned as `Raw`); see the README.
