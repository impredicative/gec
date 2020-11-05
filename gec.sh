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

# Run repo-specific command
case "${CMD}" in
  create)
    GITUSER=$(${TOOL} config core.owner)
    echo "Creating repo ${REPO} in GitHub and GitLab."

    # Create GitHub repo
    # Ref: https://stackoverflow.com/a/64636218/
    echo
    read -s -p "GitHub token with access to 'repo' scope: " GITHUB_TOKEN
    echo -e "\nCreating repo ${REPO} in GitHub."
    curl -sS -f -X POST -o /dev/null \
      -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" \
      https://api.github.com/user/repos -d "{\"name\": \"${REPO}\", \"private\": true}"
    echo "Created repo ${REPO} in GitHub."

    # Create GitLab repo
    # Ref: https://stackoverflow.com/a/64656788/
    # This is optional as the repo is automatically created upon first push.
    echo
    read -s -p "GitLab token with access to 'api' scope: " GITLAB_TOKEN
    echo -e "\nCreating repo ${REPO} in GitLab."
    curl -sS -f -X POST -o /dev/null \
      -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" -H "Content-Type:application/json" \
      "https://gitlab.com/api/v4/projects" -d "{\"path\": \"${REPO}\", \"visibility\": \"private\"}"
    echo "Created repo ${REPO} in GitLab."

    echo -e "\nCreated repo ${REPO} in GitHub and GitLab."
      ;;
  clone)
    echo "Cloning and configuring repo ${REPO}."

    GITUSER=$(${TOOL} config core.owner)
    mkdir -p "${GITDIR}" && cd "$_"
    echo -e "\nCloning repo ${REPO} from GitHub."
    git clone -c http.postBuffer=2000000000 -c user.name=gec -c user.email=gec@users.noreply.git.com git@github.com:${GITUSER}/${REPO}.git .
    echo "Cloned repo ${REPO} from GitHub."
    git remote set-url --add origin git@gitlab.com:${GITUSER}/${REPO}.git
    echo -e "\nAdded GitLab URL for repo ${REPO}."

    echo -e "\nCloned and configured repo ${REPO}."
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
    ${TOOL} state "${REPO}" && echo
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
      echo "${TOOL}: Failed: $@" >&2
      exit 2
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
    echo "${REPO} (${MOUNT_STATE})"
    ;;
  status|info|?)
    ${TOOL} state "${REPO}" && echo
    cd "${GITDIR}"
    git status -bs
    mountpoint -q "${DECDIR}" && echo && findmnt -f "${DECDIR}" || :
    ;;
  log)
    ${TOOL} state "${REPO}" && echo
    cd "${GITDIR}"
    git log --color=always --decorate -10 | grep -v '^Author: '
    ;;
  du.git)
    ${TOOL} state "${REPO}" && echo
    set -x
    cd "${GITDIR}"
    du -h -c -d 1
    ;;
  du.enc)
    ${TOOL} state "${REPO}" && echo
    set -x
    cd "${ENCDIR}"
    du -h -c -d 1
    ;;
  du.dec)
    ${TOOL} state "${REPO}" && echo
    if mountpoint -q "${DECDIR}"; then
      set -x
      cd "${DECDIR}"
      du -h -c -d 1
    else
      echo "${TOOL}: Failed: $@" >&2
      exit 3
    fi
    ;;
  rm)
    if ! mountpoint "${DECDIR}"; then
      set -x
      rm -rfI "${DECDIR}"
      rm -rfI "${GITDIR}"
    else
      echo "${TOOL}: Failed: $@" >&2
      exit 3
    fi
    ;;
  del)
    GITUSER=$(${TOOL} config core.owner)
    echo "Deleting repo ${REPO} in GitHub and GitLab under user ${GITUSER}."

    # Delete GitHub repo
    # Ref: https://stackoverflow.com/a/30644156/
    echo
    read -s -p "GitHub token with access to 'delete_repo' scope: " GITHUB_TOKEN
    echo -e "\nDeleting repo ${REPO} in GitHub."
    curl -sS -f -X DELETE -o /dev/null \
      -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" \
      https://api.github.com/repos/${GITUSER}/${REPO}
    echo "Deleted repo ${REPO} in GitHub."

#    # Delete GitLab repo
    # Ref: https://stackoverflow.com/a/52132529/
    echo
    read -s -p "GitLab token with access to 'api' scope: " GITLAB_TOKEN
    echo -e "\nDeleting repo ${REPO} in GitLab."
    curl -sS -f -X DELETE -o /dev/null \
      -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" -H "Content-Type:application/json" \
      "https://gitlab.com/api/v4/projects/${GITUSER}%2F${REPO}"
    echo "Deleted repo ${REPO} in GitLab."

    echo -e "\nDeleted repo ${REPO} in GitHub and GitLab under user ${GITUSER}."
      ;;
  *)
   echo "${TOOL}: Unknown command: $@" >&2
   exit 1
   ;;
esac
