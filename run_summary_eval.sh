#!/bin/bash

# ================= Summary vs Standard Agent 评估脚本 =================
# Model A 使用 SummaryMemory，Model B 使用 Standard，交替正反派
# 通过 tmux 后台并行挂起实验（与 run_avalon.sh 一致）

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

# --- 实验参数 ---
MODEL_A="deepseek-v4-flash_2"
MODEL_B="deepseek-v4-flash"
AGENT_TYPE_A="SummaryMemory"
AGENT_TYPE_B="Standard"
NUM_GAMES=10
PARALLEL_WORKERS=2
GAMES_PER_WORKER=$((NUM_GAMES / PARALLEL_WORKERS))
PLAYER_NUM=7
SLEEP_BETWEEN=3

load_model "$MODEL_A" a || exit 1
load_model "$MODEL_B" b || exit 1

LOG_TAG="${MODEL_A}_SummaryVS_${MODEL_B}_Standard_${PLAYER_NUM}Players"

TMUX_SAFE_TAG="${LOG_TAG//./_}"
TMUX_SAFE_TAG="${TMUX_SAFE_TAG//:/_}"
SESSION_NAME="Avalon_SummaryEval_Parallel_${TMUX_SAFE_TAG}"

# ==========================================================

if ! command -v tmux &> /dev/null; then
    echo "Error: tmux is not installed."
    exit 1
fi

if [ $((NUM_GAMES % PARALLEL_WORKERS)) -ne 0 ]; then
    echo "Error: NUM_GAMES ($NUM_GAMES) must be divisible by PARALLEL_WORKERS ($PARALLEL_WORKERS)."
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
    local start_game=$(( worker_id * GAMES_PER_WORKER + 1 ))
    local end_game=$(( (worker_id + 1) * GAMES_PER_WORKER ))

    tmux send-keys -t $target "cd $WORK_DIR" C-m
    tmux send-keys -t $target "source activate $CONDA_ENV || conda activate $CONDA_ENV" C-m

    cmd="for (( i=$start_game; i<=$end_game; i++ )); do \
if [ \$((i % 2)) -eq 0 ]; then \
ASSIGN_A_TO=good; GOOD_AGT=$AGENT_TYPE_A; EVIL_AGT=$AGENT_TYPE_B; \
else \
ASSIGN_A_TO=evil; GOOD_AGT=$AGENT_TYPE_B; EVIL_AGT=$AGENT_TYPE_A; \
fi; \
echo \"[Worker $worker_id] Running Game \$i/$NUM_GAMES (assign_a_to=\$ASSIGN_A_TO)\"; \
python $PYTHON_SCRIPT \
--rounds 1 \
--worker_id eval_${worker_id}_\$i \
--log_tag \"$LOG_TAG\" \
--player_num $PLAYER_NUM \
--good_agent_type \$GOOD_AGT \
--evil_agent_type \$EVIL_AGT \
--assign_a_to \$ASSIGN_A_TO \
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
--model_b_reasoning '$MODEL_B_USE_REASONING'; \
sleep $SLEEP_BETWEEN; \
done; \
echo \"[Worker $worker_id] All games completed ($start_game-$end_game).\""

    echo "Starting Worker $worker_id in $target (Games: $start_game-$end_game)..."
    tmux send-keys -t $target "$cmd" C-m
}

init_and_run "$SESSION_NAME:0" "0"

for ((i=1; i<PARALLEL_WORKERS; i++)); do
    tmux new-window -t $SESSION_NAME -n "Worker_$i"
    init_and_run "$SESSION_NAME:$i" "$i"
done

echo "=================================================="
echo "Summary-Memory Eval started: $NUM_GAMES games total"
echo "Players: $PLAYER_NUM"
echo "Split into $PARALLEL_WORKERS windows ($GAMES_PER_WORKER games each)."
echo "Model A: $MODEL_A ($MODEL_A_NAME, $AGENT_TYPE_A, Reasoning: $MODEL_A_USE_REASONING)"
echo "Model B: $MODEL_B ($MODEL_B_NAME, $AGENT_TYPE_B, Reasoning: $MODEL_B_USE_REASONING)"
echo "Sleep between games: ${SLEEP_BETWEEN}s"
echo "Log Tag: $LOG_TAG"
echo "Check output: tmux attach -t $SESSION_NAME"
echo "=================================================="
