#!/usr/bin/env bash
set -e

# x86_64-linux-musl Toolchain Builder v2
# Interactive build configuration using dialog

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.mk"
LOCAL_CONFIG="$SCRIPT_DIR/local.mk"

# Component mapping: display name -> make target
# Using function instead of associative array for bash 3.x compatibility
get_make_target() {
    case "$1" in
        "autoconf") echo "autoconf" ;;
        "binutils") echo "binutils" ;;
        "gcc") echo "gcc" ;;
        "musl (dynamic)") echo "musl" ;;
        "musl (static)") echo "musl-shared" ;;
        "libtool") echo "libtool" ;;
        *) echo "$1" ;;
    esac
}

# Default selections (marked with *)
DEFAULT_COMPONENTS=("autoconf" "binutils" "gcc" "musl (dynamic)")

# Temporary file for dialog output
DIALOG_TMPFILE=$(mktemp /tmp/build-dialog.XXXXXX)
trap "rm -f $DIALOG_TMPFILE" EXIT

# ============================================================================
# Helper functions
# ============================================================================

check_dialog() {
    if ! command -v dialog &> /dev/null; then
        cat << EOF
ERROR: The 'dialog' program is not installed.

dialog is required for interactive mode. Please install it:

  macOS:    brew install dialog
  Ubuntu:   sudo apt-get install dialog
  Fedora:   sudo dnf install dialog
  Arch:     sudo pacman -S dialog

Alternatively pass the --headless flag.
EOF
        exit 1
    fi
}

# Read value from config.mk
read_config_value() {
    local var_name="$1"
    local value=""

    # First check local.mk if it exists
    if [ -f "$LOCAL_CONFIG" ]; then
        value=$(grep "^${var_name}[[:space:]]*=" "$LOCAL_CONFIG" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    fi

    # Fall back to config.mk if not found
    if [ -z "$value" ]; then
        value=$(grep "^${var_name}[[:space:]]*[:?]\?=" "$CONFIG_FILE" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    fi

    # Expand $(CURDIR) if present
    value="${value//\$(CURDIR)/$SCRIPT_DIR}"

    echo "$value"
}

# Write to local.mk (create if doesn't exist)
write_local_config() {
    local var_name="$1"
    local var_value="$2"

    # Create local.mk if it doesn't exist
    if [ ! -f "$LOCAL_CONFIG" ]; then
        cat > "$LOCAL_CONFIG" << 'EOF'
# Local configuration overrides
# This file was automatically created by the build script.
# You can edit this file to customize the build.

EOF
    fi

    # Check if variable already exists in local.mk
    if grep -q "^${var_name}[[:space:]]*=" "$LOCAL_CONFIG" 2>/dev/null; then
        # Update existing value (macOS compatible)
        case "$(uname -s)" in
            Darwin*)
                sed -i '' "s|^${var_name}[[:space:]]*=.*|${var_name} = ${var_value}|" "$LOCAL_CONFIG"
                ;;
            *)
                sed -i "s|^${var_name}[[:space:]]*=.*|${var_name} = ${var_value}|" "$LOCAL_CONFIG"
                ;;
        esac
    else
        # Append new variable
        echo "${var_name} = ${var_value}" >> "$LOCAL_CONFIG"
    fi
}

