#!/bin/bash

# ================= 配置区域 (Configuration) =================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_JSON="$SCRIPT_DIR/config/models.json"

load_model() {
    local alias="$1" side="$2"
    eval "$(python3 - "$MODELS_JSON" "$alias" "$side" <<'PY'
import json, sys
path, alias, side = sys.argv[1], sys.argv[2], sys.argv[3].upper()
with open(path, encoding="utf-8") as f:
    data = {k: v for k, v in json.load(f).items() if not k.startswith("_") and isinstance(v, dict)}
if alias not in data:
    sys.exit(f"Unknown model '{alias}' in {path}")
cfg, p = data[alias], f"MODEL_{side}"
r = "True" if cfg.get("use_reasoning") else "False"
fields = {
    f"{p}_NAME": cfg.get("model_name", alias),
    f"{p}_API_KEY": cfg["api_key"],
    f"{p}_BASE_URL": cfg["base_url"],
    f"{p}_TEMP": str(cfg.get("temperature", "None")),
    f"{p}_TOP_P": str(cfg.get("top_p", "None")),
    f"{p}_MAX_TOKENS": str(cfg.get("max_tokens", "None")),
    f"{p}_USE_REASONING": r,
}
for k, v in fields.items():
    print(f"export {k}='{str(v).replace(chr(39), chr(39)+chr(92)+chr(39)+chr(39))}'")
PY
)"
}

WORK_DIR="/data2/AVALON/SoDe_Avalon_5"
CONDA_ENV="/data/shy/env_work"
PYTHON_SCRIPT="run_simulation_avalon.py"

# --- 实验通用参数 ---
TOTAL_ROUNDS=10    # 总运行轮数
PARALLEL_WORKERS=2   # 并行窗口数量
ROUNDS_PER_WORKER=$((TOTAL_ROUNDS / PARALLEL_WORKERS))

# --- 游戏参数 ---
PLAYER_NUM=7       # 游戏人数 (5-10)

# --- 对战模型：填写 config/models.json 中的总名字 ---
MODEL_A="kimi-k2.5"
MODEL_B="deepseek-v4-flash"

load_model "$MODEL_A" a || exit 1
load_model "$MODEL_B" b || exit 1

# 定义日志后缀（使用总名字，便于区分同名 model_name）
LOG_TAG="${MODEL_A}_VS_${MODEL_B}_${PLAYER_NUM}Players"

# tmux 的 session 名不能包含 '.' / ':' 等分隔符，否则会报 bad session name
TMUX_SAFE_TAG="${LOG_TAG//./_}"
TMUX_SAFE_TAG="${TMUX_SAFE_TAG//:/_}"
SESSION_NAME="Avalon_Exp_Parallel_${TMUX_SAFE_TAG}"

# ==========================================================

# 检查 tmux
if ! command -v tmux &> /dev/null; then
    echo "Error: tmux is not installed."
    exit 1
fi

# 重建 Session
tmux has-session -t $SESSION_NAME 2>/dev/null
if [ $? == 0 ]; then
    echo "Session $SESSION_NAME already exists. Killing it..."
    tmux kill-session -t $SESSION_NAME
fi

echo "Creating session $SESSION_NAME..."
tmux new-session -d -s $SESSION_NAME -n "Worker_0"

# 定义初始化函数
init_and_run() {
    local target=$1
    local worker_id=$2
    
    # 1. 进入目录
    tmux send-keys -t $target "cd $WORK_DIR" C-m
    
    # 2. 激活环境
    tmux send-keys -t $target "source activate $CONDA_ENV || conda activate $CONDA_ENV" C-m
    
    # 3. 设置 Proxy (如果需要)
    # tmux send-keys -t $target "export NO_PROXY=localhost,127.0.0.1,10.119.141.215" C-m
    
    # 4. 构建 Python 命令
    cmd="python $PYTHON_SCRIPT \
        --rounds $ROUNDS_PER_WORKER \
        --worker_id $worker_id \
        --log_tag \"$LOG_TAG\" \
        --player_num $PLAYER_NUM \
        --model_a_name '$MODEL_A_NAME' \
        --model_a_key '$MODEL_A_API_KEY' \
        --model_a_url '$MODEL_A_BASE_URL' \
        --model_a_temp '$MODEL_A_TEMP' \
        --model_a_top_p '$MODEL_A_TOP_P' \
        --model_a_max_tokens '$MODEL_A_MAX_TOKENS' \
        --model_a_reasoning '$MODEL_A_USE_REASONING' \
        --model_b_name '$MODEL_B_NAME' \
        --model_b_key '$MODEL_B_API_KEY' \
        --model_b_url '$MODEL_B_BASE_URL' \
        --model_b_temp '$MODEL_B_TEMP' \
        --model_b_top_p '$MODEL_B_TOP_P' \
        --model_b_max_tokens '$MODEL_B_MAX_TOKENS' \
        --model_b_reasoning '$MODEL_B_USE_REASONING'"

    echo "Starting Worker $worker_id in $target (Rounds: $ROUNDS_PER_WORKER)..."
    tmux send-keys -t $target "$cmd" C-m
}

# 启动 Worker 0 (Session 创建时自带的窗口)
init_and_run "$SESSION_NAME:0" "0"

# 启动其余 Worker (创建新窗口)
for ((i=1; i<PARALLEL_WORKERS; i++)); do
    tmux new-window -t $SESSION_NAME -n "Worker_$i"
    init_and_run "$SESSION_NAME:$i" "$i"
done

echo "=================================================="
echo "Experiment started: Avalon ($TOTAL_ROUNDS rounds total)"
echo "Players: $PLAYER_NUM"
echo "Split into $PARALLEL_WORKERS windows ($ROUNDS_PER_WORKER rounds each)."
echo "Model A: $MODEL_A ($MODEL_A_NAME, Reasoning: $MODEL_A_USE_REASONING)"
echo "Model B: $MODEL_B ($MODEL_B_NAME, Reasoning: $MODEL_B_USE_REASONING)"
echo "Log Tag: $LOG_TAG"
echo "Check output: tmux attach -t $SESSION_NAME"
echo "=================================================="