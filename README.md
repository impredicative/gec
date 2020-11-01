# gec

**`gec`** is a simple and opinionated Bash utility with convenience commands for using [gocryptfs](https://github.com/rfjakob/gocryptfs) with git.
It refrains from doing anything clever, making it possible to fallback to the underlying gocryptfs or git commands if a need should arise.
It transparently uses data encryption and version control while leveraging redundant remote storage.

It is in a very early stage of development and documentation, but it is usable.
Even after this is remedied, it is still just a stopgap until a more sophisticated and cross-platform utility is developed in Golang.

## Contents
* [Requirements](#requirements)
* [Limitations](#limitations)
* [Installation](#installation)
* [Development](#development)
* [Setup](#setup)
* [Workflow](#workflow)
* [Roadmap](#roadmap)

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
```shell script
wget https://raw.githubusercontent.com/impredicative/gec/master/gec.sh -O ~/.local/bin/gec
chmod +x ~/.local/bin/gec
```

## Development
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
1. $ `gec set owner <owner>`  # Just once for all future repos
1. $ `ssh-keygen -f ~/.ssh/id_gec`  # Use and save a passphrase to prevent any unauthorized push
1. Add `~/.ssh/id_gec.pub` key in GitHub and GitLab.
1. Create or prepend to `~/.ssh/config` the contents:
    ```shell script
    Match host github.com,gitlab.com exec "[[ $(git config user.name) = gec ]]"
        IdentityFile ~/.ssh/id_gec
    ```
1. $ `chmod go-rw ~/.ssh/config`

## Workflow
In the workflows below:
* `<owner>` refers to the previously configured owner
* `<repo>` refers to an identical repository name, e.g. "travel", in both GitHub and GitLab.
It can optionally be auto-determined if a command is run from its encrypted or decrypted directory.
When it can be auto-determined, to disambiguate a command's arguments that follow, it can be specified as a single period.

For a new repo:
* Create a `<repo>` under the `<owner>` in GitHub and GitLab.
* $ `gec clone <repo>`
* $ `gec init.fs [<repo>]`  # Set and save the new password and the printed master key
* $ `gec send <repo> "Initialize"`  # Commit and push. Can specify current repo as a single period.

For an existing repo with a previously initialized filesystem:
* $ `gec clone <repo>`

To use a repo:
* $ `gec pull [<repo>]`  # If and when changed on remote
* $ `gec use [<repo>]`  # Mount and CD. Asks for password.
* $ `gec status [<repo>]`
* $ `gec send <repo> "a non-secret commit message"`  # Commit and push. Can specify current repo as a single period.
* $ `gec umount [<repo>]`  # Optional, except before `gec pull` or `git checkout`, etc.

## Roadmap
* Improve stdout messages.
* Document all commands.
* Try git LFS.
* Try Microsoft Scalar instead of git.
