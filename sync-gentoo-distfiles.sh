#!/bin/bash
# MAKE SURE YOU HAVE READ https://wiki.gentoo.org/wiki/Project:Infrastructure/Mirrors/Source
# More information https://github.com/ipfs/notes/issues/296

RSYNC="/usr/bin/rsync"
# --checksum is slow, don't use, --numeric-ids should speed up
DELETE=""
# since removed files causes issues, only remove, and clean once in a while
#DELETE="--delete-after"
OPTS="--quiet --recursive --links --perms --times -D --delete --timeout=300 --numeric-ids"
OPTS="-v --no-motd --recursive --links --perms --times -D ${DELETE} --timeout=300 --numeric-ids"

SRC="ftp.ussg.iu.edu::gentoo-distfiles$1"
# for the first sync, find a quick one from https://www.gentoo.org/downloads/mirrors/
SRC="trumpetti.atm.tut.fi::gentoo$1"

#If you are waiting for access to our master mirror, select one of our mirrors to mirror from:
#SRC="rsync://rsync.de.gentoo.org/gentoo-portage" # for Europe
#SRC="rsync://rsync.us.gentoo.org/gentoo-portage" # for the rest of the world
#Uncomment the following line only if you have been granted access to masterportage.gentoo.org
#SRC="rsync://masterportage.gentoo.org/gentoo-portage"
DSTBASE="${HOME}/gentoo-distfiles"
DST="${DSTBASE}$1"

echo "Started update at" `date` >> $0.log 2>&1
logger -t rsync "re-rsyncing the gentoo-portage tree"
${RSYNC} ${OPTS} ${SRC} ${DST} >> $0.log 2>&1
echo "End: "`date` >> $0.log 2>&1

# TODO collect any difference in mtime from the above
# BUG during rsync some files are updated/replaces, so this delete mangling might not help much

# do a dryrun of sync and grab the delete lines
mv $0.delete.log $0.delete.log.old
${RSYNC} ${OPTS} --dry-run --delete ${SRC} ${DST}  2>&1 | tee $0.delete.log >> $0.log
cat $0.delete.log >> $0.log
echo "Delete dl done: "`date` >> $0.log 2>&1
# TODO grep the delete file for files to do ipfs pin rm, but that requires the hash for it, so needs a lookup in $0.ipfsadd.log
# hopefully this will be easier in the future
# make sure we don't refer to anything that might have been removed,
# see https://github.com/ipfs/go-ipfs/issues/4260#issuecomment-406827554
# Update, we need verify stuff, but with file-order it is on magnitude of an hour
mv verify.log verify.log.old
(time (ipfs filestore verify --local --file-order | grep -v ^ok)) | tee verify.log
[[ "$DELETE" != "" ]] && time ipfs repo gc >> $0.log 2>&1
echo "gc done: "`date` >> $0.log 2>&1

# gentoo-distfiles might be a symlink so take it's childs /* and -w to wrap it
# symlinks in the tree might not yet be working; https://github.com/VictorBjelkholm/arch-mirror/issues/1

# some optimizations for large datasets; https://github.com/ipfs/notes/issues/212
# Sharding is needed to handle directories that otherwise generates to large objects - here we force it
ipfs config --json Experimental.ShardingEnabled true
ipfs config --json Datastore.NoSync true
# allow --nocopy
ipfs config --json Experimental.FilestoreEnabled true

# Using tempfile to get last line https://github.com/VictorBjelkholm/arch-mirror/blob/master/ipfsify.sh
HASHFILE=$0.ipfsadd.log
mv ${HASHFILE} ${HASHFILE}.old
# re-adding the tree takes over an hour
# gentoo-distfiles might be a symlink so take it's childs /* and -w to wrap it
ipfs add -w -r --nocopy --local ${DSTBASE}/* > ${HASHFILE}
HASH="$(tail -n1 ${HASHFILE} | cut -d ' ' -f2)"
echo "ipfs add ${HASH} done: "`date` >> $0.log 2>&1
logger -t rsync "sync gentoo-portage tree done IPFS ${HASH}"

# run ipfs name commands in background since they are slow
ipfs name publish /ipfs/${HASH} &
# if ipns is mounted we get; "Error: cannot manually publish while IPNS is mounted" needs a workaround for that

# Add DNS; _dnslink.distfiles.gentoo.org TXT "dnslink=/ipfs/${HASH}"
# it speeds up name resolution since IPNS for the moment is "to" slow
[[ -x dnsupdate.sh ]] && [[ "${HASH}" != "" ]]&& sh dnsupdate.sh "dnslink=/ipfs/${HASH}"
# example; dig txt _dnslink.arch.victor.earth
# symlinks might not yet be working; https://github.com/VictorBjelkholm/arch-mirror/issues/1
