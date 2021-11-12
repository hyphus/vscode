#!/bin/bash

set -e

function install_extension {
    EXTENSION_NAME="${1}"

    echo "Installing extension ${EXTENSION_NAME}..."
    # This is ugly and the API isn't publicly documented so you have to read the source to figure out the flags
    # The current flags only fetch the latest version of the plugin
    # https://github.com/microsoft/vscode/blob/main/src/vs/platform/extensionManagement/common/extensionGalleryService.ts
    API_PAYLOAD=$(cat <<EOF
{
        "assetTypes": null,
        "filters": [
            {
                "criteria": [
                    {
                        "filterType": 7,
                        "value": "${EXTENSION_NAME}"
                    }
                ],
                "direction": 2,
                "pageSize": 1,
                "pageNumber": 1,
                "sortBy": 0,
                "sortOrder": 0,
                "pagingToken": null
            }
        ],
        "flags": 0x202
}
EOF
)
    PLUGIN_INFO=$(curl -s -X POST https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json;api-version=6.1-preview.1' \
    -d "$API_PAYLOAD")

    # Skip any plugins without results
    if [ "$(echo "$PLUGIN_INFO" | jq -r '.results[].resultMetadata[].metadataItems[].count')" = 0 ]; then
        echo "Unable to find extension $EXTENSION_NAME. Ignoring."
        return
    fi

    VSIX_URL=$(echo "$PLUGIN_INFO" | jq -r '.results[].extensions[].versions[].files[] | select(.assetType=="Microsoft.VisualStudio.Services.VSIXPackage") | .source')
    VERSION=$(echo "$PLUGIN_INFO" | jq -r '.results[].extensions[].versions[].version')

    EXTENSION_PATH="${EXTENSIONS_DIR}/${EXTENSION_NAME}-${VERSION}"
    mkdir "$EXTENSION_PATH"

    # The VSIX file is actually just a zip file
    curl -s -o "/tmp/${EXTENSION_NAME}.zip" "$VSIX_URL"
    unzip -q "/tmp/${EXTENSION_NAME}.zip" "extension/*" -d "$EXTENSION_PATH"

    # The zip file contains a top level extension directory which isn't needed
    shopt -s dotglob
    mv "${EXTENSION_PATH}/extension"/* "${EXTENSION_PATH}/"
    rm -rf "${EXTENSION_PATH}/extension/"
    shopt -u dotglob
    echo "Done."
}

if [ "$(uname)" != "Linux" ]; then
    echo "$(uname) is unsupported."
    exit 1
fi

VSCODE_DIR="${HOME}/.vscode"

# Check if local setup or for remote
if [ "$1" = "--remote" ]; then
    echo "Configuring for vscode remote."
    VSCODE_DIR="${HOME}/.vscode-server"
fi

EXTENSIONS_DIR="${VSCODE_DIR}/extensions"
mkdir -p "$EXTENSIONS_DIR"

mkdir -p "$VSCODE_DIR/data/Machine"
cp settings.json "$VSCODE_DIR/data/Machine/settings.json"

while read -r extension; do
    install_extension "$extension"
done < ./extensions.txt
