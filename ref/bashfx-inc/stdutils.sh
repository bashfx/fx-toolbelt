#!/usr/bin/env bash
#===============================================================================
#-------------------------------------------------------------------------------
#$ name: 
#$ author: 
#$ semver: 
#-------------------------------------------------------------------------------
#=====================================code!=====================================

  readonly LIB_STDUTILS="${BASH_SOURCE[0]}";


  _index=

#-------------------------------------------------------------------------------
# Load Guard
#-------------------------------------------------------------------------------

if ! _index=$(is_lib_registered "LIB_STDUTILS"); then 

  register_lib LIB_STDUTILS;



#-------------------------------------------------------------------------------
# Utils
#-------------------------------------------------------------------------------

# width=$(tput cols 2>/dev/null || echo 80);



  deref_var() {
    local __varname="$1"
    [[ "$__varname" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1;
    eval "printf '%s' \"\$${__varname}\"";
  }

  #update to take prefix as a paramter isntead of do_
  # do_inspect(){
  #   declare -F | grep 'do_' | awk '{print $3}'
  #   _content=$(sed -n -E "s/[[:space:]]+([^#)]+)\)[[:space:]]+cmd[[:space:]]*=[\'\"]([^\'\"]+)[\'\"].*/\1 \2/p" "$0")
  #   __printf "$LINE\n"
  #   while IFS= read -r row; do
  #     info "$row"
  #   done <<< "$_content"
  # }


################################################################################
#
#  __print_in_columns (Low-Ordinal Helper)
#
################################################################################
# Description: Reads a list from stdin and formats it into fixed-width columns.
# Arguments:
#   1: num_cols (integer) - The number of columns to print.
#   2: col_width (integer) - The width of each individual column.
# Returns: 0.
__print_in_columns() {
    local num_cols="$1";
    local col_width="$2";
    local -a items=();
    
    mapfile -t items

    local count=${#items[@]};
    if [[ $count -eq 0 ]]; then return 0; fi

    # THE FIX: Remove the explicit `\n` from the format string.
    # The `printf` in the loop will now only print the formatted row,
    # and the calling context (or the implicit newline from the command
    # substitution ending) will handle the line break.
    local format_string="";
    for ((i=0; i<num_cols; i++)); do
        format_string+="%-*s ";
    done;

    for ((i=0; i<count; i+=num_cols)); do
        local -a row_args=();
        for ((j=0; j<num_cols; j++)); do
            row_args+=("$col_width" "${items[i+j]:-}");
        done;
        # We add the newline here, outside the format string, for clarity and control.
        printf -- "${format_string}\n" "${row_args[@]}";
    done;
    return 0;
}




do_inspect(){
  info "Available Commands (from dispatch):";
  
  # The sed command here is a simplified version to extract just the command.
  # The final pipe to `pr` does the column formatting.
  sed -n '/dispatch()/,/esac/p' "$0" \
    | grep -oE '^\s*\(([^)]+)\)' \
    | sed 's/[()]/ /g' \
    | tr '|' '\n' \
    | awk '{$1=$1;print "  "$0}' \
    | sort -u \
    | __print_in_columns 4 20;

  line;
  
  info "Available Functions (by prefix):";
  declare -F \
    | awk '{print $3}' \
    | grep -E '^(do_|dev_|is_)' \
    | sed 's/^/  /' \
    | sort \
    | __print_in_columns 4 20;

  return 0;
}


  # Removes leading and trailing whitespace from a string and prints the result.
  trim_string() {
    local var="$*"
    # Remove leading whitespace characters
    var="${var#"${var%%[![:space:]]*}"}"
    # Remove trailing whitespace characters
    var="${var%"${var##*[![:space:]]}"}"
    printf '%s' "$var"
  }

  # in_array moved to base.sh
  
  is_empty_file(){
    local this=$1;
    trace "Checking for empty file ($this)";
    if [[ -s "$this" ]]; then
      if grep -q '[^[:space:]]' "$this"; then
        return 1;
      else
        return 0;
      fi
    fi
    return 0;
  }


  #ex  list2="$(join_by \| ${list[@]})"
  join_by(){
    local IFS="$1"; shift;
    echo "$*";
  }

  split_by(){
    local this on;
    this="$1";
    on="$2";
    array=(${this//$on/ })
    echo "${array[@]}"
  }

  has_subdirs(){
    local dir="$1"
    for d in "$dir"/*; do
      [ -d "$d" ] && return 0
    done
    return 1
  }

  # @note uses portable find
  sub_dirs(){
    local path=$1
    res=($($cmd_find "$path" -type d -printf '%P\n' ))
    echo "${res[*]}"
  }


  pop_array(){
    local match="$1"; shift
    local temp=()
    local array=($@)
    for val in "${array[@]}"; do
        [[ ! "$val" =~ "$match" ]] && temp+=($val)
    done
    array=("${temp[@]}")
    unset temp
    echo "${array[*]}"
  }

   requote(){
    whitespace="[[:space:]]"
    for i in "$@"; do
      if [[ $i =~ $whitespace ]]; then
        i=\"$i\"
      fi
      echo "$i"
    done
  }

   argsify(){
    local IFS ret key arg var prev
    prev="$IFS"; IFS='|'
    args=$(auto_escape "$*"); ret=$?

    case "${@}" in
      *\ * ) ret=0;;
      * ) arg="$1";;
    esac

    [ $ret -eq 0 ] && arg="'$*'" && trace "Args needs special love <3"

    trace "ARG is $arg"

    IFS=$prev
    echo "$arg"
  }

   auto_escape(){
    local str="$1"
    printf -v q_str '%q' "$str"
    if [[ "$str" != "$q_str" ]]; then
      ret=0
    else
      ret=1
    fi
    echo "$q_str"
    return $ret
  }



  # Compares two semantic version strings.
  # Usage: compare_versions "1.2.3" ">=" "1.2.0"
  # Handles standard operators: =, ==, !=, <, <=, >, >=
  compare_versions() {
      # Easy case: versions are identical
      if [[ "$1" == "$3" ]]; then
          case "$2" in
              '='|'=='|'>='|'<=') return 0 ;;
              *) return 1 ;;
          esac
      fi

      # Split versions into arrays using '.' as a delimiter
      local OLD_IFS="$IFS"
      IFS='.'
      local -a v1=($1) v2=($3)
      IFS="$OLD_IFS"

      # Find the longest version array to iterate through
      local i
      local len1=${#v1[@]}
      local len2=${#v2[@]}
      local max_len=$(( len1 > len2 ? len1 : len2 ))

      # Compare each component numerically
      for ((i = 0; i < max_len; i++)); do
          # Pad missing components with 0
          local c1=${v1[i]:-0}
          local c2=${v2[i]:-0}

          if (( c1 > c2 )); then
              case "$2" in '>'|'>='|'!=') return 0 ;; *) return 1 ;; esac
          fi
          if (( c1 < c2 )); then
              case "$2" in '<'|'<='|'!=') return 0 ;; *) return 1 ;; esac
          fi
      done

      # If we get here, they are equal component-by-component
      case "$2" in '='|'=='|'>='|'<=') return 0 ;; *) return 1 ;; esac
  }




#-------------------------------------------------------------------------------
# @is_array
#-------------------------------------------------------------------------------
	is_array(){
		identify;
		local var_name="$1"

		# An empty string is not a valid variable name.
		[[ -z "$var_name" ]] && return 1;

		# Use 'declare -p' to check the variable's attributes.
		# The regex looks for 'declare -a' (indexed) or 'declare -A' (associative).
		# We redirect stderr to hide the "not found" error from declare.
		[[ $(declare -p "$var_name" 2>/dev/null) =~ ^declare\ -[aA] ]] && return 0;
		return 1;
	}





#-------------------------------------------------------------------------------
# @array_len
#-------------------------------------------------------------------------------
	array_len(){
		identify;
		local var_name="$1";
		# Use our robust is_array function to validate.
		if ! is_array "$var_name"; then
				warn "'$var_name' is not an array. Cannot get length.";
				return 1;
		fi
		# Create a nameref to the actual array.
		local -n arr_ref="$var_name";
		# Echo the length.
		echo "${#arr_ref[@]}";
		return 0;
	}


#-------------------------------------------------------------------------------
# @is_empty_array
#-------------------------------------------------------------------------------
#-------------------------------------------------------------------------------
# @is_empty_array
#-------------------------------------------------------------------------------
	is_empty_array(){
		identify;
		local var_name="$1"

		# It can't be an empty array if it's not an array at all.
		! is_array "$var_name" && return 1;
		
		# Create a nameref to get the length.
		local -n arr_ref="$var_name"

		[[ ${#arr_ref[@]} -eq 0 ]] && return 0 # Is an empty array
		return 1;
	}




#-------------------------------------------------------------------------------
# @array_from_glob
#-------------------------------------------------------------------------------
# used mostly for globbing files in a directory
# usage:
# 		 | > declare -a my_array
# 		 | > array_from_glob "${DIR}/*.file" my_array

	array_from_glob() { 
		local glob_pattern="$1"; # The glob pattern as a string local -n 
		target_array="$2"; # Nameref to the array to be populated 
		# Use the glob pattern directly to populate the array 
		target_array=( $glob_pattern ); # Shell will expand $glob_pattern here
	}


#-------------------------------------------------------------------------------
# @stream_array
#-------------------------------------------------------------------------------
	# converts an array to a pipeable stream via namerefs
	# usage: 
	# 		 | > stream_array arr | filter
	stream_array() {
		# The first argument is the STRING NAME of the array.
		local array_name="$1";

		# --- VALIDATION (using the name) ---
		# First, check if the variable with this name is actually an array.
		# This check is performed on the NAME, not the content.
		if [[ ! "$(declare -p "$array_name" 2>/dev/null)" =~ ^declare\ -[aA] ]]; then
			error "Error: stream_array expects the name of an array as its argument." >&2;
			return 1;
		fi

		# --- PROCESSING (using the nameref) ---
		# Now that we know it's a valid array name, create the nameref for easy access.
		local -n arr_ref="$array_name";

		# Stream producer - this part was already correct.
		printf "%s\n" "${arr_ref[@]}";
	}


		#-------------------------------------------------------------------------------
# @array_diff
#-------------------------------------------------------------------------------
		# Calculates the set difference of two arrays (array1 - array2).
		# Usage: array_diff <array1_name> <array2_name> <result_array_name>
		array_diff(){
			local -n arr1=$1;
			local -n arr2=$2;
			local -n result=$3;

			local -A to_remove_map
			for item in "${arr2[@]}"; do
				if [[ -n "$item" ]]; then
					to_remove_map[$item]=1;
				fi
			done

			result=();
			for item in "${arr1[@]}"; do
				if [[ ! -v to_remove_map[$item] ]]; then
					result+=("$item");
				fi
			done
		}

#-------------------------------------------------------------------------------
# @filters - Stream Test Functions. Do not Delete.
#-------------------------------------------------------------------------------

	#-------------------------------------------------------------------------------
# @noop_filter
#-------------------------------------------------------------------------------
	noop_filter(){
		while IFS= read -r line; do
			echo "cat: $line";
		done
	}

	#-------------------------------------------------------------------------------
# @noop_cat_filter
#-------------------------------------------------------------------------------
	noop_cat_filter(){
		info "catting";
		cat
	}


  find_repos(){
    think "Finding repo folders..."
    warn "This may take a few seconds..."
    this="$cmd_find ${2:-.} -mindepth 1"
    [[ $1 =~ "1" ]] && this+=" -maxdepth 2" || :
    [[ $1 =~ git ]] && this+=" -name .git"  || :
    this+=" -type d ! -path ."
    awk_cmd="awk -F'.git' '{ sub (\"^./\", \"\", \$1); print \$1 }'"
    cmd="$this | $awk_cmd"
    __print "$cmd"
    eval "$cmd" #TODO:check if theres a better way to do this
  }



	super_substring_filter(){
			if [[ $# -eq 0 ]]; then cat; return 0; fi

			local -a includes=() excludes=() exact_include=() exact_exclude=()
			local ALL_MODE=1 found_match=false; # <--- 1. DECLARE FLAG

			for arg in "$@"; do
				case "$arg" in
					('!#'*) exact_exclude+=("${arg#!#}"); ;;
					('!'*)  excludes+=("${arg#!}");       ;;
					('#'*)  exact_include+=("${arg#\#}"); ;;
					('%'*)  includes+=("${arg#\%}");      ;;
					('*'*)  ALL_MODE=0;           ;; #include only
					(*) includes+=("${arg#\%}");  ;;
				esac
			done

			while IFS= read -r line; do

				if [ "$ALL_MODE" -eq 1 ]; then
					local is_excluded=false
					for p in "${exact_exclude[@]}"; do [[ "$line" == "$p" ]] && { is_excluded=true; break; }; done
					if ! "$is_excluded"; then
						for p in "${excludes[@]}"; do [[ "$line" == *"$p"* ]] && { is_excluded=true; break; }; done
					fi
					if "$is_excluded"; then continue; fi

					local is_included=false
					if (( ${#exact_include[@]} == 0 && ${#includes[@]} == 0 )); then
						is_included=true;
					else
						for p in "${exact_include[@]}"; do [[ "$line" == "$p" ]] && { is_included=true; break; }; done
						if ! "$is_included"; then
							for p in "${includes[@]}"; do [[ "$line" == *"$p"* ]] && { is_included=true; break; }; done
						fi
					fi
				else
					#include everyting
					is_included=true;
				fi


				if "$is_included"; then
					found_match=true # <--- 2. SET FLAG ON SUCCESS
					echo "$line"
				fi
			done

			# --- 3. FINAL CHECK ---
			if ! "$found_match"; then
				# error "Filter produced no matches." >&2
				return 1
			fi
	}

#-------------------------------------------------------------------------------
# @fruit - start a new basefile
#-------------------------------------------------------------------------------



	BASE_LIST=(apple banana cherry durian elder fig guava honeydew\
						imbe jackfruit kiwi lime mango orange pineapple\
						quince raspberry strawberry tangerine uglifruit\
						vanilla watermelon xigua yuzu zucchini);


	random_pick_array(){
		identify;
		# Use a nameref to refer to the array passed by name.
		local -n arr=$1

		# Handle the edge case of an empty array to prevent a division-by-zero error.
		if (( ${#arr[@]} == 0 )); then
				echo "Error: Array is empty." >&2
				return 1
		fi

		# Pick a random index from 0 to (size - 1) and echo the element.
		local pick="${arr[$((RANDOM % ${#arr[@]}))]}" #adds pid for unique
		
		[ -n "$pick" ] && pick="${pick}_$$";
		[ -z "$pick" ] && pick="book_$$";
		 echo "$pick";

		return 0;
	}

#-------------------------------------------------------------------------------
# Load Guard Error
#-------------------------------------------------------------------------------

else
  error "Library LIB_STDUTILS found at index [$_index]";
  return 1;
fi
