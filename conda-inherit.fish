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

    # Check if first argument is 'activate' or 'deactivate'
    if test \"\$argv[1]\" = \"activate\" -o \"\$argv[1]\" = \"deactivate\"
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
        # Add current pane's new entry (CONDA_DEFAULT_ENV might be empty after deactivate)
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
        set -l ACTIVE_PANES (tmux list-panes -s -F '#{pane_id}' 2>/dev/null)
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
        tmux setenv TMUX_SESSION_CONDA_ENVS "$TMUX_SESSION_CONDA_ENVS" 2>/dev/null

        # Find parent pane's conda environment
        set -l PARENT_CONDA_ENV ""
        set -l PARENT_ENV_FOUND 0
        for entry in (string split " " $TMUX_SESSION_CONDA_ENVS)
            if test -n "$entry"
                set -l pane_id (string split ":" $entry)[1]
                if test "$pane_id" = "$TMUX_PARENT_PANE_ID"
                    set PARENT_CONDA_ENV (string split ":" $entry)[2]
                    set PARENT_ENV_FOUND 1
                    break
                end
            end
        end

        # Handle parent environment inheritance
        if test $PARENT_ENV_FOUND -eq 1
            if test -n "$PARENT_CONDA_ENV" -a "$PARENT_CONDA_ENV" != "$CONDA_DEFAULT_ENV"
                # Parent has an env, activate it
                $flavor activate $PARENT_CONDA_ENV 2>/dev/null
            else if test -z "$PARENT_CONDA_ENV" -a -n "$CONDA_DEFAULT_ENV"
                # Parent has no env but we do, deactivate to match
                $flavor deactivate 2>/dev/null
            end
        end
    end
    set -e TMUX_PARENT_PANE_ID
else
    # No parent pane (first shell in tmux session) - respect auto_activate_base
    if test -z "$CONDA_DEFAULT_ENV"
        if $flavor config --show 2>/dev/null | grep -q "auto_activate_base: True\|auto_activate_base: true"
            $flavor activate base 2>/dev/null
        end
    end
end
