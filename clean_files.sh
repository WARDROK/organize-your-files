#!/bin/bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

help() {
  cat <<EOF
Usage: $SCRIPT_NAME [CATALOGS_PATHS]... [OPTIONS]...

Options:
	-h, --help			Show this help message and exit
	-x, --catalog PATH	Specify the result catalog path (default: ./X)
		--default		Use default settings for operations
	-d, --duplicates	Remove duplicate files
	-e, --empty			Remove empty files
	-t, --temporary		Remove temporary files
	-s, --same-name		Remove files with same names
	-a, --access		Change access permissions to default
	-k, --tricky		Replace tricky letters in filenames with default
	-c, --copy			Copy files to a result catalog
	-r, --rename		Rename files

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

# Operation functions
op_duplicates() { echo "RUN: duplicates (X='$DEFAULT_CATALOG', Y='${CATALOGS[*]}', default=$DEFAULT_OPTION)"; }
op_empty()      { echo "RUN: empty (X='$DEFAULT_CATALOG', Y='${CATALOGS[*]}', default=$DEFAULT_OPTION)"; }
op_temporary()  { echo "RUN: temporary (X='$DEFAULT_CATALOG', Y='${CATALOGS[*]}', default=$DEFAULT_OPTION)"; }
op_same_name()  { echo "RUN: same-name (X='$DEFAULT_CATALOG', Y='${CATALOGS[*]}', default=$DEFAULT_OPTION)"; }
op_access()     { echo "RUN: access (X='$DEFAULT_CATALOG', Y='${CATALOGS[*]}', default=$DEFAULT_OPTION)"; }
op_tricky()     { echo "RUN: tricky-names (X='$DEFAULT_CATALOG', Y='${CATALOGS[*]}', default=$DEFAULT_OPTION)"; }
op_copy()       { echo "RUN: copy (X='$DEFAULT_CATALOG', Y='${CATALOGS[*]}', default=$DEFAULT_OPTION)"; }
op_rename()     { echo "RUN: rename (X='$DEFAULT_CATALOG', Y='${CATALOGS[*]}', default=$DEFAULT_OPTION)"; }

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
(( DO_COPY ))		&& op_copy
(( DO_RENAME ))		&& op_rename
