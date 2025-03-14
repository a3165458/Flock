#!/bin/bash
# Miniconda安装路径
MINICONDA_PATH="$HOME/miniconda"
CONDA_EXECUTABLE="$MINICONDA_PATH/bin/conda"

# 系统检测
OS_NAME=$(uname -s)
ARCH_NAME=$(uname -m)

# 自动选择 Miniconda 安装包
if [ "$OS_NAME" = "Darwin" ]; then
    OS_TYPE="mac"
    [ "$ARCH_NAME" = "arm64" ] && MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-arm64.sh" \
        || MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-x86_64.sh"
elif [ "$OS_NAME" = "Linux" ]; then
    OS_TYPE="linux"
    MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"
else
    echo "❌ 不支持的操作系统: $OS_NAME"
    exit 1
fi

# 仅 Linux 需要 root 检查
if [ "$OS_TYPE" = "linux" ] && [ "$(id -u)" != "0" ]; then
    echo "⚠️ 此脚本需要以 root 用户权限运行（仅限 Linux）"
    echo "请尝试使用 'sudo -i' 切换到 root 用户后运行"
    exit 1
fi

# Conda 初始化保障
ensure_conda_initialized() {
    if [ -f "$HOME/.bashrc" ]; then
        source "$HOME/.bashrc"
    elif [ -f "$HOME/.zshrc" ]; then
        source "$HOME/.zshrc"
    fi
    if [ -f "$CONDA_EXECUTABLE" ]; then
        eval "$("$CONDA_EXECUTABLE" shell.bash hook 2>/dev/null || "$CONDA_EXECUTABLE" shell.zsh hook)"
    fi
}

# 安装 Conda
install_conda() {
    if [ -f "$CONDA_EXECUTABLE" ]; then
        echo "✅ Conda 已安装于: $MINICONDA_PATH"
        ensure_conda_initialized
        return 0
    fi

    echo "🔧 正在安装 Miniconda..."
    curl -# -L "$MINICONDA_URL" -o miniconda.sh
    bash miniconda.sh -b -p "$MINICONDA_PATH"
    rm miniconda.sh

    # 初始化配置
    "$CONDA_EXECUTABLE" init
    ensure_conda_initialized

    # 环境变量配置
    if [ "$SHELL" = "/bin/zsh" ]; then
        echo 'export PATH="$HOME/miniconda/bin:$PATH"' >> ~/.zshrc
        source ~/.zshrc
    else
        echo 'export PATH="$HOME/miniconda/bin:$PATH"' >> ~/.bashrc
        source ~/.bashrc
    fi

    # 验证安装
    if command -v conda &>/dev/null; then
        echo "✅ Conda 安装成功 | 版本: $(conda --version)"
    else
        echo "❌ Conda 安装异常，请手动执行: source ~/.bashrc 或重新登录"
    fi
}

# 安装 Node.js 和 npm
install_nodejs_and_npm() {
    if command -v node >/dev/null; then
        echo "✅ Node.js 已安装 | 版本: $(node -v)"
    else
        echo "🔧 正在安装 Node.js..."
        if [ "$OS_TYPE" = "linux" ]; then
            curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
            sudo apt-get install -y nodejs git
        elif [ "$OS_TYPE" = "mac" ]; then
            brew install node
        fi
    fi

    if command -v npm >/dev/null; then
        echo "✅ npm 已安装 | 版本: $(npm -v)"
    else
        [ "$OS_TYPE" = "linux" ] && sudo apt-get install -y npm
    fi
}

# 安装 PM2
install_pm2() {
    if command -v pm2 >/dev/null; then
        echo "✅ PM2 已安装 | 版本: $(pm2 -v)"
    else
        echo "🔧 正在安装 PM2..."
        npm install pm2@latest -g
        
        # macOS 特殊配置
        if [ "$OS_TYPE" = "mac" ]; then
            echo "📝 请在 macOS 上手动执行以下命令完成 PM2 配置:"
            echo "1. pm2 save"
            echo "2. pm2 startup"
            echo "3. 执行上条命令输出的安装指令"
        fi
    fi
}

