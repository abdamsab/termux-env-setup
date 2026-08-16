# PostgreSQL cheatsheet (Termux)

PostgreSQL running on this device (Termux) as a runit service. The superuser is
your **Termux OS username** (here `u0_a365`) — there is no separate `postgres`
or `root` role. Your initial password lives in `~/.pgpass_initial` (`PG_PASS=…`).

Server facts:

- Socket: `$PREFIX/tmp/.s.PGSQL.5432` · TCP: `127.0.0.1:5432`
- Data dir: `$PREFIX/var/lib/postgresql`
- Auth: `trust` for local connections (initdb default), so no password is asked
  locally. GUI apps connect over TCP even with a wrong password.
- Config: `$PREFIX/var/lib/postgresql/postgresql.conf` and `pg_hba.conf`

---

## Connect

```sh
psql -d postgres              # local socket as your Termux user (no password)
psql -U u0_a365 -d postgres   # explicit user
psql -h 127.0.0.1 -p 5432 -U u0_a365 -d postgres     # TCP (GUI apps use this)
PGPASSWORD="$(cut -d= -f2- ~/.pgpass_initial)" \
  psql -h 127.0.0.1 -U u0_a365 -d postgres           # with password from file
```

GUI app (Selectable, PG Orbit, DBeaver, SQLite-compatible clients…):

```
Host: 127.0.0.1   Port: 5432   User: u0_a365
Password: <from ~/.pgpass_initial>   Database: postgres
```

Python / SQLAlchemy:

```python
from sqlalchemy import create_engine, text
engine = create_engine(
    "postgresql+psycopg2://u0_a365:PASSWORD@127.0.0.1:5432/postgres"
)
with engine.connect() as c:
    print(c.execute(text("select version()")).scalar())
```

---

## psql meta-commands (inside `psql`)

| Command | Meaning |
|---|---|
| `\l` / `\l+` | list databases (with sizes) |
| `\c dbname` | connect to another database |
| `\dn` | list schemas |
| `\dt` / `\dt *.*` | list tables (all schemas) |
| `\di` | list indexes |
| `\du` | list roles/users |
| `\dp` | table privileges |
| `\d tablename` | describe table/columns/indexes/constraints |
| `\d+ tablename` | detailed description (+ storage/sizes) |
| `\df` / `\df function` | list/describe functions |
| `\dv` / `\dm` | views / materialized views |
| `\x` | toggle expanded (vertical) output |
| `\timing` | toggle per-query timing |
| `\conninfo` | show current connection |
| `\encoding` | show client encoding (default UTF8) |
| `\i file.sql` | run SQL from a file |
| `\copy table TO/FROM 'file.csv' CSV HEADER` | client-side COPY |
| `\o file.txt` | write query output to a file (`\o` alone stops) |
| `\password [user]` | set/change password |
| `\q` | quit |

---

## Databases

```sql
CREATE DATABASE mydb;
CREATE DATABASE mydb OWNER u0_a365 ENCODING 'UTF8';
ALTER DATABASE mydb RENAME TO mydb2;
DROP DATABASE mydb;                       -- needs no active connections
```

```sh
createdb mydb          # create (CLI)
dropdb mydb            # drop (CLI)
```

## Tables & DDL

```sql
CREATE TABLE users (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email      text NOT NULL UNIQUE,
    name       text,
    age        int CHECK (age >= 0),
    created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE users ADD COLUMN phone text;
ALTER TABLE users ALTER COLUMN name SET NOT NULL;
ALTER TABLE users DROP COLUMN phone;
ALTER TABLE users RENAME TO people;
DROP TABLE IF EXISTS people;

CREATE TABLE orders (
    id      bigint PRIMARY KEY,
    user_id bigint REFERENCES users(id) ON DELETE CASCADE,
    total   numeric(10,2) NOT NULL,
    status  text DEFAULT 'pending'
);
```

## Data (DML)

```sql
INSERT INTO users (email, name) VALUES ('a@x.com', 'Ann') RETURNING id;
INSERT INTO users (email) VALUES ('b@x.com') ON CONFLICT (email) DO NOTHING;
INSERT INTO users (email, name) VALUES ('c@x.com', 'Cy')
    ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name;

UPDATE users SET age = 30 WHERE email = 'a@x.com' RETURNING id;
DELETE FROM users WHERE id = 3 RETURNING *;

-- bulk load from CSV
\copy users (email, name) FROM 'users.csv' CSV HEADER;
```

## Queries

```sql
SELECT * FROM users WHERE age BETWEEN 18 AND 65 ORDER BY created_at DESC LIMIT 10;

-- joins
SELECT o.id, u.email, o.total
FROM orders o JOIN users u ON u.id = o.user_id
WHERE o.status = 'pending';

-- aggregate
SELECT status, count(*), sum(total) FROM orders GROUP BY status HAVING count(*) > 1;

-- window functions
SELECT email, age,
       row_number() OVER (ORDER BY created_at) AS rn,
       avg(age) OVER () AS global_avg
FROM users;

-- CTE
WITH old AS (SELECT * FROM users WHERE created_at < now() - interval '1 year')
SELECT count(*) FROM old;

-- common types / casts
SELECT now(), now()::date, '5'::int, '2026-01-01'::date, interval '30 minutes';
SELECT '{"a":1}'::jsonb -> 'a';                       -- JSON operators
```

