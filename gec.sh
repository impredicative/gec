#!/usr/bin/env bash
set -euo pipefail

# Define repo-agnostic vars
TOOL="$(basename "$0")"
if [ "$#" -ge 1 ]; then
  CMD="$1"
else
   echo "${TOOL}: Provide a command as a positional argument." >&2
   exit 1
fi
CONFIGFILE="${HOME}/.gec"
_APPDIR="${HOME}/gec"
_GITDIR="${_APPDIR}/encrypted"
_DECDIR="${_APPDIR}/decrypted"

touch -a "${CONFIGFILE}"

# Run repo-agnostic command
case "${CMD}" in
  config)
    shift
    git config -f "${CONFIGFILE}" "$@"
    exit
    ;;
  ls|list)
    ls -1 "${_GITDIR}" 2>&- | xargs -i ${TOOL} state {} || :
    exit
    ;;
esac

# Define repo-specific vars
if [ "$#" -ge 2 ] && [ "$2" != '.' ]; then
  REPO="$2"
else
  case "${PWD}"/ in
    ${_GITDIR}/*/*) REPO=$(realpath --relative-to="${_GITDIR}" "${PWD}" | cut -d/ -f1);;
    ${_DECDIR}/*/*) REPO=$(realpath --relative-to="${_DECDIR}" "${PWD}" | cut -d/ -f1);;
    *)
     echo "${TOOL}: Failed to identify repo. Provide it as a positional argument or change to its directory." >&2
     exit 1
     ;;
  esac
fi
GITDIR="${_GITDIR}/${REPO}"
ENCDIR="${GITDIR}/fs"
DECDIR="${_DECDIR}/${REPO}"

# Define logging functions
logr () { echo "[${TOOL}:${REPO}] ${1}" ; }  # Log raw
log () { logr "${1}." ; }  # Log
logn () { echo; log "$1" ; }  # Log after newline
loge () { log "Failed ${CMD}. $1" >&2 ; }  # Log error

# Define utility functions
_du () {  # Disk usage
  cd "$1"
  du -h -c -d 1
}

