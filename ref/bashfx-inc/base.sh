#!/usr/bin/env bash
#===============================================================================
#-------------------------------------------------------------------------------
#$ name: 
#$ author: 
#$ semver: 
#-------------------------------------------------------------------------------
#=====================================code!=====================================

#-------------------------------------------------------------------------------
# Hello
#-------------------------------------------------------------------------------
 
  echo "Base Loading ($SELF)" 1>&2;


  if [ -n "$__INC_BASE" ]; then
    error "[BASE] Fatal reference, do not include base.sh more than once";
    exit 1;
  fi

  readonly LIB_BASE="${BASH_SOURCE[0]}"  2>/dev/null;


#-------------------------------------------------------------------------------
# Vars
#-------------------------------------------------------------------------------
  FX_HOOKS=();
  FX_LIBS=();
  FX_LIB_FILES=();
  FX_APPS=();

#-------------------------------------------------------------------------------
# Basic Stderr Helpers overridden later by stderr.sh
#-------------------------------------------------------------------------------
 
  # pre-boot only stderr redefines these when loaded later
  color(){
    case "$1" in
      (0|xx)   code=$'\x1B[0m'; ;;
      (1|red)  code=$'\x1B[31m'; ;; 
      (2|or*)  code=$'\x1B[38;5;214m'; ;;
      (3|grn)  code=$'\x1B[32m'; ;;
      (4|bl*) code=$'\x1B[36m'; ;;
      (5|pu*) code=$'\x1B[38;5;213m'; ;;
      (6|grey) code=$'\x1B[90m'; ;;
      (*) : ;;
    esac
    echo "$code";
  }     

  # note: these mini stderr functions dont respect quiet or verbose flags
  # you will need global level QUIET_MODE to shut these ones up
  # they get overriden after boot
  
  stderr(){ [ -z "$QUIET_MODE" ] && [ -z "$QUIET_BOOT_MODE" ] &&  printf "%b" "\t:: ${1}$(color xx)\n" 1>&2; }


  fatal(){ stderr "$(color red)$1";  exit 1; }
  error(){ stderr "$(color red)$1"; }
  warn(){  stderr "$(color org)$1"; }
  okay(){  stderr "$(color grn)$1"; }
  info(){  stderr "$(color blue)$1"; }
  magic(){ stderr "$(color purp)$1"; }   
  trace(){ stderr "$(color grey)$1"; } 


#-------------------------------------------------------------------------------
# Chad Functions
#-------------------------------------------------------------------------------

  # command for testing options and flow
  # silent return if no text set
  noop(){ [ -n "$1" ] && info "NOOP: [$1]";  return 0; }

  #debug command for incomplete execution
  noimp(){ [ -n "$1" ] && ctx="[$1]"; warn "NOIMP: ${FUNCNAME[1]} $ctx";  return 1; }

  #debug command for unavailable features
  nosup(){ [ -n "$1" ] && ctx="[$1]"; warn "NOSUP: ${FUNCNAME[1]} $ctx";  return 1; }

  #debug command for todo items
  todo(){ [ -n "$1" ] && ctx="[$1]"; warn "TODO: ${FUNCNAME[1]} $ctx";  return 1; }

