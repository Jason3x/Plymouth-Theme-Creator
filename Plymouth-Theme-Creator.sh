#!/bin/bash

#---------------------------------#
# Plymouth Theme Creator from GIF #
# By Jason                        #
#---------------------------------#

# --- Root privilege check ---
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -- "$0" "$@"
fi

CURR_TTY="/dev/tty1"
APP_NAME="Plymouth Theme Creator by Jason"
THEME_DIR="/roms/tools/plymouthThemes"
TARGET_DIR="/usr/share/plymouth/themes"
export TERM=linux
export XDG_RUNTIME_DIR="/run/user/$UID"

ExitMenu() {
  printf "\e[?25h" > $CURR_TTY
  clear > $CURR_TTY
  if [[ ! -z $(pgrep -f gptokeyb) ]]; then
    pgrep -f gptokeyb | sudo xargs kill -9
  fi
  exit 0
}

CheckDeps() {
  check_internet() {
    curl -s --head --request GET https://www.google.com --max-time 5 | head -n 1 | grep "200\|301\|302" &>/dev/null
  }
  for cmd in dialog convert identify awk; do
    if ! command -v "$cmd" &>/dev/null; then
      dialog --backtitle "$APP_NAME" --title "Installing dependencies" --infobox "\nInstalling missing package: $cmd..." 7 50 > $CURR_TTY
      sleep 1
      if check_internet; then
        apt update &>/dev/null
        apt install -y imagemagick &>/dev/null
      else
        dialog --backtitle "$APP_NAME" --title "Error" --msgbox "\nNo internet connection. '$cmd' required." 7 50 > $CURR_TTY
        ExitMenu
      fi
    fi
  done
}

ConvertGIF() {
  mkdir -p "$THEME_DIR"
  GIFS=$(find "$THEME_DIR" -type f -iname "*.gif" | sort)
  if [ -z "$GIFS" ]; then
    dialog --backtitle "$APP_NAME" --title "No GIF Found" --msgbox "\nNo GIF found in:\n$THEME_DIR" 7 50 > $CURR_TTY
    ExitMenu
  fi

  menu_items=()
  index=1
  declare -A GIF_PATHS
  while IFS= read -r file; do
    name=$(basename "$file")
    menu_items+=("$index" "$name")
    GIF_PATHS[$index]="$file"
    ((index++))
  done <<< "$GIFS"

  selection=$(dialog \
    --backtitle "$APP_NAME" \
    --title "Choose GIF" \
    --menu "Select a GIF to convert into a Plymouth Theme:" 15 70 10 \
    "${menu_items[@]}" 2>&1 > $CURR_TTY) || ExitMenu

  infile="${GIF_PATHS[$selection]}"
  name=$(basename "$infile" .gif)
  workdir="$THEME_DIR/$name"

  # Check if theme already exists
  if [ -d "$THEME_DIR/$name" ]; then
    dialog --backtitle "$APP_NAME" --title "Theme Exists" --yesno "\nThe theme '$name' already exists.\nDo you want to overwrite it?" 7 50 > $CURR_TTY
    if [ $? -eq 0 ]; then
      rm -rf "$TARGET_DIR/$name"
      rm -rf "$workdir"
    else
      ConvertGIF
      return
    fi
  fi

  # Ask speed
  speed_menu=$(dialog --backtitle "$APP_NAME" --title "Animation Speed" \
    --menu "Choose playback speed:" 15 50 7 \
    1 "Much Slower" \
    2 "Slower" \
    3 "Slightly Slower" \
    4 "Normal" \
    5 "Slightly Faster" \
    6 "Faster" \
    7 "Much Faster" \
    2>&1 > $CURR_TTY) || ConvertGIF

  case "$speed_menu" in
    1) speed_factor=6 ;;
    2) speed_factor=4 ;;
    3) speed_factor=3 ;;
    4) speed_factor=2 ;;
    5) speed_factor=1.5 ;;
    6) speed_factor=1 ;;
    7) speed_factor=0.5 ;;
    *) speed_factor=2 ;;
  esac

  mkdir -p "$workdir"
  dialog --backtitle "$APP_NAME" --title "Processing" --infobox "\nConverting GIF.\nPlease wait..." 6 30 > $CURR_TTY
  sleep 1
  convert "$infile" -coalesce -resize 640x480 "$workdir/progress-%d.png"

  total_frames=$(ls "$workdir"/progress-*.png 2>/dev/null | wc -l)
  if [ "$total_frames" -eq 0 ]; then
    dialog --backtitle "$APP_NAME" --title "Error" --msgbox "\nGIF conversion failed." 7 50 > $CURR_TTY
    ExitMenu
  fi

  cat > "$workdir/$name.script" <<EOF
screen.w = Window.GetWidth(0);
screen.h = Window.GetHeight(0);
screen.half.w = Window.GetWidth(0) / 2;
screen.half.h = Window.GetHeight(0) / 2;

state.status = "play";
state.time = 0.0;

for (i = 0; i < $total_frames; i++)
  flyingman_image[i] = Image("progress-" + i + ".png");
flyingman_sprite = Sprite();

flyingman_sprite.SetX(Window.GetX() + (Window.GetWidth(0) / 2 - flyingman_image[0].GetWidth() / 2));
flyingman_sprite.SetY(Window.GetY() + (Window.GetHeight(0) / 2 - flyingman_image[0].GetHeight() / 2));

progress = 0;
speed = $speed_factor;

fun refresh_callback () {
  flyingman_sprite.SetImage(flyingman_image[Math.Int(progress / speed) % $total_frames]);
  progress++;
}

Plymouth.SetRefreshFunction (refresh_callback);
EOF

  cat > "$workdir/$name.plymouth" <<EOF
[Plymouth Theme]
Name=$name
Description=$(basename "$infile")
Comment=By Jason
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/$name
ScriptFile=/usr/share/plymouth/themes/$name/$name.script
EOF
  
    # Ask to apply
  dialog --backtitle "$APP_NAME" --title "Apply Theme" --yesno "\nDo you want to apply this theme now?" 7 50 > $CURR_TTY
  if [ $? -eq 0 ]; then
  dialog --backtitle "$APP_NAME" --title "Redirection" --infobox "\nStarting the Plymouth-cp script" 5 40 > $CURR_TTY
  sleep 2
    /bin/bash /roms/tools/Plymouth-cp.sh
    exit 0
  else
    dialog --backtitle "$APP_NAME" --title "Saved" --msgbox "\nTheme saved at:\n$THEME_DIR/$name" 7 70 > $CURR_TTY
    ConvertGIF
  fi
}

# Lancement clean
sudo chmod 666 $CURR_TTY
printf "\e[?25l" > $CURR_TTY
clear > $CURR_TTY
dialog --clear
trap ExitMenu EXIT

# Support manette avec gptokeyb
sudo chmod 666 /dev/uinput
export SDL_GAMECONTROLLERCONFIG_FILE="/opt/inttools/gamecontrollerdb.txt"
pgrep -f gptokeyb | sudo xargs kill -9 2>/dev/null
/opt/inttools/gptokeyb -1 "Plymouth-Theme-Creator.sh" -c "/opt/inttools/keys.gptk" > /dev/null 2>&1 &

# Lancer
CheckDeps
ConvertGIF
