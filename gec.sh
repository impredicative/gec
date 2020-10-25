#!/usr/bin/env bash
set -euo pipefail

CMD="$1"
REPO="$2"
CONFIGFILE="${HOME}/.gec"
_APPDIR="${HOME}/gocryptfs"
GITDIR="${_APPDIR}/encrypted/${REPO}"
ENCDIR="${GITDIR}/fs"
DECDIR="${_APPDIR}/decrypted/${REPO}"

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
    git config http.postBuffer 2000000000
    git config user.name ${GITUSER}
    git config user.email ${GITUSER}@users.noreply.git.com
    git config --local -l
    ;;
  init.fs)
    set -x
    mkdir -p -v "${ENCDIR}"
    gocryptfs -init -nofail -sharedstorage "${ENCDIR}"
    mkdir -p -v "${DECDIR}"
    ;;
  mount)
    set -x
    gocryptfs -nofail -sharedstorage "${ENCDIR}" "${DECDIR}"
    ;;
  mount.ro)
    set -x
    gocryptfs -nofail -sharedstorage -ro "${ENCDIR}" "${DECDIR}"
    ;;
  umount|unmount|dismount)  # Remember to exit $DECDIR before using.
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
  shell.dec)  # Remember to exit after using, otherwise umount won't work.
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
  status)
    set -x
    cd "${GITDIR}"
    git status
    mountpoint "${DECDIR}" && findmnt "${DECDIR}" || :
    ;;
  log)
    set -x
    cd "${GITDIR}"
    git log
    ;;
  du.git)
    set -x
    cd "${GITDIR}"
    du -h -c -d 1
    ;;
  du.enc)
    set -x
    cd "${ENCDIR}"
    du -h -c -d 1
    ;;
  du.dec)
    set -x
    cd "${DECDIR}"
    mountpoint "${DECDIR}" && du -h -c -d 1
    ;;
  rm)
    set -x
    rm -rf "${DECDIR}"
    rm -rf "${GITDIR}"
    ;;
  *)
   echo "Invalid command"
   exit 1
   ;;
esac