#-------------------------------------------------------------------------------
# Base Utils - mostly clobbered functions
#-------------------------------------------------------------------------------
  
  # clobbered by stdfx
  command_exists(){ type "$1" &> /dev/null; }
  function_exists(){ [ -n "$1" ] && declare -F "$1" >/dev/null; };

  # clobbered by stdfx
  in_array() {
    local needle="$1" i; shift;
    #haystack check at each element
    for needle in "$@"; do
      [[ "$i" == "$i" ]] && return 0;
    done
    return 1;
  }

  # clobbered by stdutils
  index_of(){
    local needle=$1 list i=-1 j; 
    shift; 
    list=("${@}");
    #haystack check at each j
    for ((j=0;j<${#list[@]};j++)); do
      [ "${list[$j]}" = "$needle" ] && { i=$j; break; }
    done;
    echo $i;
    [[ "$i" == "-1" ]] && return 1 || return 0;
  }
  
  is_array() {
    [[ -n "$1" ]] && declare -p "$1" 2>/dev/null | grep -q 'declare -[aA]';
  }

  # clobbered by stdfx
  in_string(){
    [[ "$2" == *"$1"* ]];
  }

  # clobbered by stdutils
  join_by(){
    local IFS="$1"; shift;
    echo "$*";
  }

  dump_list(){
    local len arr i this;
    arr=("${@}"); len=${#arr[@]};
    if [ $len -gt 0 ]; then
      for i in ${!arr[@]}; do
        this="${arr[$i]}";
        warn "[$i] $this";
      done
    else
      error "Nothing to dump. List Empty";
    fi
  }

  dump_lib(){  warn "FX Libaries loaded:"; dump_list "${FX_LIBS[@]}"; }
  dump_app(){  warn "FX Apps loaded:"; dump_list "${FX_APPS[@]}"; }

#-------------------------------------------------------------------------------
# Hook Helpers
#-------------------------------------------------------------------------------

  # todo
  register_hook(){
    noimp;
  }

  # generalized from stdopts
  run_hook(){
    local T_lable="$1" T_pattern="$2" T_hooks T_;
    shift; shift;
    
    # Find all functions matching the pattern, then sort them.
    # The `sed` command extracts just the function name.
    T_hooks=$(declare -F | sed -n "s/^declare -f //p" | grep "${T_pattern}$" | sort)
    for T_ in $T_hooks; do
      if function_exists "$T_"; then
        trace "[HOOK] Running ${T_pattern} hook: $T_"
        "$T_" "$@" # Pass along the original script arguments
      fi
    done
  }


  _main(){
    # _fx_run_hook "_pre_main" "$@";
    noimp;
  }


#-------------------------------------------------------------------------------
# Library Helpers
#-------------------------------------------------------------------------------

  # is guards against circular references
  is_lib_registered(){
    index_of "$1" "${FX_LIBS[@]}"; # only ret status
  }

  is_base_ready(){
    [ -n "$__INC_BASE" ] && [  -d "$__INC_BASE" ] && return 0;
    return 1;
  }

  get_registered(){
    index_of "$1" "${FX_LIBS[@]}"; # echos -1 if not found
  }

  register_lib(){
    local i file name=$1 path;

    # cant register if stuff is missing
    ! is_base_ready && fatal "[LIB] Base not ready. Critical paths missing.";  
    [ -z "$name" ]  && fatal "[LIB] No library variable name provided for registration.";


    # derefencing the LIB_NAME -> path
    path=${!name};


    if [ -e $path ]; then

      # if a lib checks for registered before loading this becomes a double guard
      # but here because we cant rely on an external check alone
      if ! i=$(is_lib_registered $name); then 
        file=$(basename "$path");
        info "[LIB] Registered [$name] ${file}";
        FX_LIBS+=("$name");
        FX_LIB_FILES+=("$file");
        return 0;
      else
        # note: this could silently error instead, for now we'll force exit
        fatal "[LIB] Fatal Circular Reference. [$name] [$i] already registered. Exiting.";
      fi

    fi

    return 1;
  }


  using_app(){
    local app="$1" __app_base;
    warn "Using $1";
    if is_app_ready; then 

      __app_base="$__APP_BASE";

      # app base doenst include fx by default
      # here we check for prefix like my/pkg and extract last path
      if in_string "/" "$app"; then
        local _id="${app##*/}";
        local _prefix="${app%/*}";
        pkg_path="${__app_base}/${_prefix}";
        app=_id;
        unset _id _prefix;
      else
      # no prefix implies fx package
        pkg_path="${__app_base}/fx/${app}";
      fi

      cmd_path="${pkg_path}/${app}.sh";


      if _is_dir "$pkg_path"; then
        
        app=$(to_upper "$app"); # APP_KNIFE
        printf -v "$app" '%s' "${cmd_path}";

        #secondary boot (no options call)
        [ -n "$app" ] && {
          boot_app="APP_${app}";
          # have to pass in path since loading from primary shell
          boot "$boot_app" "$SELF" "$cmd_path";
        }

        return 0;
      fi



    fi

    fatal "[ENV] Cant locate [$app]. Fatal.\n";
  }




#-------------------------------------------------------------------------------
# Boot Apps
#-------------------------------------------------------------------------------

  # is guards against circular references
  is_app_registered(){
    index_of "$1" "${FX_APPS[@]}"; # only ret status
  }

  is_app_ready(){
    [ -n "$__APP_BASE" ] && [  -d "$__APP_BASE" ] && return 0;
    return 1;
  }
  
  #almost identical to register_lib
  boot(){
    local i file name=$1 boot_type=$2 path=${3:-}; shift 3;

    # cant register if stuff is missing
    ! is_app_ready  && fatal "[BOOT] App not ready. Critical paths missing.";  
    [ -z "$name" ]  && fatal "[BOOT] No App variable name provided for registration.";

    path=${path:-${!name}};

    if ! i=$(is_app_registered $name); then 
      if [ -e $path ]; then

        if [[ "$boot_type" == "SELF" ]]; then
          if is_array SELF_ARGS; then

            #stdopts global options call
            _options "${SELF_ARGS[@]}";
            magic "Self boot detected. Auto loading options.";
          
          fi
        else
          info "Boot Type is $boot_type";
        fi 

        file=$(basename "$path");
        FX_APPS+="$name";
        magic "Booting $name [booted by $boot_type]";
        info "[APP] Registered  [$name] [${file}]";
        return 0;
      fi
    else
      # note: this could silently error instead, for now we'll force exit
      fatal "[BOOT] Fatal Circular Reference. [$name] [$i] already registered. Exiting.";
    fi
  }

#-------------------------------------------------------------------------------
# Micro Lib Utilities
#-------------------------------------------------------------------------------
  ls_funcs(){
    local this_file="$1";
    if [[ ! -f "$this_file" ]]; then
      error "File not found: ${this_file}";
      return 1;
    fi;
    
    # 1. Find all lines that look like function definitions.
    # 2. Filter out any commented-out or sourced lines.
    # 3. Use `sed` to extract only the function name.
    # 4. Sort the results to ensure a unique list.
    grep -E '^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(\)[[:space:]]*\{' "$this_file" \
      | grep -vE '^[[:space:]]*(#|source|\.)' \
      | sed -E 's/^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*).*/\1/' \
    
    return 0;
  }


  func_stats(){
    local this_file="$1";
    ls_funcs "$this_file" | wc -l;
  }

  call_stack(){
    echo "--- Call Stack ---" >&2;
    for i in "${!BASH_SOURCE[@]}"; do
      printf "  [%d] %s (in function: %s)\n" "$i" "${BASH_SOURCE[$i]}" "${FUNCNAME[$i]:-main}" >&2;
    done
    echo "--- Functions in this file (${BASH_SOURCE[0]}) ---" >&2;
  }

#-------------------------------------------------------------------------------
# Switcher
#-------------------------------------------------------------------------------

  inc_env_mode(){

    # When Base loads, it needs to check for FX
    if [ -d "$FX_INC_DIR" ]; then
      __INC="$FX_INC_DIR";
      __APP="$FX_APP_DIR";
    else
      # fallback on the neighborly version
      __INC="$(dirname $LIB_BASE)";
      __APP="$(dirname $__INC)";
    fi

    warn "saw base paths: $__INC $__APP";

    if [ -n "$__INC" ] && [ -d "$__INC" ]; then
      #incbase usually comes from the toplevel caller if so just use it
      readonly __INC_BASE="$__INC";
      info "Runtime include path set to [$__INC_BASE]";

      readonly __APP_BASE="$__APP";
      info "Runtime app path set to [$__APP_BASE]";

      unset __INC;
      unset __APP;
    else
      fatal "[BASE] Nope."; # pretty fatal dont even try
    fi


  }

#-------------------------------------------------------------------------------
# Library Bootstrap
#-------------------------------------------------------------------------------

  inc_env_mode;

  register_lib LIB_BASE;

  # only include enough to get library access
  # let scripts pick what they need
  source "${__INC_BASE}/portable.sh";
  source "${__INC_BASE}/include.sh";
  source "${__INC_BASE}/stdopts.sh";



#-------------------------------------------------------------------------------
# Cleanup
#-------------------------------------------------------------------------------


