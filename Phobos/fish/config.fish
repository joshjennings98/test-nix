echo "Welcome to:
       ___           _     _                         __ _              __ _     _
      |_  |         | |   ( )                       / _(_)            / _(_)   | |
        | | ___  ___| |__ |/ ___     ___ ___  _ __ | |_ _  __ _      | |_ _ ___| |__
        | |/ _ \/ __| '_ \  / __|   / __/ _ \| '_ \|  _| |/ _` |     |  _| / __| '_ \
    /\__/ / (_) \__ \ | | | \__ \  | (_| (_) | | | | | | | (_| |  _  | | | \__ \ | | |
    \____/ \___/|___/_| |_| |___/   \___\___/|_| |_|_| |_|\__, | (_) |_| |_|___/_| |_|
                                                           __/ |
                                                          |___/
" >/dev/null

set -gx EDITOR hx

# commands to run in interactive sessions can go here
if status is-interactive
    # up -> search command history
    bind \e\[A 'if not commandline --paging-mode ; fzf_select_history (commandline -b) ; else ; commandline --function up-line ; end'
    # ctrl + e -> edit current command in $EDITOR
    bind \ce edit_command_buffer
end

# FUNCTIONS
function fzf_select_history --description "Search command history using fzf"
    test -n "$FZF_TMUX_HEIGHT"; or set FZF_TMUX_HEIGHT 60%
    begin
        set -lx FZF_DEFAULT_OPTS "--height 60% --tiebreak=index +m"
        history -z | eval fzf --read0 --print0 -q '(commandline)' | read -lz result
        and commandline -- $result
    end
    commandline -f repaint
end

function edit_command_buffer --description "Open the current command buffer in a text editor ($EDITOR) to make modifying long/multiline commands easier"
    set -l f (mktemp)
    if set -q f[1]
        mv $f $f.fish
        set f $f.fish
    else
        # We should never execute this block but better to be paranoid.
        set f /tmp/fish.(echo %self).fish
        touch $f
    end

    set -l p (commandline -C)
    commandline -b >$f
    $EDITOR $f

    commandline -r (cat $f)
    commandline -C $p
    command rm $f
end

function yq2 --description "Interactive jq/yq REPL that will repaint the commandline with the chosen query using 'yq'. Supports -r to repaint with 'yq -r'."
    if [ (count $argv) -eq 0 ]
        or begin
            [ (count $argv) -eq 1 ]
            and [ "$argv[1]" = -r ]
        end
        set input (mktemp)
        function __cleanup_input --on-event fish_exit
            rm -f $input
        end
        yq -o=json >$input
    else if [ (count $argv) -gt 1 ]
        and [ "$argv[1]" = -r ]
        echo "this command must be used as a pipe"
        return 1
    else
        echo "this command must be used as a pipe"
        return 1
    end

    set paths (yq -o=json '.' $input | \
        jq -r '
            [ path(..)
              | map(if type=="number" then "[]" else tostring end)
              | join(".")
              | split(".[]")
              | join("[]")
            ]
            | unique
            | map("." + .)
            | .[]
        ' | string collect -N) # collect array with newlines https://fishshell.com/docs/current/cmds/string.html#collect-subcommand

    set -l query (echo $paths | fzf --preview-window='up:60%' \
                                --query . \
                                --preview "jq --color-output -r {q} $input" \
                                --bind "tab:replace-query" \
                                --bind "enter:print-query+abort") # only print query --print-query would print both

    set -l cmd (status current-commandline)
    set -l new_cmd (string replace -r '[j|y]q2(\s+[^\|]+)?' "yq -o=json | jq '$query'\$1" -- $cmd)
    commandline -r $new_cmd
end

function mkcd --description "Make a directory (if it doesn't exist) and cd into it"
    mkdir $argv[1] 2>/dev/null
    cd $argv[1]
end

function .. --description "Go up N directories"
    if count $argv >/dev/null
        cd (echo '../' | string repeat -n $argv[1])
    else
        cd ..
    end
end

function Git --description "Clone (if necessary) project into ~/Git"
    if count $argv >/dev/null
        if test -d ~/Git/$argv[1]
            cd ~/Git/$argv[1]
        else
            cd ~/Git
            git clone https://github.com/Arm-Debug/$argv[1]
            cd $argv[1]
        end
    else
        cd ~/Git
    end
end

function password --description "Copy password (or set an environment variable if 'envvar' in Tags) using keepassxc"
    set -l db $argv[1]
    if test (count $argv) -lt 1
        set db (find ~ -type f -not -path "*/\.git/*" -name "*.kdbx" 2>&1 | grep -v "Permission denied" | fzf $fzf_flags)
    end
    read -s -P "Password for $db: " -l password
    set -l entries (echo $password | keepassxc-cli ls -q $db | string collect -N)
    set -l entry (echo $entries | fzf)
    set -l tags (echo $password | keepassxc-cli show -q $db $entry -a Tags)
    if string match -q "*envvar*" $tags
        set -gx $entry (echo $password | keepassxc-cli show -q $db $entry -a Password)
    else
        echo "Password copied to clipboard for 10 seconds"
        echo $password | keepassxc-cli clip -q $db $entry
        echo "Clipboard cleared"
    end
    set -e password
end

# ABBREVIATIONS
abbr --add newpush git push --set-upstream origin \(git branch --show-current\)
abbr --add gca git commit --amend --no-edit \&\& git push --force
abbr --add gcm git commit -m \"\$\(cat \$\(find \"\$\(git rev-parse --show-toplevel\)/changes/\" -type f -exec ls -t1 \{\} + \| head -n 1\)\)\"

# ALIASES
alias la='ls -aF' # list all files (including hidden)
alias ll='ls -lhFBA' # list all files (including hidden) in a human readable way
alias lr='ls -R' # list EVERYTHING (recursive ls)

alias kctx='kubectl config use-context (kubectl config get-contexts -o name | fzf)' # switch kubernetes context with fzf
alias ksso='aws sso login --sso-session arm' # log into aws cluster

alias jq2=yq2

# PROMPT
set fish_greeting # don't show greeting
set -g __fish_git_prompt_show_informative_status 1 # show info on staged files etc.
set -g __fish_git_prompt_showuntrackedfiles 1 # show untracked files even though it's slow
set fish_prompt_pwd_dir_length 0 # show full path
set -g __fish_git_prompt_color_branch magenta
set -g __fish_git_prompt_showupstream informative
set -g __fish_git_prompt_char_upstream_ahead " ↑ "
set -g __fish_git_prompt_char_upstream_behind " ↓ "
set -g __fish_git_prompt_char_upstream_prefix ""
set -g __fish_git_prompt_char_stateseparator ""

set -g __fish_git_prompt_char_stagedstate " "
set -g __fish_git_prompt_char_dirtystate " "
set -g __fish_git_prompt_char_untrackedfiles " "
set -g __fish_git_prompt_char_conflictedstate " ✖"
set -g __fish_git_prompt_char_cleanstate ""

set -g __fish_git_prompt_color_dirtystate yellow
set -g __fish_git_prompt_color_stagedstate green
set -g __fish_git_prompt_color_invalidstate red
set -g __fish_git_prompt_color_untrackedfiles blue

# set the prompt
function fish_prompt
    set last_status $status

    printf '%s' (echo $USER@)
    printf '%s ' (hostname)
    printf '[%s] ' (kubectl config current-context)
    printf '%s' (__fish_git_prompt) | sed -e 's/ //' -e 's/$/ /' -e 's/(/[/' -e 's/)/]/'

    set_color $fish_color_cwd
    printf '%s\n' (prompt_pwd)
    set_color normal

    set_color cyan
    echo -n "➤  "
    set_color normal
end

# PATH
fish_add_path $HOME/.local/bin
fish_add_path $HOME/go/bin
fish_add_path /usr/local/go/bin

# ALWAYS RUN
go env -w GOPRIVATE=github.com/Arm-Debug
