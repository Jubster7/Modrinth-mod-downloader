#!/bin/bash
# === Configuration ===
MODRINTH_API="https://api.modrinth.com/v2"
DEFAULT_VERSION="1.20.6"

LOADER="fabric"
MODS_FILE="mods.txt"
MODS_DIR="./mods"
OLD_MODS_DIR="./oldmods"
VERSION_PREFIX="@version"
SEEN_IDS=()

# === Colors (tput-compatible for macOS & Linux) ===
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput bold; tput setaf 4)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)
RESET=$(tput sgr0)

# === Logging Helpers ===
verbose=0

log_info()     { echo -e "${WHITE}$1${RESET}"; }
log_step()     {
	if [[ $verbose -eq 1 ]]; then 
		echo -e "${WHITE} $1${RESET}";
	fi
}
log_warn()     { echo -e "${YELLOW}$1${RESET}";}
log_bigtitle() { echo -e "${GREEN}$1${RESET}";}
log_error()    { echo -e "${RED}$1${RESET}"; }
log_title()    { echo -e "${BLUE}$1${RESET}"; }

# === Utilities ===
contains() {
    local match="$1"
    shift
    for e; do [[ "$e" == "$match" ]] && return 0; done
    return 1
}

trim_leading() {
	local line="$1"
	trimmed="${line#"${line%%[![:space:]]*}"}"
	echo "$trimmed"
}

