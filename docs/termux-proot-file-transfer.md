# Copying Files Between Termux and PRoot Ubuntu

## TL;DR

Use `proot-distro copy` (v5+) for the safest transfer. Fall back to `cp` for
quick one-offs. Use tar for large directories with symlinks.

```bash
# Best: built-in, symlink-safe, lock-aware
proot-distro copy ~/file.txt ubuntu:/root/
proot-distro copy ubuntu:/root/file.txt ~/

# Quick: direct cp against the rootfs
ROOTFS=$PREFIX/var/lib/proot-distro/containers/ubuntu/rootfs
cp ~/file.txt "$ROOTFS/root/"
cp "$ROOTFS/root/file.txt" ~/

# From inside proot, /sdcard is already mounted
tar -cf /sdcard/backup.tar -C ~/my_folder .
# Then from Termux:
cp /sdcard/backup.tar ~/extracted/
tar -xf /sdcard/backup.tar -C ~/extracted/
```

---

## How It Works

The PRoot Ubuntu rootfs lives inside Termux's private app storage. Termux owns
these files and can read/write them directly — no network, no server, no special
permissions needed.

The rootfs path (proot-distro v5.5.3+):

```
$PREFIX/var/lib/proot-distro/containers/ubuntu/rootfs/
```

Expanded:

```
/data/data/com.termux/files/usr/var/lib/proot-distro/containers/ubuntu/rootfs/
```

> WARNING: Older guides reference `installed-rootfs/` instead of
> `containers/`. That path is legacy. Proot-distro v5.x migrated to the
> `containers/<name>/rootfs` layout. Always check `ls $PREFIX/var/lib/`
> if the old path doesn't exist.

---

## Method 1: proot-distro copy (Recommended)

proot-distro v5+ ships a built-in `copy` command that is specifically designed
for this use case. It:

- Walks symlinks inside the rootfs with chroot semantics (prevents escape)
- Acquires container locks to prevent concurrent corruption
- Preserves metadata (timestamps, permissions, symlinks)
- Supports `--recursive` for directories and `--move` for mv semantics

### Syntax

```
proot-distro copy <source> <destination>
```

Either side can use the `container:path` spec. The bare `container:` prefix
means "path inside the container rootfs." Without a prefix, the path is on
the host (Termux) filesystem.

### Examples

```bash
# Single file: Termux -> Ubuntu
proot-distro copy ~/config.yaml ubuntu:/etc/myapp/

# Single file: Ubuntu -> Termux
proot-distro copy ubuntu:/var/log/syslog ~/logs/

# Directory: Termux -> Ubuntu
proot-distro copy -r ~/project ubuntu:/opt/project/

# Directory: Ubuntu -> Termux
proot-distro copy -r ubuntu:/var/lib/postgresql ~/backups/pg-data/

# Move instead of copy
proot-distro copy --move ~/archive.tar ubuntu:/tmp/

# Overwrite existing files (default behavior)
proot-distro copy -r --force ~/dotfiles ubuntu:/root/
```

### Container name

The container name is the distro name you installed. Default is `ubuntu`. If
you installed something else:

```bash
proot-distro list              # see installed distros and their names
proot-distro copy ~/file debian:/root/
```

---

## Method 2: Direct cp Against the Rootfs

For quick one-off transfers, you can cp directly against the rootfs directory.
This is what everyone used before `proot-distro copy` existed.

### Set up the variable

```bash
ROOTFS=$PREFIX/var/lib/proot-distro/containers/ubuntu/rootfs
```

Add to `.bashrc` for convenience:

```bash
alias proot-rootfs="$ROOTFS"
```

### Copy Termux -> Ubuntu

```bash
cp ~/file.txt "$ROOTFS/root/"
cp -p ~/config.conf "$ROOTFS/etc/myapp/"    # preserve timestamps/mode
```

### Copy Ubuntu -> Termux

```bash
cp "$ROOTFS/root/file.txt" ~/downloads/
cp -p "$ROOTFS/etc/nginx/nginx.conf" ~/backups/
```

