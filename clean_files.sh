#!/bin/bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

help() {
  cat <<EOF
Usage: $SCRIPT_NAME [CATALOGS_PATHS]... [OPTIONS]...

Options:
	-h, --help          Show this help message and exit
	-x, --catalog PATH	Specify the destination catalog path (default: ./X)
	    --default       Use default settings for operations
	-d, --duplicates    Remove duplicate files (files with same content)
	-e, --empty         Remove empty files
	-t, --temporary     Remove temporary files
	-s, --same-name     Remove files with same names
	-a, --access        Change access permissions to default
	-k, --tricky        Replace tricky letters in filenames with default
	-m, --move          Move files to a destination catalog
	-c, --copy          Copy files to a destination catalog
	-r, --rename        Rename files

Example:
    $SCRIPT_NAME ./X ./Y1 ./Y2 ./Y3 --catalog ./X --duplicates --empty --temporary --same-name --access --copy --tricky --default
EOF
  exit 0
}

wrong_usage() {
  echo "$SCRIPT_NAME: wrong usage" >&2
  echo "Try '$SCRIPT_NAME --help' for more information." >&2
  exit 1
}

#######################
# Operation functions #
#######################

op_duplicates() {
  # Remove duplicate files (same content) from input catalogs.
  # Use size grouping first to avoid hashing everything.
  # Use md5sum for content comparison.
  # In interactive mode, read user input from /dev/tty.
  # In default mode (--default), automatically delete duplicates, keeping the oldest.

  local all_files=()
  local input_catalog
  local file_path
  local file_index=0
  local file_size
  local file_hash hash_line
  local file_mtime
  local oldest_index oldest_mtime
  local keep_file_path
  local answer

  declare -A size_to_indexes=()

  # Collect all files from provided catalogs
  for input_catalog in "${CATALOGS[@]}"; do
    [[ -d "$input_catalog" ]] || continue
    while IFS= read -r -d '' file_path; do
      all_files+=("$file_path")
    done < <(find "$input_catalog" -type f -print0)
  done

  # If no files found, return
  (( ${#all_files[@]} > 0 )) || { echo "No files found."; return 0; }

  # Group file indexes by size
  for file_index in "${!all_files[@]}"; do
    file_size="$(stat -c %s -- "${all_files[$file_index]}" 2>/dev/null || echo -1)"
    [[ "$file_size" != "-1" ]] || continue
    size_to_indexes["$file_size"]+="$file_index "
  done

  # Process each size group with more than one file
  for file_size in "${!size_to_indexes[@]}"; do
    read -r -a size_group_indexes <<< "${size_to_indexes[$file_size]}"
    (( ${#size_group_indexes[@]} > 1 )) || continue

    # Group by md5 hash within this size group
    declare -A hash_to_indexes=()

    for file_index in "${size_group_indexes[@]}"; do
      file_path="${all_files[$file_index]}"

      # Compute hash; if failed (permission), skip file
      hash_line="$(md5sum -- "$file_path" 2>/dev/null || true)"
      [[ -n "$hash_line" ]] || continue
      file_hash="${hash_line%% *}"

      hash_to_indexes["$file_hash"]+="$file_index "
    done

    # For each hash group with more than one file, handle duplicates
    for file_hash in "${!hash_to_indexes[@]}"; do
      read -r -a duplicate_indexes <<< "${hash_to_indexes[$file_hash]}"
      (( ${#duplicate_indexes[@]} > 1 )) || continue

      # Find oldest file by mtime (smallest timestamp)
      oldest_index="${duplicate_indexes[0]}"
      oldest_mtime="$(stat -c %Y -- "${all_files[$oldest_index]}" 2>/dev/null || echo 9223372036854775807)"

      for file_index in "${duplicate_indexes[@]}"; do
        file_mtime="$(stat -c %Y -- "${all_files[$file_index]}" 2>/dev/null || echo 9223372036854775807)"
        if (( file_mtime < oldest_mtime )); then
          oldest_mtime="$file_mtime"
          oldest_index="$file_index"
        fi
      done

      keep_file_path="${all_files[$oldest_index]}"

      # Auto mode (--default): delete all but the oldest
      if [[ "$DEFAULT_OPTION" == "y" ]]; then
        for file_index in "${duplicate_indexes[@]}"; do
          [[ "$file_index" == "$oldest_index" ]] && continue
          rm -f -- "${all_files[$file_index]}"
          echo "DELETED DUPLICATE: ${all_files[$file_index]}"
        done
        echo "KEPT OLDEST: $keep_file_path"
        continue
      fi

      # Interactive: show set and ask once per duplicate set
      echo "DUPLICATES FOUND (same content):"
      echo "  Suggested keep oldest: $keep_file_path"
      for file_index in "${duplicate_indexes[@]}"; do
        [[ "$file_index" == "$oldest_index" ]] && continue
        echo "  Duplicate: ${all_files[$file_index]}"
      done

      printf "Delete duplicates and keep oldest? [y/N] " > /dev/tty
      IFS= read -r answer < /dev/tty
      if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
        for file_index in "${duplicate_indexes[@]}"; do
          [[ "$file_index" == "$oldest_index" ]] && continue
          rm -f -- "${all_files[$file_index]}"
          echo "DELETED DUPLICATE: ${all_files[$file_index]}"
        done
        echo "KEPT OLDEST: $keep_file_path"
      else
        echo "SKIPPED DUPLICATE SET."
      fi
    done

    unset hash_to_indexes
  done
}

op_empty()      { echo "RUN: empty (X='$DEFAULT_CATALOG', Y='${CATALOGS[*]}', default=$DEFAULT_OPTION)"; }
op_temporary()  { echo "RUN: temporary (X='$DEFAULT_CATALOG', Y='${CATALOGS[*]}', default=$DEFAULT_OPTION)"; }
op_same_name()  { echo "RUN: same-name (X='$DEFAULT_CATALOG', Y='${CATALOGS[*]}', default=$DEFAULT_OPTION)"; }
op_access()     { echo "RUN: access (X='$DEFAULT_CATALOG', Y='${CATALOGS[*]}', default=$DEFAULT_OPTION)"; }
op_tricky()     { echo "RUN: tricky-names (X='$DEFAULT_CATALOG', Y='${CATALOGS[*]}', default=$DEFAULT_OPTION)"; }

op_transfer() {
  # Transfer files from input catalogs into destination catalog.
  # MODE: "copy" or "move"
  # Preserve relative paths and handle conflicts by suggesting keeping the newer file.
  # Skip input catalogs that are the same as the destination catalog.
  # Interactive input is read from /dev/tty.

  local MODE="$1"
  local x="$DEFAULT_CATALOG"
  local x_abs y_abs
  local y src rel dst dst_dir
  local src_mtime dst_mtime
  local choice default_choice

  [[ "$MODE" == "copy" || "$MODE" == "move" ]] || wrong_usage

  # Ensure destination catalog exists
  [[ -d "$x" ]] || mkdir -p -- "$x"

  x_abs="$(realpath -m -- "$x")"

  for y in "${CATALOGS[@]}"; do
    [[ -d "$y" ]] || continue

    y_abs="$(realpath -m -- "$y")"
    if [[ "$y_abs" == "$x_abs" ]]; then
      echo "SKIP: input catalog equals destination catalog: $y"
      continue
    fi

    while IFS= read -r -d '' src; do
      rel="${src#"$y"/}"
      dst="$x/$rel"
      dst_dir="$(dirname -- "$dst")"

      if [[ ! -e "$dst" ]]; then
        mkdir -p -- "$dst_dir"
        if [[ "$MODE" == "copy" ]]; then
          cp -p -- "$src" "$dst"
          echo "COPIED: $src -> $dst"
        else
          mv -- "$src" "$dst"
          echo "MOVED: $src -> $dst"
        fi
        continue
      fi

      src_mtime="$(stat -c %Y -- "$src" 2>/dev/null || echo 0)"
      dst_mtime="$(stat -c %Y -- "$dst" 2>/dev/null || echo 0)"

      if (( src_mtime > dst_mtime )); then
        default_choice="r"  # replace dst with src
      else
        default_choice="k"  # keep existing dst
      fi

      # Default option handling
      if [[ "$DEFAULT_OPTION" == "y" ]]; then
        if [[ "$default_choice" == "r" ]]; then
          if [[ "$MODE" == "copy" ]]; then
            cp -p -- "$src" "$dst"
          else
            mv -f -- "$src" "$dst"
          fi
          echo "REPLACED (newer kept): $dst"
        else
          echo "KEPT (newer kept): $dst"
        fi
        continue
      fi

      # Interactive decision
      echo "CONFLICT: destination already exists"
      echo "  SRC: $src"
      echo "  DST: $dst"
      if [[ "$default_choice" == "r" ]]; then
        echo "  Suggested: keep newer -> REPLACE destination"
      else
        echo "  Suggested: keep newer -> KEEP destination"
      fi

      printf "Choose [r]eplace / [k]eep / [s]kip (default: %s): " "$default_choice" > /dev/tty
      IFS= read -r choice < /dev/tty
      choice="${choice:-$default_choice}"

      case "$choice" in
        r|R)
          if [[ "$MODE" == "copy" ]]; then
            cp -p -- "$src" "$dst"
          else
            mv -f -- "$src" "$dst"
          fi
          echo "REPLACED: $dst"
          ;;
        k|K)
          echo "KEPT: $dst"
          ;;
        s|S)
          echo "SKIPPED: $src"
          ;;
        *)
          wrong_usage
          ;;
      esac

    done < <(find "$y" -type f -print0)
  done
}

op_copy() {
  op_transfer "copy"
}

op_move() {
  op_transfer "move"
}


op_rename()     { echo "RUN: rename (X='$DEFAULT_CATALOG', Y='${CATALOGS[*]}', default=$DEFAULT_OPTION)"; }

source ./.clean_files

# Parse command-line arguments
CATALOGS=()
DEFAULT_CATALOG="./X"
DEFAULT_OPTION="n"

DO_DUPLICATES=0
DO_EMPTY=0
DO_TEMPORARY=0
DO_SAME_NAME=0
DO_ACCESS=0
DO_TRICKY=0
DO_MOVE=0
DO_COPY=0
DO_RENAME=0

(( $# == 0 )) && wrong_usage
while (( $# > 0 )); do
  case "$1" in
    -h|--help)
      help
      ;;

    -x|--catalog)
      [[ $# -ge 2 ]] || wrong_usage
      DEFAULT_CATALOG="$2"
      shift 2
      ;;

    --default)
      DEFAULT_OPTION="y"
      shift
      ;;

    -d|--duplicates) DO_DUPLICATES=1; shift ;;
    -e|--empty)      DO_EMPTY=1;      shift ;;
    -t|--temporary)  DO_TEMPORARY=1;  shift ;;
    -s|--same-name)  DO_SAME_NAME=1;  shift ;;
    -a|--access)     DO_ACCESS=1;     shift ;;
    -k|--tricky)     DO_TRICKY=1;     shift ;;  # -k to avoid conflict with -t
    -m|--move)       DO_MOVE=1;       shift ;;
    -c|--copy)       DO_COPY=1;       shift ;;
    -r|--rename)     DO_RENAME=1;     shift ;;

    -*|--*)
      echo "$SCRIPT_NAME: Unknown option $1" >&2
      echo "Try '$SCRIPT_NAME --help' for more information." >&2
      exit 1
      ;;

    *)
      CATALOGS+=("$1")
      shift
      ;;
  esac
done

# Wrong usage if no catalogs were provided
(( ${#CATALOGS[@]} > 0 )) || wrong_usage

# Run selected operations after parsing
(( DO_DUPLICATES ))	&& op_duplicates
(( DO_EMPTY ))		&& op_empty
(( DO_TEMPORARY ))  && op_temporary
(( DO_SAME_NAME ))	&& op_same_name
(( DO_ACCESS ))		&& op_access
(( DO_TRICKY ))		&& op_tricky
(( DO_MOVE )) && op_move
(( DO_COPY ))		&& op_copy
(( DO_RENAME ))		&& op_rename
