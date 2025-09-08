#!/usr/bin/env bash
#===============================================================================
#-------------------------------------------------------------------------------
#$ name: 
#$ author: 
#$ semver: 
#-------------------------------------------------------------------------------
#=====================================code!=====================================

  readonly LIB_PORTABLE="${BASH_SOURCE[0]}";
  _index=

#-------------------------------------------------------------------------------
# Load Guard
#-------------------------------------------------------------------------------

if ! _index=$(is_lib_registered "LIB_PORTABLE"); then 

  register_lib LIB_PORTABLE;

#-------------------------------------------------------------------------------
# Utils
#-------------------------------------------------------------------------------

  readonly BASH_MAJOR=${BASH_VERSINFO[0]};

  # ? basename file type which printf? read dirname cp mv chmod compgen unset unalias
  # sleep kill declare

  _known=( sed grep awk md5 realpath readlink
          find date column wc head tail cat  
          tree git tput fswatch rsync sort tr

         );

  cmd_wrapper() {
    local T_name="$1"
    local T_global="$2"
    local T_path=""

    if command -v "$T_name" >/dev/null 2>&1; then
      T_path=$(command -v "$T_name")
    fi
    eval "$T_global=\"$T_path\"" # Set the global variable
  }

  depends_on(){
    noimp;
  }

  check_type(){ noimp; }

  sed_test(){ noimp; }
  grep_test(){ noimp; }
  find_test(){ noimp; }



# A portable, safe replacement for 'sed -i'.
# Applies a sed script to a file by writing to a temp file and then replacing the original.
# Usage: __sed_in_place <sed_script> <target_file>
__sed_in_place() {
    local sed_script="$1"
    local target_file="$2"

    # Fail early if the target file doesn't exist or isn't writable
    if [[ ! -f "${target_file}" || ! -w "${target_file}" ]]; then
        __error "File not found or not writable: ${target_file}"
        return 1
    fi

    # Create a temporary file to hold the modified contents
    local tmp_file
    tmp_file=$(mktemp) || { __error "Failed to create temp file for in-place edit."; return 1; }

    # Apply the sed script, redirecting output to the temp file
    if ! sed "${sed_script}" "${target_file}" > "${tmp_file}"; then
        __error "sed command failed while processing ${target_file}"
        rm -f "${tmp_file}" # Clean up the temp file on failure
        return 1
    fi

    # Atomically replace the original file with the new one
    if ! mv "${tmp_file}" "${target_file}"; then
        __error "Failed to move temp file to overwrite ${target_file}"
        return 1
    fi

    return 0
}

#-------------------------------------------------------------------------------
# Load Guard Error
#-------------------------------------------------------------------------------

else
  dump_libs;
  error "Library LIB_PORTABLE already loaded [$_index]";
  exit 1;

fi
