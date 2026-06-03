from typing import List, Dict, Any


def build_summary_user_prompt(
    turn_number: int,
    objective_info: str,
    raw_dialogue: List[Dict[str, str]],
    previous_summaries: List[Dict[str, Any]] = None,
) -> str:
    """Build the user prompt for turn summarization."""
    parts = []

    if previous_summaries:
        parts.append("**Context:**")
        for entry in previous_summaries:
            parts.append(
                f"Turn {entry['turn']} — Objective: {entry['objective_facts']}; "
                f"Discussion: {entry['discussion_summary']}"
            )
        parts.append("")

    parts.append(f"**Objective Information of Turn {turn_number}:**")
    parts.append(objective_info)
    parts.append("")

    parts.append(f"**Raw Dialogue of Turn {turn_number}:**")
    if raw_dialogue:
        for msg in raw_dialogue:
            role_label = "You" if msg["role"] == "assistant" else "Others/Game"
            parts.append(f"[{role_label}]: {msg['content']}")
    else:
        parts.append("(No dialogue recorded for this turn.)")
    parts.append("")

    parts.append(
        "**Task:**\n"
        "Summarize the dialogue above. You must ONLY summarize the spoken parts. "
        "Do not alter or summarize the objective information (team proposals, votes, quest results, fail votes) "
        "provided above, just retain them as facts.\n"
        "For the dialogue summary, strictly extract the core content for each player (including yourself). "
        "Focus heavily on:\n"
        "* Who proposed which team.\n"
        "* Who suspected or accused whom.\n"
        "* Who defended whom.\n"
        "Keep it highly concise."
    )

    return "\n".join(parts)


def build_history_context_message(summary_memory: List[Dict[str, Any]]) -> str:
    """Build User Message 1 (History Context) for action decisions."""
    if not summary_memory:
        return "Here is the summarized history of previous turns:\n\n(No previous turns yet.)"

    lines = ["Here is the summarized history of previous turns:\n"]
    for entry in summary_memory:
        lines.append(f"Turn {entry['turn']} Summary:")
        lines.append(f"- Objective Facts: {entry['objective_facts']}")
        lines.append(f"- Discussions: {entry['discussion_summary']}")
        lines.append("")
    return "\n".join(lines).strip()


def build_action_trigger(observations: List[str], instruction: str) -> str:
    """Build the final User Message (Action Trigger) for the current decision."""
    parts = []
    if observations:
        parts.append("== Information you missed/observed ==")
        parts.extend(observations)
        parts.append("")

    parts.append("== Current Task Instruction ==")
    parts.append(instruction)
    return "\n".join(parts)
