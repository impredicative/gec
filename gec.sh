#!/usr/bin/env bash
set -euo pipefail  # Note the use of `set` elsewhere in the file.

# Define repo-agnostic vars
TOOL="$(basename "$0")"
TPUT_BOLD=$(tput bold)
TPUT_RED=$(tput setaf 1)
TPUT_GREEN=$(tput setaf 2)
TPUT_YELLOW=$(tput setaf 3)
TPUT_BLUE=$(tput setaf 4)
TPUT_MAGENTA=$(tput setaf 5)
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
_SOCKDIR="/run/user/${UID}/gec"
LS_FORMAT="all=${TPUT_CYAN}%4s${TPUT_RESET} enc=${TPUT_MAGENTA}${TPUT_BOLD}%4s${TPUT_RESET} .git=${TPUT_CYAN}${TPUT_BOLD}%4s${TPUT_RESET} %s ${TPUT_BLUE}${TPUT_BOLD}%s${TPUT_RESET}\n"

touch -a "${CONFIGFILE}"

# Define repo-agnostic utility functions
_contains () {  # Space-separated list $1 contains line $2. `grep -x` enforces an exact match.
  echo "$1" | tr ' ' '\n' | grep -F -x -q "$2"
}
_du_hs () {  # Disk usage for single match
  # Note: Using -h is avoided because it returns variable length output such as 1002M and 402M.
  du -B1 -s "$@" | cut -f1 | numfmt --to=si
}
_du_hsc () {  # Total disk usage for single or multiple matches
  # Note: Using -h is avoided because it returns variable length output such as 1002M and 402M.
  du -B1 -s -c "$@" | tail -1 | cut -f1 | numfmt --to=si
}
_du_hcd () {  # CD and disk usage for depth of 1
  cd "$1"
  du -h -c -d 1
}
_shell () {  # Shell into dir
  cd "$1"
  local user_shell=$(getent passwd $USER | cut -d : -f 7)
  $user_shell
}
min_num () {  # Min of numbers
  # Ref: https://stackoverflow.com/a/25268449/
  printf "%s\n" "$@" | sort -g | head -n1
}

# Run repo-agnostic command
case "${CMD}" in
  _list_commands)  # Used by completion script.
    echo "$(grep -Eo "^  [a-z\.]+[|)]" "$0" | tr -d ' |)')"
    exit
    ;;
  _list_repos)  # Used by completion script.
    if [ -d "$_GITDIR" ]; then
      ls -1 "$_GITDIR"
    fi
    exit
    ;;
  config)
    shift
    git config -f "${CONFIGFILE}" "$@"
    exit
    ;;
  install)
    if [ "$#" -ge 2 ]; then
      release="$2"
    else
      release=$(curl -sS -f -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/impredicative/gec/releases | jq -r .[0].tag_name)
    fi
    source_file="https://raw.githubusercontent.com/impredicative/gec/${release}/gec.sh"
    dest_file="$0"
    sudo wget -q "${source_file}" -O "${dest_file}"
    sudo chmod +x "${dest_file}"
    log "Installed ${release} from ${source_file} to ${dest_file}"

    # Install Bash completion script
    # Ref: https://serverfault.com/a/1013395/
    bash_completion_dir="${HOME}/.local/share/bash-completion/completions"
    mkdir -p "${bash_completion_dir}"
    bash_completion_file="${bash_completion_dir}/${TOOL}"
    wget -q https://raw.githubusercontent.com/impredicative/gec/${release}/completion.bash -O "${bash_completion_file}"
    log "Installed bash completion script for ${release} to ${bash_completion_file}"

    # Install Fish completion script
    fish_completion_dir="${HOME}/.config/fish/completions"
    mkdir -p "${fish_completion_dir}"
    fish_completion_file="${fish_completion_dir}/${TOOL}.fish"
    wget -q https://raw.githubusercontent.com/impredicative/gec/${release}/completion.fish -O "${fish_completion_file}"
    log "Installed fish completion script for ${release} to ${fish_completion_file}"

    exit
    ;;
  lock)
    mkdir -p "${_DECDIR}"
    log "Unmounting all mounted repos"
    if findmnt -t fuse.gocryptfs -n -o target | grep "^${_DECDIR}/" | xargs -i basename "{}" | xargs -i ${TOOL} umount {}; then
      # Note: grep returns nonzero exitcode if there are no matching lines. To force 0 exitcode, use { grep "^${_DECDIR}/" || :; }
      log "Unmounted all mounted repos"
    else
      log "No repo is mounted"
    fi
