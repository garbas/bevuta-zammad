#!/usr/bin/env bash
set -e


VERSION=$1
TARGET_DIR="$PWD"
WORK_DIR=$(mktemp -d)
SOURCE_DIR=$WORK_DIR/zammad-$VERSION


rm -rf \
    ./source.json \
    ./gemset.nix \
    ./yarn.lock \
    ./yarn.nix


# Check that working directory was created.
if [[ ! "$WORK_DIR" || ! -d "$WORK_DIR" ]]; then
    echo "Could not create temporary directory."
    exit 1
fi

# Delete the working directory on exit.
function cleanup {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT


pushd $WORK_DIR

echo ":: Creating source.json"
nix-prefetch-github zammad zammad --rev $VERSION --json > $TARGET_DIR/source.json

echo ":: Fetching source"
curl -L https://github.com/zammad/zammad/archive/$VERSION.tar.gz --output source.tar.gz
tar zxf source.tar.gz

if [[ ! "$SOURCE_DIR" || ! -d "$SOURCE_DIR" ]]; then
    echo "Source directory does not exists."
    exit 1
fi

pushd $SOURCE_DIR

echo ":: Creating gemset.nix"
bundix --lockfile=./Gemfile.lock  --gemfile=./Gemfile --gemset=$TARGET_DIR/gemset.nix

echo ":: Creating yarn.nix"
yarn install
cp yarn.lock $TARGET_DIR
yarn2nix > $TARGET_DIR/yarn.nix

popd
popd
