#!/usr/bin/env bash
set -euxo pipefail

# Installation:
# - Ensure gocryptfs and git are available.
# - $ wget https://raw.githubusercontent.com/impredicative/gec/master/gec.sh > ~/.local/bin/gec

# Workflow:
# - Create a <repo> under a fixed <owner> in GitHub and GitLab.
# - Ensure SSH access exists to repo in GitHub and GitLab.
# - $ gec set owner <owner>  # just once for all future repos
# - $ gec clone <repo>
# - $ gec init.fs <repo>
# - $ gec mount <repo>  # use mount.ro for read-only mount
# - Work with files in $DECDIR
# - $ gec umount <repo>  # optional, except before git pull/merge/checkout
# - $ gec commit <repo> "<non-secret commit message>"
# - $ gec push <repo>

CMD="$1"
REPO="$2"
CONFIGFILE="${HOME}/.gec"
APPDIR="${HOME}/gocryptfs"
GITDIR="${APPDIR}/encrypted/${REPO}"
ENCDIR="${GITDIR}/fs"
DECDIR="${APPDIR}/decrypted/${REPO}"
set +x
touch -a "${CONFIGFILE}"

# Configuration helpers from https://unix.stackexchange.com/a/433816/
sed_escape() {
  sed -e 's/[]\/$*.^[]/\\&/g'
}
cfg_write() { # path, key, value
  cfg_delete "$1" "$2"
  echo "$2=$3" >> "$1"
}
cfg_read() { # path, key -> value
  test -f "$1" && grep "^$(echo "$2" | sed_escape)=" "$1" | sed "s/^$(echo "$2" | sed_escape)=//" | tail -1
}
cfg_delete() { # path, key
  test -f "$1" && sed -i "/^$(echo $2 | sed_escape).*$/d" "$1"
}
cfg_haskey() { # path, key
  test -f "$1" && grep "^$(echo "$2" | sed_escape)=" "$1" > /dev/null
}

# Run command
case "${CMD}" in
  set)
    cfg_write "${CONFIGFILE}" "$2" "$3"
    set -x
    cat "${CONFIGFILE}"
    ;;
  clone)
    GITUSER=$(cfg_read "${CONFIGFILE}" owner)
    set -x
    mkdir -p -v "${GITDIR}" && cd "$_"

    # Clone:
    git clone git@github.com:${GITUSER}/${REPO}.git .
    git remote set-url --add origin git@gitlab.com:${GITUSER}/${REPO}.git
    git remote -v

    # Configure:
    git config http.postBuffer 5242880000
    git config user.name ${GITUSER}
    git config user.email ${GITUSER}@users.noreply.git.com
    git config --local -l
    ;;
  init.fs)
    set -x
    mkdir -p -v "${ENCDIR}"
    gocryptfs -init -nofail -sharedstorage "${ENCDIR}"
    ;;
  mount)
    set -x
    mkdir -p -v "${DECDIR}"
    gocryptfs -nofail -sharedstorage "${ENCDIR}" "${DECDIR}"
    ;;
  mount.ro)
    set -x
    mkdir -p -v "${DECDIR}"
    gocryptfs -nofail -sharedstorage -ro "${ENCDIR}" "${DECDIR}"
    ;;
  umount|unmount|dismount)  # Remember to exit $DECDIR first.
    set -x
    fusermount -u "${DECDIR}"
    ;;
  commit)
    set -x
    cd "${GITDIR}"
    git add -A
    git commit -m "$3"
    git show --name-status
    ;;
  push)
    set -x
    cd "${GITDIR}"
    git push
    ;;
  shell.dec)  # Remember to exit, otherwise umount won't work.
    set -x
    cd "${DECDIR}"
    USER_SHELL=$(getent passwd $USER | cut -d : -f 7)
    $USER_SHELL
    ;;
  shell.git)
    set -x
    cd "${GITDIR}"
    USER_SHELL=$(getent passwd $USER | cut -d : -f 7)
    $USER_SHELL
    ;;
  *)
   echo "Invalid command"
   exit 1
   ;;
esac
