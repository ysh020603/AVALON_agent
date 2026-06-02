"""
Belief / opponent-modeling system prompts for Avalon.
Reuses GAME_RULE and ROLE_PROMPTS from Avalon_system_prompts without modifying that module.
"""

from prompts.Avalon_system_prompts import GAME_RULE, ROLE_PROMPTS

BELIEF_JSON_INSTRUCTION = """
### Identity Belief Task (Parallel Mental Model)
This is NOT a game action. Your only job here is to output your current belief about **every** player's role.

**DO NOT** use Markdown code blocks (e.g., ```json); output only a single raw JSON object on one line.

**Required JSON shape:**
{
  "player_roles": {
    "1": "<role name or Unknown>",
    "2": "<role name or Unknown>",
    ...
  }
}

**Rules:**
- Keys in `player_roles` MUST be string IDs for all players from 1 to N (N = total player count). No omissions.
- For yourself (`player_id` in [Your ID]): set the value to your true role name (which you know).
- For players whose identity is explicitly revealed to you by the rules (e.g., the evil players known to Merlin, the two candidates seen by Percival, evil teammates): set the value to the confirmed role. If there is identity ambiguity that cannot be resolved into a single role based on available game information, uniformly output "Unknown".
- For all other players: you must infer a unique and definite role identity based on existing game information. Only when there are no clues at all and no valid inference can be made may you uniformly output "Unknown".
- Each player can only be assigned one role per judgment; multiple or ambiguous roles are not allowed.
- Use the standard in-game role terms: Merlin, Percival, Loyal Servant, Morgana, Assassin, Mordred, Oberon, Minion.
""".strip()


MAIN_CHANNEL_SYSTEM_ADDENDUM = """
[Belief-enhanced output — main game channel]
For each reply in this channel, you MAY first write a Markdown section where you reason about **every** player's role (players 1..N), following the same identity rules as in a mental model: your own role is known; use confirmed info from visibility/teammates where the rules grant it; otherwise infer a single definite role or say you treat them as Unknown; use standard role names (Merlin, Percival, Loyal Servant, Morgana, Assassin, Mordred, Oberon, Minion).
After that section, output **exactly one** raw JSON object for the current game task (as specified in [Game Requirements] below). Put that JSON as the **last** line(s) of your message. Do **not** wrap it in Markdown code fences (no ```json). Do **not** output any other JSON object in the same message (so the parser can read your action).
""".strip()


MAIN_ACT_IDENTITY_MARKDOWN_INSTRUCTION = """
### Identity reasoning (Markdown, before your game action JSON)
Before the JSON required for this step, write a **Markdown** section in which you analyze **every** player from 1 to N (N = total player count). For each player, state your best single-role judgment (or Unknown), consistent with these rules:
- For yourself ([Your ID]): use your true role.
- For players whose role is explicitly fixed by the rules for you (e.g., evils Merlin sees, Percival's two candidates, evil teammates): give that confirmed role; if the rules leave ambiguity that cannot be resolved to one role, use Unknown.
- For everyone else: infer one definite role from available game information when possible; use Unknown only when there are no usable clues.
- One role per player; use standard names: Merlin, Percival, Loyal Servant, Morgana, Assassin, Mordred, Oberon, Minion.

**Suggested Markdown shape (fill for all players 1..N; keep it short):**
### Identity beliefs
- **Player 1:** (role or Unknown) — (one-line reason)
- **Player 2:** (role or Unknown) — (one-line reason)
- (continue with **Player 3** … **Player N** in the same style)

Then output **one** raw JSON object for **this phase's game action** only, on the **last** line(s) of your reply, with **no** Markdown code fences. Do not include a second JSON object or a `player_roles` blob here — only the phase JSON (e.g., statement / team / vote / success / target).
""".strip()


def get_avalon_belief_system_prompt(role_name, player_count, board_config, **kwargs):
    """
    Same structure as get_avalon_prompt, but game-action JSON instructions are replaced by BELIEF_JSON_INSTRUCTION.
    """
    base = GAME_RULE.format(
        player_count=player_count,
        board_config_description=board_config,
    )

    specific = ROLE_PROMPTS.get(role_name, ROLE_PROMPTS["Loyal Servant"])
    kwargs["output_instruction"] = BELIEF_JSON_INSTRUCTION

    try:
        formatted_specific = specific.format(**kwargs)
    except KeyError as e:
        print(f"[Warning] Belief prompt formatting missing key: {e}")
        formatted_specific = specific

    return base + "\n" + formatted_specific
