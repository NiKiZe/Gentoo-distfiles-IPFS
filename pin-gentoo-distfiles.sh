#!/bin/bash
# More information https://github.com/ipfs/notes/issues/296
# And https://github.com/NiKiZe/Gentoo-distfiles-IPFS

# This scripts takes an ipfs node, and pins it, by first adding to the IPFS MFS
# Which also allows for tracking old hashes and thus using ipfs pin update
# once MFS stabilizes pin on it's own should not be needed (it should do best effort pins automatically)

#IPFSSOURCE="/ipns/gentoo.free.netboot.se"
IPFSSOURCE="/ipns/QmescA7sGoc4yZEe3Gof7dYt2qkkxDEXQPT2z84MpjVu8o"
PINNAME="gentoo-distfiles.pin"
PINNAMEOLD="${PINNAME}.old"

# get hash of source
NEWHASHPATH=$(ipfs name resolve ${IPFSSOURCE})
[[ "$NEWHASHPATH" == "" ]] && exit
[[ "$NEWHASHPATH" == "/ipfs/" ]] && exit

# check for existing, grab hash
OLDHASH=$(ipfs files stat --hash /${PINNAME} 2> /dev/null)
# if new is same as old hash then exit
[[ "$NEWHASHPATH" == "/ipfs/$OLDHASH" ]] && exit

# if existing, move it to old
if [[ "$OLDHASH" != "" ]]; then
  ipfs files ls /${PINNAMEOLD} 2>&1 > /dev/null && ipfs files rm -r /${PINNAMEOLD} >> $0.log 2>&1
  ipfs files cp /ipfs/${OLDHASH} /${PINNAMEOLD} >> $0.log 2>&1
fi

ipfs files cp ${NEWHASHPATH} /${PINNAME}.new >> $0.log 2>&1
ipfs files rm -r /${PINNAME} >> $0.log 2>&1
ipfs files mv /${PINNAME}.new /${PINNAME} >> $0.log 2>&1
if [[ "$OLDHASH" != "" ]]; then
  ipfs pin update /ipfs/$OLDHASH $NEWHASHPATH
else
  ipfs pin add --progress $NEWHASHPATH || ipfs files rm -r /${PINNAME} >> $0.log 2>&1
fi

# TODO if old, remove old pin, update should handle that
