# PostgreSQL cheatsheet (Termux)

> **This device:** PostgreSQL (runit service) · superuser = **your Termux username** (`u0_a365`)
> · data dir `$PREFIX/var/lib/postgresql` · auth `trust` locally (no password asked)
> · your password is saved in `~/.pgpass_initial`.

---

## Table of contents

| # | Section | What it answers |
|---|---|---|
| 1 | [Connect](#1-connect) | How do I get into psql / a GUI app / Python? |
| 2 | [Quick reference](#2-quick-reference) | One-liners for the 20 most common tasks |
| 3 | [psql meta-commands](#3-psql-meta-commands) | `\d` `\l` `\dt` `\x` `\copy` … |
| 4 | [Databases](#4-databases) | create / rename / drop databases |
| 5 | [Tables & DDL](#5-tables--ddl) | create / alter / drop tables, constraints |
| 6 | [Data (DML)](#6-data-dml) | insert / update / delete / upsert / copy |
| 7 | [Queries](#7-queries) | select / join / group / window / CTE / JSON |
| 8 | [Indexes](#8-indexes) | create / drop / explain |
| 9 | [Users, roles & privileges](#9-users-roles--privileges) | create user / grant / change password |
| 10 | [Inspect schema & data](#10-inspect-schema--data) | "what's in this DB?" — tables, columns, constraints, FKs |
| 11 | [Forgot my password?](#11-forgot-my-password) | find it, or reset it |
| 12 | [Transactions & locking](#12-transactions--locking) | begin / commit / rollback / locks |
| 13 | [Backup & restore](#13-backup--restore) | pg_dump / pg_restore / restore into fresh DB |
| 14 | [Maintenance](#14-maintenance) | vacuum / analyze / reindex / reload |
| 15 | [Admin queries](#15-admin-queries) | sizes, connections, current user |
| 16 | [Service management](#16-service-management) | start / stop / autostart postgres |
| 17 | [Troubleshooting](#17-troubleshooting) | connection refused, role does not exist, … |

---

## 1. Connect

```sh
psql -d postgres                                   # socket, as your Termux user
psql -h 127.0.0.1 -p 5432 -U u0_a365 -d postgres   # TCP (what GUI apps use)
psql "postgresql://u0_a365@127.0.0.1:5432/postgres" # URI form
```

GUI apps (Selectable, PG Orbit, DBeaver): `Host 127.0.0.1 · Port 5432 · User u0_a365 · DB postgres`.

Python / SQLAlchemy:

```python
from sqlalchemy import create_engine
engine = create_engine("postgresql+psycopg2://u0_a365:PASSWORD@127.0.0.1:5432/postgres")
```

## 2. Quick reference

| Task | One-liner |
|---|---|
| Connect | `psql -d postgres` |
| List databases | `psql -d postgres -c "\l"` |
| List tables in current DB | `psql -d mydb -c "\dt"` |
| Describe a table | `psql -d mydb -c "\d users"` |
| Create a database | `createdb mydb` |
| Drop a database | `dropdb mydb` |
| List roles | `psql -d postgres -c "\du"` |
| Change my password | `psql -d postgres -c "ALTER USER $USER WITH PASSWORD 'new';"` |
| Read my saved password | `cut -d= -f2- ~/.pgpass_initial` |
| Backup one DB | `pg_dump mydb > mydb.sql` |
| Restore one DB | `psql -d postgres -f mydb.sql` |
| Schema of whole DB | `psql -d mydb -c "\d+ *.*"` (or §10) |
| Start / stop postgres | `sv up postgres` / `sv down postgres` |
| Check status | `sv status postgres` |

## 3. psql meta-commands

| Command | Meaning |
|---|---|
| `\l` / `\l+` | list databases (sizes) |
| `\c dbname` | connect to another database |
| `\dn` | list schemas |
| `\dt` / `\dt *.*` | list tables (all schemas) |
| `\di` | list indexes |
| `\du` | list roles/users |
| `\dp` | table privileges |
| `\d t` / `\d+ t` | describe table (detail) |
| `\df` | list functions |
| `\dv` / `\dm` | views / materialized views |
| `\x` | toggle expanded (vertical) output |
| `\timing` | toggle per-query timing |
| `\conninfo` | show current connection |
| `\i file.sql` | run SQL from a file |
| `\copy t TO 'f.csv' CSV HEADER` | export table to CSV |
| `\copy t FROM 'f.csv' CSV HEADER` | import CSV into table |
| `\o out.txt` | write query output to file (`\o` alone stops) |
| `\password` | set password for current user |
| `\q` | quit |

## 4. Databases

```sql
CREATE DATABASE mydb;
CREATE DATABASE mydb OWNER u0_a365 ENCODING 'UTF8';
ALTER DATABASE mydb RENAME TO mydb2;
DROP DATABASE mydb;              -- must have no active connections
```

CLI: `createdb mydb` · `dropdb mydb`

## 5. Tables & DDL

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

## 6. Data (DML)

```sql
INSERT INTO users (email, name) VALUES ('a@x.com', 'Ann') RETURNING id;
INSERT INTO users (email) VALUES ('b@x.com') ON CONFLICT (email) DO NOTHING;
INSERT INTO users (email, name) VALUES ('c@x.com', 'Cy')
    ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name;   -- upsert

UPDATE users SET age = 30 WHERE email = 'a@x.com' RETURNING id;
DELETE FROM users WHERE id = 3 RETURNING *;

\copy users (email, name) FROM 'users.csv' CSV HEADER;        -- bulk load
```

## 7. Queries

```sql
SELECT * FROM users WHERE age BETWEEN 18 AND 65
ORDER BY created_at DESC LIMIT 10;

SELECT o.id, u.email, o.total
FROM orders o JOIN users u ON u.id = o.user_id
WHERE o.status = 'pending';

SELECT status, count(*), sum(total)
FROM orders GROUP BY status HAVING count(*) > 1;

SELECT email, row_number() OVER (ORDER BY created_at) AS rn,
       avg(age) OVER () AS global_avg
FROM users;

WITH old AS (SELECT * FROM users WHERE created_at < now() - interval '1 year')
SELECT count(*) FROM old;

SELECT now(), now()::date, '5'::int, '2026-01-01'::date, interval '30 minutes';
SELECT '{"a":1}'::jsonb -> 'a';
```

## 8. Indexes

```sql
CREATE INDEX idx_users_email ON users (email);
CREATE UNIQUE INDEX ON users (email, name);
CREATE INDEX idx_users_lower ON users (lower(email));                       -- expression
CREATE INDEX idx_orders_partial ON orders (status) WHERE status='pending';  -- partial
CREATE INDEX idx_users_fts ON users USING gin (to_tsvector('english', name)); -- full-text

DROP INDEX idx_users_email;
REINDEX TABLE users;
ANALYZE users;

EXPLAIN SELECT * FROM users WHERE email = 'a@x.com';   -- plan
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM users;        -- plan + real timings
```

Types: `btree` (default: =, <, >, ordering) · `gin`/`gist` (arrays, JSON, full-text)
· `hash` (equality only) · `brin` (huge tables).

## 9. Users, roles & privileges

```sql
CREATE ROLE app WITH LOGIN PASSWORD 'secret';
CREATE USER app2 WITH PASSWORD 'secret';                 -- LOGIN + NOLOGIN flag
ALTER ROLE u0_a365 WITH PASSWORD 'newpass';              -- change password
ALTER ROLE app WITH SUPERUSER;  /  WITH NOSUPERUSER;
DROP ROLE app;

GRANT CONNECT ON DATABASE mydb TO app;
GRANT USAGE ON SCHEMA public TO app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO app;
GRANT SELECT ON users TO app;
REVOKE DELETE ON users FROM app;
```

## 10. Inspect schema & data

> "What tables exist?" → `\dt` · "describe one table" → `\d users` · "entire schema as SQL" → `\d+ *.*` · "everything in SQL text" → `pg_dump --schema-only`

```sql
-- all tables (+ sizes, owner, comment)
SELECT schemaname, tablename, tableowner
FROM pg_tables WHERE schemaname = 'public';

-- all columns of one table
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'users' ORDER BY ordinal_position;

-- primary keys
SELECT tc.table_name, kcu.column_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
WHERE tc.constraint_type = 'PRIMARY KEY' AND tc.table_name = 'users';

-- foreign keys (table -> referenced table)
SELECT conrelid::regclass AS "table",
       a.attname AS column,
       confrelid::regclass AS "references"
FROM pg_constraint c
JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
WHERE c.contype = 'f' AND conrelid::regclass = 'orders'::regclass;

-- indexes on a table
SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'users';

-- all views / functions
SELECT viewname FROM pg_views WHERE schemaname = 'public';
SELECT proname FROM pg_proc WHERE pronamespace = 'public'::regnamespace;

-- counts
SELECT (SELECT count(*) FROM users) AS users, (SELECT count(*) FROM orders) AS orders;
```

## 11. Forgot my password?

Your password is stored at `~/.pgpass_initial` as `PG_PASS=…`. **Read it:**

```sh
cat ~/.pgpass_initial                    # whole line:  PG_PASS=…
cut -d= -f2- ~/.pgpass_initial           # just the password value
```

**Reset it** (local `trust` auth means you never need the old one — you can always
do this):

```sh
psql -d postgres -c "ALTER USER $USER WITH PASSWORD 'newpass';"
echo "PG_PASS=newpass" > ~/.pgpass_initial
```

> The current password is **not** printed in this cheatsheet on purpose — read it
> with the commands above.

## 12. Transactions & locking

```sql
BEGIN;
INSERT INTO orders VALUES (1, 1, 9.99);
SAVEPOINT sp;
UPDATE orders SET total = 0 WHERE id = 1;
ROLLBACK TO sp;                 -- undo back to savepoint, keep the rest
COMMIT;                         -- or ROLLBACK;

SHOW transaction_isolation;              -- default: read committed
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT * FROM users FOR UPDATE;          -- lock rows
SELECT pg_backend_pid();                 -- my connection id
```

## 13. Backup & restore

```sh
pg_dump mydb > mydb.sql                       # plain SQL (schema + data)
pg_dump mydb -Fc > mydb.dump                  # compressed custom format
pg_dumpall > all.sql                          # whole cluster (roles + DBs)
pg_dump --schema-only mydb > mydb_schema.sql  # schema only

psql -d postgres -f mydb.sql                  # restore plain SQL
pg_restore -d mydb mydb.dump                  # restore custom format

createdb newdb && pg_restore -d newdb mydb.dump   # restore into a fresh DB
pg_restore --list mydb.dump | head                 # inspect before restore
```

## 14. Maintenance

```sql
VACUUM mydb;         -- reclaim space (cheap)
VACUUM FULL mydb;    -- heavy, locks table
ANALYZE mydb;        -- update planner stats
REINDEX TABLE mydb;  -- rebuild indexes
```

```sh
pg_ctl reload -D $PREFIX/var/lib/postgresql   # apply config changes without restart
pg_ctl -D $PREFIX/var/lib/postgresql -l pg.log start
pg_ctl stop -D $PREFIX/var/lib/postgresql
```

## 15. Admin queries

```sql
SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database;
SELECT current_user, current_database(), version();
SELECT pg_size_pretty(pg_total_relation_size('users'));      -- table + indexes
SELECT usename, application_name, client_addr, state,
       now() - query_start AS running_for
FROM pg_stat_activity WHERE state = 'active';                -- running queries
SELECT pid, pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'active';
```

## 16. Service management

```sh
export SVDIR=$PREFIX/var/service        # needed in non-interactive shells
sv status postgres    # "run: postgres: (pid …) normally up"
sv up postgres        # start
sv down postgres      # stop
sv-enable postgres    # autostart on Termux launch (already done)
sv-disable postgres   # disable autostart
```

## 17. Troubleshooting

| Problem | Fix |
|---|---|
| `connection refused` / port closed | `sv status postgres`; if down → `sv up postgres` |
| `role "root" does not exist` | No `root` role — use your Termux username `u0_a365` |
| `database "u0_a365" does not exist` | `psql` without `-d` opens a DB named like the user → `psql -d postgres` or `createdb u0_a365` |
| GUI app won't connect | `127.0.0.1:5432`, user `u0_a365`, db `postgres` |
| `password authentication failed` | Locally auth is `trust` (no password needed); check `pg_hba.conf` for TCP hosts |
| config change not applied | `pg_ctl reload -D $PREFIX/var/lib/postgresql` |
| lost the password | §11 — read `~/.pgpass_initial`, or reset with `ALTER USER … WITH PASSWORD` |

---

*See also: `~/termux_setup/jupyter-cheatsheet.md` (SQL from notebooks) and
`~/termux_setup/marimo-cheatsheet.md` (SQLAlchemy usage).*
