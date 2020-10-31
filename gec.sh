#!/usr/bin/env bash
set -euo pipefail

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

TOOL="$(basename "$0")"
CMD="$1"
CONFIGFILE="${HOME}/.gec"
_APPDIR="${HOME}/gec"
_GITDIR="${_APPDIR}/encrypted"

touch -a "${CONFIGFILE}"

case "${CMD}" in
  get)
    cfg_read "${CONFIGFILE}" "$2"
    exit
    ;;
  set)
    cfg_write "${CONFIGFILE}" "$2" "$3"
    set -x
    cat "${CONFIGFILE}"
    exit
    ;;
  ls)
    ls -1 "${_GITDIR}" 2>&- || :
    exit
    ;;
esac

REPO="$2"
GITDIR="${_GITDIR}/${REPO}"
ENCDIR="${GITDIR}/fs"
DECDIR="${_APPDIR}/decrypted/${REPO}"

# Run command
case "${CMD}" in
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
    git config user.name gec
    git config user.email gec@users.noreply.git.com
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
    git add -A -v
    git commit -m "$3"
    git log --color=always --decorate -1 | grep -v '^Author: '
    ;;
  pull)
    if ! mountpoint "${DECDIR}"; then
      set -x
      cd "${GITDIR}"
      git pull
    else
      echo "Failed: ${TOOL} $@" >&2
      exit 1
    fi
    ;;
  push)
    set -x
    cd "${GITDIR}"
    git push
    ;;
  send)
    set -x
    ${TOOL} commit ${REPO} "$3"
    ${TOOL} push ${REPO}
    ;;
  shell.dec)  # Remember to exit after using, otherwise umount won't work.
    set -x
    mountpoint "${DECDIR}"
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
  use)
    set -x
    ${TOOL} mount ${REPO}
    ${TOOL} shell.dec ${REPO}
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
    git log --color=always --decorate -10 | grep -v '^Author: '
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
    mountpoint "${DECDIR}"
    cd "${DECDIR}"
    du -h -c -d 1
    ;;
  rm)
    if ! mountpoint "${DECDIR}"; then
      set -x
      rm -rfI "${DECDIR}"
      rm -rfI "${GITDIR}"
    else
      echo "Failed: ${TOOL} $@" >&2
      exit 1
    fi
    ;;
  *)
   echo "Failed: ${TOOL} $@" >&2
   exit 1
   ;;
esac
