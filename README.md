# gec

**`gec`** is a simple and opinionated Bash utility with convenience commands for using [gocryptfs](https://github.com/rfjakob/gocryptfs) with git.
It refrains from doing anything clever, making it possible to fallback to the underlying gocryptfs or git commands.
It allows data encryption, version control, and replication, while leveraging free storage.

It is in a very early stage of development and documentation.
Even after this is remedied, it is still just a stopgap until a more sophisticated and cross-platform utility is developed in Golang.

## Requirements
1. gocryptfs ≥ 2.0-beta1
1. git
1. Linux (tested with Ubuntu)
1. A dedicated [GitHub](https://github.com/) and [GitLab](https://gitlab.com/) account with an identical username!

The known applicable size [limits](https://stackoverflow.com/a/59479166/) are:

| Subject | Value | Type | Enforcer |
|---------|-------|------|----------|
| File    | 100M  | Hard | GitHub   |
| Push    | 2G    | Hard | GitHub   |
| Repo    | 5G    | Soft | GitHub   |
| Repo    | 10G   | Hard | GitLab   |

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

## Storage repo Setup
In the workflows below:
* `<owner>` refers to an identical username in both GitHub and GitLab
* `<repo>` refers to an identical repository name, e.g. "travel", in both GitHub and GitLab

### On first device
* Create a `<repo>` under a fixed `<owner>` in GitHub and GitLab.
* Ensure SSH access exists to repo in GitHub and GitLab.
* $ gec set owner `<owner>`  # Just once for all future repos
* $ gec clone `<repo>`
* $ gec init.fs `<repo>`  # Asks for new password. Save printed master key.

### On subsequent devices
* Ensure SSH access exists to repo in GitHub and GitLab.
* $ gec set owner `<owner>`  # Just once for all future repos
* $ gec clone `<repo>`

## Storage repo Usage
* $ gec pull `<repo>`  # If changed on remote
* $ gec use `<repo>`  # Mount and CD. Asks for password.
* $ gec status `<repo>`  # Optional
* $ gec send `<repo>` "a non-secret commit message"  # Commit and push
* $ gec umount `<repo>`  # Optional, except before git pull/merge/checkout

## High-level Roadmap
* Try clone,send,push,pull with password-protected SSH key.
* Auto-detect and use current `<repo>` whenever possible.
* Improve stdout messages.
* Try git LFS.
* Try Microsoft Scalar instead of git.
