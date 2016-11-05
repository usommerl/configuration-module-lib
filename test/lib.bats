#!/usr/bin/env bats

load test_helper
load stub

setup() {
  make_testspace && cd $TESTSPACE
  cp $REPO_ROOT/lnkr_lib.sh .
  readonly LNKR_LIB_TEST=true
  source lnkr_lib.sh
}

teardown() {
  print_output
  rm_stubs
  rm_testspace
}

@test '__main should print help if no argument is provided' {
  run __main
  [ "${lines[0]}" = "SYNOPSIS: $(basename $0) [OPTION]" ]
  [ "$status" -eq 1 ]
}

@test '__main should print help if unknown argument is provided' {
  run __main --wrong-argument
  [ "${lines[0]}" = "SYNOPSIS: $(basename $0) [OPTION]" ]
  [ "$status" -eq 1 ]
}

@test '__main should print help when help switch is provided' {
  run __main --help
  [ "${lines[0]}" = "SYNOPSIS: $(basename $0) [OPTION]" ]
  [ "$status" -eq 0 ]
}

@test '__main should add library and journal files to gitignore' {
  run __main
  [ -f "$TESTSPACE/.gitignore" ]
  [ "$(cat $TESTSPACE/.gitignore | wc -l)" -eq 2 ]
  [ "$(grep 'lnkr_lib.sh' $TESTSPACE/.gitignore | wc -l)" -eq 1 ]
  [ "$(grep '.lnkr.journal' $TESTSPACE/.gitignore | wc -l)" -eq 1 ]
}

@test '__main should not add library multiple times to gitignore' {
  run __main
  run __main
  [ "$(wc -l $TESTSPACE/.gitignore | cut -d ' ' -f 1)" -eq 2 ]
  [ "$(grep 'lnkr_lib.sh' $TESTSPACE/.gitignore | wc -l)" -eq 1 ]
  [ "$(grep '.lnkr.journal' $TESTSPACE/.gitignore | wc -l)" -eq 1 ]
}

@test '__logger_base should print to STDOUT' {
  run info 'line1'
  [ $(echo "${lines[0]}" | grep 'info.*line1' | wc -l) -eq 1 ]
  run warn 'line2'
  [ $(echo "${lines[0]}" | grep 'warn.*line2' | wc -l) -eq 1 ]
  run fail 'line3'
  [ $(echo "${lines[0]}" | grep 'fail.*line3' | wc -l) -eq 1 ]
}

@test '__operation should fail if callback is not defined' {
  run __operation "test"
  [ "$status" -eq 1 ]
  [ $(echo "${lines[@]}" | grep 'fail.*__test.*not defined' | wc -l) -eq 1 ]
}

@test 'link should create backup if file exists in target location' {
  local timestamp='2016-08-09T2120:36+02:00'
  local linkname='link'
  local linkpath="$TESTSPACE/$linkname"
  touch $linkpath
  stub date $timestamp
  run link "$TESTSPACE/file" $linkname
  [ "$status" -eq 0 ]
  [ "$(ls -l1 ${linkpath}.backup-$timestamp)" ]
  [ -L $linkpath ]
}

@test 'link should fail if file with same name as backup file exists' {
  local timestamp='2016-08-09T2120:36+02:00'
  local linkname='link'
  local linkpath="$TESTSPACE/$linkname"
  local linktarget="$TESTSPACE/file"
  touch "$linkpath" "$linktarget" "$linkpath.backup-$timestamp"
  stub date $timestamp
  run link $linktarget $linkname
  [ "$status" -eq 1 ]
  [ $(echo "${lines[@]}" | grep "Could not create backup" | wc -l) -eq 1 ]
  [ ! -L $linkpath ]
}

@test 'link should create parent directories if they do not exist' {
  local linkname='link'
  local parent_dir="$TESTSPACE/does_not_exist"
  local linkpath="$parent_dir/$linkname"
  [ ! -e "$parent_dir" ]
  run link "$TESTSPACE/file" $linkpath
  [ -e "$parent_dir" ]
  [ -L $linkpath ]
}

