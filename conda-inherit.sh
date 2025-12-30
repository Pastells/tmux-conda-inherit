# Compatible with both bash and zsh

# Ensure flavor is set
if [[ -z "$flavor" ]]; then
  echo "Error: \$flavor not set. Set it to conda, mamba, or micromamba." >&2
  return 1
fi

#############
# UV
#############

if [[ "$flavor" == "uv" ]]; then
    # On pane creation: inherit parent's VIRTUAL_ENV
    if [[ -n "$ZSH_VERSION" ]]; then
        for entry in ${=TMUX_SESSION_CONDA_ENVS}; do
            if [[ "${entry%%:*}" == "$TMUX_PARENT_PANE_ID" ]]; then
                parent_venv="${entry#*:}"
                if [[ -n "$parent_venv" && -f "$parent_venv/bin/activate" ]]; then
                    source "$parent_venv/bin/activate"
                fi
                break
            fi
        done
    else
        for entry in $TMUX_SESSION_CONDA_ENVS; do
            if [[ "${entry%%:*}" == "$TMUX_PARENT_PANE_ID" ]]; then
                parent_venv="${entry#*:}"
                if [[ -n "$parent_venv" && -f "$parent_venv/bin/activate" ]]; then
                    source "$parent_venv/bin/activate"
                fi
                break
            fi
        done
    fi


  # Record current pane's VIRTUAL_ENV
  if [[ -n "$TMUX" ]]; then
      current_env="${VIRTUAL_ENV:-}"
      tmux setenv TMUX_SESSION_CONDA_ENVS \
          "$(tmux showenv TMUX_SESSION_CONDA_ENVS 2>/dev/null | sed 's/^TMUX_SESSION_CONDA_ENVS=//' | sed "s|$TMUX_PANE:[^ ]*||") $TMUX_PANE:$current_env"
  fi

  return 0
fi


#############
# CONDA
#############

# Get function definition
flavor_definition=$(declare -f "$flavor")
if [[ -z "$flavor_definition" ]]; then
  echo "Error: $flavor function not found. Is conda initialized?" >&2
  return 1
fi

original_flavor_name="original_$flavor"

# Redefine the function by replacing its name with the new name
eval "${original_flavor_name}${flavor_definition#"$flavor"}"