# Check if component version has changed by comparing with built version
check_version_changes() {
    local component="$1"
    local current_version=""
    local build_dir_name=""

    case "$component" in
        autoconf)
            current_version=$(read_config_value "AUTOCONF_VERSION")
            build_dir_name="autoconf"
            ;;
        binutils)
            current_version=$(read_config_value "BINUTILS_VERSION")
            build_dir_name="binutils"
            ;;
        gcc)
            current_version=$(read_config_value "GCC_VERSION")
            build_dir_name="gcc"
            ;;
        musl|musl-shared)
            # Both musl and musl-shared use the same directory
            # Musl uses git, so we check the git URL and branch instead
            local musl_url=$(read_config_value "MUSL_GIT_URL")
            local musl_branch=$(read_config_value "MUSL_GIT_BRANCH")
            current_version="${musl_url}#${musl_branch}"
            build_dir_name="musl"
            ;;
        libtool)
            current_version=$(read_config_value "LIBTOOL_VERSION")
            build_dir_name="libtool"
            ;;
        pkgconfig)
            current_version=$(read_config_value "PKGCONFIG_VERSION")
            build_dir_name="pkgconfig"
            ;;
        *)
            return 0
            ;;
    esac

    local build_dir=$(read_config_value "BUILD_DIR")
    local component_build_dir="${build_dir}/${build_dir_name}"
    local version_file="${component_build_dir}/.version"

    # If build directory doesn't exist, nothing to clean
    if [ ! -d "$component_build_dir" ]; then
        return 0
    fi

    # If no version file exists, ignore (will be created on next successful build)
    if [ ! -f "$version_file" ]; then
        return 0
    fi

    # Read the built version
    local built_version=$(cat "$version_file")

    # Compare versions
    if [ "$built_version" != "$current_version" ]; then
        echo "Version mismatch for $component ($built_version → $current_version), cleaning ${component_build_dir}"
        rm -rf "$component_build_dir"
    fi
}

# ============================================================================
# Dialog prompts
# ============================================================================

prompt_musl_source() {
    local current_url=$(read_config_value "MUSL_GIT_URL")

    dialog --title "Musl libc Source" \
           --menu "Select musl libc source:\n\nCurrent: $current_url" 15 70 3 \
           1 "Keep current URL" \
           2 "Official musl (git://git.musl-libc.org/musl)" \
           3 "Custom git URL" \
           2> "$DIALOG_TMPFILE"

    local choice=$?
    [ $choice -ne 0 ] && exit 1

    choice=$(cat "$DIALOG_TMPFILE")

    case $choice in
        2)
            write_local_config "MUSL_GIT_URL" "git://git.musl-libc.org/musl"
            ;;
        3)
            dialog --title "Custom Musl URL" \
                   --inputbox "Enter musl git repository URL:" 10 70 \
                   2> "$DIALOG_TMPFILE"

            [ $? -ne 0 ] && exit 1

            local custom_url=$(cat "$DIALOG_TMPFILE")
            if [ -n "$custom_url" ]; then
                write_local_config "MUSL_GIT_URL" "$custom_url"
            fi
            ;;
        *)
            # Keep current
            ;;
    esac
}

prompt_components() {
    local args=(
        --title "Component Selection"
        --checklist "Select components to build (* = default):\n\nUse SPACE to select, ENTER to confirm"
        15 70 6
    )

    # Add each component to the checklist
    for comp in "autoconf" "binutils" "gcc" "musl (dynamic)" "musl (static)" "libtool"; do
        local status="off"
        for default in "${DEFAULT_COMPONENTS[@]}"; do
            if [ "$comp" = "$default" ]; then
                status="on"
                break
            fi
        done
        args+=("$comp" "" "$status")
    done

    dialog "${args[@]}" 2> "$DIALOG_TMPFILE"

    [ $? -ne 0 ] && exit 1

    # Read selected components
    SELECTED_COMPONENTS=$(cat "$DIALOG_TMPFILE")
}

prompt_build_mode() {
    dialog --title "Build Mode" \
           --menu "Select build mode:" 12 70 2 \
           1 "Local build mode" \
           2 "Docker build mode" \
           2> "$DIALOG_TMPFILE"

    local choice=$?
    [ $choice -ne 0 ] && exit 1

    choice=$(cat "$DIALOG_TMPFILE")

    BUILD_MODE="local"
    DOCKER_COPY_LOCAL=false

    case $choice in
        1)
            # Local build mode
            prompt_toolchain_dir
            ;;
        2)
            # Docker build mode
            BUILD_MODE="docker"
            prompt_docker_options
            ;;
    esac
}

prompt_toolchain_dir() {
    local current_dir=$(read_config_value "TOOL_ROOT")

    dialog --title "Toolchain Directory" \
           --inputbox "Enter toolchain installation directory:\n\nCurrent: $current_dir" 12 70 "$current_dir" \
           2> "$DIALOG_TMPFILE"

    [ $? -ne 0 ] && exit 1

    local new_dir=$(cat "$DIALOG_TMPFILE")
    if [ -n "$new_dir" ] && [ "$new_dir" != "$current_dir" ]; then
        write_local_config "TOOL_ROOT" "$new_dir"
    fi
}