#    mkdir -p "${_GITDIR}"
#    cd "${_GITDIR}"
#    ls -1 | xargs -i ${TOOL} umount {}
    exit
    ;;
  ls|list)
    mkdir -p "${_GITDIR}"
    cd "${_GITDIR}"
    PATTERN=${2:-*}

    # Print individual state
    ls -1d ${PATTERN} | uniq | xargs -i ${TOOL} state {}

    # Print cumulative disk usage
    alldirs_size=$(_du_hsc ./${PATTERN})
    encdirs_size=$(_du_hsc ./${PATTERN}/fs)
    gitdirs_size=$(_du_hsc ./${PATTERN}/.git)
    printf "${LS_FORMAT}" ${alldirs_size} ${encdirs_size} ${gitdirs_size} "          " "(total)"
    exit
    ;;
  test.ssh)
    # Ref: https://stackoverflow.com/a/70585901/
    log "Testing SSH access to GitHub"
    set +e
    ssh -i ~/.ssh/id_gec -T git@github.com  # Expected exit status is 1.
    exit_status=$?
    set -e
    if [ ${exit_status} -ne 1 ] && [ ${exit_status} -ne 0 ]; then
      loge "GitHub SSH exit status was ${exit_status} but the expected status was 0 or 1"
      exit ${exit_status}
    fi
    log "GitHub SSH exit status was ${exit_status} as was expected"

    echo
    log "Testing SSH access to Bitbucket"
    set +e
    ssh -i ~/.ssh/id_gec -T git@bitbucket.org
    exit_status=$?
    set -e
    if [ ${exit_status} -ne 0 ]; then
      loge "Bitbucket SSH exit status was ${exit_status} but the expected status was 0"
      exit ${exit_status}
    fi
    log "Bitbucket SSH exit status was ${exit_status} as was expected"

    exit
    ;;
  test.token)
    read -p "GitHub token with access to 'repo' and 'delete_repo' scopes: " GITHUB_TOKEN
    logn "Testing token access to GitHub"
    # Ref: https://stackoverflow.com/a/70588035/
    authorized_scopes=$(curl -sS -f -I -H "Authorization: token ${GITHUB_TOKEN}" https://api.github.com | grep ^x-oauth-scopes: | cut -d' ' -f2- | tr -d "[:space:]" | sed 's/,/ /g')
    logr "GitHub token has access to the scopes: ${authorized_scopes}"
    for required_scope in repo delete_repo; do
      if _contains "${authorized_scopes}" "${required_scope}"; then
        log "GitHub token has access to the required '${required_scope}' scope"
      else
        loge "GitHub token does not have access to the required '${required_scope}' scope"
        exit 11
      fi
    done

    echo
    GITUSER=$(${TOOL} config core.owner)
    read -p "Bitbucket personal access token with access to 'repository:read', 'repository:admin' and 'repository:delete' scopes: " BITBUCKET_TOKEN
    logn "Testing token access to Bitbucket"
    # Ref: https://stackoverflow.com/a/73263692/
    authorized_scopes=$(curl -sS -f -I -u "${GITUSER}:${BITBUCKET_TOKEN}" https://api.bitbucket.org/ | grep ^x-oauth-scopes: | cut -d' ' -f2- | tr -d "[:space:]" | sed 's/,/ /g')
    logr "Bitbucket token has access to the scopes: ${authorized_scopes}"
    for required_scope in repository repository:admin repository:delete; do  # Note: 'repository:read' is returned by server as just 'repository'.
      if _contains "${authorized_scopes}" "${required_scope}"; then
        log "Bitbucket token has access to the required '${required_scope}' scope"
      else
        loge "Bitbucket token does not have access to the required '${required_scope}' scope"
        exit 11
      fi
    done

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
DOTGITDIR="${GITDIR}/.git"
ENCDIR="${GITDIR}/fs"
DECDIR="${_DECDIR}/${REPO}"
SOCKFILE="${_SOCKDIR}/${REPO}.socket"

# Define repo-specific logging functions
logr () { echo "[${TOOL}:${REPO}] ${1}" ; }  # Log raw
logrn () { echo; logr "$1" ; }  # Log raw after newline
log () { logr "${1}." ; }  # Log
logn () { echo; log "$1" ; }  # Log after newline
loge () { log "Failed ${CMD}. $1" >&2 ; }  # Log error
logw () { log "warning: $1" >&2 ; }  # Log warning

# Define repo-specific utility functions
_decrypt_paths () {  # Decrypted gocryptfs paths
  # Note: The input paths are over stdin, and must be relative to ENCDIR.
  cat - | grep -v '/gocryptfs.diriv$' | gocryptfs-xray -decrypt-paths "${SOCKFILE}" 2>&- || :
  # Note: "|| :" is used because gocryptfs-xray sometimes outputs: "errno 2: no such file or directory"
}

# Validate repo name
# Ref: https://stackoverflow.com/a/59082561/
repo_valid_pattern="^[a-zA-Z0-9_][a-zA-Z0-9_-]{0,99}$"
if [[ ! "$REPO" =~ $repo_valid_pattern ]]; then
    loge "Repo name must match pattern ${repo_valid_pattern} so as to ensure broad compatibility"
    exit 1
fi
repo_invalid_pattern="--"
if [[ "$REPO" =~ $repo_invalid_pattern ]]; then
    loge "Repo name must not match pattern ${repo_invalid_pattern} so as to ensure broad compatibility"
    exit 1
fi

# Validate repo existence
# Ref: https://stackoverflow.com/a/64945650/
mkdir -p "${_GITDIR}"
known_repos=$(ls -1 "${_GITDIR}")
if _contains "${known_repos}" "${REPO}"; then
  if _contains "clone init" "${CMD}"; then
    loge "Repo already exists locally"
    exit 1
  fi
else
  if ! _contains "clone create del init init.fs" "${CMD}"; then
    loge "Repo doesn't exist locally"
    exit 1
  fi
fi

# Run repo-specific command
case "${CMD}" in
  amend)
    cd "${GITDIR}"

    log "Adding changes"
    git add -A

    if ! git diff-index --quiet @; then
      log "Added changes"
      # Ref: https://stackoverflow.com/a/34093391/
      if [ "$#" -ge 3 ]; then
        COMMIT_MESSAGE="${3}"
        logr "Amending commit: ${COMMIT_MESSAGE}"
        git commit --amend -m "${COMMIT_MESSAGE}"
        logr "Amended commit: ${COMMIT_MESSAGE}"
      else
        COMMIT_MESSAGE=$(git log -1 --format=%s)
        logr "Amending commit: ${COMMIT_MESSAGE}"
        git commit --amend --no-edit
        logr "Amended commit: ${COMMIT_MESSAGE}"
      fi
      echo
      git log --color=always --decorate -1 | grep -v '^Author: '
    else
      log "No changes to amend"
    fi
    ;;
  check.dec)
    if ! mountpoint -q "${DECDIR}"; then
      loge "Mount first"
      exit 3
    fi
    cd ${DECDIR}
    log "Checking decrypted file sizes"
    large_files=$(find -type f -size +100000000c -exec ls -lh --si '{}' \;)
    if [[ "$large_files" != "" ]]; then
      loge "The decrypted files listed below exceed GitHub's file size hard limit of 100M"
      echo "${large_files}" >&2
      exit 4
    fi
    log "Decrypted files sizes are not over GitHub's hard limit of 100M"
    ;;
  check.git)
    cd ${GITDIR}
    log "Checking sizes of git repo"

    # Check for large files
    large_files=$(find ./fs -type f -size +100000000c -exec ls -lh --si '{}' \;)
    if [[ "$large_files" != "" ]]; then
      loge "The encrypted files listed below exceed GitHub's file size hard limit of 100M"
      echo "${large_files}" >&2
      logr "To list the decrypted analogs of the above files, run: ${TOOL} check.dec ${REPO}"
      exit 4
    else
      log "Encrypted files sizes are not over GitHub's hard limit of 100M"
    fi

    git_sizer_json=$(git-sizer -j --json-version 2 --no-progress)

