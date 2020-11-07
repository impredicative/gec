# gec

**`gec`** is a simple and opinionated Bash utility with convenience commands for using [gocryptfs](https://github.com/rfjakob/gocryptfs) with git.
It refrains from doing anything clever, making it possible to fallback to the underlying gocryptfs or git commands if a need should arise.
It transparently uses data encryption and version control while leveraging redundant remote storage.

It is in an early stage of development. Breaking changes are possible.

## Contents
* [Requirements](#requirements)
* [Limitations](#limitations)
* [Installation](#installation)
* [Development](#development)
* [Setup](#setup)
* [Directories](#directories)
* [Commands](#commands)
* [Workflow](#workflow)
* [Roadmap](#roadmap)

## Requirements
1. gocryptfs ≥ 2.0-beta1
1. git
1. Linux
1. A dedicated [GitHub](https://github.com/) and [GitLab](https://gitlab.com/) account with an identical username!
If using Firefox, the [Multi-Account Containers](https://addons.mozilla.org/en-US/firefox/addon/multi-account-containers/) add-on can be useful.

## Limitations
1. The known applicable size [limits](https://stackoverflow.com/a/59479166/) are tabulated below.
These limits are not checked or enforced by this tool. If a hard limit is violated, a `push` or `send` will simply fail.
Note that the size of an encrypted file can be just slightly larger than the size of its decrypted file.

    | Subject | Value | Type | Enforcer |
    |---------|-------|------|----------|
    | File    | 100M  | Hard | GitHub   |
    | Push    | 2G    | Hard | GitHub   |
    | Repo    | 5G    | Soft | GitHub   |
    | Repo    | 10G   | Hard | GitLab   |

1. Due to the use of the gocryptfs `-sharedstorage` option, no hardlink can be created in a decrypted repo.

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
In the steps below:
* `<owner>` refers to an identical username in both GitHub and GitLab

On each device:
1. Run `gec config core.owner <owner>` once for all future repos.
1. Run `ssh-keygen -f ~/.ssh/id_gec` once to create a new SSH key. Use and securely save a passphrase for this key to minimize the risk of any unauthorized push.
1. Add the `~/.ssh/id_gec.pub` file for the key created above into the `<owner>` account in both GitHub and GitLab.
1. Create or prepend to `~/.ssh/config` the contents:
    ```shell script
    Match host github.com,gitlab.com exec "[[ $(git config user.name) = gec ]]"
        IdentityFile ~/.ssh/id_gec
    ```
1. Run `chmod go-rw ~/.ssh/config` to tighten permissions of the file as is advised in `man ssh_config`.

## Directories
Storage repos are created in `~/gec/`. This location is created automatically. Both encrypted and decrypted files are organized in this location.
Although this location is not currently configurable, a softlink or hardlink can be used to redirect it elsewhere if needed.

For each repo, these directories are created and used:

| Location                    | Description                                   |
|-----------------------------|-----------------------------------------------|
| `~/gec/encrypted/<repo>`    | git repo contents                             |
| `~/gec/encrypted/<repo>/fs` | encrypted filesystem contents within git repo |
| `~/gec/decrypted/<repo>`    | decrypted filesystem mountpoint               |

## Commands
### Repo-agnostic
* **`config <key> [<val>]`**: Get or set a value of key from configuration file `~/.gec`.
* **`ls`**: List the name and mount state of all repos in `~/gec/encrypted`.

### Repo-specific
In the commands below, `<repo>` refers to an identical repository name, e.g. "travel-us", in both GitHub and GitLab.
It can be auto-determined if a command is run from its encrypted or decrypted directory.
When it can be auto-determined, to disambiguate a command's arguments that follow, it can alternatively be specified as a period.

#### Informational
* **`? [<repo>]`**: Alias of `status`.
* **`du.dec [<repo>]`**:  Print the human-friendly disk usage of the decrypted directory for a depth of one.
* **`du.enc [<repo>]`**:  Print the human-friendly disk usage of the encrypted filesystem directory for a depth of one.
* **`du.git [<repo>]`**:  Print the human-friendly disk usage of the git repo directory for a depth of one.
* **`info [<repo>]`**: Alias of `status`.
* **`log [<repo>]`**: Print the git log for the last ten commits.
* **`state [<repo>]`**: Print the repo name and mount state.
* **`status  [<repo>]`**: Print the repo name, mount state, short git status, and mount information if mounted.

#### Remote oriented
A [GitHub token](https://github.com/settings/tokens/new) and a [GitLab token](https://gitlab.com/-/profile/personal_access_tokens) are required.
For your security, these tokens are not saved by `gec`.
* **`create <repo>`**: Create the repo in GitHub and GitLab. It must not already exist.
The GitHub and GitLab tokens must have access to their `repo` and `api` scopes respectively.
* **`del [<repo>]`**: Delete an existing repo in GitHub and GitLab.
The GitHub and GitLab tokens must have access to their `delete_repo` and `api` scopes respectively.

#### git oriented
* **`clone <repo>`**: Clone and configure a preexisting repo from GitHub into its git repo directory, and add its GitLab URL.
* **`commit <repo> "<commit_msg>"`**: Add and commit all changes. `<commit_msg>` is not encrypted. To auto-determine `<repo>`, specify a period in its place.
* **`pull [<repo>]`**: Pull commits from remote. For safety, a prerequisite is that the repo must be in a dismounted state.
* **`push [<repo>]`**: Push commits to remote.
* **`send <repo> "<commit_msg>"`**: Add, commit, and push all changes. `<commit_msg>` is not encrypted. To auto-determine `<repo>`, specify a period in its place.

#### gocryptfs oriented
* **`dismount`**: Alias of `umount`.
* **`init.fs [<repo>]`**: Initialize the encrypted filesystem for an empty repo. No commit or push is made. A new password is requested. The password and a printed master key must be securely saved.
* **`mount [<repo>]`**: Mount a repo into its decrypted mountpoint. The repo must be in a dismounted state.
* **`mount.ro [<repo>]`**: Mount in read-only mode a repo into its decrypted mountpoint. The repo must be in a dismounted state.
* **`umount [<repo>]`**: Unmount a previously mounted repo.
* **`unmount`**: Alias of `umount`.

#### System
* **`rm [<repo>]`**: Interactively remove all directories of the repo. The repo must be in a dismounted state.
* **`shell.dec [<repo>]`**: Provide a shell into the decrypted mountpoint of a mounted repo.
* **`shell.git [<repo>]`**: Provide a shell into the git repo directory.

#### Compound
* **`use [<repo>]`**: Mount and provide a shell into the decrypted mountpoint. The repo must be in a dismounted state.
* **`use.ro [<repo>]`**: Mount read-only and provide a shell into the decrypted mountpoint. The repo must be in a dismounted state.

## Workflow
Refer to the [repo-specific commands](#repo-specific) section for details on using the commands in the workflows below.

For a new repo:
* `gec create <repo>`
* `gec clone <repo>`
* `gec init.fs [<repo>]`
* `gec send <repo> "Initialize"`

For an existing repo with a previously initialized filesystem:
* `gec clone <repo>`

To use a repo:
* `gec pull [<repo>]`  # If and when changed on remote
* `gec use [<repo>]`
* `gec status [<repo>]`
* `gec send <repo> "a non-secret commit message"`
* `gec umount [<repo>]`

## Roadmap
* Consider adding `init.git` command.
* Mirror to https://gitee.com/
* Release.
* Rewrite using Golang.
