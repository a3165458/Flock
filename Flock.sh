#!/bin/bash

# 检查是否以root用户运行脚本
if [ "$(id -u)" != "0" ]; then
    echo "此脚本需要以root用户权限运行。"
    echo "请尝试使用 'sudo -i' 命令切换到root用户，然后再次运行此脚本。"
    exit 1
fi

# 检查并安装 Conda
function install_conda() {
    if command -v conda > /dev/null 2>&1; then
        echo "Conda 已安装"
    else
        echo "Conda 未安装，正在安装..."
        wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh
        bash miniconda.sh -b -p $HOME/miniconda
        echo 'export PATH="$HOME/miniconda/bin:$PATH"' >> ~/.bashrc
        source ~/.bashrc
        conda init
        source ~/.bashrc
    fi
}

# 检查并安装 Node.js 和 npm
function install_nodejs_and_npm() {
    if command -v node > /dev/null 2>&1; then
        echo "Node.js 已安装"
    else
        echo "Node.js 未安装，正在安装..."
        curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi
    if command -v npm > /dev/null 2>&1; then
        echo "npm 已安装"
    else
        echo "npm 未安装，正在安装..."
        sudo apt-get install -y npm
    fi
}

# 检查并安装 PM2
function install_pm2() {
    if command -v pm2 > /dev/null 2>&1; then
        echo "PM2 已安装"
    else
        echo "PM2 未安装，正在安装..."
        npm install pm2@latest -g
    fi
}

function install_node() {
    install_conda
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
    source activate llm-loss-validator
    # 安装依赖
    pip install -r requirements.txt
    # 获取当前目录的绝对路径
    SCRIPT_DIR="$(pwd)"
    # 创建启动脚本
    cat << EOF > run_validator.sh
#!/bin/bash
source $HOME/miniconda/bin/activate llm-loss-validator
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
    pm2 start run_validator.sh --name "llm-loss-validator"
    echo "验证者节点已经启动."
}

function check_node() {
    pm2 logs llm-loss-validator
}

function uninstall_node() {
    pm2 delete llm-loss-validator && rm -rf llm-loss-validator
}

# 主菜单
function main_menu() {
    clear
    echo "脚本以及教程由推特用户大赌哥 @y95277777 编写，免费开源，请勿相信收费"
    echo "=========================Flock验证者节点安装======================================="
    echo "节点社区 Telegram 群组:https://t.me/niuwuriji"
    echo "节点社区 Telegram 频道:https://t.me/niuwuriji"
    echo "请选择要执行的操作:"
    echo "1. 安装常规节点"
    echo "2. 查看节点日志"
    echo "3. 删除节点"
    read -p "请输入选项（1-3）: " OPTION
    case $OPTION in
    1) install_node ;;
    2) check_node ;;
    3) uninstall_node ;;
    *) echo "无效选项。" ;;
    esac
}

# 显示主菜单
main_menu
