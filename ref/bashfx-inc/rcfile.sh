#!/usr/bin/env bash
#===============================================================================
#-----------------------------><-----------------------------#
#$ name:templating
#$ author:qodeninja
#$ desc:
#-----------------------------><-----------------------------#
#=====================================code!=====================================

  echo "loaded rcfile.sh" >&2;

  # LOCAL_LIB_DIR="$(dirname ${BASH_SOURCE[0]})";
  # source "${LOCAL_LIB_DIR}/stderr.sh";


#-------------------------------------------------------------------------------
# Universal Link Functions
#-------------------------------------------------------------------------------

  get_this_rc_val(){
    local this=${!THIS_RC_VAR};
    if [ -n "$this" ]; then
      echo "$this";
      return 0;
    fi
    return 1;
  }

## HMM IS THIS BROKEN??

	save_rc_file(){
    local rc ret src=$1 dest=$2 lbl=$3; #src has embedded doc
    trace "save rc file args (src=$1) (dest=$2) (lbl=$3)";

    # Ensure directory exists
    mkdir -p "$(dirname "$dest")" || { error "Failed to create directory for rc file: $(dirname "$dest")"; return 1; }

    #MISSING -> SUPPOSED TO GET EMBEDDED DOC HERE BASED ON LABEL!

    if is_empty_file "$dest"; then
      warn "File is empty or whitespace only!";
      return 1;
    else
      okay "RC file created successfully: $dest";
    fi
    return 0;
	}


  set_rc_var() {
    local var_name="$1" var_value="$2"
    local rc_file="${FX_RC:-$(fx_get_rc_file)}" # Use FX_RC, fallback to fx_get_rc_file
    local temp_file="${rc_file}.tmp"
    local found=false

    if [ -z "$rc_file" ]; then
      error "RC file path not determined. Cannot set variable."
      return 1
    fi

    if [ ! -f "$rc_file" ]; then
      warn "RC file not found at $rc_file. Creating it."
      touch "$rc_file" || { error "Failed to create RC file."; return 1; }
    fi

    info "Setting $var_name=$var_value in $rc_file"

    # Read the file line by line, modifying if variable found
    while IFS= read -r line; do
      if [[ "$line" =~ ^export[[:space:]]+"$var_name"(=|$) ]]; then
        echo "export $var_name="$var_value"" >> "$temp_file"
        found=true
      else
        echo "$line" >> "$temp_file"
      fi
    done < "$rc_file"

    # If variable not found, append it
    if ! $found; then
      echo "export $var_name="$var_value"" >> "$temp_file"
    fi

    # Atomically replace the original file
    mv "$temp_file" "$rc_file" || { error "Failed to update RC file."; return 1; }
    okay "Variable $var_name set to $var_value in $rc_file."
    return 0
  }






#-------------------------------------------------------------------------------
# 
#-------------------------------------------------------------------------------


  get_this_rc_file(){
    local this=${!THIS_RC_VAR};
    [ -n "$this" ] && [ -f "$this" ] && { 
      echo "$this";
      return 0;
    }
    return 1;
  }

  
  del_this_rc_file(){
    local this=${!THIS_RC_VAR};

    if [ ! -z "$this" ]; then
      trace "[RC] rc file found $this, deleting...";
      [ -f "$this" ] && { rm "$this"; } || :
      # should have been removed. permission error?
      [ ! -f "$this" ] && { return 0; } || :
      return 1;
    fi
    
    warn "[RC] rc file not found...";
    return 0;
  }


	load_this_rc_file(){
    local this=${!THIS_RC_VAR};
    if [ -n "$this" ] && [ -f $this ]; then  # must pass 
      source "$this" --load-vars;
      return 0;
    fi
    return 1;
	}


  dump_this_rc_file(){
    local this=${!THIS_RC_VAR};
    if [ -f $this ]; then 
      local text="$(cat ${this}; printf '@@')";
      text="${text%@@}"
      __docbox "$text";
      return 0;
    else
      error "[RC] Cannot find [this] rcfile ($this). Nothing to dump.";
    fi
    return 1;
  }
