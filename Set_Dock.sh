#!/bin/bash

# Build a default Dock using dockutil
# Jamf Parameters (names only, no .app):
#   $4-$11 = apps to add in order (leave blank to skip)
# Example:
#   $4="Activity Monitor"  $5="System Settings"  $6="TextEdit"  $7="Spotify"  $8="Google Chrome"  $9="Self Service+"

set -euo pipefail

# Give macOS time to fully build the default Dock
sleep 20

LoggedInUser="$(stat -f "%Su" /dev/console)"
LoggedInUserHome="/Users/${LoggedInUser}"

dockutilPath="/usr/local/bin/dockutil"

# Collect Jamf parameters into an array (blanks are fine; we'll skip them)
APPS=(
  "${4:-}"
  "${5:-}"
  "${6:-}"
  "${7:-}"
  "${8:-}"
  "${9:-}"
  "${10:-}"
  "${11:-}"
)

get_app_path() {
  local app="$1"

  # If caller provided a full path, use it
  if [[ "$app" == /* ]]; then
    [[ -d "$app" ]] && { echo "$app"; return 0; }
    return 1
  fi

  # Otherwise, try common locations
  local candidates=(
    "/Applications/${app}.app"
    "/System/Applications/${app}.app"
    "/System/Applications/Utilities/${app}.app"
  )

  local p
  for p in "${candidates[@]}"; do
    [[ -d "$p" ]] && { echo "$p"; return 0; }
  done

  return 1
}

install_dockutil_if_needed() {
  if [[ -x "$dockutilPath" ]]; then
    echo "dockutil already installed at $dockutilPath"
    return 0
  fi

  echo "dockutil not installed, installing..."

  dockutilURL="$(
    /usr/bin/curl -fsSL "https://api.github.com/repos/kcrawford/dockutil/releases/latest" \
      | /usr/bin/grep -E 'browser_download_url' \
      | /usr/bin/grep -E '\.pkg"' \
      | /usr/bin/head -1 \
      | /usr/bin/cut -d '"' -f 4
  )"

  if [[ -z "${dockutilURL:-}" ]]; then
    echo "ERROR: Could not determine dockutil download URL"
    exit 1
  fi

  /usr/bin/curl -fsSL --location "$dockutilURL" -o "/tmp/dockutil.pkg"
  /usr/sbin/installer -pkg "/tmp/dockutil.pkg" -target /
}

wait_for_dock() {
  echo "Waiting for Dock process for user ${LoggedInUser}..."
  until /usr/bin/pgrep -u "$LoggedInUser" Dock >/dev/null 2>&1; do
    sleep 2
  done
}

configureDefaultDock() {
  echo "Logged in user is: $LoggedInUser"
  echo "Logged in user's home: $LoggedInUserHome"

  # Safety: only proceed for a real user session
  if [[ -z "${LoggedInUser:-}" || "${LoggedInUser}" == "root" || "${LoggedInUser}" == "loginwindow" ]]; then
    echo "No GUI user session detected; exiting."
    exit 0
  fi

  install_dockutil_if_needed
  wait_for_dock

  echo "Clearing Dock..."
  sudo -u "$LoggedInUser" "$dockutilPath" --remove all --no-restart "$LoggedInUserHome"

  echo "Adding requested apps (blank parameters are skipped)..."
  local position=2
  local app appPath

  for app in "${APPS[@]}"; do
    [[ -z "${app}" ]] && continue

    if appPath="$(get_app_path "$app")"; then
      echo "Adding: ${app} (${appPath}) at position ${position}"
      sudo -u "$LoggedInUser" "$dockutilPath" \
        --add "$appPath" \
        --no-restart \
        --position "$position" \
        "$LoggedInUserHome"
      position=$((position + 1))
    else
      echo "WARNING: App not found for '${app}' (skipping)"
    fi
  done

  # Marker file so you can scope / avoid reruns if you want
  /usr/bin/touch "$LoggedInUserHome/Library/Preferences/com.j24.docksetup.plist"

  echo "Restarting Dock..."
  sudo -u "$LoggedInUser" /usr/bin/killall Dock || true
}

configureDefaultDock
exit 0