### Copy a directory

```bash
cp -a ~/my_folder "$ROOTFS/opt/"            # preserves permissions, symlinks
```

> NOTE: `cp -a` preserves the Source ownership (Termux UID). From the host
> side, these files appear owned by the Termux user. From inside proot, they
> appear owned by root because proot remaps UIDs. This is normal and expected.

---

## Method 3: tar for Directories and Large Transfers

Use tar when the source or destination has symlinks, special permissions, or
many small files. tar handles these correctly; cp may silently dereference
symlinks or lose permission bits.

### Via /sdcard (available inside proot by default)

proot-distro automatically mounts Android shared storage. Both Termux and the
proot container can see `/sdcard`.

```bash
# Pack in proot, unpack in Termux
proot-distro login ubuntu -- tar -cf /sdcard/backup.tar -C /home/user/project .
tar -xf /sdcard/backup.tar -C ~/restored/

# Pack in Termux, unpack in proot
tar -cf /sdcard/backup.tar -C ~/project .
proot-distro login ubuntu -- tar -xf /sdcard/backup.tar -C /home/user/project/
```

### Via the rootfs directly

```bash
# Pack from Termux into the rootfs
tar -cf "$ROOTFS/tmp/backup.tar" -C ~/project .

# Unpack inside proot
proot-distro login ubuntu -- tar -xf /tmp/backup.tar -C /home/user/

# Or unpack from Termux directly
mkdir -p ~/restored
tar -xf "$ROOTFS/tmp/backup.tar" -C ~/restored/
```

### Compressed tar

```bash
tar -czf /sdcard/backup.tar.gz -C ~/project .
proot-distro login ubuntu -- tar -xzf /sdcard/backup.tar.gz -C /home/user/
```

---

## Method 4: Shared Bind Mounts (Permanent)

Instead of copying back and forth, bind-mount a directory so both environments
see the same path.

### Per-login (temporary)

```bash
proot-distro login --bind ~/shared-workspace:/workspace ubuntu
```

Now `/workspace` inside proot points to `~/shared-workspace` on Termux.

### Permanent via alias

Add to Termux's `~/.bashrc`:

```bash
alias ubuntu='proot-distro login --bind ~/shared-workspace:/workspace ubuntu'
```

### Multiple bind mounts

```bash
proot-distro login \
  --bind ~/shared-workspace:/workspace \
  --bind ~/projects:/home/ubuntu/projects \
  --bind ~/notes:/root/notes \
  ubuntu
```

### --shared-home flag

proot-distro has a built-in flag to share Termux's `$HOME` as `/root` inside
proot:

```bash
proot-distro login --shared-home ubuntu
```

This binds `$PREFIX/../home` (Termux home) to `/root` inside proot. Your
Termux dotfiles, scripts, and data are directly visible. This is the simplest
way to avoid copying altogether.

> NOTE: --shared-home and --bind are mutually exclusive for the same mount
> point. Don't combine them for overlapping paths.

---

## Common Pitfalls

### 1. File ownership displays differently

From Termux:

```
ls -la $ROOTFS/root/file.txt
# -rw-r--r-- u0_a365 u0_a365 1234 ... file.txt
```

From inside proot:

```
ls -la /root/file.txt
# -rw-r--r-- root root 1234 ... file.txt
```

This is normal. proot remaps UIDs. The underlying file is the same.

### 2. sudo is unnecessary inside proot

Everything inside proot runs as root (UID 0). You don't need sudo. If you
type `sudo`, it will either fail ("no new privileges") or do nothing useful.

### 3. Permissions are cosmetic, not enforced

proot doesn't have real root privileges on the kernel. File permissions inside
proot are enforced by proot's interception layer, not by the kernel's VFS.
This means:
- Permission errors inside proot are real (proot checks before acting)
- But SUID bits, capabilities, and chown don't actually work

### 4. Distro name varies

If you didn't install Ubuntu, replace `ubuntu` in all commands with your
distro name:

```bash
proot-distro list              # shows installed distros
proot-distro copy file debian:/root/   # example for Debian
```

