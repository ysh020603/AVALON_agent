#!/bin/bash

# ================= 配置区域 (Configuration) =================
# 并行身份推断 / 对手建模版本：对应 run_simulation_avalon_belief.py

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
CONDA_ENV="/data/shy/env_work"   # 请按本机 conda 环境修改
PYTHON_SCRIPT="run_simulation_avalon_belief.py"

# --- 实验通用参数 ---
TOTAL_ROUNDS=50
PARALLEL_WORKERS=2
ROUNDS_PER_WORKER=$((TOTAL_ROUNDS / PARALLEL_WORKERS))

# --- 游戏参数 ---
PLAYER_NUM=7

# --- 对战模型：填写 config/models.json 中的总名字即可 ---
MODEL_A="kimi-k2.5"
MODEL_B="deepseek-v4-flash"

load_model "$MODEL_A" a || exit 1
load_model "$MODEL_B" b || exit 1

LOG_TAG="${MODEL_A}_VS_${MODEL_B}_${PLAYER_NUM}Players_Belief"

SESSION_NAME="Avalon_Belief_Exp_Parallel_${LOG_TAG}"

# ==========================================================

if ! command -v tmux &> /dev/null; then
    echo "Error: tmux is not installed."
    exit 1
fi

tmux has-session -t $SESSION_NAME 2>/dev/null
if [ $? == 0 ]; then
    echo "Session $SESSION_NAME already exists. Killing it..."
    tmux kill-session -t $SESSION_NAME
fi

echo "Creating session $SESSION_NAME..."
tmux new-session -d -s $SESSION_NAME -n "Worker_0"

init_and_run() {
    local target=$1
    local worker_id=$2

    tmux send-keys -t $target "cd $WORK_DIR" C-m
    tmux send-keys -t $target "source activate $CONDA_ENV || conda activate $CONDA_ENV" C-m

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

init_and_run "$SESSION_NAME:0" "0"

for ((i=1; i<PARALLEL_WORKERS; i++)); do
    tmux new-window -t $SESSION_NAME -n "Worker_$i"
    init_and_run "$SESSION_NAME:$i" "$i"
done

echo "=================================================="
echo "Experiment started: Avalon + Belief / opponent modeling ($TOTAL_ROUNDS rounds total)"
echo "Players: $PLAYER_NUM"
echo "Split into $PARALLEL_WORKERS windows ($ROUNDS_PER_WORKER rounds each)."
echo "Model A: $MODEL_A ($MODEL_A_NAME, Reasoning: $MODEL_A_USE_REASONING)"
echo "Model B: $MODEL_B ($MODEL_B_NAME, Reasoning: $MODEL_B_USE_REASONING)"
echo "Log Tag: $LOG_TAG"
echo "Check output: tmux attach -t $SESSION_NAME"
echo "=================================================="
