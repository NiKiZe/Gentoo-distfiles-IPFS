## Gentoo-distfiles-IPFS Mirror
Note this is still work in progress!
> Scripts for syncing Gentoo distfiles, adding to IPFS and maintaining publishes to IPNS

- Follow along with discussions here: https://github.com/ipfs/notes/issues/296
- Relevant Gentoo forum thread: https://forums.gentoo.org/viewtopic.php?p=8244506
- Also relevant is similar project for Arch: https://github.com/ipfs/notes/issues/84

### Using as a mirror

The intention of this is to use IPFS as a mirror for distfiles as described at https://www.gentoo.org/downloads/mirrors/

- Add `https://ipfs.io/ipns/gentoo.free.netboot.se/` to your `GENTOO_MIRRORS` variable in `make.conf` make sure to keep fallbacks
- Enjoy immutable and distributed updates to your system!

There are a few ways you can use the IPFS Gentoo mirror.

- Use IPNS directly (slow): https://ipfs.io/ipns/QmescA7sGoc4yZEe3Gof7dYt2qkkxDEXQPT2z84MpjVu8o
- Use IPFS directly (fast but harder for you to update): - don't use
- Use DNS via IPNS (fast and can be resolved anywhere): https://ipfs.io/ipns/gentoo.free.netboot.se/

Recommend to use DNS via IPNS for now, until performance issues with IPNS has been resolved.

### Usage with local daemon

To get the most benefit of IPFS when downloading packages, you should be running
a local go-ipfs node. Once you have it up and running, you can replace `ipfs.io`
with `localhost:8080` and everything should work the same, except you get better
caching and you help rehost the packages you download.

### Mount IPFS and locate files via fuse

This would avoid duplicate files and remove need for portage to download anything - but have not been tested yet

### Hosting your own mirror

#### Requirements

- go-ipfs version 0.4.14 or later (tested with 0.4.16)
- about 500GB of diskspace (real usage will be around ~390GB but good with a buffer)
  - This diskspace requirement only applies if you want to host your own mirror, not if you're using a existing one

#### Setup

Want to setup your own IPFS mirror? It's easy, just follow these steps:

- Edit `./sync-gentoo-distfiles.sh` to make sure mirror and other things is set appropiately.
- Run `./sync-gentoo-distfiles.sh` which downloads the latest distfiles
  to `./gentoo-distfiles`.
- Add to crontab `10 */4 *  * *  sh /home/distfiles/sync-gentoo-distfiles.sh &`

> TODO write more details here

### Findings

- Large directories does not work without sharding: https://github.com/ipfs/go-ipfs/issues/5282
- go-ipfs gateway does not support symlinks yet: https://github.com/ipfs/go-ipfs/pull/3508

## License

MIT 2018 - Christian Nilsson
Based on work by Victor Bjelkholm