### 5. Large files may hit storage limits

Termux's app storage has a quota. If the rootfs is large, check available
space:

```bash
df -h $PREFIX/var/lib/proot-distro/
du -sh $ROOTFS/
```

---

## Cheatsheet

```
╔══════════════════════════════════════════════════════════════════╗
║  TERMUX <-> PROOT FILE TRANSFER CHEATSHEET                      ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  ROOTFS PATH                                                     ║
║  $PREFIX/var/lib/proot-distro/containers/<distro>/rootfs         ║
║                                                                  ║
║  proot-distro copy (RECOMMENDED)                                 ║
║  ───────────────────────────────────────────────────────────     ║
║  proot-distro copy <src> <dst>        copy file/dir              ║
║  proot-distro copy -r <src> <dst>     recursive copy             ║
║  proot-distro copy --move <src> <mv>  move instead of copy       ║
║                                                                  ║
║  Container spec:  <distro>:<path>                                ║
║  No prefix: host (Termux) filesystem                             ║
║                                                                  ║
║  Examples:                                                       ║
║    proot-distro copy ~/file ubuntu:/root/                        ║
║    proot-distro copy -r ~/dir ubuntu:/opt/dir                    ║
║    proot-distro copy ubuntu:/etc/passwd ~/                       ║
║                                                                  ║
║  DIRECT CP (quick one-offs)                                      ║
║  ───────────────────────────────────────────────────────────     ║
║  R=$PREFIX/var/lib/proot-distro/containers/ubuntu/rootfs         ║
║                                                                  ║
║  cp file $R/root/                     Termux -> Ubuntu           ║
║  cp $R/root/file ~/                   Ubuntu -> Termux           ║
║  cp -p src dst                        preserve timestamps/mode   ║
║  cp -a dir $R/opt/                    recursive + symlinks       ║
║                                                                  ║
║  TAR (large dirs, symlinks, batch)                               ║
║  ───────────────────────────────────────────────────────────     ║
║  tar -cf /sdcard/bak.tar -C ~/dir .   pack (in Termux)           ║
║  proot login -- tar -xf /sdcard/bak.tar -C ~/   unpack (proot)   ║
║  tar -czf $R/tmp/bak.tar.gz -C ~/d . pack compressed             ║
║  mkdir out && tar -xf $R/tmp/bak.tar.gz -C out  unpack (host)   ║
║                                                                  ║
║  SHARED MOUNTS                                                   ║
║  ───────────────────────────────────────────────────────────     ║
║  proot-distro login --shared-home ubuntu    share $HOME          ║
║  proot login --bind ~/work:/workspace u     custom bind           ║
║  /sdcard already mounted by default (both sides see it)          ║
║                                                                  ║
║  LISTS & INFO                                                    ║
║  ───────────────────────────────────────────────────────────     ║
║  proot-distro list                  installed distros             ║
║  proot-distro info <distro>         rootfs path, distro details   ║
║                                                                  ║
║  GOTCHAS                                                         ║
║  ───────────────────────────────────────────────────────────     ║
║  - Ownership differs: Termux user on host, root inside proot      ║
║  - sudo is unnecessary inside proot (already root)               ║
║  - installed-rootfs/ is LEGACY; use containers/<name>/rootfs/    ║
║  - cp -a preserves Termux UID as owner (expected)                ║
║  - proot-distro copy is symlink-safe; raw cp is not              ║
╚══════════════════════════════════════════════════════════════════╝
```

---

## Quick Setup Alias

Add to Termux's `~/.bashrc`:

```bash
# Shortcuts for proot file operations
ROOTFS="$PREFIX/var/lib/proot-distro/containers/ubuntu/rootfs"
alias proot-rsync='rsync -av --progress'
alias proot-cp='proot-distro copy'
alias proot-bak='tar -cf /sdcard/proot-bak.tar -C $ROOTFS'
alias proot-res='cd ~ && tar -xf /sdcard/proot-bak.tar -C $ROOTFS'
```
