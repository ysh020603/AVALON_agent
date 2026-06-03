import json
import os
from typing import Any, Dict, List, Optional

from Agents.Agent import Agent
from prompts.Avalon_summary_prompts import (
    build_action_trigger,
    build_history_context_message,
    build_summary_user_prompt,
)


class AgentSummaryMemory(Agent):
    """
    Summary-Memory Agent: replaces stacked raw history with per-turn summarized memory.

    Maintains:
    - summary_memory: compressed summaries + objective facts from past turns
    - current_turn_dialogue: raw multi-turn messages within the current quest turn
    """

    AGENT_TYPE = "SummaryMemory"

    def __init__(
        self,
        player_id: int,
        role: str,
        llm_config: Dict[str, Any],
        llm_func,
    ):
        super().__init__(player_id, role, llm_config, llm_func)
        self.summary_memory: List[Dict[str, Any]] = []
        self.current_turn_dialogue: List[Dict[str, str]] = []
        self.system_prompt: Optional[str] = None
        self.last_input_messages: List[Dict[str, str]] = []

    def _ensure_system_prompt(self, memory: List[Dict[str, str]]) -> None:
        if self.system_prompt is None and memory:
            self.system_prompt = memory[0]["content"]

    def _strip_obs_prefix(self, content: str) -> str:
        if content.startswith("[Game Announcement/Observation]: "):
            return content[len("[Game Announcement/Observation]: "):]
        return content

    def _append_user_content(self, content: str) -> None:
        """Append user content; merge into last user if roles would not alternate."""
        content = content.strip()
        if not content:
            return
        if self.current_turn_dialogue and self.current_turn_dialogue[-1]["role"] == "user":
            self.current_turn_dialogue[-1]["content"] += "\n" + content
        else:
            self.current_turn_dialogue.append({"role": "user", "content": content})

    def _observations_to_dialogue(self, observations: List[str]) -> None:
        if not observations:
            return
        batched = "\n".join(self._strip_obs_prefix(o) for o in observations)
        self._append_user_content(batched)

    @staticmethod
    def _append_action_trigger(messages: List[Dict[str, str]], action_trigger: str) -> None:
        """Append action trigger; merge with trailing user to keep user/assistant alternation."""
        if messages and messages[-1]["role"] == "user":
            messages[-1]["content"] += "\n\n" + action_trigger
        else:
            messages.append({"role": "user", "content": action_trigger})

    @staticmethod
    def _enforce_alternation(messages: List[Dict[str, str]]) -> List[Dict[str, str]]:
        """Merge consecutive same-role messages so user/assistant strictly alternate.

        The leading system message (if any) is preserved as-is; the remaining
        messages are collapsed whenever two adjacent entries share the same role.
        """
        if not messages:
            return messages

        result: List[Dict[str, str]] = []
        start = 0
        if messages[0]["role"] == "system":
            result.append(dict(messages[0]))
            start = 1

        for msg in messages[start:]:
            if result and result[-1]["role"] != "system" and result[-1]["role"] == msg["role"]:
                result[-1]["content"] += "\n\n" + msg["content"]
            else:
                result.append(dict(msg))
        return result

    def _build_action_messages(
        self,
        phase: str,
        observations: List[str],
        context: Dict[str, Any],
    ) -> List[Dict[str, str]]:
        messages = [{"role": "system", "content": self.system_prompt}]

        history_content = build_history_context_message(self.summary_memory)
        messages.append({"role": "user", "content": history_content})

        messages.extend(self.current_turn_dialogue)

        instruction = self._construct_instruction(phase, context)
        action_trigger = build_action_trigger(observations=[], instruction=instruction)
        self._append_action_trigger(messages, action_trigger)

        return self._enforce_alternation(messages)

    def finalize_turn(
        self,
        turn_number: int,
        objective_info: str,
    ) -> None:
        """Summarize the completed turn and append to summary_memory."""
        self._ensure_system_prompt([{"role": "system", "content": self.system_prompt or ""}])

        summary_user = build_summary_user_prompt(
            turn_number=turn_number,
            objective_info=objective_info,
            raw_dialogue=self.current_turn_dialogue,
            previous_summaries=self.summary_memory,
        )

        summary_messages = self._enforce_alternation([
            {"role": "system", "content": self.system_prompt},
            {"role": "user", "content": summary_user},
        ])

        discussion_summary = self.call(summary_messages)

        entry = {
            "turn": turn_number,
            "objective_facts": objective_info,
            "discussion_summary": discussion_summary,
            "summary_prompt": summary_messages,
        }
        self.summary_memory.append(entry)

        self.current_turn_dialogue = []

    def act(
        self,
        memory: List[Dict[str, str]],
        phase: str,
        observations: List[str],
        context: Dict[str, Any] = None,
        game_condition: Dict[str, Any] = None,
    ) -> str:
        if context is None:
            context = {}

        self._ensure_system_prompt(memory)

        self._observations_to_dialogue(observations)

        action_messages = self._build_action_messages(phase, observations, context)
        self.last_input_messages = list(action_messages)

        response = self.call(action_messages)

        self.current_turn_dialogue.append({"role": "assistant", "content": response})

        memory.clear()
        memory.extend(action_messages)
        memory.append({"role": "assistant", "content": response})

        return response

    def save_summary_log(self, save_path: str, game_id: str = "unknown") -> str:
        """Serialize this agent's per-turn summary memory to a JSON file."""
        if not os.path.exists(save_path):
            os.makedirs(save_path, exist_ok=True)

        model_name = self.llm_config.get("name", "unknown")
        safe_model = model_name.replace("/", "_").replace(" ", "_")
        filename = f"summary_Player_{self.player_id}_{self.role}_{safe_model}_game_{game_id}.json"

        payload = {
            "player_id": self.player_id,
            "role": self.role,
            "model": model_name,
            "game_id": game_id,
            "summary_memory": self.summary_memory,
        }

        filepath = os.path.join(save_path, filename)
        with open(filepath, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=4)

        print(f"[SummaryMemory] Player {self.player_id} summary log saved to {filepath}")
        return filepath
