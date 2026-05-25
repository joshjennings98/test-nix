#!/bin/bash

declare -a LIST_OF_WINDOW_TITLES_THAT_PREVENT_LOCKING=(
  "YouTube"
  "Netflix"
  "Disney+"
)

get_active_id() {
  xprop -root | awk '$1 ~ /_NET_ACTIVE_WINDOW/ { print $5 }'
}

get_window_title() {
  xprop -id $1 | awk -F '=' '$1 ~ /_NET_WM_NAME\(UTF8_STRING\)/ { print $2 }'
}

should_lock() {
  id=$(get_active_id)
  title=$(get_window_title $id)

  for i in "${LIST_OF_WINDOW_TITLES_THAT_PREVENT_LOCKING[@]}"; do
    if [[ $title =~ $i ]]; then
      return 1
    fi
  done

  return 0
}

if should_lock; then
  i3lock -c 000000
fi