trim_trailing() {
	local line="$1"
	trimmed="${line%"${line##*[![:space:]]}"}"
	echo "$trimmed"
}


get_latest_compatible_version() {
    local versions
    versions=$(curl -s "$MODRINTH_API/project/$slug/version")
    if ! echo "$versions" | jq empty 2>/dev/null; then
        log_error "Invalid version data for $slug"
		SLUG_ERROR+=("$slug")
        return
    fi

    local version
  	version=$(echo "$versions" | jq -c "first(.[] | select(.game_versions[] == \"$mc_version\" and .loaders[] == \"$LOADER\"))")
    [[ "$version" == "null" ]] && return
    echo "$version"
}

download_mod_and_deps() {
    local version_json="$1"
	local dependency="${2:-"false"}"
	local version_id
    version_id=$(echo "$version_json" | jq -r '.id')
    local project_id
	project_id=$(echo "$version_json" | jq -r '.project_id')
	title=$(curl -s "$MODRINTH_API/project/$project_id" | jq -r '.title')

    if contains "$version_id" "${SEEN_IDS[@]}"; then
        log_step "$title has already been downloaded"
		return;
	fi
    SEEN_IDS+=("$version_id")



    # === Find Primary File or Fallback ===
    local file
    file=$(echo "$version_json" | jq -c '.files[] | select(.primary == true)')
    if [[ -z "$file" ]]; then
        file=$(echo "$version_json" | jq -c '.files[] | select(.filename | endswith(".jar"))' | head -n 1)
        log_warn "No primary file —  using first .jar file"
    fi


    if [[ -n "$file" ]]; then
        local url 
        url=$(echo "$file" | jq -r '.url')
        local filename
        filename=$(echo "$file" | jq -r '.filename')

        
        if [[ -z "$url" || -z "$filename" ]]; then
            log_error "Missing URL or filename for version $version_id"
			if [[ $dependency != "false" ]]; then
				DEPENDENCY_ERROR+=("$title")
				DEPENDENCY_ERROR_PARENT+=("$title")
			fi
        else
			# === Check if file is already present === 
			 if contains "$filename" "${PRE_DOWNLOADED[@]}"; then
				log_step "$filename is already present, moving to folder"
				mv "$OLD_MODS_DIR/$filename" "$MODS_DIR/$filename"
			else 
            	log_step "Downloading $filename"
            	curl -sL "$url" -o "$MODS_DIR/$filename"
            fi
        fi
    else
        log_error "No usable file found for version $version_id"
		if [[ $dependency != "false" ]]; then
			DEPENDENCY_ERROR+=("$title")
			DEPENDENCY_ERROR_PARENT+=("$dependency")
		fi
    fi

    # === Handle Required Dependencies ===
    local deps 
    deps=$(echo "$version_json" | jq -c '.dependencies[]?')
    for dep in $deps; do
        local type
        type=$(echo "$dep" | jq -r '.dependency_type')
        if [[ "$type" == "required" ]]; then
            local dep_id
            dep_id=$(echo "$dep" | jq -r '.project_id')
            local dep_versions
            dep_versions=$(curl -s "$MODRINTH_API/project/$dep_id/version")
            local dep_version
            dep_version=$(echo "$dep_versions" | jq -c "first(.[] | select(.game_versions[] == \"$mc_version\" and .loaders[] == \"$LOADER\"))")
			dep_title=$(curl -s "$MODRINTH_API/project/$dep_id" | jq -r '.title')
            if [[ "$dep_version" != "null" ]]; then
                log_step "Processing dependency: $dep_title"
                download_mod_and_deps "$dep_version" "$title"
            else
                log_error "Dependency: $dep_title of $title has no compatible version"
				DEPENDENCY_ERROR+=("$dep_title")
				DEPENDENCY_ERROR_PARENT+=("$title")
            fi
        fi
    done
}

# **** ====== Program start ====== ****
root="$(dirname -- "${BASH_SOURCE[0]:-$0}")"

cd -- "$root" || exit
SECONDS=0
# === Rename mods directory
if [ -e "$OLD_MODS_DIR" ]; then
	#log_error "Old mods directory already exists, exiting"
	#exit
	log_error "Old mods directory already exists, moving to trash"
	mv "$OLD_MODS_DIR" "$HOME/.Trash/oldmods $(date '+%I.%M.%S %p' | sed 's/^0//' | tr '[:upper:]' '[:lower:]')"
fi

if [ -d "$MODS_DIR" ]; then
    mv $MODS_DIR $OLD_MODS_DIR
else
	log_info "No pre-downloaded mods found"
fi

PRE_DOWNLOADED=("$OLD_MODS_DIR"/*)

for i in "${!PRE_DOWNLOADED[@]}"; do
    PRE_DOWNLOADED[$i]="${PRE_DOWNLOADED[$i]##*/}"
done

mkdir -p "$MODS_DIR"

echo; echo; echo
log_title " ${#PRE_DOWNLOADED[@]} Mods already present:\n"
for file in "${PRE_DOWNLOADED[@]}"; do
	log_info "\t$file"
done
echo


# === Read Mod Slugs from File ===
MODS=()
while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^#.*$ || "$line" =~ ^[[:space:]]*$ ]] && continue
    MODS+=("$line")
done < "$MODS_FILE"

NUM_MODS=${#MODS[@]}
NO_COMPATIBLE_VERSION=()
DEPENDENCY_ERROR=()
DEPENDENCY_ERROR_PARENT=()
SLUG_ERROR=()
NUM_DOWNLOADED=0

if  [[ "$NUM_MODS" == "0" ]] || (( NUM_MODS == 0 )); then
	log_error "No lines found in file, exiting..."
	exit
fi
line=${MODS[0]}
needle=$VERSION_PREFIX
# trim leading whitespace
trimmed=$(trim_leading "$line")

mc_version=""

# enable extended globs
shopt -s extglob
index=0
if [[ "$trimmed" == *"$needle"*([![:space:]])* ]]; then
	first="${trimmed%%[[:space:]]*}"
	new_first="${first//$needle/}"
	
    result=$(trim_trailing "$(trim_leading "${new_first}${trimmed#"$first"}")")
	
    log_info "Version: $result"
    mc_version=$result
	((NUM_MODS--))
	((index++))
else
	mc_version=$DEFAULT_VERSION
	log_warn "No version is detected, using default version: $DEFAULT_VERSION"
fi
log_info "$NUM_MODS mod slugs loaded from $MODS_FILE"

# === Loop over all mods and download ===
while (( index < NUM_MODS + 1 )); do
	slug="${MODS[index]}"
	
	status=$(curl -s -o /dev/null -w "%{http_code}" "$MODRINTH_API/project/$slug")
	if [[ "$status" != 200 ]]; then
		log_error "Project not found for slug: $slug"
		SLUG_ERROR+=("$slug")
		
		((index++))
		continue
	fi

	title=$(curl -s "$MODRINTH_API/project/$slug" | jq -r '.title')
	log_title "$title ($slug):"

	version_json=$(get_latest_compatible_version "$slug")
	if [[ -z "$version_json" || "$version_json" == "null" ]]; then
		log_warn "No compatible version for $title ($slug)"
		NO_COMPATIBLE_VERSION+=("$slug")
		
		((index++))
		continue
	fi

	download_mod_and_deps "$version_json"
	((NUM_DOWNLOADED++))
	
    ((index++))
done

mv "$OLD_MODS_DIR" "$HOME/.Trash/old at $(date '+%I.%M.%S %p' | sed 's/^0//' | tr '[:upper:]' '[:lower:]')"


log_bigtitle "———  Summary ———"
if (( ${#DEPENDENCY_ERROR[@]} != 0 )); then
	log_info "${#DEPENDENCY_ERROR[@]} dependencies failed to download"
	for i in "${!DEPENDENCY_ERROR[@]}"; do
		log_error "${DEPENDENCY_ERROR[i]} —  no usable file found, required dependency of \`${DEPENDENCY_ERROR_PARENT[i]}\`"
	done
fi

log_info "Elapsed time: $SECONDS seconds"
log_info "$NUM_DOWNLOADED out of $NUM_MODS mods successfully downloaded, $((NUM_MODS-NUM_DOWNLOADED)) mods skipped:"

if (( ${#SLUG_ERROR[@]} != 0 )); then
	log_title "Invalid project: "
	for slug in "${SLUG_ERROR[@]}"; do
		log_warn "\t($slug)"
	done
fi

if (( ${#NO_COMPATIBLE_VERSION[@]} != 0 )); then
	log_title "No compatible version: "
	for slug in "${NO_COMPATIBLE_VERSION[@]}"; do
		title=$(curl -s "$MODRINTH_API/project/$slug" | jq -r '.title')
		log_info "\t$title ($slug)"
	done
fi