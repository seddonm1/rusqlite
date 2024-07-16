#!/bin/sh -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
echo "$SCRIPT_DIR"
cd "$SCRIPT_DIR" || { echo "fatal error" >&2; exit 1; }
cargo clean -p libsqlite3-sys
TARGET_DIR="$SCRIPT_DIR/../target"
export SQLITE3_LIB_DIR="$SCRIPT_DIR/sqlite3"
mkdir -p "$TARGET_DIR" "$SQLITE3_LIB_DIR"

# Download and build the amalgamation
# https://www.sqlite.org/src/info/e3f8c70ef5a7349c
SQLITE=e3f8c70e
curl -O https://www.sqlite.org/src/zip/$SQLITE/SQLite-$SQLITE.zip
unzip "SQLite-$SQLITE.zip"
cd "SQLite-$SQLITE"
bash configure
make sqlite3.c
cd ..
cp "SQLite-$SQLITE/sqlite3.c" "$SQLITE3_LIB_DIR/sqlite3.c"
cp "SQLite-$SQLITE/sqlite3.h" "$SQLITE3_LIB_DIR/sqlite3.h"
cp "SQLite-$SQLITE/sqlite3ext.h" "$SQLITE3_LIB_DIR/sqlite3ext.h"
rm -r "SQLite-$SQLITE"
rm -r "SQLite-$SQLITE.zip"

export SQLITE3_INCLUDE_DIR="$SQLITE3_LIB_DIR"
# Regenerate bindgen file for sqlite3.h
rm -f "$SQLITE3_LIB_DIR/bindgen_bundled_version.rs"
cargo update --quiet
# Just to make sure there is only one bindgen.rs file in target dir
find "$TARGET_DIR" -type f -name bindgen.rs -exec rm {} \;
env LIBSQLITE3_SYS_BUNDLING=1 cargo build --features "buildtime_bindgen session" --no-default-features
find "$TARGET_DIR" -type f -name bindgen.rs -exec mv {} "$SQLITE3_LIB_DIR/bindgen_bundled_version.rs" \;

# Regenerate bindgen file for sqlite3ext.h
# some sqlite3_api_routines fields are function pointers with va_list arg but currently stable Rust doesn't support this type.
# FIXME how to generate portable bindings without :
sed -i.bk -e 's/va_list/void*/' "$SQLITE3_LIB_DIR/sqlite3ext.h"
rm -f "$SQLITE3_LIB_DIR/bindgen_bundled_version_ext.rs"
find "$TARGET_DIR" -type f -name bindgen.rs -exec rm {} \;
env LIBSQLITE3_SYS_BUNDLING=1 cargo build --features "buildtime_bindgen loadable_extension" --no-default-features
find "$TARGET_DIR" -type f -name bindgen.rs -exec mv {} "$SQLITE3_LIB_DIR/bindgen_bundled_version_ext.rs" \;
git checkout "$SQLITE3_LIB_DIR/sqlite3ext.h"
rm -f "$SQLITE3_LIB_DIR/sqlite3ext.h.bk"

# Sanity checks
cd "$SCRIPT_DIR/.." || { echo "fatal error" >&2; exit 1; }
cargo update --quiet
cargo test --features "backup blob chrono functions limits load_extension serde_json trace vtab bundled"
printf '    \e[35;1mFinished\e[0m bundled sqlite3 tests\n'
