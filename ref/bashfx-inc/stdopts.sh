#!/usr/bin/env bash
#===============================================================================
#-------------------------------------------------------------------------------
#$ name: 
#$ author: 
#$ semver: 
#-------------------------------------------------------------------------------
#=====================================code!=====================================

#-------------------------------------------------------------------------------
# 
#-------------------------------------------------------------------------------

  readonly LIB_STDOPTS="${BASH_SOURCE[0]}";
  _index=

#-------------------------------------------------------------------------------
# Load Guard
#-------------------------------------------------------------------------------

if ! _index=$(is_lib_registered "LIB_STDOPTS"); then 

  register_lib LIB_STDOPTS;



#-------------------------------------------------------------------------------
# Utils
#-------------------------------------------------------------------------------
  
  # __debug_mode(){ [ -z "$opt_debug" ] && return 1; [ $opt_debug -eq 0 ] && return 0 || return 1; }
  # __quiet_mode(){ [ -z "$opt_quiet" ] && return 1; [ $opt_quiet -eq 0 ] && return 0 || return 1; }
  opt_debug=${opt_debug:-1};
  opt_quiet=${opt_quiet:-1};
  opt_trace=${opt_trace:-1};
  opt_silly=${opt_silly:-1};
  opt_yes=${opt_yes:-1};
  opt_dev=${opt_dev:-1};
  opt_flags=${opt_flags:-1};


#-------------------------------------------------------------------------------
# 
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# Option Hooks
#-------------------------------------------------------------------------------

  _fx_run_options_hook() {
    local pattern="$1"
    shift
    local hook_funcs
    
    # Find all functions matching the pattern, then sort them.
    # The `sed` command extracts just the function name.
    hook_funcs=$(declare -F | sed -n "s/^declare -f //p" | grep "${pattern}$" | sort)
    
    for func in $hook_funcs; do
      if function_exists "$func"; then
        trace "[HOOK] Running ${pattern} hook: $func"
        "$func" "$@" # Pass along the original script arguments
      fi
    done
  }


# @lbl options

  global_options(){
    noop;
  }

  local_options(){
    # Using local ensures these variables don't leak into the global scope.
    local err

    #these can be overwritten

    # Process arguments in a single loop for clarity and efficiency.
    for arg in "$@"; do
      trace "testing option arg $arg"
      case "$arg" in
        --yes|-y)           opt_yes=0;;
        --flag*|-F)         opt_flags=0;;
        --file*|-F)         opt_file=0; opt_file_arg="$arg";; # should be like --file=path
        --debug|-d)         opt_debug=0;;
        --tra*|-t)          opt_trace=0;;
        --sil*|--verb*|-V)  opt_silly=0;;
        --dev|-D)           opt_dev=0;;
        --quiet|-q)         opt_quiet=0;;
        -*)                 err="Invalid flag [$arg].";; # Capture unknown flags
      esac
    done



    # Apply hierarchical verbosity rules.
    # Higher levels of verbosity enable lower levels.
    [ "$opt_silly" -eq 0 ] && { opt_trace=0; opt_debug=0; }
    [ "$opt_trace" -eq 0 ] && { opt_debug=0; }
    [ "$opt_dev" -eq 0 ]   && { opt_debug=0; opt_flags=0; }

    # Final override: if quiet is on, it trumps all other verbosity.
    if [ "$opt_quiet" -eq 0 ]; then
      opt_debug=1; opt_trace=1; opt_silly=1;
    else
      noop;
      #warn "Quiet is $opt_quiet";
    fi

    #set any options errors

  }


  _options(){

    _fx_run_options_hook "_pre_options" "$@";
    global_options "${@}";
    local_options "${@}";
    _fx_run_options_hook "_post_options" "$@";
    # echo "${@}";    echo "trying options ($opt_debug) ($opt_trace) ($opt_silly) ($opt_yes)";
  }

#-------------------------------------------------------------------------------
# Load Guard Error
#-------------------------------------------------------------------------------

else

  error "Library LIB_STDOPTS found at index [$_index]";
  exit 1;

fi
