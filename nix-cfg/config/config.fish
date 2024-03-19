echo "Welcome to:
       ___           _     _                         __ _              __ _     _
      |_  |         | |   ( )                       / _(_)            / _(_)   | |
        | | ___  ___| |__ |/ ___     ___ ___  _ __ | |_ _  __ _      | |_ _ ___| |__
        | |/ _ \/ __| '_ \  / __|   / __/ _ \| '_ \|  _| |/ _` |     |  _| / __| '_ \
    /\__/ / (_) \__ \ | | | \__ \  | (_| (_) | | | | | | | (_| |  _  | | | \__ \ | | |
    \____/ \___/|___/_| |_| |___/   \___\___/|_| |_|_| |_|\__, | (_) |_| |_|___/_| |_|
                                                           __/ |
                                                          |___/
" > /dev/null

set -gx EDITOR vim

# commands to run in interactive sessions can go here
if status is-interactive
    # up -> search command history
    bind \e\[A 'if not commandline --paging-mode ; fzf_select_history (commandline -b) ; else ; commandline --function up-line ; end'
    # ctrl + p -> search all filenames in current directory (recursive)
    bind \cp 'fzf_file_search (commandline -b)'
    # ctrl + e -> edit current command in $EDITOR
    bind \ce edit_command_buffer
    # ctrl + s -> search for string (regex) in files in current directory (recursive)
    bind \cs 'search_files (commandline -b)'
    # placeholder
    bind \cf 'tmux-sessioniser'
end

#############
# FUNCTIONS #
#############

function fzf_select_history --description "Search command history using fzf"
    test -n "$FZF_TMUX_HEIGHT"; or set FZF_TMUX_HEIGHT 60%
    begin
        set -lx FZF_DEFAULT_OPTS "--height 60% --tiebreak=index +m --preview 'echo {}' --preview-window bottom:40%"
        history -z | eval fzf --read0 --print0 -q '(commandline)' | read -lz result
        and commandline -- $result
    end
    commandline -f repaint
end

function fzf_file_search --description "Search for files in current directory (recusively) using fzf"
    if test (count $argv) = 0
        set fzf_flags --reverse --preview 'echo -e "{+}\n" ; batcat --color=always {}' --preview-window 50%
    else
        set fzf_flags --reverse --query "$argv" --preview 'echo -e "{+}\n" ; batcat --color=always {}' --preview-window 50%
    end

    set files (find . -type f -not -path "*/\.git/*" 2>&1 | grep -v "Permission denied" | fzf $fzf_flags | string split0)

    if [ $files ]
        $EDITOR (echo $files | sed -e '/^$/d' -e 's/\n/ /g')
    end
end

function search_files --description "Search for a string (regex) in the files in the current directory (recursively) using fzf and ripgrep"
    set -x RG_PREFIX rg --column --line-number --no-heading --smart-case
    set -l file
    set file (
        FZF_DEFAULT_COMMAND="$RG_PREFIX '$argv'" \
            fzf --sort \
                --reverse \
                --phony -q "$argv" \
                --delimiter : \
                --preview 'batcat --color=always {1} --highlight-line {2} --line-range {2}:' \
                --bind "change:reload:$RG_PREFIX {q} || true" \
                --preview-window="up:60%"
    )
    and $EDITOR (echo $file | awk -F: '{ printf "%s:%s", $1,$2 }')
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
    commandline -b > $f
    $EDITOR $f

    commandline -r (cat $f)
    commandline -C $p
    command rm $f
end

function mkcd --description "Make a directory (if it doesn't exist) and cd into it"
    mkdir $argv[1] 2> /dev/null
    cd $argv[1]
end

function .. --description "Go up N directories"
   if count $argv > /dev/null
        cd (echo '../' | string repeat -n $argv[1])
    else
        cd ..
    end
end

function envsource --description "Source standard env files using fish"
  for line in (cat $argv | grep -v '^#' | grep -v '^\s*$')
    set -l item (string split -m 1 '=' $line)
    set -gx $item[1] (string trim --chars=\'\" $item[2])
    echo "Exported key $item[1]"
  end
end

#################
# ABBREVIATIONS #
#################

abbr --add extract tar -xvzf
abbr --add archive tat -cvzf

abbr --add newpush git push --set-upstream origin \(git branch --show-current\)
abbr --add gca git commit --amend --no-edit \&\& git push --force

###########
# ALIASES #
###########

alias lsalias="echo Aliases: && grep -in --color -e '^alias\s+*' ~/.config/fish/config.fish | grep -v lsalias | sed -e 's/alias //' -e 's/=.*\s*#/  -> /' -e 's/[[:digit:]]*://' | grep --colour -e '[a-z\.]*  ' && echo -e \"\nAbbreviations:\" && abbr | sed -e 's/.* -- //g' -e 's/ \'/  ->  /g' -e 's/^test\$/test  ->  test files using fzf/' | tr -d \"'\" | grep --colour -e  '^[^ ]*'" # horrible snippet to list aliases and abbreviations

alias la='ls -aF' # list all files (including hidden)
alias ll='ls -lhFBA' # list all files (including hidden) in a human readable way
alias lr='ls -R' # list EVERYTHING (recursive ls)

##########
# PROMPT #
##########

# don't show greeting
set fish_greeting

# git prompt stuff
set -g __fish_git_prompt_show_informative_status 0
set -g __fish_git_prompt_hide_untrackedfiles 1
set fish_prompt_pwd_dir_length 0

set -g __fish_git_prompt_color_branch magenta
set -g __fish_git_prompt_showupstream "informative"
set -g __fish_git_prompt_char_upstream_ahead " ↑"
set -g __fish_git_prompt_char_upstream_behind " ↓"
set -g __fish_git_prompt_char_upstream_prefix ""
set -g __fish_git_prompt_char_stateseparator ""

set -g __fish_git_prompt_char_stagedstate " ●"
set -g __fish_git_prompt_char_dirtystate " ○"
set -g __fish_git_prompt_char_untrackedfiles " ◌"
set -g __fish_git_prompt_char_conflictedstate " ✖"
set -g __fish_git_prompt_char_cleanstate " ✔"

set -g __fish_git_prompt_color_dirtystate white
set -g __fish_git_prompt_color_stagedstate blue
set -g __fish_git_prompt_color_invalidstate red
set -g __fish_git_prompt_color_untrackedfiles $fish_color_normal
set -g __fish_git_prompt_color_cleanstate green

# set the prompt
function fish_prompt
    set last_status $status

    printf '%s' (echo $USER@)
    printf '%s ' (hostname)
    #printf '[%s] ' (kubectl config current-context)

    set_color $fish_color_cwd
    printf '%s\n' (prompt_pwd)
    set_color normal

    printf '%s' (__fish_git_prompt) | sed -e 's/ //' -e 's/$/ /' -e 's/(/[/' -e 's/)/]/'
    set_color cyan
    echo -n "➤  "
    set_color normal
end

########
# PATH #
########

# fish_add_path $HOME/go/bin
# fish_add_path /usr/local/go/bin
# fish_add_path $HOME/.cargo/bin

#kubectl completion fish | source
