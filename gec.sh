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
LS_FORMAT="%11s .git=%4s enc=%4s all=%4s %s\n"

touch -a "${CONFIGFILE}"

# Define utility functions
_du_hsc () {  # Disk usage
  du -h -s -c "$@" | tail -1 | cut -f1
}

# Run repo-agnostic command
case "${CMD}" in
  install)
    releases=$(curl -sS -f -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/impredicative/gec/releases)
    release=$(echo "${releases}" | python -c 'import json,sys; print(json.load(sys.stdin)[0]["tag_name"])')
    FILE="$0"
    wget -q https://raw.githubusercontent.com/impredicative/gec/${release}/gec.sh -O "${FILE}"
    chmod +x "${FILE}"
    echo "[gec] Installed ${release} to ${FILE}"
    exit
    ;;
  config)
    shift
    git config -f "${CONFIGFILE}" "$@"
    exit
    ;;
  ls|list)
    mkdir -p "${_GITDIR}"
    cd "${_GITDIR}"
    shift
    PATTERN=${@:-*}

    # Print individual state
    ls -1d ${PATTERN} | uniq | xargs -i ${TOOL} state {}

    # Print cumulative disk usage1)
    gitdirs_size=$(_du_hsc ./${PATTERN}/.git)
    encdirs_size=$(_du_hsc ./${PATTERN}/fs)
    alldirs_size=$(_du_hsc ./${PATTERN})
    printf "${LS_FORMAT}" "" ${gitdirs_size} ${encdirs_size} ${alldirs_size} "(total)"
    exit
    ;;
  lock)
    mkdir -p "${_GITDIR}"
    cd "${_GITDIR}"
    ls -1 | xargs -i ${TOOL} umount {}
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
_du_hcd () {  # Disk usage
  cd "$1"
  du -h -c -d 1
}
_shell () {  # Shell into dir
  cd "$1"
  USER_SHELL=$(getent passwd $USER | cut -d : -f 7)
  $USER_SHELL
}

