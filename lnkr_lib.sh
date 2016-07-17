#!/usr/bin/env bash

set -e
declare -r REPO_NAME=$(basename $(git rev-parse --show-toplevel))
declare -r LOGFILE=$SCRIPT_DIRECTORY/lnkr.log
declare -r INSTALL_SWITCH_SHORT='-i'
declare -r INSTALL_SWITCH_LONG='--install'
declare -r REMOVE_SWITCH_SHORT='-r'
declare -r REMOVE_SWITCH_LONG='--remove'

info() {
  echo -e "[info] $@"
}

warn() {
  echo -e "\e[1;33m[warn]\e[0m $@"
}

fail() {
  echo -e "\e[1;31m[fail]\e[0m $@ Aborting." >&2
  exit 1
}

lnk() {
  local target=$1
  local linkname=$2
  if [[ -e $linkname ]]; then
    local backup_location="${linkname}.backup-$(timestamp)"
    warn "File ${linkname} exists. Creating backup..."
    if [[ -e $backup_location ]]; then
      fail "Could not create backup"
    fi
    warn "mv -n  $(mv -vn $linkname $backup_location)"
		echo -e "$(timestamp_and_uid)BAK$(pad)$backup_location" >> "$LOGFILE"
  fi

  mkdir -p $(dirname "$linkname")
  info "ln -sf $(ln -vsfT $target $linkname)"
	echo -e "$(timestamp_and_uid)LNK$(pad)$target$(pad)$linkname" >> "$LOGFILE"
}

setup_submodules() {
  init_and_update_submodules
  modify_submodules_push_url
}

init_and_update_submodules() {
  info "Initialize and update all submodules"
  git submodule update --init
}

modify_submodules_push_url() {
  info 'Modify push-url of all submodules from github.com (Use SSH instead of HTTPS)'
  git submodule foreach '
  pattern="^.*https:\/\/(github.com)\/(.*\.git).*"
  orgURL=$(git remote -v show | grep origin | grep push)
  newURL=$(echo $orgURL | sed -r "/$pattern/{s/$pattern/git@\1:\2/;q0}; /$pattern/!{q1}")
  if [ "$?" -eq 0 ]; then
    command="git remote set-url --push origin $newURL"
    echo "$command"
    $($command)
  fi
  '
}

restore_entry() {
  local backup_location=$1
  local original_location=$(echo $backup_location | sed 's/\.backup.*$//')

  info "Recorded backup location is ${backup_location}"
  if [[ -e $backup_location ]] && ! [[ -L $backup_location ]]; then
    if [[ -L $original_location ]]; then
      rm $original_location
    fi
    if [[ -e $original_location ]]; then
      fail "Could not move backup to ${original_location}"
    else
      # Look for a different solution
      info "mv -n $(mv -nv $backup_location $original_location)"
      local pattern=$(echo $backup_location | sed -r 's/(.*)(backup.*$)/\2/')
      sed -i "/${pattern}/d" "$LOGFILE"
    fi
  else
    fail 'Backup location does not exist'
  fi
}

default_remove_procedure() {
  #if ! [[ -e $LOGFILE ]]; then
  #touch $LOGFILE
  #fi
  local log_contained_lines=false
  while read -r e; do
    restore_entry $e
    log_contained_lines=true
  done < $LOGFILE
  if ! $log_contained_lines; then
    info 'Log file is empty. There are no backups to restore.'
  fi
}

print_divider() {
  echo -e "------ \e[1;37m${REPO_NAME} $@\e[0m"
}

timestamp() {
  echo "$(date --iso-8601=s)"
}

pad() {
  echo -e "\t\0"
}

timestamp_and_uid() {
  echo -e "$(timestamp)$(pad)$(id -u)$(pad)"
}

remove() {
  print_divider 'Remove'
  if declare -F restore_hook &> /dev/null; then
      restore_hook
  else
      default_remove_procedure
  fi
  print_divider
}

install() {
  print_divider 'Install'
  if declare -F install_hook &> /dev/null; then
    install_hook
  else
    fail 'Function install_hook() is not defined'
  fi
  print_divider
}


print_help() {
  local script_name=$(basename $0)
  local indent_option='  '
  local indent='      '
  echo ""
  echo -e "SYNOPSIS: ${script_name} [OPTION]\n"
  echo -e "${indent_option} ${INSTALL_SWITCH_SHORT}, ${INSTALL_SWITCH_LONG}\n"
  echo -e "${indent} Executes the install procedure defined in install_hook."
  echo -e "${indent} Symbolic links that are created with lnk and su_lnk won't"
  echo -e "${indent} overwrite existing files. These functions create backups"
  echo -e "${indent} that will be restored automatically if you run this script"
  echo -e "${indent} with the ${REMOVE_SWITCH_LONG} option."
  echo ""
  echo -e "${indent_option} ${REMOVE_SWITCH_SHORT}, ${REMOVE_SWITCH_LONG}\n"
  echo -e "${indent} Removes created links and restores all backups that where"
  echo -e "${indent} made during a previous install."
  echo ""
}

main() {
  case "$1" in
    $REMOVE_SWITCH_SHORT | $REMOVE_SWITCH_LONG)
      remove
      ;;
    $INSTALL_SWITCH_SHORT | $INSTALL_SWITCH_LONG)
      install
      ;;
    *)
      print_help
      ;;
  esac
}

main "$@"
exit 0
