#!/usr/bin/env bash
#===============================================================================
#-----------------------------><-----------------------------#
#$ name:linker
#$ author:qodeninja
#$ desc:
#-----------------------------><-----------------------------#
#=====================================code!=====================================

  echo "loaded proflink.sh" >&2;

# note: fatal and other printer functions require stderr.sh

#-------------------------------------------------------------------------------
# Pathulate Profile
#-------------------------------------------------------------------------------

  # XDG_FX_HOME = HOME, but dont use HOME directly. Lets us virtualize base paths

  standard_profile(){
    local BASH_PROFILE;
    if [ -f "$XDG_FX_HOME/.profile" ]; then
      BASH_PROFILE="$XDG_FX_HOME/.profile";
    else
      BASH_PROFILE="$XDG_FX_HOME/.bash_profile";
    fi
    echo "$BASH_PROFILE"
  }

  # use canon when physical matters

  canonical_profile() {
    think "Checking canonical profile";

    local BASH_PROFILE LAST_BASH_PROFILE;

    BASH_PROFILE=$(standard_profile);

    if [ -L "$BASH_PROFILE" ]; then
      LAST_BASH_PROFILE="$BASH_PROFILE" #origin if linked
      if command -v realpath >/dev/null 2>&1; then
        trace "Realpathing BASH_PROFILE ($BASH_PROFILE)...";
        BASH_PROFILE=$(realpath --logical "$BASH_PROFILE");
      else
      
        # Fallback if realpath is not available (macOS, older systems).
        # This may not fully resolve symlinks in all cases, but it's better than nothing.
        warn "realpath not found. Profile path may not be fully resolved."
        # Use `readlink` if available as a slightly better alternative to just echoing
        command -v readlink >/dev/null 2>&1 && BASH_PROFILE=$(readlink "$BASH_PROFILE") || :


      fi
    fi
    echo "$BASH_PROFILE"
  }

#-------------------------------------------------------------------------------
# Universal Link Functions
#-------------------------------------------------------------------------------

  assert_profile_exists(){
    profile_exists && return 0;
    fatal "[LNK] Critical error, required profile ($prof). Profile not found.";
  }


  profile_exists(){
    think "Profile Exists or recover...";
    local prof=$FX_PROFILE;
    [ -z "$prof" ] || [ ! -f "$prof" ] && { 

      local this=$(standard_profile);
      if [ -n "$this" ] && [ -f "$this" ]; then
        recover "[LNK] FX_PROFILE not set, but standard profile found at [$this]";
        trace "Temporarily using standard profile...";
        export FX_PROFILE=$this;
        return 0
      fi

      warn "[LNK] Invalid profile ($prof). Profile not found.";
      return 1; 
    }
    return 0;
  }



  # does a grep check for src in profile
  has_profile_link(){
    think "Checking for link...";
    local res ret src=$1 prof=$FX_PROFILE _line;
    if profile_exists; then
      grep -qF "$_line" "$prof" && return 0;
    fi
    return 1;  #not fatal if profile doesnt exist
  }


  has_hot_profile_link(){
    think "Checking for hot link...";
    local res ret src=$1 prof=$FX_PROFILE _line;
    if has_profile_link && [ -f "$src" ]; then
      trace "Hot linked source found...";
      return 0;
    else
      warn "[LNK] Src file ($src) doesnt exist";
    fi
    return 1;  #not fatal if profile doesnt exist
  }



  # links src (rc) to profile
  set_profile_link(){
    local res ret src=$1 prof=$FX_PROFILE _line;

    # src must exist or linking it doesnt make sense
    [ -z "$src" ] || [ ! -f "$src" ] && { 
      error "[LNK] Invalid src ($src). File must exist in order to link.";
      return 1; 
    }

    if has_profile_link "$src"; then
      warn "[LNK] Profile already linked.";
      return 0;
    else
      if assert_profile_exists; then 
        _line="source \"$src\";"
        echo "$_line" >> "$prof"; #grep check from  has
        return 0;
      fi
    fi
    return 1;
  }



  # remove src (rc) from profile
  rem_profile_bak(){
    think "Remove profile link...";
    local res ret src=$1 prof=$(canonical_profile) _line;

    if has_profile_link "$src"; then
      trace "Attempting to remove link...";
      _line="source \"$src\";"
      sed -i.bak "\|^$_line\$|d" "$prof"; #we need canonical profile or symlink will break
      [ -f $prof.bak ] && rm "$prof.bak";
      return 0;
    fi

    return 1;
  }


#-------------------------------------------------------------------------------
# Dev Drivers 
#-------------------------------------------------------------------------------


  dev_dump_profile(){
    local prof=$(canonical_profile);
    trace "profile:$prof";
    res=$(cat $prof);
    __docbox "$res";
  }


#-------------------------------------------------------------------------------
# Use case 1 > fx.rc to profile
#-------------------------------------------------------------------------------

# @clean nuke unused linker code

	# link_profile_str(){
  #   trace "Getting embedded link.";
  #   local str ret;

  #   str=$(block_print "link:bashfx" "${SELF_PATH}");

  #   if [ ${#str} -gt 0 ]; then
  #     echo -e "$str"
  #   else 
  #     error "Problem reading embedded link";
  #     exit 1;
  #   fi
	# }


  # link_profile(){
  #   trace "Linking fx.rc to profile"
  #   local res ret src;
  #   src=$(canonical_profile);
  #   res=$(sed -n "/#### bashfx ####/,/########/p" "$src");

  #   if [ -z "$FX_RC" ] || [ ! -f "$FX_RC" ]; then
  #     error "Cannot update profile, missing fx.rc. ($FX_RC)"
  #     return 1
  #   fi

  #   [ -z "$res" ] && ret=1 || ret=0;

  #   if [ $ret -eq 1 ]; then

  #     data="$(link_profile_str)";
  #     printf "$data" >> "$src";

  #     okay "Bashfx FX(1) has been installed ...";
  #   else
  #     warn "fx.rc already linked to profile. Skipping.";
  #   fi
  # }


  # unlink_profile(){
  #   trace "Unlinking fx.rc from profile";
  #   local res ret src=$(canonical_profile);

  #   if grep -q "#### bashfx ####" "$src"; then
  #     #sed delete
  #     sed -i.bak "/#### bashfx ####/,/########/d" "$src"; ret=$?;
  #     rm -f "${src}.bak";
  #     okay "-> Bashfx FX(1) has been uninstalled ...";
  #   else
  #     warn "-> fx.rc was already unlinked.";
  #   fi

  # }

  # has_profile_link(){
  #   trace "Linking fx.rc to profile"
  #   local res ret src;
  #   src=$(canonical_profile);
  #   res=$(sed -n "/#### bashfx ####/,/########/p" "$src");
  #   [ -z "$res" ] && ret=1 || ret=0;
  #   return $ret;
  # }

