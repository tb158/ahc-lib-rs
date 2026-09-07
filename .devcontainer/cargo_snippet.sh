#!/bin/bash

# This script generates Rust code snippets for Visual Studio Code in the context of Competitive Programming.

# Public mirror of src/lib. Every generated snippet body starts with this URL so that
# submitted code carries the provenance link AtCoder's generative-AI rule requires
# (code written before a contest must be published beforehand and its URL noted in
# the relevant part of the submission).
LIB_URL="https://github.com/tb158/ahc-lib-rs"

# Navigate to the lib directory within the workspace folder
cd $WORKSPACE_FOLDER/src/lib

# Run the tests silently. Exit with an error if tests fail.
if ! cargo test &>/dev/null; then
    echo "Error: Tests failed."
    exit 1
fi

# Generate Rust code snippets using cargo-snippet, then post-process the JSON with sed:
#   1. add "scope": "rust" so the snippets only fire inside Rust files
#   2. insert $LIB_URL as a comment on the first line of every snippet body
# and finally, save the modified output to a rust.code-snippets file in the .vscode directory of the workspace folder
cargo snippet -t vscode \
    | sed -r \
        -e 's|^(\s*)"prefix"|\1"scope": "rust",\n\1"prefix"|' \
        -e 's|^(\s*)"body": \[$|\1"body": [\n\1  "// '"$LIB_URL"'",|' \
    > $WORKSPACE_FOLDER/.vscode/rust.code-snippets
echo "Snippets generated."
