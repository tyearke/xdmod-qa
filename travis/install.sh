#!/usr/bin/env bash

# Install required components for Travis tests.

script_dir="$(cd "$(dirname $0)" || exit 2; pwd -P)"
qa_dir="$(dirname "$script_dir")"

source "$script_dir/helpers.sh"

# Check that this repo has been set up for Travis correctly and exit if not.
repo_type="$("$script_dir/check-repo-type.sh")"
if [ "$repo_type" == "unknown" ]; then
    echo "Repository has not been properly set up to use XDMoD Travis scripts." >&2
    exit 2
fi

# For the remainder of this script, quit immediately if a command fails.
set -e

# Install global dependencies.
start_travis_fold global-dependencies
echo "Installing global dependencies..."

#fix for https://github.com/travis-ci/travis-ci/issues/8365
pear config-set php_dir "$(php -r 'echo substr(get_include_path(),2);')"

# Update PEAR.
pear channel-update pear.php.net

# Install core's PEAR dependencies.
pear install --alldeps Log

end_travis_fold global-dependencies
echo

# Initialize variables for tracking application-level package manager initialization.
composer_initialized=false
npm_initialized=false

# Install application-level dependencies declared in the given directory.
#
# Args:
#     $1: The directory to install dependencies for.
function install_dependencies() {
    dir_path="$1"
    dir_name="$(basename "$dir_path")"

    start_travis_fold "$dir_name-dependencies"
    echo "Installing dependencies for \"$dir_path\"..."
    pushd "$dir_path" >/dev/null

    # If Composer dependencies are declared, install them.
    if [ -e "composer.json" ]; then
        # If Composer has not been initialized yet, do so.
        if ! $composer_initialized; then
            echo "Updating Composer..."
            composer self-update --stable
            composer_initialized=true
        fi

        composer install
    fi

    # If npm dependencies are declared, install them.
    if [ -e "package.json" ]; then
        # If npm has not been initialized yet, do so.
        if ! $npm_initialized; then
            # If set, use version of Node set in environment variable.
            if [ -n "$NODE_VERSION" ]; then
                source ~/.nvm/nvm.sh
                nvm install "$NODE_VERSION"
                nvm use "$NODE_VERSION"
            fi

            # Update npm.
            echo "Updating npm..."
            npm update -g npm

            npm_initialized=true
        fi

        # Install repo's npm dependencies.
        echo "Installing npm dependencies..."
        npm install
    fi

    popd >/dev/null
    end_travis_fold "$dir_name-dependencies"
    echo
}

# Install QA dependencies.
install_dependencies "$qa_dir"

# If this repo is a module, get and set up the corresponding version of Open XDMoD.
if [ "$repo_type" == "module" ]; then
    start_travis_fold open-xdmod
    echo "Obtaining and integrating with Open XDMoD code..."

    xdmod_branch="$TRAVIS_BRANCH"
    echo "Cloning Open XDMoD branch '$xdmod_branch'"
    git clone --depth=1 --branch="$xdmod_branch" https://github.com/ubccr/xdmod.git "$XDMOD_SOURCE_DIR"

    pushd "$XDMOD_SOURCE_DIR" >/dev/null
    echo "Retrieving Open XDMoD submodules..."
    git submodule update --init --recursive
    popd >/dev/null

    # Create a symlink from Open XDMoD to this module.
    ln -s "$(pwd)" "$XDMOD_SOURCE_DIR/open_xdmod/modules/$XDMOD_MODULE_DIR"

    end_travis_fold open-xdmod
    echo

    # Install Open XDMoD dependencies.
    install_dependencies "$XDMOD_SOURCE_DIR"
fi

# Install this repo's dependencies.
install_dependencies "$(pwd)"
