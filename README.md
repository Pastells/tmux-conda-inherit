# conda-inherit

Automatically inherit conda/mamba/micromamba environments when creating new tmux panes or windows.

## Description

When you split a tmux pane, your conda environment resets to `base`.  
This plugin fixes that by automatically activating the parent pane's environment in new panes and windows.  
No manual activation needed!

**Features:**
- Automatic environment inheritance from parent panes
- Works with conda, mamba, and micromamba
- Supports bash, zsh, and fish
- Automatic cleanup of closed panes
- Lightweight with minimal performance impact

## Requirements

- [tmux](https://github.com/tmux/tmux) >= 3.0
- [tpm](https://github.com/tmux-plugins/tpm) (Tmux Plugin Manager)
- [bash](https://www.gnu.org/software/bash/), [zsh](https://zsh.sourceforge.io), or [fish](https://fishshell.com)
- [conda](https://github.com/conda/conda)/[mamba](https://github.com/mamba-org/mamba)/[micromamba](https://github.com/mamba-org/micromamba-releases) (Initialized in your shell)

## Installation

### tmux configuration

Add to `~/.config/tmux/tmux.conf` or `~/.tmux.conf`:

```tmux
# Install plugin via TPM
set -g @plugin 'oluevaera/tmux-conda-inherit'
```

```tmux
# Add -e "TMUX_PARENT_PANE_ID=#{pane_id}" to your window split/new keybinds
bind '%' run 'tmux split-window -c "#{pane_current_path}" -e "TMUX_PARENT_PANE_ID=#{pane_id}" -h'
bind '"' run 'tmux split-window -c "#{pane_current_path}" -e "TMUX_PARENT_PANE_ID=#{pane_id}" -v'
bind c run 'tmux new-window -c "#{pane_current_path}" -e "TMUX_PARENT_PANE_ID=#{pane_id}"'
```

### Shell configuration

Add **after** conda initialization block:

**Bash/Zsh** (`~/.bashrc` or `~/.zshrc`):
```bash
if [[ -n "$TMUX" ]]; then
  export flavor='micromamba'  # Change to 'conda' or 'mamba' if needed
  source ~/.config/tmux/plugins/conda-inherit/conda-inherit.sh
fi
```

**Fish** (`~/.config/fish/config.fish`):
```fish
if set -q TMUX
    set -g flavor micromamba  # Change to 'conda' or 'mamba' if needed
    source ~/.config/tmux/plugins/conda-inherit/conda-inherit.fish
end
```

<details>
<summary><strong>Technical Details</strong></summary>

### How It Works

1. When you activate a conda environment, the plugin records `pane_id:env_name` in a session variable
2. When creating a new pane, tmux passes the parent pane ID via `-e "TMUX_PARENT_PANE_ID=#{pane_id}"`
3. The new shell looks up the parent's environment and activates it automatically
4. Closed panes are cleaned up automatically when creating new panes

### Environment Storage

The plugin maintains `TMUX_SESSION_CONDA_ENVS` containing space-separated pairs:
```
%0:myenv %1:myenv %2:otherenv
```

### Performance

- **Pane creation**: minimal overhead (one `tmux list-panes` call + cleanup)
- **Conda activate**: Pure shell operations, no subprocess overhead
- **Memory**: Negligible (function definitions + small env variable)

### Troubleshooting

**"Error: conda function not found"**
- Conda must be initialized before sourcing this plugin

**Environments not inheriting**
- Check tmux version: `tmux -V` (must be >= 3.0)
- Verify keybinds include `-e "TMUX_PARENT_PANE_ID=#{pane_id}"`
- Restart tmux: `tmux kill-server` then `tmux`

</details>
