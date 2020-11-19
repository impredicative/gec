#!/usr/bin/env bash
set -euo pipefail

# Define repo-agnostic vars
TOOL="$(basename "$0")"
TPUT_BOLD=$(tput bold)
TPUT_RED=$(tput setaf 1)
TPUT_GREEN=$(tput setaf 2)
TPUT_YELLOW=$(tput setaf 3)
TPUT_BLUE=$(tput setaf 4)
TPUT_MAGNETA=$(tput setaf 5)
TPUT_CYAN=$(tput setaf 6)
TPUT_WHITE=$(tput setaf 7)
TPUT_RESET=$(tput sgr0)

# Define repo-agnostic logging functions
logr () { echo "[${TOOL}] ${1}" ; }  # Log raw
log () { logr "${1}." ; }  # Log
logn () { echo; log "$1" ; }  # Log after newline
loge () { log "Error: $1" >&2 ; }  # Log error
logw () { log "warning: $1" >&2 ; }  # Log warning

# Define additional repo-agnostic vars
if [ "$#" -ge 1 ]; then
  CMD="$1"
else
   loge "Provide a command as a positional argument"
   exit 1
fi
CONFIGFILE="${HOME}/.gec"
_APPDIR="${HOME}/gec"
_GITDIR="${_APPDIR}/encrypted"
_DECDIR="${_APPDIR}/decrypted"
LS_FORMAT="all=${TPUT_CYAN}%4s${TPUT_RESET} enc=${TPUT_MAGNETA}${TPUT_BOLD}%4s${TPUT_RESET} .git=${TPUT_CYAN}${TPUT_BOLD}%4s${TPUT_RESET} %s ${TPUT_BLUE}${TPUT_BOLD}%s${TPUT_RESET}\n"

touch -a "${CONFIGFILE}"

# Define utility functions
_du_hs () {  # Disk usage for single match
  du -h -s "$@" | cut -f1
}
_du_hsc () {  # Total disk usage for single or multiple matches
  du -h -s -c "$@" | tail -1 | cut -f1
}
_du_hcd () {  # CD and disk usage for depth of 1
  cd "$1"
  du -h -c -d 1
}
_shell () {  # Shell into dir
  cd "$1"
  USER_SHELL=$(getent passwd $USER | cut -d : -f 7)
  $USER_SHELL
}

# Run repo-agnostic command
case "${CMD}" in
  config)
    shift
    git config -f "${CONFIGFILE}" "$@"
    exit
    ;;
  install)
    release=$(curl -sS -f -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/impredicative/gec/releases | jq -r .[0].tag_name)
    FILE="$0"
    wget -q https://raw.githubusercontent.com/impredicative/gec/${release}/gec.sh -O "${FILE}"
    chmod +x "${FILE}"
    log "Installed ${release} to ${FILE}"
    exit
    ;;
  lock)
    mkdir -p "${_GITDIR}"
    cd "${_GITDIR}"
    ls -1 | xargs -i ${TOOL} umount {}
    exit
    ;;
  ls|list)
    mkdir -p "${_GITDIR}"
    cd "${_GITDIR}"
    shift
    PATTERN=${@:-*}

    # Print individual state
    ls -1d ${PATTERN} | uniq | xargs -i ${TOOL} state {}

    # Print cumulative disk usage
    alldirs_size=$(_du_hsc ./${PATTERN})
    encdirs_size=$(_du_hsc ./${PATTERN}/fs)
    gitdirs_size=$(_du_hsc ./${PATTERN}/.git)
    printf "${LS_FORMAT}" ${alldirs_size} ${encdirs_size} ${gitdirs_size} "          " "(total)"
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
     loge "Failed to identify repo. Provide it as a positional argument or change to its directory"
     exit 1
     ;;
  esac
fi
GITDIR="${_GITDIR}/${REPO}"
ENCDIR="${GITDIR}/fs"
DECDIR="${_DECDIR}/${REPO}"

# Define repo-specific logging functions
logr () { echo "[${TOOL}:${REPO}] ${1}" ; }  # Log raw
logrn () { echo; logr "$1" ; }  # Log raw after newline
log () { logr "${1}." ; }  # Log
logn () { echo; log "$1" ; }  # Log after newline
loge () { log "Failed ${CMD}. $1" >&2 ; }  # Log error
logw () { log "warning: $1" >&2 ; }  # Log warning

# Validate repo name
# Ref: https://stackoverflow.com/a/59082561/ https://gitlab.com/gitlab-org/gitlab/-/issues/21661
repo_valid_pattern="^[a-zA-Z0-9_][a-zA-Z0-9_-]{0,99}$"
if ! [[ "$REPO" =~ $repo_valid_pattern ]]; then
    loge "Repo name must match pattern ${repo_valid_pattern} so as to ensure broad compatibility"
    exit 1
fi
repo_invalid_pattern="--"
if [[ "$REPO" =~ $repo_invalid_pattern ]]; then
    loge "Repo name must not match pattern ${repo_invalid_pattern} so as to ensure broad compatibility"
    exit 1
fi

