# gec

**`gec`** is a simple and opinionated Bash utility with convenience commands for working with git with [gocryptfs](https://github.com/rfjakob/gocryptfs).
It is a stopgap until a more sophisticated and cross-platform utility is implemented in Golang.

## Requirements
1. gocryptfs ≥ 2.0-beta1
1. git
1. Linux (tested with Ubuntu)
1. A dedicated GitHub and GitLab account with the same username!

## Installation
### For general use
```bash
wget https://raw.githubusercontent.com/impredicative/gec/master/gec.sh -O ~/.local/bin/gec
chmod +x ~/.local/bin/gec
```
### For development
```bash
git clone git@github.com:impredicative/gec.git
ln -s "${PWD}/gec.sh" ~/.local/bin/gec
```

## Workflow
* Create a `<repo>` under a fixed `<owner>` in GitHub and GitLab.
* Ensure SSH access exists to repo in GitHub and GitLab.
* $ gec set owner `<owner>`  # just once for all future repos
* $ gec clone `<repo>`
* $ gec init.fs `<repo>`
* $ gec mount `<repo>`  # use mount.ro instead for read-only mount
* $ gec shell.dec `<repo>`
* $ gec umount `<repo>`  # optional, except before git pull/merge/checkout
* $ gec commit `<repo>` "non-secret commit message"
* $ gec push `<repo>`
