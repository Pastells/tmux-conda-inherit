# Fish shell support for conda-inherit

# Ensure flavor is set
if not set -q flavor
    echo "Error: \$flavor not set. Set it to conda, mamba, or micromamba." >&2
    return 1
end

# Check if the flavor function exists
if not functions -q $flavor
    echo "Error: $flavor function not found. Is conda initialized?" >&2
    return 1
end

# Copy the original function
functions -c $flavor original_$flavor

# Define the wrapper function using eval for dynamic naming
eval "function $flavor --wraps=original_$flavor
    original_$flavor \$argv
    set -l CONDA_RTN_CODE \$status

    # Check if function execution was successful
    if test \$CONDA_RTN_CODE -ne 0
        return \$CONDA_RTN_CODE
    end

    # Check if first argument is 'activate'
    if test \"\$argv[1]\" = \"activate\"
        set -l TMUX_SESSION_CONDA_ENVS
        set -l CONDA_ENV_OTHER_PANES

        if set TMUX_SESSION_CONDA_ENVS (tmux showenv TMUX_SESSION_CONDA_ENVS 2>/dev/null)
            # Remove the prefix
            set TMUX_SESSION_CONDA_ENVS (string replace 'TMUX_SESSION_CONDA_ENVS=' '' \$TMUX_SESSION_CONDA_ENVS)
            # Rebuild list without current pane's old entry
            set -l CLEANED_ENVS
            for entry in (string split ' ' \$TMUX_SESSION_CONDA_ENVS)
                if test -n \"\$entry\"
                    set -l pane_id (string split ':' \$entry)[1]
                    if test \"\$pane_id\" != \"\$TMUX_PANE\"
                        set -a CLEANED_ENVS \$entry
                    end
                end
            end
            set CONDA_ENV_OTHER_PANES (string join ' ' \$CLEANED_ENVS)
        end
        # Add current pane's new entry
        if test -n \"\$CONDA_ENV_OTHER_PANES\"
            tmux setenv TMUX_SESSION_CONDA_ENVS \"\$TMUX_PANE:\$CONDA_DEFAULT_ENV \$CONDA_ENV_OTHER_PANES\"
        else
            tmux setenv TMUX_SESSION_CONDA_ENVS \"\$TMUX_PANE:\$CONDA_DEFAULT_ENV\"
        end
    end
end"

# Env variable set with the split-window or new-window keybind
if set -q TMUX_PARENT_PANE_ID
    if set TMUX_SESSION_CONDA_ENVS (tmux showenv TMUX_SESSION_CONDA_ENVS 2>/dev/null)
        # Strip prefix
        set TMUX_SESSION_CONDA_ENVS (string replace "TMUX_SESSION_CONDA_ENVS=" "" $TMUX_SESSION_CONDA_ENVS)

        # Clean up: remove entries for closed panes
        set -l ACTIVE_PANES (tmux list-panes -s -F '#{pane_id}')
        set -l CLEANED_ENVS
        for entry in (string split " " $TMUX_SESSION_CONDA_ENVS)
            if test -n "$entry"
                set -l pane_id (string split ":" $entry)[1]
                if contains -- $pane_id $ACTIVE_PANES
                    set -a CLEANED_ENVS $entry
                end
            end
        end
        set TMUX_SESSION_CONDA_ENVS (string join " " $CLEANED_ENVS)
        tmux setenv TMUX_SESSION_CONDA_ENVS "$TMUX_SESSION_CONDA_ENVS"

        # Find parent pane's conda environment
        set -l PARENT_CONDA_ENV ""
        for entry in (string split " " $TMUX_SESSION_CONDA_ENVS)
            if test -n "$entry"
                set -l pane_id (string split ":" $entry)[1]
                if test "$pane_id" = "$TMUX_PARENT_PANE_ID"
                    set PARENT_CONDA_ENV (string split ":" $entry)[2]
                    break
                end
            end
        end
        if test -n "$PARENT_CONDA_ENV"
            $flavor activate $PARENT_CONDA_ENV
        end
    end
    set -e TMUX_PARENT_PANE_ID
end