# Run repo-specific command
case "${CMD}" in
  amend)
    COMMIT_MESSAGE="${3:?'Provide a commit message as a positional argument.'}"
    cd "${GITDIR}"

    log "Adding changes"
    git add -A
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
  check.git)
    cd ${GITDIR}
    log "Checking sizes of git repo"
    size_json=$(git-sizer -j --json-version 2 --no-progress)

    # Check approximation of largest file size
    max_blob_size=$(echo "${size_json}" | jq '.maxBlobSize.value')
    max_blob_size_fmt=$(numfmt --to=si $max_blob_size)
    if (( $max_blob_size > 100000000 ));then
      loge "Largest blob size of ${max_blob_size_fmt} is over GitHub's file size hard limit of 100M"
      exit 4
    else
      log "Largest blob size of ${max_blob_size_fmt} is not over GitHub's file size hard limit of 100M"
    fi

    # Check approximation of total repo size
    repo_size=$(echo "${size_json}" | jq '.uniqueBlobSize.value+.uniqueTreeSize.value+.uniqueCommitSize.value')
    repo_size_fmt=$(numfmt --to=si $repo_size)
    if (( $repo_size > 10000000000 )); then
      loge "Repo size of ${repo_size_fmt} is over GitLab's repo size hard limit of 10G"
      exit 4
    elif (( $repo_size > 5000000000 )); then
      logw "Repo size of ${repo_size_fmt} is over GitHub's repo size soft limit of 5G, but not over GitLab's repo size hard limit of 10G"
    else
      log "Repo size of ${repo_size_fmt} is not over GitHub's repo size soft limit of 5G"
    fi

    # Check commit size if pre-commit repo size was given
    if (( $# >= 3 )); then
      pre_commit_repo_size="${3}"
      commit_size=$((repo_size-pre_commit_repo_size))
      commit_size_fmt=$(numfmt --to=si $commit_size)
      if (( $commit_size > 2000000000 )); then
        loge "Commit size of ${commit_size_fmt} is over GitHub's push size hard limit of 2G"
        exit 4
      else
        log "Commit size of ${commit_size_fmt} is not over GitHub's push size hard limit of 2G"
      fi
    fi

    log "Checked sizes of git repo"
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
  commit)
    COMMIT_MESSAGE="${3:?'Provide a commit message as a positional argument.'}"
    cd "${GITDIR}"

    log "Adding changes"
    git add -A -v
    log "Added changes"

    if ! git diff-index --quiet @; then
      # Ref: https://stackoverflow.com/a/34093391/

      logr "Committing: ${COMMIT_MESSAGE}"
      pre_commit_repo_size=$(git-sizer -j --json-version 2 --no-progress | jq '.uniqueBlobSize.value+.uniqueTreeSize.value+.uniqueCommitSize.value')
      git commit -m "${COMMIT_MESSAGE}"
      logr "Committed: ${COMMIT_MESSAGE}"
      git log --color=always --decorate -1 | grep -v '^Author: '

      logn "Running git garbage collection as necessary"
      git gc --auto
      log "Ran git garbage collection as necessary"

      echo
      ${TOOL} check.git ${REPO} ${pre_commit_repo_size}

    else
      log "No changes to commit"
    fi
    ;;
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

    # Delete GitLab repo
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
  done)
    if mountpoint -q "${DECDIR}"; then
      ${TOOL} umount ${REPO}
    else
      log "Repo is unmounted"
    fi
    ${TOOL} send ${REPO} "${@:3}"
    ;;
  du)
    _du_hcd "${GITDIR}"
    ;;
  du.dec)
    if mountpoint -q "${DECDIR}"; then
      _du_hcd "${DECDIR}"
    else
      loge "Mount first"
      exit 3
    fi
    ;;
  du.enc)
    _du_hcd "${ENCDIR}"
    ;;
  gc)
    cd ${GITDIR}
    shift 2
    repo_size=$(_du_hs "${GITDIR}/.git")
    pack_size=$(_du_hs "${GITDIR}/.git/objects/pack")
    logr "Running git garbage collection having pre-gc sizes: .git=${repo_size} pack=${pack_size}"
    git gc "$@"
    repo_size=$(_du_hs "${GITDIR}/.git")
    pack_size=$(_du_hs "${GITDIR}/.git/objects/pack")
    logr "Ran git garbage collection having post-gc sizes: .git=${repo_size} pack=${pack_size}"
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
    gocryptfs -init "${ENCDIR}"
    mkdir -p "${DECDIR}"
    logn "Initialized encrypted filesystem"
    ;;
  log|logs)
    cd "${GITDIR}"
    git log --color=always --decorate -10 | grep -v '^Author: '
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
  pull)
    if ! mountpoint -q "${DECDIR}"; then
      cd "${GITDIR}"
      log "Pulling commits (fast-forward only)"
      git pull --ff-only origin
      log "Pulled commits (fast-forward only)"
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
  rename)
    old_name="${REPO}"
    new_name="${3:?'Provide a new repo name as a positional argument.'}"
    log "Renaming remotely and locally to ${new_name}"
    GITUSER=$(${TOOL} config core.owner)

    # Check if mounted
    if mountpoint -q "${DECDIR}"; then
      loge "Unmount first"
      exit 2
    fi

    # Rename GitHub repo
    # Ref: https://docs.github.com/en/free-pro-team@latest/rest/reference/repos#update-a-repository
    logn "Renaming repo in GitHub"
    read -s -p "GitHub token with access to 'repo' scope: " GITHUB_TOKEN
    echo
    curl -sS -f -X PATCH -o /dev/null \
      -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" \
      https://api.github.com/repos/${GITUSER}/${REPO} -d "{\"name\": \"${new_name}\"}"
    log "Renamed repo in GitHub"

    # Rename GitLab repo
    # Ref: https://docs.gitlab.com/ee/api/projects.html#edit-project
    logn "Renaming repo in GitLab"
    read -s -p "GitLab token with access to 'api' scope: " GITLAB_TOKEN
    echo
    curl -sS -f -X PUT -o /dev/null \
      -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" -H "Content-Type:application/json" \
      "https://gitlab.com/api/v4/projects/${GITUSER}%2F${REPO}" -d "{\"name\": \"${new_name}\", \"path\": \"${new_name}\"}"
    log "Renamed repo in GitLab"

    # Move decryption directory
    if [ -d "${DECDIR}" ]; then
      new_decdir=$(realpath -ms "${DECDIR}/../${new_name}")
      if [ ! -d "${new_decdir}" ]; then
        logn "Moving decryption directory"
        mv -v "${DECDIR}" "${new_decdir}"
        log "Moved decryption directory"
      else
        loge "Aborting because new decryption directory ${new_decdir} already exists"
        exit 5
      fi
    else
      logw "Decryption directory ${DECDIR} cannot be moved because it does not exist"
    fi

    # Move git directory
    if [ -d "${GITDIR}" ]; then
      new_gitdir=$(realpath -ms "${GITDIR}/../${new_name}")
      if [ ! -d "${new_gitdir}" ]; then
        logn "Moving git directory"
        mv -v "${GITDIR}" "${new_gitdir}"
        log "Moved git directory"
      else
        loge "Aborting because new git directory ${new_gitdir} already exists"
        exit 5
      fi
    else
      logw "Git directory ${GITDIR} cannot be moved because it does not exist"
    fi

    # Update origin URLs
    if [ -d "${new_gitdir}/.git" ]; then
      cd "${new_gitdir}"
      logrn "Updating origin URLs from:"
      git remote get-url --all origin | sed 's/^/  /'
      git remote set-url --delete origin git@github.com:${GITUSER}/${old_name}.git
      git remote set-url --add origin git@github.com:${GITUSER}/${new_name}.git
      git remote set-url --delete origin git@gitlab.com:${GITUSER}/${old_name}.git
      git remote set-url --add origin git@gitlab.com:${GITUSER}/${new_name}.git
      logr "Updated origin URLs to:"
      git remote get-url --all origin | sed 's/^/  /'
    else
      logw "Origin URLs cannot be updated because .git directory ${GITDIR} does not exist"
    fi

    logn "Renamed remotely and locally to ${new_name}"
    ;;
  rm)
    if mountpoint -q "${DECDIR}"; then
      ${TOOL} umount ${REPO}
      echo
    fi

    log "Interactively removing local directories"

    if [ -d "${DECDIR}" ]; then
      logn "Removing local decryption directory"
      rm -rfI "${DECDIR}"
      log "Removed local decryption directory"
    else
      logw "Decryption directory ${DECDIR} cannot be removed because it does not exist"
    fi

    if [ -d "${GITDIR}" ]; then
      logn "Removing local git directory"
      rm -rfI "${GITDIR}"
      log "Removed local git directory"
    else
      logw "Git directory ${GITDIR} cannot be removed because it does not exist"
    fi

    log "Interactively removed local directories"
    ;;
  send)
    ${TOOL} commit ${REPO} "${@:3}"
    echo
    ${TOOL} push ${REPO}
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
  state)
    # Get mount state
    if mountpoint -q "${DECDIR}"; then
      MOUNT_OPTION=$(findmnt -fn -o options "${DECDIR}" | cut -d, -f1)
      MOUNT_STATE="${TPUT_GREEN}${TPUT_BOLD}mounted ${MOUNT_OPTION}${TPUT_RESET}"
    else
      MOUNT_STATE="dismounted"
    fi

    # Measure disk usage
    ALLDIR_SIZE=$(_du_hs "${GITDIR}")
    ENCDIR_SIZE=$(_du_hs "${ENCDIR}")
    GITDIR_SIZE=$(_du_hs "${GITDIR}/.git")

    # Print state
    printf "${LS_FORMAT}" ${ALLDIR_SIZE} ${ENCDIR_SIZE} ${GITDIR_SIZE} "${MOUNT_STATE}" ${REPO}
    ;;
  status|info|?)
    ${TOOL} state ${REPO}
    cd "${GITDIR}"
    echo
    git status -bs
    mountpoint -q "${DECDIR}" && echo && findmnt -f "${DECDIR}" || :
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
  *)
   loge "Unknown command"
   exit 1
   ;;
esac
