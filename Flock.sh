#!/bin/bash
# Miniconda安装路径
MINICONDA_PATH="$HOME/miniconda"
CONDA_EXECUTABLE="$MINICONDA_PATH/bin/conda"

# 检查是否以root用户运行脚本
if [ "$(id -u)" != "0" ]; then
    echo "此脚本需要以root用户权限运行。"
    echo "请尝试使用 'sudo -i' 命令切换到root用户，然后再次运行此脚本。"
    exit 1
fi

# 确保 conda 被正确初始化
ensure_conda_initialized() {
    if [ -f "$HOME/.bashrc" ]; then
        source "$HOME/.bashrc"
    fi
    if [ -f "$CONDA_EXECUTABLE" ]; then
        eval "$("$CONDA_EXECUTABLE" shell.bash hook)"
    fi
}

# 检查并安装 Conda
function install_conda() {
    if [ -f "$CONDA_EXECUTABLE" ]; then
        echo "Conda 已安装在 $MINICONDA_PATH"
        ensure_conda_initialized
    else
        echo "Conda 未安装，正在安装..."
        wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh
        bash miniconda.sh -b -p $MINICONDA_PATH
        rm miniconda.sh
        
        # 初始化 conda
        "$CONDA_EXECUTABLE" init
        ensure_conda_initialized
        
        echo 'export PATH="$HOME/miniconda/bin:$PATH"' >> ~/.bashrc
        source ~/.bashrc
    fi
    
    # 验证 conda 是否可用
    if command -v conda &> /dev/null; then
        echo "Conda 安装成功，版本: $(conda --version)"
    else
        echo "Conda 安装可能成功，但无法在当前会话中使用。"
        echo "请在脚本执行完成后，重新登录或运行 'source ~/.bashrc' 来激活 Conda。"
    fi
}

# 检查并安装 Node.js 和 npm
function install_nodejs_and_npm() {
    if command -v node > /dev/null 2>&1; then
        echo "Node.js 已安装，版本: $(node -v)"
    else
        echo "Node.js 未安装，正在安装..."
        curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi
    if command -v npm > /dev/null 2>&1; then
        echo "npm 已安装，版本: $(npm -v)"
    else
        echo "npm 未安装，正在安装..."
        sudo apt-get install -y npm
    fi
}

# 检查并安装 PM2
function install_pm2() {
    if command -v pm2 > /dev/null 2>&1; then
        echo "PM2 已安装，版本: $(pm2 -v)"
    else
        echo "PM2 未安装，正在安装..."
        npm install pm2@latest -g
    fi
}

function install_node() {
    install_conda
    ensure_conda_initialized
    install_nodejs_and_npm
    install_pm2
    apt update && apt upgrade -y
    apt install curl sudo python3-venv iptables build-essential wget jq make gcc nano npm -y
    read -p "输入Hugging face API: " HF_TOKEN
    read -p "输入Flock API: " FLOCK_API_KEY
    read -p "输入任务ID: " TASK_ID
    # 克隆仓库
    git clone https://github.com/FLock-io/llm-loss-validator.git
    # 进入项目目录
    cd llm-loss-validator
    # 创建并激活conda环境
    conda create -n llm-loss-validator python==3.10 -y
    source "$MINICONDA_PATH/bin/activate" llm-loss-validator
    # 安装依赖
    pip install -r requirements.txt
    # 获取当前目录的绝对路径
    SCRIPT_DIR="$(pwd)"
    # 创建启动脚本
    cat << EOF > run_validator.sh
#!/bin/bash
source "$MINICONDA_PATH/bin/activate" llm-loss-validator
cd $SCRIPT_DIR/src
CUDA_VISIBLE_DEVICES=0 \
bash start.sh \
--hf_token "$HF_TOKEN" \
--flock_api_key "$FLOCK_API_KEY" \
--task_id "$TASK_ID" \
--validation_args_file validation_config.json.example \
--auto_clean_cache False
EOF
    chmod +x run_validator.sh
    pm2 start run_validator.sh --name "llm-loss-validator" -- start && pm2 save && pm2 startup
    echo "验证者节点已经启动."
}

function check_node() {
    pm2 logs llm-loss-validator
}

function uninstall_node() {
    pm2 delete llm-loss-validator && rm -rf llm-loss-validator
}

