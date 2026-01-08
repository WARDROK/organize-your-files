# Documentation - clean_files.sh

## Overview

`clean_files.sh` is a Bash script for scanning one or more directory trees and performing cleanup / organization tasks:

- remove duplicate files by content (keep the **oldest**)
- remove empty files
- remove temporary files (by regex from config)
- remove files with the same name (keep the **newest**)
- normalize permissions (chmod to a configured value)
- rename files containing “tricky” characters
- copy/move files into a destination catalog (with conflict handling)
- interactively rename files inside their current directory

The script reads configuration from `./.clean_files` (the same directory where you run the script).

## Requirements

- Tools available in typical Linux environment:
  `bash`, `find`, `stat`, `md5sum`, `grep`, `sed`, `chmod`, `cp`, `mv`, `rm`, `realpath`
- Config file: `./.clean_files`

## Configuration file: `./.clean_files`

Example:

```bash
SUGGESTED_ACCESS='644'
TRICKY_LETTERS=']:".;#*?$'\''|\<>&![{}'
TRICKY_LETTER_SUBSTITUTE='_'
TMP_FILES='.*(\.tmp|.temp|~)'
```

### About `TRICKY_LETTERS`

- `TRICKY_LETTERS` is used inside a regex character class like: `[...]`
- If you want to include the `]` character, it **must be the first character** in `TRICKY_LETTERS`.
  
  Example:

  ```bash
  TRICKY_LETTERS=']:;.'
  ```

  If `]` is not first, the regex can break (because `]` normally closes the character class).

## Usage

```bash
./clean_files.sh [CATALOGS_PATHS]... [OPTIONS]...
```

- `CATALOGS_PATHS` are directories that will be scanned recursively.
- You must provide at least one catalog path, otherwise the script prints “wrong usage”.

## Options

- `-h, --help` – show help and exit
- `-x, --catalog PATH` – destination catalog (used by `--copy` and `--move`, default: `./X`)
- `--default` – automatic mode for: duplicates/empty/temporary/same-name/access/tricky
- `-d, --duplicates` – remove duplicate files by content (keep the **oldest**)
- `-e, --empty` – remove empty files
- `-t, --temporary` – remove temporary files matched by `TMP_FILES`
- `-s, --same-name` – remove files with the same basename (keep the **newest**)
- `-a, --access` – set permissions to `SUGGESTED_ACCESS`
- `-k, --tricky` – rename files by replacing `TRICKY_LETTERS` with `TRICKY_LETTER_SUBSTITUTE` (keeps extension)
- `-c, --copy` – copy files into `--catalog` preserving relative paths (conflicts resolved by mtime suggestion)
- `-m, --move` – move files into `--catalog` preserving relative paths (conflicts resolved by mtime suggestion)
- `-r, --rename` – interactive rename of each file (renames only in the same directory, does not move)

## Examples

### Help

```bash
./clean_files.sh --help
```

### Remove duplicates (interactive)

```bash
./clean_files.sh ./X ./Y1 ./Y2 -d
```

### Remove duplicates (automatic)

```bash
./clean_files.sh ./X ./Y1 ./Y2 -d --default
```

### Remove empty files

```bash
./clean_files.sh ./X ./Y1 -e
```

### Remove temporary files (by TMP_FILES regex)

```bash
./clean_files.sh ./X ./Y1 ./Y2 -t
```

### Remove same-name files (keep newest)

```bash
./clean_files.sh ./X ./Y1 ./Y2 -s
```

### Normalize permissions to SUGGESTED_ACCESS

```bash
./clean_files.sh ./X ./Y1 -a
```

### Rename “tricky” filenames

```bash
./clean_files.sh ./X ./Y1 ./Y2 -k
```

### Copy into destination catalog

```bash
./clean_files.sh ./Y1 ./Y2 --catalog ./X -c
```

### Move into destination catalog

```bash
./clean_files.sh ./Y1 ./Y2 --catalog ./X -m
```

### Interactive rename (no moving, same directory only)

```bash
./clean_files.sh ./Y1 -r
```

### Multiple operations

- You can combine multiple operations in one run:

```bash
./clean_files.sh ./X ./Y1 ./Y2 -c ./X -e -t -a -c --default
```

## Author

Łukasz Szydlik - <https://www.linkedin.com/in/%C5%82ukasz-szydlik-2a783131a/>
