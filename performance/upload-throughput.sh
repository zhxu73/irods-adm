#!/bin/bash

show_help()
{
  cat <<EOF

$ExecName version $Version

Usage:
 $ExecName [options] DEST-COLL

This script measures upload throughput from the client running this script to
the CyVerse Data Store. It uploads a 10 GiB file twenty times in a row, with
each upload being to a new data object. It generates the same output as
\`iput -v\` would. The test results are written to stdout, while errors and
status messages are written to stderr.

Caution should be taken when choosing the name of the the collection where the
objects are uploaded. To ensure that no overwrites occur in iRODS, the script
deletes any files that would be overwritten before it performs the test.

It does its best to clean up after itself. It attempts to delete anything it
creates with one caveat. If a parent collection has to be created during the
creation of the destination collection, the parent collection is not deleted.

Parameters:
 DEST-COLL  The name of the collection where the test file will be uploaded

Options:
 -S, --src-dir SRC-DIR  the directory where the 10 GiB temporary test file will
                        be generated. Defaults to the system default temporary
                        directory.

 -h, --help     show help and exit
 -v, --version  show version and exit

Example:
The following example uses a local file \`testFile\` that is temporarily stored
in the user's home folder. It uploads the file into the collection
\`UploadPerf\` under the client user's home collection. To keep track of the
upload progress, it splits stdout so that it is written both to stderr and a
file named \`upload-results\` stored in the user's home folder.

 iinit
 icd
 $ExecName "\$HOME"/testFile UploadPerf \\
   | tee /dev/stderr > "\$HOME"/upload-results
EOF
}


set -o errexit -o nounset -o pipefail

readonly ExecAbsPath=$(readlink --canonicalize "$0")
readonly ExecName=$(basename "$ExecAbsPath")
readonly Version=2

readonly ObjBase=upload
readonly NumRuns=2


main()
{
  local opts
  if ! opts=$(getopt --name "$ExecName" --longoptions help,src-dir:,version --options hS:v -- "$@")
  then
    show_help >&2
    return 1
  fi

  eval set -- "$opts"

  local srcDir="$TMPDIR"
  local versionReq=0
  while true
  do
    case "$1" in
      -h|--help)
        show_help
        return 0
        ;;
      -S|--src-dir)
        srcDir="$2"
        shift 2
        ;;
      -v|--version)
        versionReq=1
        shift
        ;;
      --)
        shift
        break
        ;;
      *)
        show_help >&2
        return 1
        ;;
    esac
  done

  if [[ "$versionReq" -eq 1 ]]
  then
    printf '%s\n' "$Version"
    return 0
  fi

  if [[ "$#" -lt 1 ]]
  then
    show_help >&2
    return 1
  fi

  local coll="$1"
  do_test "$srcDir" "$coll"
}


do_test()
{
  local tmpDir="$1"
  local coll="$2"

  local testFile
  testFile=$(TMPDIR="$tmpDir" mktemp)

  # shellcheck disable=SC2064
  trap "rm --force '$testFile'" EXIT

  printf 'Ensuring 10 GiB test file %s exists\n' "$testFile" >&2
  if ! truncate --size 10GiB "$testFile"
  then
    printf 'Failed to create 10 GiB file %s\n' "$testFile" >&2
    printf 'Cannot continue test\n' >&2
    return 1
  fi

  printf 'Ensuring destination collection %s exists\n' "$coll" >&2
  local createdColl
  if ! createdColl=$(mk_dest_coll "$coll")
  then
    printf 'Failed to create destination collection %s\n' "$coll" >&2
    printf 'Cannont continue test\n' >&2
    return 1
  fi

  if [[ "$createdColl" -ne 0 ]]
  then
    printf 'Ensuring any previously uploaded test data objects have been removed\n' >&2

    if ! ensure_clean "$coll"
    then
      printf 'Failed to remove previously uploaded data objects\n' >&2
      printf 'Cannot continue test\n' >&2
      return 1
    fi
  fi

  printf 'Beginning test\n' >&2
  local attempt
  for attempt in $(seq "$NumRuns")
  do
    local obj
    obj=$(mk_obj_path "$coll" "$attempt")

    iput -v "$testFile" "$obj"
  done

  printf 'Removing uploaded test data objects\n' >&2
  ensure_clean "$coll" >&2

  if [[ "$createdColl" -ne 0 ]]
  then
    printf 'Removing destination collection %s\n' "$coll" >&2
    irm -f -r "$coll" >&2
  fi
}


ensure_clean()
{
  local coll="$1"

  local status=0

  local attempt
  for attempt in $(seq "$NumRuns")
  do
    local obj
    obj=$(mk_obj_path "$coll" "$attempt")

    local errMsg
    if ! errMsg=$(irm -f "$obj" 2>&1)
    then
      if ! [[ "$errMsg" =~ ^ERROR:\ rmUtil:\ srcPath\ .*\ does\ not\ exist$ ]]
      then
        printf '%s\n' "$errMsg" >&2
        status=1
      fi
    fi
  done

  return "$status"
}


mk_dest_coll()
{
  local createdColl=0
  if ! ils "$coll" &> /dev/null
  then
    if ! imkdir -p "$coll"
    then
      return 1
    fi

    createdColl=1
  fi

  printf '%s' "$createdColl"
}


mk_obj_path()
{
  local coll="$1"
  local attempt="$2"

  printf '%s/%s-%02d' "$coll" "$ObjBase" "$attempt"
}


main "$@"