function install_train_node() {
    install_conda
    ensure_conda_initialized
    install_nodejs_and_npm
    install_pm2
    
    # 安装必要的工具
    apt update && apt upgrade -y
    apt install curl sudo python3-venv iptables build-essential wget jq make gcc nano git -y
    
    # 克隆 QuickStart 仓库
    git clone https://github.com/FLock-io/testnet-training-node-quickstart.git
    cd testnet-training-node-quickstart
    
    # 创建并激活 conda 环境
    conda create -n training-node python==3.10 -y
    source "$MINICONDA_PATH/bin/activate" training-node
    
    # 安装依赖
    pip install -r requirements.txt
    
    # 获取必要信息
    read -p "输入任务ID (TASK_ID): " TASK_ID
    read -p "输入Flock API Key: " FLOCK_API_KEY
    read -p "输入Hugging Face Token: " HF_TOKEN
    read -p "输入Hugging Face 用户名: " HF_USERNAME
    
    # 创建运行脚本
    cat << EOF > run_training_node.sh
#!/bin/bash
source "$MINICONDA_PATH/bin/activate" training-node
TASK_ID=$TASK_ID FLOCK_API_KEY="$FLOCK_API_KEY" HF_TOKEN="$HF_TOKEN" CUDA_VISIBLE_DEVICES=0 HF_USERNAME="$HF_USERNAME" python full_automation.py
EOF
    
    chmod +x run_training_node.sh
    
    # 使用 PM2 启动训练节点
    pm2 start run_training_node.sh --name "flock-training-node" -- start && pm2 save && pm2 startup
    
    echo "训练节点已启动。您可以使用 'pm2 logs flock-training-node' 查看日志。"
}

function update_task_id() {
    read -p "输入新的任务ID (TASK_ID): " NEW_TASK_ID
    
    # 更新验证者节点的 Task ID
    if [ -f "llm-loss-validator/run_validator.sh" ]; then
        sed -i "s/--task_id \".*\"/--task_id \"$NEW_TASK_ID\"/" llm-loss-validator/run_validator.sh
        pm2 restart llm-loss-validator
        echo "验证者节点的 Task ID 已更新并重启。"
    else
        echo "未找到验证者节点的运行脚本。"
    fi
    
    # 更新训练节点的 Task ID
    if [ -f "testnet-training-node-quickstart/run_training_node.sh" ]; then
        sed -i "s/TASK_ID=.*/TASK_ID=$NEW_TASK_ID/" testnet-training-node-quickstart/run_training_node.sh
        pm2 restart flock-training-node
        echo "训练节点的 Task ID 已更新并重启。"
    else
        echo "未找到训练节点的运行脚本。"
    fi
}

# 升级节点
function update_node() {
    # 升级验证者节点
    if [ -d "llm-loss-validator" ]; then
        cd llm-loss-validator && git pull && pm2 restart llm-loss-validator
        echo "验证者节点已升级."
    else
        echo "未找到验证者节点目录."
    fi

    # 升级训练节点
    if [ -d "testnet-training-node-quickstart" ]; then
        cd testnet-training-node-quickstart && git pull && pm2 restart flock-training-node
        echo "训练节点已升级."
    else
        echo "未找到训练节点目录."
    fi
}

# 主菜单
function main_menu() {
    clear
    echo "脚本以及教程由推特用户大赌哥 @y95277777 编写，免费开源，请勿相信收费"
    echo "=========================Flock节点安装======================================="
    echo "节点社区 Telegram 群组:https://t.me/niuwuriji"
    echo "节点社区 Telegram 频道:https://t.me/niuwuriji"
    echo "请选择要执行的操作:"
    echo "1. 安装验证者节点"
    echo "2. 安装训练节点"
    echo "3. 查看验证者节点日志"
    echo "4. 查看训练节点日志"
    echo "5. 删除常规节点"
    echo "6. 删除训练节点"
    echo "7. 修改任务 ID 并重启节点"
    echo "8. 升级节点"
    read -p "请输入选项（1-8）: " OPTION
    case $OPTION in
    1) install_node ;;
    2) install_train_node ;;
    3) check_node ;;
    4) pm2 logs flock-training-node ;;
    5) uninstall_node ;;
    6) pm2 delete flock-training-node && rm -rf testnet-training-node-quickstart ;;
    7) update_task_id ;;
    8) update_node ;;  # 添加升级节点功能
    *) echo "无效选项。" ;;
    esac
}

# 显示主菜单
main_menu
