#!/bin/bash
# MAKE SURE YOU HAVE READ https://wiki.gentoo.org/wiki/Project:Infrastructure/Mirrors/Source
# More information https://github.com/ipfs/notes/issues/296

RSYNC="/usr/bin/rsync"
# --checksum is slow, don't use, --numeric-ids should speed up
# removed files causes issues, do them separate
OPTS="--quiet --recursive --links --perms --times -D --delete --timeout=300 --numeric-ids"
OPTS="-v --no-motd --recursive --links --perms --times -D --timeout=300 --numeric-ids"

SRC="ftp.ussg.iu.edu::gentoo-distfiles$1"
# for the first sync, find a quick one from https://www.gentoo.org/downloads/mirrors/
SRC="trumpetti.atm.tut.fi::gentoo$1"

#If you are waiting for access to our master mirror, select one of our mirrors to mirror from:
#SRC="rsync://rsync.de.gentoo.org/gentoo-portage" # for Europe
#SRC="rsync://rsync.us.gentoo.org/gentoo-portage" # for the rest of the world
#Uncomment the following line only if you have been granted access to masterportage.gentoo.org
#SRC="rsync://masterportage.gentoo.org/gentoo-portage"
REPONAME="gentoo-distfiles"
DSTBASE="${HOME}/${REPONAME}"
DST="${DSTBASE}$1"

# some optimizations for large datasets; https://github.com/ipfs/notes/issues/212
# Sharding is needed to handle directories that otherwise generates to large objects - here we force it
ipfs config --json Experimental.ShardingEnabled true
ipfs config --json Datastore.NoSync true
# allow --nocopy
ipfs config --json Experimental.FilestoreEnabled true

getmfsrepohash() {
  ipfs files stat --hash /${REPONAME} 2> /dev/null
}

OLDREPOHASH=$(getmfsrepohash)

echo "Started rsync at " `date` >> $0.log 2>&1
logger -t rsync "re-rsyncing the gentoo-portage tree"
${RSYNC} ${OPTS} ${SRC} ${DST} >> $0.log 2>&1
echo "Done rsync at "`date` >> $0.log 2>&1

# TODO collect any difference in mtime from the above
# BUG during rsync some files are updated/replaces, so this delete mangling might not help much
# TODO handle if delete.log is missing - which timestamp should be used?
LASTSYNCDONE=$(stat -c %Z $0.delete.log)
# grab last delete date, and remove 24 hours
# this should give us all modified files
OLDFILEDATE=$(date -u --date=@$((${LASTSYNCDONE} - 24*60*60)))

# Using tempfile to get last line https://github.com/VictorBjelkholm/arch-mirror/blob/master/ipfsify.sh
HASHFILE=$0.ipfsadd.log
mv ${HASHFILE} ${HASHFILE}.old

removeold_ipfs() {
  if ipfs files ls $1 2>&1 > /dev/null; then
    echo removing $1 $2 >> $0.delete.log 2>&1
    ipfs files rm -r --local $1 >> $0.delete.log 2>&1
    [[ "$2" != "" ]] && (ipfs pin rm -r --local $2 >> $0.delete.log 2>&1) &
  fi
}

