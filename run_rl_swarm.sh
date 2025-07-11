#!/bin/bash

set -euo pipefail

# General arguments
ROOT=$PWD

# GenRL Swarm version to use
GENRL_SWARM_TAG="v0.1.1"

export IDENTITY_PATH
export GENSYN_RESET_CONFIG
export CONNECT_TO_TESTNET=true
export ORG_ID
export HF_HUB_DOWNLOAD_TIMEOUT=120  # 2 minutes
export SWARM_CONTRACT="0xFaD7C5e93f28257429569B854151A1B8DCD404c2"
export HUGGINGFACE_ACCESS_TOKEN="None"

# Path to an RSA private key. If this path does not exist, a new key pair will be created.
# Remove this file if you want a new PeerID.
DEFAULT_IDENTITY_PATH="$ROOT"/swarm.pem
IDENTITY_PATH=${IDENTITY_PATH:-$DEFAULT_IDENTITY_PATH}

DOCKER=${DOCKER:-""}
GENSYN_RESET_CONFIG=${GENSYN_RESET_CONFIG:-""}

# Bit of a workaround for the non-root docker container.
if [ -n "$DOCKER" ]; then
    volumes=(
        /home/gensyn/rl_swarm/modal-login/temp-data
        /home/gensyn/rl_swarm/keys
        /home/gensyn/rl_swarm/configs
        /home/gensyn/rl_swarm/logs
    )

    for volume in ${volumes[@]}; do
        sudo chown -R 1001:1001 $volume
    done
fi

# Will ignore any visible GPUs if set.
CPU_ONLY=${CPU_ONLY:-""}

# Set if successfully parsed from modal-login/temp-data/userData.json.
ORG_ID=${ORG_ID:-""}

GREEN_TEXT="\033[32m"
BLUE_TEXT="\033[34m"
RED_TEXT="\033[31m"
RESET_TEXT="\033[0m"

echo_green() {
    echo -e "$GREEN_TEXT$1$RESET_TEXT"
}

echo_blue() {
    echo -e "$BLUE_TEXT$1$RESET_TEXT"
}

echo_red() {
    echo -e "$RED_TEXT$1$RESET_TEXT"
}

ROOT_DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"

