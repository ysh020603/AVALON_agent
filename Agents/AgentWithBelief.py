from typing import Any, Dict, List, Optional

from prompts.Avalon_belief_prompts import MAIN_ACT_IDENTITY_MARKDOWN_INSTRUCTION

from Agents.Agent import Agent


class BeliefAgent(Agent):
    """
    Extends Agent with a separate multiturn `belief_memory` thread for identity beliefs.
    Main-channel `act` appends identity-reasoning instructions before the game JSON.
    """

    def __init__(
        self,
        player_id: int,
        role: str,
        llm_config: Dict[str, Any],
        llm_func,
    ):
        super().__init__(player_id, role, llm_config, llm_func)
        self.belief_memory: List[Dict[str, str]] = []

    def _construct_instruction(self, phase: str, context: Dict[str, Any]) -> str:
        base = super()._construct_instruction(phase, context)
        return base + "\n\n" + MAIN_ACT_IDENTITY_MARKDOWN_INSTRUCTION

    def init_belief_system(self, system_content: str) -> None:
        self.belief_memory = [{"role": "system", "content": system_content}]

    def _construct_belief_instruction(self, phase: str, context: Dict[str, Any]) -> str:
        if context is None:
            context = {}

        if phase == "speech":
            return """
[Identity Belief Task — Discussion Phase]
You have just observed the information above (and any prior belief history in this thread).
Update your belief about every player's role.
Output only the JSON object in the format specified in the system prompt (player_roles for all players).
""".strip()

        elif phase == "proposal":
            ts = context.get("team_size", 0)
            return f"""
[Identity Belief Task — Team Proposal Phase]
You are the Leader and must propose a team of {ts} players for the quest (handled in the main game channel).
Separately here: output your current belief about every player's role as JSON (player_roles for all players).
""".strip()

        elif phase == "voting":
            rid = context.get("round", 0)
            return f"""
[Identity Belief Task — Voting Phase]
Round {rid}: you are about to vote on the proposed team (main game channel).
Output your current belief about every player's role as JSON (player_roles for all players).
""".strip()

        elif phase == "execution":
            rid = context.get("round", 0)
            return f"""
[Identity Belief Task — Mission Phase]
Round {rid}: you may execute the mission (main game channel).
Output your current belief about every player's role as JSON (player_roles for all players).
""".strip()

        elif phase == "assassination":
            return """
[Identity Belief Task — Assassination Phase]
The Good faction won the quests; you may choose an assassination target (main game channel).
Output your current belief about every player's role as JSON (player_roles for all players).
""".strip()

        return """
[Identity Belief Task]
Output your current belief about every player's role as JSON (player_roles for all players).
""".strip()

    def infer_identities(
        self,
        phase: str,
        observations: List[str],
        context: Optional[Dict[str, Any]] = None,
    ) -> str:
        if context is None:
            context = {}

        full_user_content = ""
        if observations:
            full_user_content += "== Information you missed/observed ==\n"
            full_user_content += "\n".join(observations) + "\n\n"

        instruction = self._construct_belief_instruction(phase, context)
        full_user_content += "== Current Task Instruction ==\n"
        full_user_content += instruction

        self.belief_memory.append({"role": "user", "content": full_user_content})
        response = self.call(self.belief_memory)
        self.belief_memory.append({"role": "assistant", "content": response})
        return response