prompt_docker_options() {
    # Check if local toolchain exists
    local tool_root=$(read_config_value "TOOL_ROOT")
    local has_local=false

    if [ -d "$tool_root" ] && [ -d "$tool_root/bin" ]; then
        has_local=true
    fi

    if $has_local; then
        dialog --title "Docker Build Options" \
               --yesno "Build from pre-built local toolchain?\n\nThis is faster but requires the toolchain to be built locally first.\n\nSelect Yes to use local toolchain, No to build from scratch." 12 70

        if [ $? -eq 0 ]; then
            DOCKER_COPY_LOCAL=true
        fi
    else
        dialog --title "Docker Build Mode" \
               --msgbox "No local toolchain found. Will build from scratch inside Docker.\n\nThis may take a while." 10 70
    fi
}

prompt_confirmation() {
    local musl_url=$(read_config_value "MUSL_GIT_URL")
    local tool_root=$(read_config_value "TOOL_ROOT")

    # Convert component selections to make targets
    local make_targets=""
    while IFS= read -r comp; do
        comp=$(echo "$comp" | tr -d '"')
        if [ -n "$comp" ]; then
            make_targets="$make_targets $(get_make_target "$comp")"
        fi
    done <<< "$SELECTED_COMPONENTS"

    local build_mode_text="Local build"
    if [ "$BUILD_MODE" = "docker" ]; then
        build_mode_text="Docker build"
        if $DOCKER_COPY_LOCAL; then
            build_mode_text="$build_mode_text (from local)"
        else
            build_mode_text="$build_mode_text (from scratch)"
        fi
    fi

    local summary="Build Configuration:\n\n"
    summary+="Musl URL:       $musl_url\n"
    summary+="Build mode:     $build_mode_text\n"
    summary+="Toolchain dir:  $tool_root\n"
    summary+="Components:     $make_targets\n\n"
    summary+="Proceed with build?"

    dialog --title "Confirmation" \
           --yesno "$summary" 16 80

    return $?
}

# ============================================================================
# Build functions
# ============================================================================

build_local() {
    local components="$1"
    local build_dir=$(read_config_value "BUILD_DIR")
    local tool_root=$(read_config_value "TOOL_ROOT")

    # Check for version changes and clean if necessary
    for comp in $components; do
        check_version_changes "$comp"
    done

    # Clear screen and show progress
    clear
    echo "======================================================================"
    echo "  x86_64-linux-musl Toolchain Build"
    echo "======================================================================"
    echo ""
    echo "Components: $components"
    echo "Build dir:  $build_dir"
    echo "Install to: $tool_root"
    echo ""

    # Build each component
    for component in $components; do
        echo "Building $component..."
        if ! make -C "$SCRIPT_DIR" "$component"; then
            echo ""
            echo "ERROR: Failed to build $component"
            exit 1
        fi
        echo ""
    done

    echo "======================================================================"
    echo "  Build Complete!"
    echo "======================================================================"
    echo ""
    echo "Toolchain installed at: $tool_root"
    echo "Add to PATH: export PATH=\"$tool_root/bin:\$PATH\""
    echo ""
}

build_docker() {
    local components="$1"

    echo "======================================================================"
    echo "  Building Docker Image"
    echo "======================================================================"
    echo ""

    if ! command -v docker &> /dev/null; then
        echo "ERROR: Docker is not installed or not in PATH"
        exit 1
    fi

    local image_name="x86_64-linux-musl-toolchain"

    if $DOCKER_COPY_LOCAL; then
        echo "Mode: Copy pre-built local toolchain"
        echo ""

        # Build locally first
        build_local "$components"

        # Build Docker image using Dockerfile.local
        echo "Creating Docker image from local toolchain..."
        if ! docker build -f "$SCRIPT_DIR/Dockerfile.local" -t "$image_name" "$SCRIPT_DIR"; then
            echo "ERROR: Failed to build Docker image"
            exit 1
        fi
    else
        echo "Mode: Build from scratch inside Docker"
        echo ""

        # Build Docker image using main Dockerfile
        if ! docker build -t "$image_name" "$SCRIPT_DIR"; then
            echo "ERROR: Failed to build Docker image"
            exit 1
        fi
    fi

    echo ""
    echo "======================================================================"
    echo "  Docker Image Built Successfully!"
    echo "======================================================================"
    echo ""
    echo "Image name: $image_name"
    echo "Run: docker run -it $image_name"
    echo ""
}