# Function named with the value of $flavor
eval "$flavor() {
  $original_flavor_name \"\$@\"
  local CONDA_RTN_CODE=\$?
  local CONDA_DEFAULT_ENV_COPY=\"\$CONDA_DEFAULT_ENV\"

  # Check if function execution was successful
  if [[ \$CONDA_RTN_CODE -ne 0 ]]; then
    return \$CONDA_RTN_CODE
  fi

  # Check if first argument is 'activate' or 'deactivate'
  if [[ \"\$1\" == \"activate\" || \"\$1\" == \"deactivate\" ]]; then
    local TMUX_SESSION_CONDA_ENVS CONDA_ENV_OTHER_PANES entry
    CONDA_ENV_OTHER_PANES=\"\"
    if TMUX_SESSION_CONDA_ENVS=\$(tmux showenv TMUX_SESSION_CONDA_ENVS 2>/dev/null); then
      # Remove the prefix
      TMUX_SESSION_CONDA_ENVS=\"\${TMUX_SESSION_CONDA_ENVS#TMUX_SESSION_CONDA_ENVS=}\"
      # Rebuild list without current pane's old entry
      local IFS=' '
      if [[ -n \"\$ZSH_VERSION\" ]]; then
        for entry in \${=TMUX_SESSION_CONDA_ENVS}; do
          if [[ \"\${entry%%:*}\" != \"\$TMUX_PANE\" ]]; then
            CONDA_ENV_OTHER_PANES=\"\$CONDA_ENV_OTHER_PANES \$entry\"
          fi
        done
      else
        for entry in \$TMUX_SESSION_CONDA_ENVS; do
          if [[ \"\${entry%%:*}\" != \"\$TMUX_PANE\" ]]; then
            CONDA_ENV_OTHER_PANES=\"\$CONDA_ENV_OTHER_PANES \$entry\"
          fi
        done
      fi
    fi
    # Add current pane's new entry (CONDA_DEFAULT_ENV might be empty after deactivate)
    tmux setenv TMUX_SESSION_CONDA_ENVS \"\$TMUX_PANE:\$CONDA_DEFAULT_ENV\$CONDA_ENV_OTHER_PANES\"
  fi
}"

# Env variable set with the split-window or new-window keybind
if [[ -n "$TMUX_PARENT_PANE_ID" ]]; then
  PARENT_ENV_FOUND=0
  if TMUX_SESSION_CONDA_ENVS=$(tmux showenv TMUX_SESSION_CONDA_ENVS 2>/dev/null); then
    # Strip prefix
    TMUX_SESSION_CONDA_ENVS="${TMUX_SESSION_CONDA_ENVS#TMUX_SESSION_CONDA_ENVS=}"

    # Clean up: remove entries for closed panes
    ACTIVE_PANES=$(tmux list-panes -s -F '#{pane_id}' 2>/dev/null | tr '\n' ' ')
    CLEANED_ENVS=""
    OLD_IFS="$IFS"
    IFS=' '
    if [[ -n "$ZSH_VERSION" ]]; then
      for entry in ${=TMUX_SESSION_CONDA_ENVS}; do
        pane_id="${entry%%:*}"
        for active in ${=ACTIVE_PANES}; do
          if [[ "$pane_id" == "$active" ]]; then
            CLEANED_ENVS="$CLEANED_ENVS $entry"
            break
          fi
        done
      done
    else
      for entry in $TMUX_SESSION_CONDA_ENVS; do
        pane_id="${entry%%:*}"
        for active in $ACTIVE_PANES; do
          if [[ "$pane_id" == "$active" ]]; then
            CLEANED_ENVS="$CLEANED_ENVS $entry"
            break
          fi
        done
      done
    fi
    TMUX_SESSION_CONDA_ENVS="${CLEANED_ENVS# }"
    tmux setenv TMUX_SESSION_CONDA_ENVS "$TMUX_SESSION_CONDA_ENVS" 2>/dev/null

    # Find parent pane's conda environment
    PARENT_CONDA_ENV=""
    if [[ -n "$ZSH_VERSION" ]]; then
      for entry in ${=TMUX_SESSION_CONDA_ENVS}; do
        if [[ "${entry%%:*}" == "$TMUX_PARENT_PANE_ID" ]]; then
          PARENT_CONDA_ENV="${entry#*:}"
          PARENT_ENV_FOUND=1
          break
        fi
      done
    else
      for entry in $TMUX_SESSION_CONDA_ENVS; do
        if [[ "${entry%%:*}" == "$TMUX_PARENT_PANE_ID" ]]; then
          PARENT_CONDA_ENV="${entry#*:}"
          PARENT_ENV_FOUND=1
          break
        fi
      done
    fi

    # Handle parent environment inheritance
    if [[ $PARENT_ENV_FOUND -eq 1 ]]; then
      if [[ -n "$PARENT_CONDA_ENV" && "$PARENT_CONDA_ENV" != "$CONDA_DEFAULT_ENV" ]]; then
        # Parent has an env, activate it
        "$flavor" activate "$PARENT_CONDA_ENV" 2>/dev/null
      elif [[ -z "$PARENT_CONDA_ENV" && -n "$CONDA_DEFAULT_ENV" ]]; then
        # Parent has no env but we do, deactivate to match
        "$flavor" deactivate 2>/dev/null
      fi
    fi
    IFS="$OLD_IFS"
  fi
  unset TMUX_SESSION_CONDA_ENVS PARENT_CONDA_ENV TMUX_PARENT_PANE_ID entry ACTIVE_PANES CLEANED_ENVS pane_id OLD_IFS PARENT_ENV_FOUND
else
  # No parent pane (first shell in tmux session) - respect auto_activate_base
  if [[ -z "$CONDA_DEFAULT_ENV" ]]; then
    if "$flavor" config --show 2>/dev/null | grep -q "auto_activate_base: True\|auto_activate_base: true"; then
      "$flavor" activate base 2>/dev/null
    fi
  fi
fi
