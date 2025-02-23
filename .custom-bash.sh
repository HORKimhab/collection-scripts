# Command alias for colored output
complete -cf ls
complete -cf grep

datetime=$(date +'%Y-%b-%d_%H-%M-%S')
alias apt='sudo apt'
alias install='update && apt install'
alias python='python3'
alias cleanall='apt autoclean && apt autoremove --purge'
alias update='apt update'
# Set highlight background only for echo content
alias upgrade='echo -e "\033[43m------ Update and Upgrade system ------\033[0m\n\033[43m------ Running: sudo apt update && sudo apt upgrade -y && "upgrade_packages"------\033[0m" && update && apt upgrade -y && upgrade_packages'

# Upgrade only
# alias upgradeonly='update && install --only-upgrade'
upgradeonly() {
  local file="$1"
  if [ -z "$file" ]; then
    echo "Package name is required."
    return 1
  fi

  # Verify if the package exists
  if ! apt-cache show "$file" >/dev/null 2>&1; then
    echo -e "Error: Package $(highlight_file "$file") is not found. Please input a valid package name."
    return 1
  fi

  install --only-upgrade "$file"
}

for cmd in start stop restart enable reload status; do
  # Dynamically create a function to call systemctl
  eval "$cmd() { sudo systemctl $cmd \$@; }"
done

# Backup and Nano file
# Function to create a backup and open a file with nano
nanobak() {
  local file="$1"
  # if [ ! -f "$1" ]; then
  #   echo "$1 is not valid file (or path). Please enter valid a file."
  #   return 1
  # fi

  highlight_file="\033[43m$1\033[0m"

  if [ ! -f "$1" ]; then
    echo -e "$highlight_file is not a valid file (or path). \nWould you like to create a new file? (y/n): \c"
    read -r response
    if [[ "$response" == y* || "$response" == Y* ]]; then
      # Create the new file and add content
      echo "#This is a new file" | sudo tee "$1" >/dev/null
      sudo nano $1
      return 1
    else
      echo -e "$highlight_file is not valid file (or path). Please enter valid a file."
      return 1
    fi
  fi

  # Get the directory of the file
  # dir=$(dirname "$1")

  # Delete backup files that are older than today in the same directory
  # find "$dir" -type f -name "$(basename "$1").*bak" -mtime +0 -exec sudo rm {} \;

  # Create the new backup and open the file with nano
  # sudo cp "$1"{,.$datetime.bak} && sudo nano "$1"

  backup_file "$file" && sudo nano "$file"
}

# Backup before truncate file
emptyfile() {
  backup_file "$1" "true"
  # if backup_file return 1, execute other command
  if [[ $? -ne 0 ]]; then
    return 1
  fi

  sudo truncate -s 0 "$1" # truncate -s 0 $1 |  empty file
  echo " #'File $1' has been empty..." | sudo tee "$1" >/dev/null
  sudo nano $1
}

# Function hight file
# E.g: echo -e "$(highlight_file "Text will be highlight") file is not found."
highlight_file() {
  local fileName="$1"
  echo "\033[43m$fileName\033[0m"
}

# use: backup_file "fileName" "true"
backup_file() {
  local datetime_bf=$(date +'%Y-%b-%d_%H-%M-%S')
  local file="$1"
  local isCheck="${2:-false}" # Default value for isCheck is 'false'

  # Check if the file exists
  if [[ ! -f "$file" && "$isCheck" == "true" ]]; then
    echo -e "$(highlight_file "$file") file is not found."
    return 1
  fi

  local dir
  dir=$(dirname "$file")
  local basename
  basename=$(basename "$file")

  # Delete backup files older than one day
  # TODO comment below to improve performance
  # sudo find "$dir" -type f -name "$basename.*bak" -mtime +0 -exec sudo rm {} \; // slow
  # Comment below cos it's slow
  # sudo find "$dir" -type f -name "$basename.*bak" -mtime +0 -print0 | xargs -0 -r sudo rm

  # Perform or simulate backup
  sudo cp "$1"{,.$datetime_bf.bak}
}

# Example of 'print_with_dashes'
# ----------------------------------------------------------------------------------------
# This is the default message of the print_with_dashes function. Please verify your usage.
print_with_dashes() {
  # If no message is provided, use the default message
  local message="${1:-This is the default message of the print_with_dashes function. Please verify your usage.}"

  # Get the length of the message
  length=${#message}

  # Print dashes equal to the length of the message
  for ((i = 0; i < length; i++)); do
    echo -n "-"
  done
  echo # Move to the next line after printing dashes

  # Print the actual message
  echo "$message"
}
# Export function to use outside
export -f print_with_dashes

# Install 
upgrade_packages(){
  upgradable=$(apt list --upgradable 2>/dev/null | awk -F/ 'NR>1 {print $1}')

    if [ -n "$upgradable" ]; then
      local upgradable_syntax="upgrade_packages: apt list --upgradable 2>/dev/null | awk -F/ 'NR>1 {print $1}'"
      # echo -e "$(highlight_file "$upgradable_syntax")"
      echo -e "$(print_with_dashes "$(highlight_file "$upgradable_syntax")")"
      # echo "$upgradable" | xargs apt install -y
    fi
}
