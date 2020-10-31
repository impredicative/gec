# gec

**`gec`** is a simple and opinionated Bash utility with convenience commands for using [gocryptfs](https://github.com/rfjakob/gocryptfs) with git.
It refrains from doing anything clever, making it possible to fallback to the underlying gocryptfs or git commands if a need should arise.
It transparently uses data encryption, version control, while leveraging redundant remote storage.

It is in a very early stage of development and documentation.
Even after this is remedied, it is still just a stopgap until a more sophisticated and cross-platform utility is developed in Golang.

## Requirements
1. gocryptfs ≥ 2.0-beta1
1. git
1. Linux
1. A dedicated [GitHub](https://github.com/) and [GitLab](https://gitlab.com/) account with an identical username!
If using Firefox, the [Multi-Account Containers](https://addons.mozilla.org/en-US/firefox/addon/multi-account-containers/) add-on can be useful.

## Limitations
* The known applicable size [limits](https://stackoverflow.com/a/59479166/) are tabulated below.
These limits are not checked or enforced by this tool. If a hard limit is violated, a `push` or `send` will simply fail.
Note that the size of an encrypted file can be just slightly larger than the size of its decrypted file.

| Subject | Value | Type | Enforcer |
|---------|-------|------|----------|
| File    | 100M  | Hard | GitHub   |
| Push    | 2G    | Hard | GitHub   |
| Repo    | 5G    | Soft | GitHub   |
| Repo    | 10G   | Hard | GitLab   |

* Due to the use of the gocryptfs `-sharedstorage` option, no hardlink can be created in the decrypted repo itself.

## Installation
### For general use
```shell script
wget https://raw.githubusercontent.com/impredicative/gec/master/gec.sh -O ~/.local/bin/gec
chmod +x ~/.local/bin/gec
```
### For development
```shell script
git clone git@github.com:impredicative/gec.git
ln -s "${PWD}/gec.sh" ~/.local/bin/gec
```

## Setup
Storage repos are created in `~/gec/`. This location is created automatically. Both encrypted and decrypted files are organized in this location.
Although this location is not currently configurable, a softlink or hardlink can be used to redirect it elsewhere if needed.

In the steps below:
* `<owner>` refers to an identical username in both GitHub and GitLab

On each device:
* $ gec set owner `<owner>`  # Just once for all future repos
* Setup SSH:
  * $ ssh-keygen  # Save SSH key having a passphrase to `/home/<user>/.ssh/id_gec`. Save the passphrase. Passphrase prevents ransomware from force pushing.
  * Add `~/.ssh/id_gec.pub` key in GitHub and GitLab.
  * Create or prepend to `~/.ssh/config` the contents:
    ```shell script
    Match host github.com,gitlab.com exec "[[ $(git config user.name) = gec ]]"
        IdentityFile ~/.ssh/id_gec
    ```
  * $ chmod go-rw ~/.ssh/config

## Usage
In the workflows below:
* `<owner>` refers to the previously configured owner
* `<repo>` refers to an identical repository name, e.g. "travel", in both GitHub and GitLab

For a new repo:
* Create a `<repo>` under the `<owner>` in GitHub and GitLab.
* $ gec clone `<repo>`
* $ gec init.fs `<repo>`  # Asks for new password. Save the password and the printed master key.
* $ gec send `<repo>` "Initialize"  # Commit and push

For an existing repo with a previously initialized filesystem:
* $ gec clone `<repo>`

To use a repo:
* $ gec pull `<repo>`  # If and when changed on remote
* $ gec use `<repo>`  # Mount and CD. Asks for password.
* $ gec status `<repo>`  # Optional
* $ gec send `<repo>` "a non-secret commit message"  # Commit and push
* $ gec umount `<repo>`  # Optional, except before git pull/merge/checkout

## Roadmap
* Try clone,send,push,pull with password-protected SSH key.
* Auto-detect and use current `<repo>` whenever possible.
* Improve stdout messages.
* Document all commands.
* Try git LFS.
* Try Microsoft Scalar instead of git.
