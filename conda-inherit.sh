# Compatible with both bash and zsh

# Ensure flavor is set
if [[ -z "$flavor" ]]; then
  echo "Error: \$flavor not set. Set it to conda, mamba, or micromamba." >&2
  return 1
fi

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

  # Check if first argument is 'activate'
  if [[ \"\$1\" == \"activate\" ]]; then
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
    # Add current pane's new entry
    tmux setenv TMUX_SESSION_CONDA_ENVS \"\$TMUX_PANE:\$CONDA_DEFAULT_ENV\$CONDA_ENV_OTHER_PANES\"
  fi
}"

# Env variable set with the split-window or new-window keybind
if [[ -n "$TMUX_PARENT_PANE_ID" ]]; then
  if TMUX_SESSION_CONDA_ENVS=$(tmux showenv TMUX_SESSION_CONDA_ENVS 2>/dev/null); then
    # Strip prefix
    TMUX_SESSION_CONDA_ENVS="${TMUX_SESSION_CONDA_ENVS#TMUX_SESSION_CONDA_ENVS=}"

    # Clean up: remove entries for closed panes
    ACTIVE_PANES=$(tmux list-panes -s -F '#{pane_id}' | tr '\n' ' ')
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
    tmux setenv TMUX_SESSION_CONDA_ENVS "$TMUX_SESSION_CONDA_ENVS"

    # Find parent pane's conda environment
    PARENT_CONDA_ENV=""
    if [[ -n "$ZSH_VERSION" ]]; then
      for entry in ${=TMUX_SESSION_CONDA_ENVS}; do
        if [[ "${entry%%:*}" == "$TMUX_PARENT_PANE_ID" ]]; then
          PARENT_CONDA_ENV="${entry#*:}"
          break
        fi
      done
    else
      for entry in $TMUX_SESSION_CONDA_ENVS; do
        if [[ "${entry%%:*}" == "$TMUX_PARENT_PANE_ID" ]]; then
          PARENT_CONDA_ENV="${entry#*:}"
          break
        fi
      done
    fi
    if [[ -n "$PARENT_CONDA_ENV" ]]; then
      "$flavor" activate "$PARENT_CONDA_ENV"
    fi
  fi
  IFS="$OLD_IFS"
  unset TMUX_SESSION_CONDA_ENVS PARENT_CONDA_ENV TMUX_PARENT_PANE_ID entry ACTIVE_PANES CLEANED_ENVS pane_id OLD_IFS
fi
