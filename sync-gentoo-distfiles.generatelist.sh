#!/bin/bash

REPONAME="gentoo-distfiles"
DSTBASE="${HOME}/${REPONAME}"
DST="${DSTBASE}$1"

getipfsfilestat() {
  local l=$1
  # convert full path, to ipfs repo based path
  # /home/user/gentoo-distfiles/ should become gentoo-distfiles/
  local fpath=${REPONAME}${l#${DSTBASE}}
  if [[ -L "$l" ]]; then
    # there are some issues with symlink - it is mostly ok to ignore those issues
    local symlinkhash=$(ipfs add --local -q -r -n --raw-leaves --nocopy -H "$l")
    local s="symlink:$fpath -> $(readlink -n $l):${symlinkhash}:0"
  else
    # starting all these processes is horrible, but for now there is no native recursive support
    local s=$(ipfs files stat --local --format "<type>:$fpath:<hash>:<cumulsize>" "/$fpath")
  fi
  local type="${s%:*:*:*}"
  case $type in
    file)
    ;;
    symlink)
    ;;
    directory)
      # directories should have trailing /, but only one
      case $fpath in
        */) ;;
        *) local s=$s/ ;;
      esac
    ;;
    *)
      >&2 echo "Unsupported type $s for $l, trying readding"
      NEWHASH=$(ipfs add --local -Q -r --nocopy --raw-leaves -H "$l")
      ipfs files cp /ipfs/${NEWHASH} "/$fpath"
    ;;
  esac
  local namehashsize="${s#*:}"
  # output path:hash:size
  echo $namehashsize
}

# run N tasks in parallel batches
N=4
# trailing / here is to make sure we get symlink target, not symlink itself
find ${DSTBASE}/ | while read l; do
  ((i=i%N)); ((i++==0)) && wait
  getipfsfilestat "$l" &
done
wait