# ============================================================================
# Main
# ============================================================================

main() {
    # Check for dialog
    check_dialog

    # Show welcome
    dialog --title "x86_64-linux-musl Toolchain Builder v2" \
           --msgbox "Welcome to the interactive toolchain builder.\n\nThis wizard will guide you through configuring and building the toolchain." 10 70

    # Run prompts
    prompt_musl_source
    prompt_components
    prompt_build_mode

    # Confirmation
    if ! prompt_confirmation; then
        clear
        echo "Build cancelled."
        exit 0
    fi

    # Clear dialog and start build
    clear

    # Convert selected components to make targets
    local make_targets=""
    while IFS= read -r comp; do
        comp=$(echo "$comp" | tr -d '"')
        if [ -n "$comp" ]; then
            make_targets="$make_targets $(get_make_target "$comp")"
        fi
    done <<< "$SELECTED_COMPONENTS"

    # Trim whitespace
    make_targets=$(echo "$make_targets" | xargs)

    # If no components selected, use defaults
    if [ -z "$make_targets" ]; then
        echo "No components selected, using defaults..."
        make_targets="autoconf binutils gcc musl"
    fi

    # Build
    if [ "$BUILD_MODE" = "docker" ]; then
        build_docker "$make_targets"
    else
        build_local "$make_targets"
    fi
}

# Headless mode (non-interactive build)
main_headless() {
    local make_targets="$1"

    # Default to all core components if --all is specified
    if [ -z "$make_targets" ]; then
        make_targets="autoconf binutils gcc musl libtool"
    fi

    echo "======================================================================"
    echo "  x86_64-linux-musl Toolchain Build (Headless Mode)"
    echo "======================================================================"
    echo ""

    local build_dir=$(read_config_value "BUILD_DIR")
    local tool_root=$(read_config_value "TOOL_ROOT")

    echo "Components: $make_targets"
    echo "Build dir:  $build_dir"
    echo "Install to: $tool_root"
    echo ""

    # Build using make
    build_local "$make_targets"
}

# Parse command line arguments
HEADLESS=false
BUILD_TARGETS=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --headless)
            HEADLESS=true
            shift
            ;;
        --all)
            # --all means build all core components
            BUILD_TARGETS="autoconf binutils gcc musl libtool"
            shift
            ;;
        --help|-h)
            cat << EOF
Usage: $0 [OPTIONS] [COMPONENTS...]

Interactive toolchain builder using dialog (default mode).

OPTIONS:
  --headless          Non-interactive mode (skip dialog prompts)
  --all               Build all core components (autoconf, binutils, gcc, musl, libtool)
  --help, -h          Show this help message

COMPONENTS:
  autoconf            GNU Autoconf
  binutils            GNU Binutils (assembler, linker, etc.)
  gcc                 GNU Compiler Collection
  musl                musl libc (dynamic)
  musl-shared         musl libc (shared)
  libtool             GNU Libtool

EXAMPLES:
  $0                           # Interactive mode with dialog
  $0 --headless --all          # Build all components without prompts
  $0 --headless gcc musl       # Build only gcc and musl

NOTES:
  - In headless mode, configuration is read from local.mk or config.mk
  - Use local.mk to override default settings (see local.mk.example)
  - Interactive mode requires 'dialog' to be installed

EOF
            exit 0
            ;;
        *)
            # Treat as component name
            BUILD_TARGETS="$BUILD_TARGETS $1"
            shift
            ;;
    esac
done

# Trim whitespace
BUILD_TARGETS=$(echo "$BUILD_TARGETS" | xargs)

# Run appropriate mode
if $HEADLESS; then
    main_headless "$BUILD_TARGETS"
elif [ $# -eq 0 ] && [ -z "$BUILD_TARGETS" ]; then
    main
else
    # If we have targets but not headless, show error
    echo "ERROR: Component arguments require --headless mode"
    echo "Try: $0 --help"
    exit 1
fi