# Run repo-specific command
case "${CMD}" in
  create)
    GITUSER=$(${TOOL} config core.owner)
    log "Creating repo in GitHub and GitLab"

    # Create GitHub repo
    # Ref: https://stackoverflow.com/a/64636218/
    echo
    read -s -p "GitHub token with access to 'repo' scope: " GITHUB_TOKEN
    logn "Creating repo in GitHub"
    curl -sS -f -X POST -o /dev/null \
      -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" \
      https://api.github.com/user/repos -d "{\"name\": \"${REPO}\", \"private\": true}"
    log "Created repo in GitHub"

    # Create GitLab repo
    # Ref: https://stackoverflow.com/a/64656788/
    # This is optional as the repo is automatically created upon first push.
    echo
    read -s -p "GitLab token with access to 'api' scope: " GITLAB_TOKEN
    logn "Creating repo in GitLab"
    curl -sS -f -X POST -o /dev/null \
      -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" -H "Content-Type:application/json" \
      "https://gitlab.com/api/v4/projects" -d "{\"path\": \"${REPO}\", \"visibility\": \"private\"}"
    log "Created repo in GitLab"

    logn "Created repo in GitHub and GitLab"
    ;;
  clone)
    log "Cloning and configuring repo"

    GITUSER=$(${TOOL} config core.owner)
    mkdir -p "${GITDIR}" && cd "$_"
    logn "Cloning repo from GitHub"
    git clone -c http.postBuffer=2000000000 -c user.name=gec -c user.email=gec@users.noreply.git.com git@github.com:${GITUSER}/${REPO}.git .
    log "Cloned repo from GitHub"
    git remote set-url --add origin git@gitlab.com:${GITUSER}/${REPO}.git
    logn "Added GitLab URL"

    logn "Cloned and configured repo"
    ;;
  init.fs)
    log "Initializing encrypted filesystem"
    mkdir -p "${ENCDIR}"
    gocryptfs -init -nofail -sharedstorage "${ENCDIR}"
    mkdir -p "${DECDIR}"
    logn "Initialized encrypted filesystem"
    ;;
  mount)
    log "Mounting repo"
    gocryptfs -nofail -sharedstorage "${ENCDIR}" "${DECDIR}"
    log "Mounted repo"
    ;;
  mount.ro)
    log "Mounting repo read-only"
    gocryptfs -nofail -sharedstorage -ro "${ENCDIR}" "${DECDIR}"
    log "Mounted repo read-only"
    ;;
  umount|unmount|dismount)  # Remember to exit $DECDIR before using.
    log "Unmounting repo"
    fusermount -u "${DECDIR}"
    log "Unmounted repo"
    ;;
  commit)
    COMMIT_MESSAGE="$3"
    cd "${GITDIR}"
    log "Adding changes"
    git add -A -v
    log "Added changes"
    logr "Committing: ${COMMIT_MESSAGE}"
    git commit -m "${COMMIT_MESSAGE}"
    logr "Committed: ${COMMIT_MESSAGE}"
    echo
    git log --color=always --decorate -1 | grep -v '^Author: '
    ;;
  pull)
    if ! mountpoint -q "${DECDIR}"; then
      cd "${GITDIR}"
      log "Pulling commits"
      git pull
      log "Pulled commits"
    else
      loge "Unmount first"
      exit 2
    fi
    ;;
  push)
    cd "${GITDIR}"
    log "Pushing commits"
    git push
    log "Pushed commits"
    ;;
  send)
    COMMIT_MESSAGE="$3"
    ${TOOL} commit ${REPO} "${COMMIT_MESSAGE}"
    ${TOOL} push ${REPO}
    ;;
  shell.dec)  # Remember to exit the shell after using, otherwise umount won't work.
    if mountpoint -q "${DECDIR}"; then
      cd "${DECDIR}"
      USER_SHELL=$(getent passwd $USER | cut -d : -f 7)
      $USER_SHELL
    else
      loge "Mount first"
      exit 2
    fi
    ;;
  shell.git)
    cd "${GITDIR}"
    USER_SHELL=$(getent passwd $USER | cut -d : -f 7)
    $USER_SHELL
    ;;
  use)
    set -x
    ${TOOL} mount ${REPO}
    ${TOOL} shell.dec ${REPO}
    ;;
  use.ro)
    set -x
    ${TOOL} mount.ro ${REPO}
    ${TOOL} shell.dec ${REPO}
    ;;
  state)
    if mountpoint -q "${DECDIR}"; then
      MOUNT_OPTION=$(findmnt -fn -o options "${DECDIR}" | cut -d, -f1)
      MOUNT_STATE="mounted ${MOUNT_OPTION}"
    else
      MOUNT_STATE="unmounted"
    fi
    echo "${REPO} (${MOUNT_STATE})"  # Output is used by ls command.
    ;;
  status|info|?)
    ${TOOL} state "${REPO}" && echo
    cd "${GITDIR}"
    git status -bs
    mountpoint -q "${DECDIR}" && echo && findmnt -f "${DECDIR}" || :
    ;;
  log)
    cd "${GITDIR}"
    git log --color=always --decorate -10 | grep -v '^Author: '
    ;;
  du.git)
    _du "${GITDIR}"
    ;;
  du.enc)
    _du "${ENCDIR}"
    ;;
  du.dec)
    if mountpoint -q "${DECDIR}"; then
      _du "${DECDIR}"
    else
      loge "Mount first"
      exit 3
    fi
    ;;
  rm)
    if ! mountpoint -q "${DECDIR}"; then
      log "Removing directories"

      if [ -d "${DECDIR}" ]; then
        logn "Removing decryption directory"
        rm -rfI "${DECDIR}"
        log "Removed decryption directory"
      fi

      logn "Removing git directory"
      rm -rfI "${GITDIR}"
      log "Removed git directory"

      logn "Removed directories"
    else
      loge "Unmount first"
      exit 3
    fi
    ;;
  del)
    GITUSER=$(${TOOL} config core.owner)
    log "Deleting repo in GitHub and GitLab"

    # Delete GitHub repo
    # Ref: https://stackoverflow.com/a/30644156/
    logn "Deleting repo in GitHub"
    read -s -p "GitHub token with access to 'delete_repo' scope: " GITHUB_TOKEN
    echo
    curl -sS -f -X DELETE -o /dev/null \
      -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" \
      https://api.github.com/repos/${GITUSER}/${REPO}
    log "Deleted repo in GitHub"

#    # Delete GitLab repo
    # Ref: https://stackoverflow.com/a/52132529/
    logn "Deleting repo in GitLab"
    read -s -p "GitLab token with access to 'api' scope: " GITLAB_TOKEN
    echo
    curl -sS -f -X DELETE -o /dev/null \
      -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" -H "Content-Type:application/json" \
      "https://gitlab.com/api/v4/projects/${GITUSER}%2F${REPO}"
    log "Deleted repo in GitLab"

    logn "Deleted repo in GitHub and GitLab"
    ;;
  *)
   echo "${TOOL}: Unknown command: $@" >&2
   exit 1
   ;;
esac
