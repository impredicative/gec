# gec

**`gec`** is a simple and opinionated Bash utility with convenience commands for using [gocryptfs](https://github.com/rfjakob/gocryptfs) with git.

It is in a very early stage of development and documentation.
Even after this is remedied, it is still just a stopgap until a more sophisticated and cross-platform utility is implemented in Golang.

## Requirements
1. gocryptfs ≥ 2.0-beta1
1. git
1. Linux (tested with Ubuntu)
1. A dedicated [GitHub](https://github.com/) and [GitLab](https://gitlab.com/) account with an identical username!

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
In the workflows below:
* `<owner>` refers to the username in both GitHub and GitLab
* `<repo>` refers to the name of a repository, e.g. "travel", in both GitHub and GitLab

### On first device
* Create a `<repo>` under a fixed `<owner>` in GitHub and GitLab.
* Ensure SSH access exists to repo in GitHub and GitLab.
* $ gec set owner `<owner>`  # just once for all future repos
* $ gec clone `<repo>`
* $ gec init.fs `<repo>`

### On subsequent devices
* Ensure SSH access exists to repo in GitHub and GitLab.
* $ gec set owner `<owner>`  # just once for all future repos
* $ gec clone `<repo>`

### On all devices
* $ gec pull `<repo>`  # if changed on remote
* $ gec use `<repo>`  # = mount and cd
* $ gec status `<repo>`  # optional
* $ gec send `<repo>` "a non-secret commit message"  # = commit and push
* $ gec umount `<repo>`  # optional, except before git pull/merge/checkout