## Indexes

```sql
CREATE INDEX idx_users_email ON users (email);
CREATE UNIQUE INDEX ON users (email, name);
CREATE INDEX idx_orders_user ON orders (user_id);
CREATE INDEX idx_users_lower ON users (lower(email));          -- expression index
CREATE INDEX idx_orders_status_partial ON orders (status) WHERE status = 'pending';  -- partial
CREATE INDEX idx_users_name_gin ON users USING gin (to_tsvector('english', name));   -- full-text

DROP INDEX idx_users_email;
REINDEX TABLE users;
ANALYZE users;                 -- refresh planner statistics

EXPLAIN SELECT * FROM users WHERE email = 'a@x.com';     -- query plan
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM users;          -- plan + timing
```

Index types: `btree` (default, for `=`/`<`/`>`/ordering), `gin`/`gist` (arrays,
JSON, full-text, ranges), `hash` (equality only), `brin` (huge sequential data).

## Roles, users & privileges

```sql
CREATE ROLE app WITH LOGIN PASSWORD 'secret';
CREATE USER app2 WITH PASSWORD 'secret';                -- same as LOGIN role
ALTER ROLE u0_a365 WITH PASSWORD 'newpass';
DROP ROLE app;

-- superuser vs normal
ALTER ROLE app WITH SUPERUSER;   /  ALTER ROLE app WITH NOSUPERUSER;

GRANT CONNECT ON DATABASE mydb TO app;
GRANT USAGE ON SCHEMA public TO app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO app;
GRANT SELECT ON users TO app;
REVOKE DELETE ON users FROM app;
```

`\du` lists roles; `\dp` shows grants. `trust` in `pg_hba.conf` means passwords
aren't checked on local connections — switch localhost lines to `scram-sha-256`
to enforce them, then `pg_ctl reload`.

## Transactions & locking

```sql
BEGIN;
INSERT INTO orders VALUES (1, 1, 9.99);
SAVEPOINT sp;
UPDATE orders SET total = 0 WHERE id = 1;
ROLLBACK TO sp;                    -- undo back to savepoint, keep the rest
COMMIT;                            -- or ROLLBACK;

SHOW transaction_isolation;        -- default: read committed
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT * FROM users FOR UPDATE;    -- lock rows
SELECT pg_backend_pid();           -- my connection / locks in pg_locks
```

## Backup & restore

```sh
# plain SQL dump (schema + data)
pg_dump mydb > mydb.sql
pg_dump -U u0_a365 -h 127.0.0.1 mydb -Fc > mydb.dump      # custom format

# whole cluster (roles + databases)
pg_dumpall > all.sql

# restore
psql -d postgres -f mydb.sql              # plain SQL
pg_restore -d mydb mydb.dump              # custom format
pg_restore --list mydb.dump | head        # inspect first

# restore into a fresh db
createdb mydb && pg_restore -d mydb mydb.dump
```

## Maintenance

```sql
VACUUM mydb;              -- reclaim space
VACUUM FULL mydb;         -- heavy, locks table
ANALYZE mydb;             -- update planner stats
REINDEX TABLE mydb;       -- rebuild indexes
```

```sh
pg_ctl -D $PREFIX/var/lib/postgresql -l pg.log start    # manual start (no runit)
pg_ctl reload -D $PREFIX/var/lib/postgresql             # apply config changes
pg_ctl stop -D $PREFIX/var/lib/postgresql
```

## Useful admin queries

```sql
SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database;
SELECT current_user, current_database(), version();
SELECT usename, application_name, client_addr, state, now()-query_start AS running_for
FROM pg_stat_activity WHERE state = 'active';            -- long-running queries
SELECT pg_size_pretty(pg_total_relation_size('users'));  -- table + indexes size
SELECT count(*) FROM pg_tables WHERE schemaname = 'public';
SELECT column_name, data_type FROM information_schema.columns
WHERE table_name = 'users';
```

## Service management (runit / termux-services)

```sh
export SVDIR=$PREFIX/var/service        # needed in non-interactive shells

sv status postgres    # "run: postgres: (pid …) normally up"
sv up postgres        # start
sv down postgres      # stop
sv-enable postgres    # autostart on Termux launch (already done)
sv-disable postgres   # disable autostart
```

## Troubleshooting

| Problem | Fix |
|---|---|
| `connection refused` / port closed | `sv status postgres`; if down: `sv up postgres` |
| `role "root" does not exist` | Use your Termux username `u0_a365` — there is no `root` role |
| `database "u0_a365" does not exist` | `psql` without `-d` opens a DB named like the user; use `psql -d postgres` or `createdb u0_a365` |
| GUI app won't connect | Use `127.0.0.1:5432`, user `u0_a365`, db `postgres` (trust auth ignores wrong passwords) |
| `password authentication failed` | Check `pg_hba.conf` auth method; locally it's `trust`, not `scram-sha-256` |
| config change not applied | `pg_ctl reload -D $PREFIX/var/lib/postgresql` |
| lost the password | Local `trust` auth needs none; update it anyway: `ALTER ROLE u0_a365 WITH PASSWORD 'new';` + refresh `~/.pgpass_initial` |

---

*See also: `~/termux_setup/jupyter-cheatsheet.md` (SQL from notebooks) and
`~/termux_setup/marimo-cheatsheet.md` (SQLAlchemy usage).*