@test 'link should warn about dead links' {
  local linkname='link'
  local linkpath="$TESTSPACE/$linkname"
  local linktarget="$TESTSPACE/file"
  run link $linktarget $linkname
  [ "$status" -eq 0 ]
  [ $(echo "${lines[0]}" | grep "dead link" | wc -l) -eq 1 ]
}

@test 'link should record link and backup in journal' {
  local ts='2016-08-09T21:20:36+02:00'
  local linkname='link'
  local id=$(id -un)
  touch "$TESTSPACE/$linkname"
  stub date $ts
  run link "$TESTSPACE/file" $linkname
  run cat $TESTSPACE/.lnkr.journal; 
  [ "${#lines[@]}" -eq 2 ]
  [ $(echo "${lines[0]}" | grep "$id.*BAK.*link.backup-$ts" | wc -l) -eq 1 ]
  [ $(echo "${lines[1]}" | grep "$id.*LNK.*file.*link" | wc -l) -eq 1 ]
}

@test 'sudo function should enable sudo mode for link function' {
  stub sudo 'Stub sudo command'
  SUDO_CMD="$BATS_TEST_DIRNAME/stub/sudo"
  local linkname='link'
  touch "$TESTSPACE/$linkname"
  run sudo link "$TESTSPACE/file" "$TESTSPACE/$linkname"
  [ "$status" -eq 0 ]
  [ $(echo "${lines[1]}" | grep "Stub sudo" | wc -l) -eq 1 ]
  [ $(echo "${lines[2]}" | grep "Create backup" | wc -l) -eq 1 ]
  [ $(echo "${lines[3]}" | grep "Stub sudo" | wc -l) -eq 1 ]
  [ $(echo "${lines[4]}" | grep "Stub sudo" | wc -l) -eq 1 ]
  [ $(echo "${lines[5]}" | grep "Create link" | wc -l) -eq 1 ]
}

@test 'sudo function should use sudo command for every argument other than link' {
  stub sudo 'Stub sudo command'
  SUDO_CMD="$BATS_TEST_DIRNAME/stub/sudo"
  run sudo random_command
  [ $(echo "${lines[@]}" | grep "Stub sudo" | wc -l) -eq 1 ]
  [ "$status" -eq 0 ]
}

@test 'sudo function should fail if sudo command is not available' {
  run sudo link target_location link_location
  [ "$status" -eq 1 ]
  [ $(echo "${lines[@]}" | grep 'sudo.*not available' | wc -l) -eq 1 ]
}

@test 'fail should abort script with exit code 1' {
  run fail 'ERROR'
  [ "$status" -eq 1 ]
}

@test 'setup_submodules should initialize submodules and modify push url' {
  repo_with_submodules
  run setup_submodules
  local submodule_dir=$(git submodule status | head -n 1 | cut -d ' ' -f 3)
  cd $submodule_dir
  [ "$(ls -1 . | wc -l)" -gt 0 ]
  [ "$(git remote -vv show | grep -e 'git@github.com.*(push)' | wc -l)" -eq 1 ]
}

@test 'setup_submodules should not modify push url if it is requested explicitly' {
  repo_with_submodules
  run setup_submodules 'KEEP_PUSH_URL'
  local submodule_dir=$(git submodule status | head -n 1 | cut -d ' ' -f 3)
  cd $submodule_dir
  [ "$(ls -1 . | wc -l)" -gt 0 ]
  [ "$(git remote -vv show | grep -e 'https://github.com.*(push)' | wc -l)" -eq 1 ]
}

@test '--install should fail if function install() is not defined' {
  run __main --install
  [ "$status" -eq 1 ]
  [ $(echo "${lines[@]}" | grep 'install.*not defined' | wc -l) -eq 1 ]
}

@test '--install should succeed if function install() is defined' {
  install() {
    printf 'fake install function\n'
  }
  run __main --install
  [ "$status" -eq 0 ]
  [ $(echo "${lines[@]}" | grep 'fake install' | wc -l) -eq 1 ]
}

@test '--install should fail if journal is not empty' {
  install() {
    link "$TESTSPACE/file" 'link'
  }
  touch "$TESTSPACE/file"
  run __main --install
  [ $(cat "$TESTSPACE/.lnkr.journal" | wc -l) -gt 0 ]
  run __main --install
  [ "$status" -eq 1 ]
  [ $(echo "${lines[@]}" | grep -i 'journal.*not empty' | wc -l) -eq 1 ]
}