# 基础依赖安装
base_install() {
    echo "🔄 安装系统依赖..."
    if [ "$OS_TYPE" = "linux" ]; then
        apt update && apt upgrade -y
        apt install -y curl sudo git python3-venv iptables build-essential wget jq make gcc nano npm
    elif [ "$OS_TYPE" = "mac" ]; then
        # 自动安装 Homebrew
        if ! command -v brew &>/dev/null; then
            echo "🔧 正在安装 Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc
            source ~/.zshrc
        fi
        brew update
        brew install curl git python3 wget jq make gcc nano npm
    fi

    install_conda
    install_nodejs_and_npm
    install_pm2
}

# 安装验证者节点
install_node() {
    base_install

    read -p "🔑 输入 Hugging Face API: " HF_TOKEN
    read -p "🔑 输入 Flock API: " FLOCK_API_KEY
    read -p "📌 输入任务 ID: " TASK_ID

    echo "⬇️ 正在克隆验证者节点仓库..."
    git clone https://github.com/FLock-io/llm-loss-validator.git
    cd llm-loss-validator || exit 1

    echo "🐍 创建 Conda 环境..."
    conda create -n llm-loss-validator python==3.10 -y
    source "$MINICONDA_PATH/bin/activate" llm-loss-validator

    echo "📦 安装 Python 依赖..."
    pip install -r requirements.txt

    echo "📝 生成启动脚本..."
    SCRIPT_DIR=$(pwd)
    cat << EOF > run_validator.sh
#!/bin/bash
source "$MINICONDA_PATH/bin/activate" llm-loss-validator
cd $SCRIPT_DIR/src
CUDA_VISIBLE_DEVICES=0 \\
TIME_SLEEP=180 \\
bash start.sh \\
--hf_token "$HF_TOKEN" \\
--flock_api_key "$FLOCK_API_KEY" \\
--task_id "$TASK_ID" \\
--validation_args_file validation_config.json.example \\
--auto_clean_cache True
EOF

    chmod +x run_validator.sh
    pm2 start run_validator.sh --name "llm-loss-validator" && pm2 save

    # 添加 GitHub 仓库更新检测脚本
    echo "📝 生成 GitHub 仓库更新检测脚本..."
    cat << EOF > check_update.sh
#!/bin/bash
source "$MINICONDA_PATH/bin/activate" llm-loss-validator
cd $SCRIPT_DIR || exit 1

# 获取远程仓库最新提交哈希
REMOTE_HASH=\$(git ls-remote https://github.com/FLock-io/llm-loss-validator.git HEAD | awk '{print \$1}')
# 获取本地仓库最新提交哈希
LOCAL_HASH=\$(git rev-parse HEAD)

# 比较哈希值，判断是否有更新
if [ "\$REMOTE_HASH" != "\$LOCAL_HASH" ]; then
    echo "🔄 检测到 GitHub 仓库更新，正在拉取最新代码..."
    git pull
    pm2 restart llm-loss-validator
    echo "✅ 验证者节点已更新并重启"
else
    echo "✅ 仓库已是最新版本，无需更新"
fi
EOF

    chmod +x check_update.sh
    # 使用 PM2 每小时运行一次更新检测，添加 --no-autorestart
    pm2 start check_update.sh --name "llm-loss-validator-update" --cron "0 */1 * * *" --no-autorestart && pm2 save

    # Linux 自动配置开机启动
    [ "$OS_TYPE" = "linux" ] && pm2 startup

    echo "🎉 验证者节点已启动！使用 'pm2 logs llm-loss-validator' 查看日志"
    echo "🔄 已启用 GitHub 仓库自动更新检测，每小时检查一次，使用 'pm2 logs llm-loss-validator-update' 查看更新日志"
}

# 安装训练节点
install_train_node() {
    base_install

    echo "⬇️ 正在克隆训练节点仓库..."
    git clone https://github.com/FLock-io/testnet-training-node-quickstart.git
    cd testnet-training-node-quickstart || exit 1

    echo "🐍 创建 Conda 环境..."
    conda create -n training-node python==3.10 -y
    source "$MINICONDA_PATH/bin/activate" training-node

    echo "📦 安装 Python 依赖..."
    pip install -r requirements.txt

    read -p "📌 输入任务 ID: " TASK_ID
    read -p "🔑 输入 Flock API Key: " FLOCK_API_KEY
    read -p "🔑 输入 Hugging Face Token: " HF_TOKEN
    read -p "👤 输入 Hugging Face 用户名: " HF_USERNAME

    echo "📝 生成训练节点脚本..."
    cat << EOF > run_training_node.sh
#!/bin/bash
source "$MINICONDA_PATH/bin/activate" training-node
TASK_ID=$TASK_ID FLOCK_API_KEY="$FLOCK_API_KEY" HF_TOKEN="$HF_TOKEN"
CUDA_VISIBLE_DEVICES=0 HF_USERNAME="$HF_USERNAME" python full_automation.py
EOF

    chmod +x run_training_node.sh
    pm2 start run_training_node.sh --name "flock-training-node" && pm2 save

    # Linux 自动配置开机启动
    [ "$OS_TYPE" = "linux" ] && pm2 startup

    echo "🎉 训练节点已启动！使用 'pm2 logs flock-training-node' 查看日志"
}

# 节点管理功能
check_node() { pm2 logs llm-loss-validator; }
uninstall_node() { 
    pm2 delete llm-loss-validator
    pm2 delete llm-loss-validator-update
    rm -rf llm-loss-validator
}
update_task_id() {
    read -p "🆔 输入新任务 ID: " NEW_TASK_ID
    
    # 更新验证者节点
    if [ -f "llm-loss-validator/run_validator.sh" ]; then
        sed -i "s/--task_id \".*\"/--task_id \"$NEW_TASK_ID\"/" llm-loss-validator/run_validator.sh
        pm2 restart llm-loss-validator
        echo "🔄 验证者节点任务 ID 已更新"
    fi
    
    # 更新训练节点
    if [ -f "testnet-training-node-quickstart/run_training_node.sh" ]; then
        sed -i "s/TASK_ID=.*/TASK_ID=$NEW_TASK_ID/" testnet-training-node-quickstart/run_training_node.sh
        pm2 restart flock-training-node
        echo "🔄 训练节点任务 ID 已更新"
    fi
}

update_node() {
    # 更新验证者节点
    if [ -d "llm-loss-validator" ]; then
        echo "🔄 升级验证者节点..."
        cd llm-loss-validator && git pull
        source "$MINICONDA_PATH/bin/activate" llm-loss-validator
        pip install -r requirements.txt
        pm2 restart llm-loss-validator
    fi

    # 更新训练节点
    if [ -d "testnet-training-node-quickstart" ]; then
        echo "🔄 升级训练节点..."
        cd testnet-training-node-quickstart && git pull
        source "$MINICONDA_PATH/bin/activate" training-node
        pip install -r requirements.txt
        pm2 restart flock-training-node
    fi
}

# 主菜单界面
main_menu() {
    clear
    echo "🌟 FLock 节点管理脚本 v2.0 | 支持 macOS/Linux"
    echo "📢 社区: https://t.me/niuwuriji"
    echo "-----------------------------------------------"
    echo "1. 安装验证者节点"
    echo "2. 安装训练节点"
    echo "3. 查看验证者日志"
    echo "4. 查看训练日志"
    echo "5. 删除验证者节点"
    echo "6. 删除训练节点"
    echo "7. 更新任务 ID"
    echo "8. 升级所有节点"
    echo "0. 退出脚本"
    echo "-----------------------------------------------"
    
    read -p "➡️ 请输入选项 (0-8): " OPTION
    case $OPTION in
        1) install_node ;;
        2) install_train_node ;;
        3) check_node ;;
        4) pm2 logs flock-training-node ;;
        5) uninstall_node ;;
        6) pm2 delete flock-training-node && rm -rf testnet-training-node-quickstart ;;
        7) update_task_id ;;
        8) update_node ;;
        0) exit 0 ;;
        *) echo "❌ 无效选项，请重新输入" ;;
    esac
    
    read -n 1 -s -r -p "🔄 按任意键返回主菜单..."
    main_menu
}

# 启动脚本
main_menu
