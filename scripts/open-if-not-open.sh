#!/bin/sh
# Opens the given URL in the default browser, or focuses the existing tab if already open.
# macOS: checks Safari and Chrome for an existing tab. Other platforms: simple open.
# Usage: sh scripts/open-if-not-open.sh http://localhost:8015

url="$1"
if [ -z "$url" ]; then
  echo "Usage: $0 <url>"
  exit 1
fi

case "$(uname -s)" in
  Darwin)
    osascript -e "
      -- Safari
      try
        tell application \"System Events\" to set safariRunning to (exists process \"Safari\")
        if safariRunning then
          tell application \"Safari\"
            repeat with w in windows
              set tabIndex to 0
              repeat with t in tabs of w
                set tabIndex to tabIndex + 1
                if URL of t starts with \"$url\" then
                  set current tab of w to t
                  set index of w to 1
                  activate
                  return
                end if
              end repeat
            end repeat
          end tell
        end if
      end try
      -- Chrome
      try
        tell application \"System Events\" to set chromeRunning to (exists process \"Google Chrome\")
        if chromeRunning then
          tell application \"Google Chrome\"
            repeat with w in windows
              set tabIndex to 0
              repeat with t in tabs of w
                set tabIndex to tabIndex + 1
                if URL of t starts with \"$url\" then
                  set active tab index of w to tabIndex
                  set index of w to 1
                  activate
                  return
                end if
              end repeat
            end repeat
          end tell
        end if
      end try
      -- Not found in any browser, open with default
      do shell script \"open \" & quoted form of \"$url\"
    " 2>/dev/null
    ;;
  Linux)
    xdg-open "$url" 2>/dev/null &
    ;;
  *)
    echo "Open $url in your browser."
    ;;
esac