@test '--remove should call pre and post hooks' {
  pre_remove_hook() {
    printf 'pre_remove\n'
  }
  post_remove_hook() {
    printf 'post_remove\n'
  }
  run __main --remove
  [ "$status" -eq 0 ]
  [ $(echo "${lines[@]}" | grep 'pre_remove.*post_remove' | wc -l) -eq 1 ]
}

@test '--remove should warn if journal is empty' {
  run __main --remove
  [ "$status" -eq 0 ]
  [ $(echo "${lines[@]}" | grep -i 'journal.*no entries' | wc -l) -eq 1 ]
}

@test '--remove should revert journal entries' {
  local linkname='link'
  printf 'file.orig\n' > "$TESTSPACE/$linkname"
  printf 'file.linked\n' > "$TESTSPACE/file"
  run link "$TESTSPACE/file" $linkname
  [ $(cat "$TESTSPACE/.lnkr.journal" | wc -l) -eq 2 ]
  run __main --remove
  [ "$status" -eq 0 ]
  [ $(grep 'file.orig' "$TESTSPACE/$linkname" | wc -l) -eq 1 ]
  [ $(cat "$TESTSPACE/.lnkr.journal" | wc -l) -eq 0 ]
}

@test '--remove should not remove new file at recorded link location' {
  local linkname='link'
  printf 'file.orig\n' > "$TESTSPACE/$linkname"
  printf 'file.linked\n' > "$TESTSPACE/file"
  run link "$TESTSPACE/file" $linkname
  rm "$TESTSPACE/$linkname" && printf 'file.new\n' > "$TESTSPACE/$linkname"
  run __main --remove
  [ "$status" -eq 0 ]
  [ $(grep 'file.new' "$TESTSPACE/$linkname" | wc -l) -eq 1 ]
  [ $(grep 'BAK' "$TESTSPACE/.lnkr.journal" | wc -l) -eq 1 ]
}

@test '--remove should not fail if backup was removed' {
  local linkname='link'
  printf 'file.orig\n' > "$TESTSPACE/$linkname"
  printf 'file.linked\n' > "$TESTSPACE/file"
  run link "$TESTSPACE/file" $linkname
  rm -v $TESTSPACE/$linkname.backup-*
  run __main --remove
  [ "$status" -eq 0 ]
  [ ! -f "$TESTSPACE/$linkname" ]
  [ $(echo "${lines[@]}" | grep -i 'backup.*does not exist' | wc -l) -eq 1 ]
  [ $(cat "$TESTSPACE/.lnkr.journal" | wc -l) -eq 0 ]
}

@test '--remove should not delete journal entry if link removal fails' {
  local linkname='link'
  printf 'file.linked\n' > "$TESTSPACE/file"
  run link "$TESTSPACE/file" $linkname
  stub rm "Unkown rm error" "1"
  run __main --remove
  [ "$status" -eq 0 ]
  [ -f "$TESTSPACE/$linkname" ]
  [ $(echo "${lines[@]}" | grep -i 'Unkown rm error' | wc -l) -eq 1 ]
  [ $(cat "$TESTSPACE/.lnkr.journal" | wc -l) -eq 1 ]
  [ $(grep 'LNK' "$TESTSPACE/.lnkr.journal" | wc -l) -eq 1 ]
}

@test '--remove should not delete journal entry if backup recreation fails' {
  local linkname='link'
  printf 'file.orig\n' > "$TESTSPACE/$linkname"
  printf 'file.linked\n' > "$TESTSPACE/file"
  run link "$TESTSPACE/file" $linkname
  stub mv "Unkown mv error" "1"
  run __main --remove
  [ "$status" -eq 0 ]
  [ ! -f "$TESTSPACE/$linkname" ]
  [ $(echo "${lines[@]}" | grep -i 'Unkown mv error' | wc -l) -eq 1 ]
  [ $(cat "$TESTSPACE/.lnkr.journal" | wc -l) -eq 1 ]
  [ $(grep 'BAK' "$TESTSPACE/.lnkr.journal" | wc -l) -eq 1 ]
}