# TODO We can only do this add if we actually have data for it
if [[ "$OLDREPOHASH" != "" ]]; then
  echo "Old repo hash $OLDREPOHASH "`date` >> $0.log 2>&1
  find ${DSTBASE}/ -newerct "${OLDFILEDATE}" \( -type f -o -type l \) | while read l; do
    lifp=/${REPONAME}${l#${DSTBASE}}
    if [[ -L "$l" ]]; then
      # there are some issues with symlink - it is mostly ok to ignore them
      OLDHASH=""
    else
      OLDHASH=$(ipfs files stat --hash $lifp) 2> /dev/null
    fi
    echo "doing add for $lifp old file hash: $OLDHASH" >> $0.log 2>&1
    # TODO use this as a pipe instead - should avoid opening and closing
    (ipfs add --nocopy --raw-leaves --local -H $l > ${HASHFILE}) >> $0.log 2>&1
    HASH="$(tail -n1 ${HASHFILE} | cut -d ' ' -f2)"
    [[ "$HASH" == "$OLDHASH" ]] && continue
    removeold_ipfs $lifp $OLDHASH >> $0.log 2>&1
    echo "got $lifp with hash $HASH" >> $0.log 2>&1
    ipfs files cp /ipfs/${HASH} $lifp >> $0.log 2>&1
  done
  NEWREPOHASH=$(getmfsrepohash)
  [[ "$NEWREPOHASH" != "$OLDREPOHASH" ]] && echo "Root hash changed from $OLDREPOHASH to $NEWREPOHASH" >> $0.log 2>&1
  echo "Add/update recently changed files new hash $NEWREPOHASH "`date` >> $0.log 2>&1

  # do a dryrun of sync and grab the delete lines
  mv $0.delete.log $0.delete.log.old
  ${RSYNC} ${OPTS} --dry-run --delete ${SRC} ${DST} 2>&1 | tee $0.delete.log >> $0.log
  cat $0.delete.log >> $0.log
  grep ^deleting "$0.delete.log" | cut -d ' ' -f 2- | while read l; do
    # hopefully this will be easier in the future
    lifp=/${REPONAME}/${l#${DSTBASE}}
    if [[ -L "$l" ]]; then
      # there are some issues with symlink - it is mostly ok to ignore them
      OLDHASH=""
    else
      OLDHASH=$(ipfs files stat --hash $lifp) 2> /dev/null
    fi
    echo "removing $lifp $OLDHASH" >> $0.log 2>&1
    removeold_ipfs $lifp $OLDHASH >> $0.log 2>&1
    echo "removing actuall file ${DSTBASE}/${l} $OLDHASH" >> $0.log 2>&1
    rm -rf ${DSTBASE}/${l} >> $0.log 2>&1
  done
  NEWREPOHASH=$(getmfsrepohash)
  [[ "$NEWREPOHASH" != "$OLDREPOHASH" ]] && echo "Root hash changed from $OLDREPOHASH to $NEWREPOHASH" >> $0.log 2>&1
  echo "Remove old files new hash $NEWREPOHASH "`date` >> $0.log 2>&1
fi # ipfs mfs files does not yet exist, first run?

# make sure we don't refer to anything that might have been removed,
# see https://github.com/ipfs/go-ipfs/issues/4260#issuecomment-406827554
# Update, we need verify stuff, but with file-order it is on magnitude of an hour
#mv verify.log verify.log.old
#(time (ipfs filestore verify --local --file-order | grep -v ^ok)) 2>&1 | tee verify.log >> $0.log
#echo "verify done: "`date` >> $0.log 2>&1
# verify on it's own don't seem to actually remove anything
#grep -q -v ^ok verify.log && (time ipfs repo gc) >> $0.log 2>&1
#echo "gc done: "`date` >> $0.log 2>&1

# re-adding the tree takes over an hour
# gentoo-distfiles might be a symlink so take it's childs /* and -w to wrap it
# symlinks in the tree might not yet be working; https://github.com/VictorBjelkholm/arch-mirror/issues/1
HASH=$NEWREPOHASH
if [[ "$OLDREPOHASH" == "" ]] || [[ "$FULLADD" == "fulladd" ]]; then
  (time (ipfs add -w -r --nocopy --local -H ${DSTBASE}/* > ${HASHFILE})) >> $0.log 2>&1
  HASH="$(tail -n1 ${HASHFILE} | cut -d ' ' -f2)"
fi

if [[ "$OLDREPOHASH" != "" ]]; then # TODO check existing old node, only update if changed
  ipfs files ls /${REPONAME}.old 2>&1 > /dev/null && ipfs files rm -r /${REPONAME}.old >> $0.log 2>&1
  ipfs files cp /ipfs/${OLDREPOHASH} /${REPONAME}.old >> $0.log 2>&1
fi
if [[ "$HASH" != "" ]] && [[ "$(getmfsrepohash)" != "$HASH" ]]; then
  ipfs files cp /ipfs/${HASH} /${REPONAME}.new >> $0.log 2>&1
  ipfs files rm -r /${REPONAME} >> $0.log 2>&1
  ipfs files mv /${REPONAME}.new /${REPONAME} >> $0.log 2>&1
fi

echo "ipfs add ${HASH} done: "`date` >> $0.log 2>&1
logger -t rsync "sync gentoo-portage tree done IPFS ${HASH}"

# run ipfs name commands in background since they are slow
(ipfs name publish /ipfs/${HASH} >> $0.log 2>&1) &
# if ipns is mounted we get; "Error: cannot manually publish while IPNS is mounted" needs a workaround for that

# Add DNS; _dnslink.distfiles.gentoo.org TXT "dnslink=/ipfs/${HASH}"
# it speeds up name resolution since IPNS for the moment is "to" slow
[[ -x dnsupdate.sh ]] && [[ "${HASH}" != "" ]]&& sh dnsupdate.sh "dnslink=/ipfs/${HASH}" >> $0.log 2>&1
# example; dig txt _dnslink.arch.victor.earth
# symlinks might not yet be working; https://github.com/VictorBjelkholm/arch-mirror/issues/1
