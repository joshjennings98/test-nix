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

#################
# ABBREVIATIONS #
#################

abbr --add extract tar -xvzf
abbr --add archive tar -cvzf

abbr --add newpush git push --set-upstream origin \(git branch --show-current\)
abbr --add gca git commit --amend --no-edit \&\& git push --force

###########
# ALIASES #
###########

alias la='ls -aF' # list all files (including hidden)
alias ll='ls -lhFBA' # list all files (including hidden) in a human readable way
alias lr='ls -R' # list EVERYTHING (recursive ls)

##########
# PROMPT #
##########

# don't show greeting
set fish_greeting

# git prompt stuff
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

# make sure that the command colour is the one I like
set -U fish_color_command 458588

# set the prompt
function fish_prompt
    set last_status $status

    printf '%s' (echo $USER@)
    printf '%s ' (hostname)
    printf '%s' (__fish_git_prompt) | sed -e 's/ //' -e 's/$/ /' -e 's/(/[/' -e 's/)/]/'

    set_color $fish_color_cwd
    printf '%s\n' (prompt_pwd)
    set_color normal

    set_color cyan
    echo -n "➤  "
    set_color normal
end