#    # Check approximation of largest file size using git-sizer
#    max_blob_size=$(echo "${git_sizer_json}" | jq '.maxBlobSize.value')
#    max_blob_size_fmt=$(numfmt --to=si $max_blob_size)
#    if (( $max_blob_size > 100000000 )); then
#      loge "Largest blob size of ${max_blob_size_fmt} is over GitHub's file size hard limit of 100M"
#      exit 4
#    else
#      log "Largest blob size of ${max_blob_size_fmt} is not over GitHub's file size hard limit of 100M"
#    fi
#   Note: This check is disabled because it is obsoleted by the previous check for large files.

    # Check approximation of total repo size using git-sizer
    repo_size=$(echo "${git_sizer_json}" | jq '.uniqueBlobSize.value+.uniqueTreeSize.value+.uniqueCommitSize.value')
    repo_size_fmt=$(numfmt --to=si $repo_size)
    if (( $repo_size > 4000000000 )); then
      loge "Repo size of ${repo_size_fmt} is over Bitbucket's hard limit of 4G"
      exit 4
    else
      log "Repo size of ${repo_size_fmt} is not over Bitbucket's hard limit of 4G"
    fi

    # Check commit size using git-sizer if pre-commit repo size was given
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
    git clone -c http.postBuffer=2147483648 -c user.name=gec -c user.email=gec@users.noreply.git.com git@github.com:${GITUSER}/${REPO}.git .
    log "Cloned repo from GitHub"
    git remote set-url --add origin git@bitbucket.org:${GITUSER}/${REPO}.git
    logn "Added Bitbucket URL"

    logn "Cloned and configured repo"
    ;;
  commit)
    COMMIT_MESSAGE="${3:?'Provide a commit message as a positional argument.'}"
    cd "${GITDIR}"

    if mountpoint -q "${DECDIR}"; then
      ${TOOL} check.dec ${REPO}
      echo
    fi

    log "Adding changes"
    git add -A -v
    log "Added changes"

    if ! git diff-index --quiet @; then
      # Ref: https://stackoverflow.com/a/34093391/

      logn "Committing changes"
      pre_commit_repo_size=$(git-sizer -j --json-version 2 --no-progress | jq '.uniqueBlobSize.value+.uniqueTreeSize.value+.uniqueCommitSize.value')
      git commit -m "${COMMIT_MESSAGE}"
      git log --color=always --decorate -1 | grep -v '^Author: '
      log "Committed changes"

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
    log "Idempotently creating repo in GitHub and Bitbucket"

    # Idempotently create GitHub repo
    read -p "GitHub token with access to 'repo' scope: " GITHUB_TOKEN
    # Ref: https://docs.github.com/en/rest/repos/repos#get-a-repository
    if curl -s -f -o /dev/null -H "Accept: application/vnd.github+json" -H "Authorization: token ${GITHUB_TOKEN}" "https://api.github.com/repos/${GITUSER}/${REPO}"; then
      log "Repo already exists in GitHub"
    else
      # Create GitHub repo
      # Ref: https://stackoverflow.com/a/64636218/
      log "Creating repo in GitHub"
      curl -sS -f -X POST -o /dev/null \
        -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" \
        https://api.github.com/user/repos -d "{\"name\": \"${REPO}\", \"private\": true}"
      log "Created repo in GitHub"
    fi

    # Idempotently create Bitbucket repo
    read -p "Bitbucket token with access to 'repository:read' and 'repository:admin' scopes: " BITBUCKET_TOKEN
    # Ref: https://stackoverflow.com/a/73346422/
    if curl -s -f -o /dev/null -u "${GITUSER}:${BITBUCKET_TOKEN}" "https://api.bitbucket.org/2.0/repositories/${GITUSER}/${REPO}"; then
      log "Repo already exists in Bitbucket"
    else
      # Create Bitbucket repo
      # Ref: https://stackoverflow.com/a/38272918/
      log "Creating repo in Bitbucket"
      curl -sS -f -X POST -o /dev/null \
        -u "${GITUSER}:${BITBUCKET_TOKEN}" \
        -H "Content-Type: application/json" \
        "https://api.bitbucket.org/2.0/repositories/${GITUSER}/${REPO}" \
        -d '{"scm": "git", "is_private": "true", "fork_policy": "no_forks"}'
      log "Created repo in Bitbucket"
    fi

    logn "Idempotently created repo in GitHub and Bitbucket"
    ;;
  del)
    GITUSER=$(${TOOL} config core.owner)
    log "Deleting repo from GitHub and Bitbucket"

    # Delete GitHub repo
    # Ref: https://stackoverflow.com/a/30644156/
    logn "Deleting repo in GitHub"
    read -p "GitHub token with access to 'delete_repo' scope: " GITHUB_TOKEN
    curl -sS -f -X DELETE -o /dev/null \
      -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" \
      https://api.github.com/repos/${GITUSER}/${REPO}
    log "Deleted repo in GitHub"

    # Delete Bitbucket repo
    # Ref: https://stackoverflow.com/a/22391849/
    logn "Deleting repo from Bitbucket"
    read -p "Bitbucket token with access to 'repository:delete' scope: " BITBUCKET_TOKEN
    curl -sS -f -X DELETE -o /dev/null \
      -u "${GITUSER}:${BITBUCKET_TOKEN}" \
      "https://api.bitbucket.org/2.0/repositories/${GITUSER}/${REPO}"
    log "Deleted repo from Bitbucket"

    logn "Deleted repo from GitHub and Bitbucket"
    ;;
  destroy)
    ${TOOL} rm ${REPO}
    ${TOOL} del ${REPO}
    ;;
  done)
    if mountpoint -q "${DECDIR}"; then
        echo
        ${TOOL} check.dec ${REPO}
    fi
    echo
    ${TOOL} umount ${REPO}
    echo
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
    shift $(min_num 2 $#)
    repo_size=$(_du_hs "${DOTGITDIR}")
    pack_size=$(_du_hs "${DOTGITDIR}/objects/pack")
    logr "Running git garbage collection having pre-gc sizes: .git=${repo_size} pack=${pack_size}"
    git gc "$@"
    repo_size=$(_du_hs "${DOTGITDIR}")
    pack_size=$(_du_hs "${DOTGITDIR}/objects/pack")
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
    shift $(min_num 2 $#)
    git log --color=always --decorate -10 "$@" | grep -v '^Author: gec <gec@users.noreply.git.com>$'
    ;;
  mount|mount.rw)
    if mountpoint -q "${DECDIR}"; then
      MOUNT_OPTION=$(findmnt -fn -o options "${DECDIR}" | cut -d, -f1)
      if [ "${MOUNT_OPTION}" = "rw" ]; then
        log "Repo is mounted read-write"
      else
        log "Repo is mounted but not read-write"
        ${TOOL} umount ${REPO}
        ${TOOL} mount ${REPO}
      fi
    else
      mkdir -p "${DECDIR}"
      mkdir -p "${_SOCKDIR}"
      rm -f "${SOCKFILE}" # Workaround for https://github.com/rfjakob/gocryptfs/issues/634
      log "Mounting repo read-write"
      gocryptfs -nofail -sharedstorage -ctlsock "${SOCKFILE}" -rw "${ENCDIR}" "${DECDIR}"
      log "Mounted repo read-write"
    fi
    ;;
  mount.ro)
    if mountpoint -q "${DECDIR}"; then
      MOUNT_OPTION=$(findmnt -fn -o options "${DECDIR}" | cut -d, -f1)
      if [ "${MOUNT_OPTION}" = "ro" ]; then
        log "Repo is mounted read-only"
      else
        log "Repo is mounted but not read-only"
        ${TOOL} umount ${REPO}
        ${TOOL} mount.ro ${REPO}
      fi
    else
      mkdir -p "${DECDIR}"
      mkdir -p "${_SOCKDIR}"
      rm -f "${SOCKFILE}" # Workaround for https://github.com/rfjakob/gocryptfs/issues/634
      log "Mounting repo read-only"
      gocryptfs -nofail -sharedstorage -ctlsock "${SOCKFILE}" -ro "${ENCDIR}" "${DECDIR}"
      log "Mounted repo read-only"
    fi
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
    read -p "GitHub token with access to 'repo' scope: " GITHUB_TOKEN
    curl -sS -f -X PATCH -o /dev/null \
      -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" \
      https://api.github.com/repos/${GITUSER}/${REPO} -d "{\"name\": \"${new_name}\"}"
    log "Renamed repo in GitHub"

    # Rename Bitbucket repo
    # Ref: https://stackoverflow.com/a/14976945/
    logn "Renaming repo in Bitbucket"
    read -p "Bitbucket token with access to 'repository:admin' scope: " BITBUCKET_TOKEN
    curl -sS -f -X PUT -o /dev/null \
      -u "${GITUSER}:${BITBUCKET_TOKEN}" \
      -H "Content-Type:application/json" \
      "https://api.bitbucket.org/2.0/repositories/${GITUSER}/${REPO}" -d "{\"name\": \"${new_name}\"}"
    log "Renamed repo in Bitbucket"

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
    new_dotgitdir="${new_gitdir}/.git"
    if [ -d "${new_dotgitdir}" ]; then
      cd "${new_gitdir}"
      logrn "Updating origin URLs from:"
      git remote get-url --all origin | sed 's/^/  /'
      git remote set-url --delete origin git@github.com:${GITUSER}/${old_name}.git
      git remote set-url --add origin git@github.com:${GITUSER}/${new_name}.git
      git remote set-url --delete origin git@bitbucket.org:${GITUSER}/${old_name}.git
      git remote set-url --add origin git@bitbucket.org:${GITUSER}/${new_name}.git
      logr "Updated origin URLs to:"
      git remote get-url --all origin | sed 's/^/  /'
    else
      logw "Origin URLs cannot be updated because the .git directory ${new_dotgitdir} does not exist"
    fi

    logn "Renamed remotely and locally to ${new_name}"
    ;;
  reset.url)
    GITUSER=$(${TOOL} config core.owner)

    if [ -d "${DOTGITDIR}" ]; then
      cd "${GITDIR}"

      # Log old URLs
      logr "Resetting origin URLs from:"
      git remote get-url --all origin | sed 's/^/  /'
      old_urls=$(git remote get-url --all origin | tr '\n' ' ')
      expected_urls="git@github.com:${GITUSER}/${REPO}.git git@bitbucket.org:${GITUSER}/${REPO}.git"

      # Add missing URLs
      for expected_url in $expected_urls; do
        if ! _contains "${old_urls}" "${expected_url}"; then
          git remote set-url --add origin "${expected_url}"
          logr "Added origin URL: ${expected_url}"
        fi
      done
      
      # Remove extra URLs
      for old_url in $old_urls; do
        if ! _contains "${expected_urls}" ${old_url}; then
          git remote set-url --delete origin "${old_url}"
          logr "Removed origin URL: ${old_url}"
        fi
      done

      # Log new URLs
      new_urls=$(git remote get-url --all origin | tr '\n' ' ')
      if [ "${old_urls}" = "${new_urls}" ]; then
        log "Origin URLs remain unchanged"
      else
        logr "Reset origin URLs to:"
        git remote get-url --all origin | sed 's/^/  /'
      fi
      
    else
      logw "Origin URLs cannot be reset because the .git directory ${DOTGITDIR} does not exist"
    fi
    ;;
  rm)
    if mountpoint -q "${DECDIR}"; then
      ${TOOL} umount ${REPO}
      echo
    fi

    log "Interactively removing local directories"

    if [ -d "${DECDIR}" ]; then
      logrn "Removing local decryption directory: ${DECDIR}"
      rm -rfI "${DECDIR}"
      logr "Removed local decryption directory: ${DECDIR}"
    else
      logw "Decryption directory ${DECDIR} cannot be removed because it does not exist"
    fi

    if [ -d "${DOTGITDIR}" ]; then
      logrn "Removing local .git directory: ${DOTGITDIR}"
      rm -rf "${DOTGITDIR}"
      # Note: -I is not used above to prevent numerous prompts of: "rm: remove write-protected regular file"
      logr "Removed local .git directory: ${DOTGITDIR}"
    else
      logw ".git directory ${DOTGITDIR} cannot be removed because it does not exist"
    fi

    if [ -d "${GITDIR}" ]; then
      logrn "Removing local git repo directory: ${GITDIR}"
      rm -rfI "${GITDIR}"
      logr "Removed local git repo directory: ${GITDIR}"
    else
      logw "Git repo directory ${GITDIR} cannot be removed because it does not exist"
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
    DOTGITDIR_SIZE=$(_du_hs "${DOTGITDIR}")

    # Print state
    printf "${LS_FORMAT}" ${ALLDIR_SIZE} ${ENCDIR_SIZE} ${DOTGITDIR_SIZE} "${MOUNT_STATE}" ${REPO}
    ;;
  status|info)
    ${TOOL} state ${REPO}
    echo
    cd "${GITDIR}"
    git status -bs
    mkdir -p "${DECDIR}"
    if mountpoint -q "${DECDIR}"; then
      cd "${ENCDIR}"
      if [[ $(git ls-files -dmo) != "" ]]; then
        echo
        git ls-files -d | _decrypt_paths | sed "s/^/[${TPUT_RED}del${TPUT_RESET}] /"
        git ls-files -m | _decrypt_paths | sed "s/^/[${TPUT_CYAN}mod${TPUT_RESET}] /"
        git ls-files -o | _decrypt_paths | sed "s/^/[${TPUT_GREEN}new${TPUT_RESET}] /"
      fi
      echo
      findmnt -f "${DECDIR}" || :
    fi
    ;;
  umount|unmount|dismount)
    if mountpoint -q "${DECDIR}" || [ "${3:-''}" = "-f" ]; then
#      log "Unmounting repo"
      fusermount -u "${DECDIR}"
      log "Unmounted repo"
    else
      log "Repo is unmounted"
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
   loge "Invalid command"
   exit 1
   ;;
esac