# Run repo-specific command
case "${CMD}" in
  create)
    GITUSER=$(${TOOL} config core.owner)
    log "Creating repo in GitHub and GitLab"

    # Create GitHub repo
    # Ref: https://stackoverflow.com/a/64636218/
    logn "Creating repo in GitHub"
    read -s -p "GitHub token with access to 'repo' scope: " GITHUB_TOKEN
    echo
    curl -sS -f -X POST -o /dev/null \
      -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" \
      https://api.github.com/user/repos -d "{\"name\": \"${REPO}\", \"private\": true}"
    log "Created repo in GitHub"

    # Create GitLab repo
    # Ref: https://stackoverflow.com/a/64656788/
    # This is optional as the repo is automatically created upon first push.
    logn "Creating repo in GitLab"
    read -s -p "GitLab token with access to 'api' scope: " GITLAB_TOKEN
    echo
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
  init)
    ${TOOL} create ${REPO}
    ${TOOL} clone ${REPO}
    ${TOOL} init.fs ${REPO}
    ${TOOL} send ${REPO} "Initialized"
    ;;
  init.fs)
    log "Initializing encrypted filesystem"
    mkdir -p "${ENCDIR}"
    gocryptfs -init -nofail -sharedstorage "${ENCDIR}"
    mkdir -p "${DECDIR}"
    logn "Initialized encrypted filesystem"
    ;;
  mount|mount.rw)
    log "Mounting repo read-write"
    gocryptfs -nofail -sharedstorage -rw "${ENCDIR}" "${DECDIR}"
    log "Mounted repo read-write"
    ;;
  mount.ro)
    log "Mounting repo read-only"
    gocryptfs -nofail -sharedstorage -ro "${ENCDIR}" "${DECDIR}"
    log "Mounted repo read-only"
    ;;
  umount|unmount|dismount)  # Remember to exit $DECDIR before using.
    if mountpoint -q "${DECDIR}"; then
      log "Unmounting repo"
      fusermount -u "${DECDIR}"
      log "Unmounted repo"
    else
      log "Repo is already unmounted"
    fi
    ;;
  commit)
    COMMIT_MESSAGE="${3:?'Provide a commit message as a positional argument.'}"
    cd "${GITDIR}"

    log "Adding changes"
    git add -A -v
    log "Added changes"

    if ! git diff-index --quiet @; then
      # Ref: https://stackoverflow.com/a/34093391/

      logr "Committing: ${COMMIT_MESSAGE}"
      git commit -m "${COMMIT_MESSAGE}"
      logr "Committed: ${COMMIT_MESSAGE}"

      echo
      git log --color=always --decorate -1 | grep -v '^Author: '

      echo
      if which git-sizer >/dev/null ; then
        ${TOOL} check.git ${REPO}
      else
        log "Skipped checking sizes of git repo since git-sizer is unavailable"
      fi

    else
      log "No changes to commit"
    fi
    ;;
  amend)
    COMMIT_MESSAGE="${3:?'Provide a commit message as a positional argument.'}"
    cd "${GITDIR}"

    log "Adding changes"
    git add -A -v
    log "Added changes"

    if ! git diff-index --quiet @; then
      # Ref: https://stackoverflow.com/a/34093391/
      logr "Amending commit: ${COMMIT_MESSAGE}"
      git commit --amend -m "${COMMIT_MESSAGE}"
      logr "Amended commit: ${COMMIT_MESSAGE}"
      echo
      git log --color=always --decorate -1 | grep -v '^Author: '
    else
      log "No changes to amend"
    fi
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
    git push -v
    log "Pushed commits"
    ;;
  send)
    ${TOOL} commit ${REPO} "${@:3}"
    echo
    ${TOOL} push ${REPO}
    ;;
  done)
    if mountpoint -q "${DECDIR}"; then
      ${TOOL} umount ${REPO}
    else
      log "Repo is unmounted"
    fi
    ${TOOL} send ${REPO} "${@:3}"
    ;;
  shell)
    _shell "${GITDIR}"
    ;;
  shell.dec)  # Remember to exit the shell after using, otherwise umount won't work.
    if mountpoint -q "${DECDIR}"; then
      _shell "${DECDIR}"
    else
      loge "Mount first"
      exit 2
    fi
    ;;
  shell.enc)
    _shell "${ENCDIR}"
    ;;
  use|use.rw)
    if mountpoint -q "${DECDIR}"; then
      MOUNT_OPTION=$(findmnt -fn -o options "${DECDIR}" | cut -d, -f1)
      if [ "${MOUNT_OPTION}" != "rw" ]; then
        ${TOOL} umount ${REPO}
        ${TOOL} mount ${REPO}
      fi
    else
      ${TOOL} mount ${REPO}
    fi
    ${TOOL} shell.dec ${REPO}
    ;;
  use.ro)
    if mountpoint -q "${DECDIR}"; then
      MOUNT_OPTION=$(findmnt -fn -o options "${DECDIR}" | cut -d, -f1)
      if [ "${MOUNT_OPTION}" != "ro" ]; then
        ${TOOL} umount ${REPO}
        ${TOOL} mount ${REPO}
      fi
    else
      ${TOOL} mount ${REPO}
    fi
    ${TOOL} shell.dec ${REPO}
    ;;
  state)
    # Get mount state
    if mountpoint -q "${DECDIR}"; then
      MOUNT_OPTION=$(findmnt -fn -o options "${DECDIR}" | cut -d, -f1)
      MOUNT_STATE="mounted ${MOUNT_OPTION}"
    else
      MOUNT_STATE="unmounted"
    fi

    # Measure disk usage
    mkdir -p "${ENCDIR}"
    GITDIR_SIZE=$(du -h -s "${GITDIR}/.git" | cut -f1)
    ENCDIR_SIZE=$(du -h -s "${ENCDIR}" | cut -f1)
    ALLDIR_SIZE=$(du -h -s "${GITDIR}" | cut -f1)

    # Print state
    printf "${LS_FORMAT}" "${MOUNT_STATE}" ${GITDIR_SIZE} ${ENCDIR_SIZE} ${ALLDIR_SIZE} ${REPO}
    ;;
  status|info|?)
    ${TOOL} state ${REPO}
    cd "${GITDIR}"
    echo
    git status -bs
    mountpoint -q "${DECDIR}" && echo && findmnt -f "${DECDIR}" || :
    ;;
  log)
    cd "${GITDIR}"
    git log --color=always --decorate -10 | grep -v '^Author: '
    ;;
  du)
    _du_hcd "${GITDIR}"
    ;;
  du.enc)
    _du_hcd "${ENCDIR}"
    ;;
  du.dec)
    if mountpoint -q "${DECDIR}"; then
      _du_hcd "${DECDIR}"
    else
      loge "Mount first"
      exit 3
    fi
    ;;
  rm)
    if mountpoint -q "${DECDIR}"; then
      ${TOOL} umount ${REPO}
      echo
    fi

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
  destroy)
    ${TOOL} rm ${REPO}
    ${TOOL} del ${REPO}
    ;;
  check.git)
    cd ${GITDIR}
    log "Checking sizes of git repo"
    size_json=$(git-sizer -j --json-version 2 --no-progress)

    max_blob_size=$(echo "${size_json}" | python -c 'import json,sys; print(json.load(sys.stdin))["maxBlobSize"]["value"]')
    max_blob_size_mb=$(echo "$max_blob_size / 1000000" | bc -l | xargs -i printf "%'.1f MB" {})
    if (( $max_blob_size > 100000000 ));then
      loge "Max blob size of ${max_blob_size_mb} is over GitHub's hard limit of 100 MB"
      exit 4
    else
      log "Max blob size of ${max_blob_size_mb} is under GitHub's hard limit of 100 MB"
    fi

    max_checkout_blob_size=$(echo "${size_json}" | python -c 'import json,sys; print(json.load(sys.stdin))["maxCheckoutBlobSize"]["value"]')
    max_checkout_blob_size_gb=$(echo "$max_checkout_blob_size / 1000000000" | bc -l | xargs -i printf "%'.1f GB" {})
    if (( $max_checkout_blob_size > 10000000000 )); then
      loge "Max checkout blob size of ${max_checkout_blob_size_gb} is over GitLab's repo size hard limit of 10 GB"
      exit 4
    else
      log "Max checkout blob size of ${max_checkout_blob_size_gb} is under GitLab's repo size hard limit of 10 GB"
    fi

#    This section is disabled because the relevance of the value is unclear.
#    unique_blob_size=$(echo "${size_json}" | python -c 'import json,sys; print(json.load(sys.stdin))["uniqueBlobSize"]["value"]')
#    unique_blob_size_gb=$(echo "$unique_blob_size / 1000000000" | bc -l | xargs -i printf "%'.1f GB" {})
#    if (( $max_checkout_blob_size > 10000000000 )); then
#      loge "Unique blob size of ${unique_blob_size_gb} is over GitLab's repo size hard limit of 10 GB"
#      exit 4
#    else
#      log "Unique blob size of ${unique_blob_size_gb} is under GitLab's repo size hard limit of 10 GB"
#    fi

    log "Checked sizes of git repo"
    ;;
  *)
   loge "Unknown command"
   exit 1
   ;;
esac