# Function to clean up the server process upon exit
cleanup() {
    echo_green ">> Shutting down trainer..."

    # Remove modal credentials if they exist
    rm -r $ROOT_DIR/modal-login/temp-data/*.json 2> /dev/null || true

    # Kill all processes belonging to this script's process group
    kill -- -$$ || true

    exit 0
}

errnotify() {
    echo_red ">> An error was detected while running rl-swarm. See $ROOT/logs for full logs."
}

trap cleanup EXIT
trap errnotify ERR

echo -e "\033[38;5;224m"
cat << "EOF"
    ██████  ██            ███████ ██     ██  █████  ██████  ███    ███
    ██   ██ ██            ██      ██     ██ ██   ██ ██   ██ ████  ████
    ██████  ██      █████ ███████ ██  █  ██ ███████ ██████  ██ ████ ██
    ██   ██ ██                 ██ ██ ███ ██ ██   ██ ██   ██ ██  ██  ██
    ██   ██ ███████       ███████  ███ ███  ██   ██ ██   ██ ██      ██

    From Gensyn

EOF

# Create logs directory if it doesn't exist
mkdir -p "$ROOT/logs"

# 跳过 modal-login，直接使用预配置的用户信息
if [ "$CONNECT_TO_TESTNET" = true ]; then
    # 检查是否存在预配置的用户数据
    if [ -f "user/modal-login/userData.json" ] && [ -f "user/modal-login/userApiKey.json" ]; then
        echo_green ">> 使用预配置的用户数据跳过登录流程..."
        # Your ORG_ID is set to: 32b8810d-ed3c-4136-a1e7-8a9892d724e5
        # 从预配置文件中读取 ORG_ID
        ORG_ID=$(awk 'BEGIN { FS = "\"" } !/^[ \t]*[{}]/ { print $(NF - 1); exit }' user/modal-login/userData.json)
        echo "Your ORG_ID is set to: $ORG_ID"
        
        # 检查API密钥是否已激活
        API_ACTIVATED=$(grep -o '"activated": true' user/modal-login/userApiKey.json | head -1)
        if [ -n "$API_ACTIVATED" ]; then
            echo_green ">> API密钥已激活，跳过激活等待..."
        else
            echo_red ">> 警告：API密钥未激活，可能需要手动激活"
        fi
        
        # 设置环境变量
        export ORG_ID
        export HUGGINGFACE_ACCESS_TOKEN="None"
    else
        echo_red ">> 未找到预配置的用户数据文件，使用默认ORG_ID"
        export ORG_ID="0xd8875f272d8Ce09Ae37D6F1B9cC79d88a24AA2c7"
        export HUGGINGFACE_ACCESS_TOKEN="None"
    fi
else
    # 如果不需要连接测试网，设置默认值
    export ORG_ID="0xd8875f272d8Ce09Ae37D6F1B9cC79d88a24AA2c7"
    export HUGGINGFACE_ACCESS_TOKEN="None"
fi

# 原有 modal-login 登录流程已被注释掉
# if [ "$CONNECT_TO_TESTNET" = true ]; then
#     # Run modal_login server.
#     echo "Please login to create an Ethereum Server Wallet"
#     cd modal-login
#     # Check if the yarn command exists; if not, install Yarn.

#     # Node.js + NVM setup
#     if ! command -v node > /dev/null 2>&1; then
#         echo "Node.js not found. Installing NVM and latest Node.js..."
#         export NVM_DIR="$HOME/.nvm"
#         if [ ! -d "$NVM_DIR" ]; then
#             curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
#         fi
#         [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
#         [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
#         nvm install node
#     else
#         echo "Node.js is already installed: $(node -v)"
#     fi

#     if ! command -v yarn > /dev/null 2>&1; then
#         # Detect Ubuntu (including WSL Ubuntu) and install Yarn accordingly
#         if grep -qi "ubuntu" /etc/os-release 2> /dev/null || uname -r | grep -qi "microsoft"; then
#             echo "Detected Ubuntu or WSL Ubuntu. Installing Yarn via apt..."
#             curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
#             echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
#             sudo apt update && sudo apt install -y yarn
#         else
#             echo "Yarn not found. Installing Yarn globally with npm (no profile edits)…"
#             # This lands in $NVM_DIR/versions/node/<ver>/bin which is already on PATH
#             npm install -g --silent yarn
#         fi
#     fi

#     ENV_FILE="$ROOT"/modal-login/.env
#     if [[ "$OSTYPE" == "darwin"* ]]; then
#         # macOS version
#         sed -i '' "3s/.*/SMART_CONTRACT_ADDRESS=$SWARM_CONTRACT/" "$ENV_FILE"
#     else
#         # Linux version
#         sed -i "3s/.*/SMART_CONTRACT_ADDRESS=$SWARM_CONTRACT/" "$ENV_FILE"
#     fi


#     # Docker image already builds it, no need to again.
#     if [ -z "$DOCKER" ]; then
#         yarn install --immutable
#         echo "Building server"
#         yarn build > "$ROOT/logs/yarn.log" 2>&1
#     fi
#     yarn start >> "$ROOT/logs/yarn.log" 2>&1 & # Run in background and log output

#     SERVER_PID=$!  # Store the process ID
#     echo "Started server process: $SERVER_PID"
#     sleep 5

#     # Try to open the URL in the default browser
#     if [ -z "$DOCKER" ]; then
#         if open http://localhost:3000 2> /dev/null; then
#             echo_green ">> Successfully opened http://localhost:3000 in your default browser."
#         else
#             echo ">> Failed to open http://localhost:3000. Please open it manually."
#         fi
#     else
#         echo_green ">> Please open http://localhost:3000 in your host browser."
#     fi

#     cd ..

#     echo_green ">> Waiting for modal userData.json to be created..."
#     while [ ! -f "modal-login/temp-data/userData.json" ]; do
#         sleep 5  # Wait for 5 seconds before checking again
#     done
#     echo "Found userData.json. Proceeding..."

#     ORG_ID=$(awk 'BEGIN { FS = "\"" } !/^[ \t]*[{}]/ { print $(NF - 1); exit }' modal-login/temp-data/userData.json)
#     echo "Your ORG_ID is set to: $ORG_ID"

#     # Wait until the API key is activated by the client
#     echo "Waiting for API key to become activated..."
#     while true; do
#         STATUS=$(curl -s "http://localhost:3000/api/get-api-key-status?orgId=$ORG_ID")
#         if [[ "$STATUS" == "activated" ]]; then
#             echo "API key is activated! Proceeding..."
#             break
#         else
#             echo "Waiting for API key to be activated..."
#             sleep 5
#         fi
#     done
# fi

echo_green ">> Getting requirements..."
pip install --upgrade pip

# Clone GenRL repository to user's working directory
echo_green ">> Initializing and updating GenRL..."
if [ ! -d "$ROOT/genrl-swarm" ]; then
    git clone --depth=1 --branch "$GENRL_SWARM_TAG" https://github.com/gensyn-ai/genrl-swarm.git "$ROOT/genrl-swarm"
else
    # Check if we are on the correct tag
    cd "$ROOT/genrl-swarm"
    CURRENT_TAG=$(git describe --tags --exact-match 2>/dev/null || echo "unknown")
    if [ "$CURRENT_TAG" != "$GENRL_SWARM_TAG" ]; then
        echo_green ">> Updating genrl-swarm to tag $GENRL_SWARM_TAG..."
        git fetch --tags
        git checkout "$GENRL_SWARM_TAG"
        git pull origin "$GENRL_SWARM_TAG"
    fi
    cd "$ROOT"
fi

echo_green ">> Installing GenRL."
if [ -d "$ROOT/genrl-swarm" ]; then
    cd "$ROOT/genrl-swarm"
    pip install -e .[examples]
    cd "$ROOT"
else
    echo_red "Error: genrl-swarm submodule not found at $ROOT/genrl-swarm"
    exit 1
fi


if [ ! -d "$ROOT/configs" ]; then
    mkdir "$ROOT/configs"
fi

if [ -f "$ROOT/configs/rg-swarm.yaml" ]; then
    # Use cmp -s for a silent comparison. If different, backup and copy.
    if ! cmp -s "$ROOT/genrl-swarm/recipes/rgym/rg-swarm.yaml" "$ROOT/configs/rg-swarm.yaml"; then
        if [ -z "$GENSYN_RESET_CONFIG" ]; then
            echo_green ">> Found differences in rg-swarm.yaml. If you would like to reset to the default, set GENSYN_RESET_CONFIG to a non-empty value."
        else
            echo_green ">> Found differences in rg-swarm.yaml. Backing up existing config."
            mv "$ROOT/configs/rg-swarm.yaml" "$ROOT/configs/rg-swarm.yaml.bak"
            cp "$ROOT/genrl-swarm/recipes/rgym/rg-swarm.yaml" "$ROOT/configs/rg-swarm.yaml"
        fi
    fi
else
    # If the config doesn't exist, just copy it.
    cp "$ROOT/genrl-swarm/recipes/rgym/rg-swarm.yaml" "$ROOT/configs/rg-swarm.yaml"
fi

if [ -n "$DOCKER" ]; then
    # Make it easier to edit the configs on Linux systems.
    sudo chmod -R 0777 /home/gensyn/rl_swarm/configs
fi

echo_green ">> Done!"

# 跳过 Hugging Face 上传交互，直接设置为 None
# HF_TOKEN=${HF_TOKEN:-""}
# if [ -n "${HF_TOKEN}" ]; then # Check if HF_TOKEN is already set and use if so. Else give user a prompt to choose.
#     HUGGINGFACE_ACCESS_TOKEN=${HF_TOKEN}
# else
#     echo -en $GREEN_TEXT
#     read -p ">> Would you like to push models you train in the RL swarm to the Hugging Face Hub? [y/N] " yn
#     echo -en $RESET_TEXT
#     yn=${yn:-N} # Default to "N" if the user presses Enter
#     case $yn in
#         [Yy]*) read -p "Enter your Hugging Face access token: " HUGGINGFACE_ACCESS_TOKEN ;;
#         [Nn]*) HUGGINGFACE_ACCESS_TOKEN="None" ;;
#         *) echo ">>> No answer was given, so NO models will be pushed to Hugging Face Hub" && HUGGINGFACE_ACCESS_TOKEN="None" ;;
#     esac
# fi
export HUGGINGFACE_ACCESS_TOKEN="None"

# 强制设置模型名称
MODEL_NAME="Qwen/Qwen3-0.6B"
export MODEL_NAME
echo_green ">> Using model: $MODEL_NAME"
echo_green ">> Models will not be pushed to Hugging Face Hub"

echo_green ">> Good luck in the swarm!"
echo_blue ">> And remember to star the repo on GitHub! --> https://github.com/gensyn-ai/rl-swarm"

python "$ROOT/genrl-swarm/src/genrl_swarm/runner/swarm_launcher.py" \
    --config-path "$ROOT/configs" \
    --config-name "rg-swarm.yaml"

wait
