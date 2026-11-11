#!/usr/bin/env python3
"""Generate Verdict.WEIGHTS from data/wowhead_stat_priorities.json.

Wowhead is the sole source for every shipped Touchstone profile (Mightie,
2026-11-11). This script walks the fetched Forever pages and emits
order-only, cap-aware Lua tables. Re-run after updating the JSON:

    python3 tools/gen_wowhead_priorities.py

The marked region in MightiePack/Modules/Touchstone/ChestAdvisor/Verdict.lua
is replaced in place. Do not hand-edit that region.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
JSON_PATH = ROOT / "data" / "wowhead_stat_priorities.json"
VERDICT_PATH = ROOT / "MightiePack" / "Modules" / "Touchstone" / "ChestAdvisor" / "Verdict.lua"

START = "-- <wowhead-priorities-start>"
END = "-- <wowhead-priorities-end>"

# Parser words and default rating-per-percent (percent caps only).
PERCENT_SCALE = {
    "Hit": 10,
    "Expertise": 10,
    "Haste": 10,
    "Crit": 14,
    "Dodge": 12,
    "Parry": 15,
    "BlockChance": 5,
}

# Wowhead list words -> one or more parser keys. Intra-tier bundles are
# preserved as given; Haste / Cast Speed both map to Haste and are
# de-duplicated. Avoidance is not split on the page, so Dodge and Parry
# share a tier and use the source-free same-direction / TRADE_OFF rule.
STAT_MAP = {
    "hit chance": ["Hit"],
    "hit": ["Hit"],
    "% hit chance": ["Hit"],
    "expertise": ["Expertise"],
    "reduced dodge/parry chance": ["Expertise"],
    "reduced chance to be dodged/parried": ["Expertise"],
    "critical strike chance": ["Crit"],
    "critical strike": ["Crit"],
    "crit chance": ["Crit"],
    "crit": ["Crit"],
    "spell critical strike chance": ["Crit"],
    "1% critical strike chance": ["Crit"],
    "1% hit chance": ["Hit"],
    "1% reduced dodge/parry chance": ["Expertise"],
    "1% haste": ["Haste"],
    "% critical strike chance": ["Crit"],
    "haste": ["Haste"],
    "spell haste": ["Haste"],
    "haste rating": ["Haste"],
    "cast speed": ["Haste"],
    "strength": ["Strength"],
    "agility": ["Agility"],
    "stamina": ["Stamina"],
    "intellect": ["Intellect"],
    "spirit": ["Spirit"],
    "armor": ["Armor"],
    "attack power": ["AttackPower"],
    "ranged attack power": ["RangedAttackPower"],
    "(ranged) attack power": ["RangedAttackPower", "AttackPower"],
    "spell damage": ["SpellDamage", "SpellPower"],
    "spell power": ["SpellPower", "SpellDamage"],
    "healing power": ["HealingPower"],
    "spell healing": ["HealingPower"],
    "shadow damage": ["ShadowDamage"],
    "fire damage": ["FireDamage"],
    "frost damage": ["FrostDamage"],
    "nature damage": ["NatureDamage"],
    "arcane damage": ["ArcaneDamage"],
    "holy damage": ["HolyDamage"],
    "spell penetration": ["SpellPenetration"],
    "spell piercing": ["SpellPenetration"],
    "spell pierce": ["SpellPenetration"],
    "weapon skill": ["WeaponSkill"],
    "weapon dps": ["WeaponDps"],
    "speed": ["WeaponSpeed"],
    "mp5": ["MP5"],
    "mp5": ["MP5"],
    "mana per 5 seconds": ["MP5"],
    "block chance": ["BlockChance"],
    "defense": ["Defense"],
    "dodge": ["Dodge"],
    "parry": ["Parry"],
    "avoidance": ["Dodge", "Parry"],
}

# Registry keys. Default tank variants use the short key (prot, feral_bear).
CLASS_TOKEN = {
    "Warrior": "WARRIOR",
    "Paladin": "PALADIN",
    "Druid": "DRUID",
    "Shaman": "SHAMAN",
    "Priest": "PRIEST",
    "Mage": "MAGE",
    "Warlock": "WARLOCK",
    "Rogue": "ROGUE",
    "Hunter": "HUNTER",
}

SPEC_KEYS = {
    ("Warrior", "Arms", None): ("arms", "Arms"),
    ("Warrior", "Fury", None): ("fury", "Fury"),
    ("Warrior", "Protection", "Balanced"): ("prot", "Protection (Balanced)"),
    ("Warrior", "Protection", "Defensive"): ("prot_defensive", "Protection (Defensive)"),
    ("Warrior", "Protection", "Offensive"): ("prot_offensive", "Protection (Offensive)"),
    ("Paladin", "Holy", None): ("holy", "Holy"),
    ("Paladin", "Protection", "Balanced"): ("prot", "Protection (Balanced)"),
    ("Paladin", "Protection", "Defensive"): ("prot_defensive", "Protection (Defensive)"),
    ("Paladin", "Protection", "Offensive"): ("prot_offensive", "Protection (Offensive)"),
    ("Paladin", "Retribution", None): ("ret", "Retribution"),
    ("Druid", "Balance", None): ("balance", "Balance"),
    ("Druid", "Feral (Cat)", None): ("feral_cat", "Feral (Cat)"),
    ("Druid", "Feral (Bear)", "Defensive"): ("feral_bear", "Feral (Bear, Defensive)"),
    ("Druid", "Feral (Bear)", "Offensive"): ("feral_bear_offensive", "Feral (Bear, Offensive)"),
    ("Druid", "Restoration", None): ("resto", "Restoration"),
    ("Shaman", "Elemental", None): ("elemental", "Elemental"),
    ("Shaman", "Enhancement", None): ("enhancement", "Enhancement"),
    ("Shaman", "Restoration", None): ("resto", "Restoration"),
    ("Priest", "Discipline", None): ("disc", "Discipline"),
    ("Priest", "Holy", None): ("holy", "Holy"),
    ("Priest", "Shadow", None): ("shadow", "Shadow"),
    ("Mage", "Arcane", None): ("arcane", "Arcane"),
    ("Mage", "Fire", None): ("fire", "Fire"),
    ("Mage", "Frost", None): ("frost", "Frost"),
    ("Warlock", "Affliction", None): ("affliction", "Affliction"),
    ("Warlock", "Demonology", None): ("demonology", "Demonology"),
    ("Warlock", "Destruction", None): ("destruction", "Destruction"),
    ("Rogue", "Assassination", None): ("assassination", "Assassination"),
    ("Rogue", "Combat", None): ("combat", "Combat"),
    ("Rogue", "Subtlety", None): ("subtlety", "Subtlety"),
    ("Hunter", "Beast Mastery", None): ("beast_mastery", "Beast Mastery"),
    ("Hunter", "Marksmanship", None): ("marksmanship", "Marksmanship"),
    ("Hunter", "Survival", None): ("survival", "Survival"),
}

CLASS_ORDER = [
    "WARRIOR", "PALADIN", "DRUID", "SHAMAN", "PRIEST",
    "MAGE", "WARLOCK", "ROGUE", "HUNTER",
]

# Display names for a bundled tier (first word if unlisted).
TIER_NAME = {
    frozenset(["WeaponDps", "WeaponSpeed"]): "Weapon DPS & Speed",
    frozenset(["Strength", "AttackPower"]): "Strength & Attack Power",
    frozenset(["Agility", "Crit"]): "Agility & Critical Strike Chance",
    frozenset(["SpellDamage", "SpellPower", "HolyDamage"]): "Spell Damage",
    frozenset(["SpellDamage", "SpellPower"]): "Spell Damage",
    frozenset(["SpellPower", "SpellDamage"]): "Spell Damage",
    frozenset(["SpellDamage", "SpellPower", "ShadowDamage"]): "Spell Damage & Shadow Damage",
    frozenset(["SpellPower", "SpellDamage", "ShadowDamage"]): "Spell Damage & Shadow Damage",
    frozenset(["SpellDamage", "SpellPower", "FireDamage"]): "Spell Damage & Fire Damage",
    frozenset(["SpellPower", "SpellDamage", "FireDamage"]): "Spell Damage & Fire Damage",
    frozenset(["SpellPower", "SpellDamage", "FireDamage", "ShadowDamage"]): "Spell Damage, Fire Damage & Shadow Damage",
    frozenset(["SpellDamage", "SpellPower", "FrostDamage", "ArcaneDamage"]): "Spell Damage, Frost Damage & Arcane Damage",
    frozenset(["SpellDamage", "SpellPower", "ArcaneDamage"]): "Spell Damage & Arcane Damage",
    frozenset(["NatureDamage", "FireDamage"]): "Nature Damage & Fire Damage",
    frozenset(["Agility", "Strength"]): "Agility & Strength",
    frozenset(["Dodge", "Parry"]): "Avoidance",
    frozenset(["RangedAttackPower", "AttackPower"]): "Ranged Attack Power",
}

WORD_NAME = {
    "Hit": "Hit",
    "Expertise": "Expertise",
    "Crit": "Crit",
    "Haste": "Haste",
    "Strength": "Strength",
    "Agility": "Agility",
    "Stamina": "Stamina",
    "Intellect": "Intellect",
    "Spirit": "Spirit",
    "Armor": "Armor",
    "AttackPower": "Attack Power",
    "RangedAttackPower": "Ranged Attack Power",
    "SpellDamage": "Spell Damage",
    "SpellPower": "Spell Power",
    "HealingPower": "Healing Power",
    "ShadowDamage": "Shadow Damage",
    "FireDamage": "Fire Damage",
    "FrostDamage": "Frost Damage",
    "NatureDamage": "Nature Damage",
    "ArcaneDamage": "Arcane Damage",
    "HolyDamage": "Holy Damage",
    "SpellPenetration": "Spell Penetration",
    "WeaponSkill": "Weapon Skill",
    "WeaponDps": "Weapon DPS",
    "WeaponSpeed": "Speed",
    "MP5": "MP5",
    "BlockChance": "Block Chance",
    "Defense": "Defense",
    "Dodge": "Dodge",
    "Parry": "Parry",
}


def norm_stat(raw: str) -> str:
    s = raw.strip()
    s = re.sub(r"\s+", " ", s)
    s = s.strip(" .")
    return s.lower()


def map_stat(raw: str) -> list[str]:
    key = norm_stat(raw)
    # Strip trailing parenthetical leftovers already split out of tiers.
    if key in STAT_MAP:
        return list(STAT_MAP[key])
    # Soft fallback: leading "1% " or "% " already covered; try without them.
    key2 = re.sub(r"^1%\s+", "", key)
    key2 = re.sub(r"^%\s+", "", key2)
    if key2 in STAT_MAP:
        return list(STAT_MAP[key2])
    raise SystemExit(f"unmapped Wowhead stat word: {raw!r}")


def first_number_pair(text: str) -> tuple[float | None, float | None]:
    m = re.search(r"(\d+(?:\.\d+)?)(?:\s*-\s*(\d+(?:\.\d+)?))?", text)
    if not m:
        return None, None
    a = float(m.group(1))
    b = float(m.group(2)) if m.group(2) else None
    return a, b


def is_total_spell_hit(line: str, caps_text: str) -> bool:
    blob = (line + " " + caps_text).lower()
    if "from gear" in blob or "from talents" in blob or "from talent" in blob:
        return True
    if "suppression" in blob and "17%" in blob:
        return True
    if "17% total" in blob:
        return True
    return False


def parse_cap(line: str, caps: dict, words: list[str]) -> dict:
    """Read cap / after-floor from a verbatim line, falling back to the page caps map."""
    info: dict = {}
    lower = line.lower()

    after_m = re.search(r"\bafter\s+(\d+(?:\.\d+)?)\s*%?", line, re.I)
    until_m = re.search(
        r"\b(?:until|before|to minimum|up to|to)\s+(\d+(?:\.\d+)?)(?:\s*-\s*(\d+(?:\.\d+)?))?\s*%?",
        line,
        re.I,
    )
    paren_m = re.search(r"\((\d+(?:\.\d+)?)(?:\s*-\s*(\d+(?:\.\d+)?))?\s*%", line)
    capword_m = re.search(r"(\d+(?:\.\d+)?)\s*%\s*cap", line, re.I)
    raw_until = re.search(
        r"\b(?:until|before|to)\s+(\d+(?:\.\d+)?)(?!\s*-\s*\d)(?!\s*%)",
        line,
        re.I,
    )

    caps_blob = " ".join(str(v) for v in caps.values())

    if after_m and "after" in lower:
        # "Hit Chance after 8%" / "Defense after 440"
        n = float(after_m.group(1))
        if "%" in line[after_m.start(): after_m.end() + 2] or "hit" in lower or "expertise" in lower:
            info["afterPercent"] = n
        elif n >= 50:
            # Defense 440, Weapon Skill 305/308, etc.
            info["afterValue"] = int(n) if n == int(n) else n
            info["capUnit"] = "raw"
        else:
            # Ambiguous small number without %: treat as percent if the word is a percent stat.
            if words and words[0] in PERCENT_SCALE:
                info["afterPercent"] = n
            else:
                info["afterValue"] = int(n) if n == int(n) else n
                info["capUnit"] = "raw"
        return info

    # "until 11-12%" from gear + talents -> total 17% spell hit cap.
    if until_m or paren_m or capword_m:
        if is_total_spell_hit(line, caps_blob) and "hit" in lower:
            info["capPercent"] = 17
            info["comment"] = (
                "page states a from-gear hit target (talents cover the rest); "
                "clamp the player's total hit, which already includes talents, at the 17% cap"
            )
            return info

    if until_m:
        a = float(until_m.group(1))
        b = float(until_m.group(2)) if until_m.group(2) else None
        span = line[until_m.start(): until_m.end() + 3]
        is_pct = "%" in span or (words and words[0] in PERCENT_SCALE and a <= 30)
        if b is not None:
            # A listed range like 11-12%: if we didn't already promote to 17%,
            # use the upper end of the listed range.
            a = b
        if is_pct:
            info["capPercent"] = int(a) if a == int(a) else a
        else:
            info["capValue"] = int(a) if a == int(a) else a
            info["capUnit"] = "raw"
        return info

    if capword_m:
        a = float(capword_m.group(1))
        info["capPercent"] = int(a) if a == int(a) else a
        return info

    if paren_m:
        a = float(paren_m.group(1))
        b = float(paren_m.group(2)) if paren_m.group(2) else None
        if is_total_spell_hit(line, caps_blob) and "hit" in lower:
            info["capPercent"] = 17
            info["comment"] = (
                "page states a from-gear hit target (talents cover the rest); "
                "clamp the player's total hit, which already includes talents, at the 17% cap"
            )
            return info
        if b is not None:
            a = b
        info["capPercent"] = int(a) if a == int(a) else a
        return info

    if raw_until and words and words[0] in ("Defense", "WeaponSkill", "Armor"):
        a = float(raw_until.group(1))
        info["capValue"] = int(a) if a == int(a) else a
        info["capUnit"] = "raw"
        return info

    # Fallback: page caps map for a first occurrence that omitted "until N"
    # in the numbered list (Hunter Survival Hit 9%; Feral Bear Offensive Hit 8%).
    return cap_from_map(words, caps, line)


def cap_from_map(words: list[str], caps: dict, line: str) -> dict:
    if not words:
        return {}
    word = words[0]
    # Only apply a map cap when this is clearly the same stat.
    candidates = []
    for label, text in (caps or {}).items():
        lab = label.lower()
        if word == "Hit" and "hit" in lab:
            # Prefer melee / ability over a body-only spell aside when the
            # list item itself does not mention spells.
            candidates.append((label, text, lab))
        elif word == "Expertise" and ("expertise" in lab or "dodge/parry" in lab or "reduced" in lab):
            candidates.append((label, text, lab))
        elif word == "WeaponSkill" and "weapon skill" in lab:
            candidates.append((label, text, lab))
        elif word == "Defense" and lab.startswith("defense"):
            candidates.append((label, text, lab))
    if not candidates:
        return {}
    # Skip "mentioned in the body, not as a numbered rank" 27% dual-wield.
    filtered = []
    for label, text, lab in candidates:
        tl = text.lower()
        if "not as a numbered" in tl or "dual-wield" in lab or "white" in lab:
            continue
        filtered.append((label, text, lab))
    if not filtered:
        return {}
    # Prefer ability/melee over spell if several hit caps exist and the
    # line does not say poison/spell.
    lower = line.lower()
    if word == "Hit":
        if "poison" in lower or "spell" in lower:
            pref = [c for c in filtered if "poison" in c[2] or "spell" in c[2]]
            if pref:
                filtered = pref
        else:
            pref = [c for c in filtered if "ability" in c[2] or "melee" in c[2] or c[2] == "hit chance"]
            if pref:
                filtered = pref
    label, text, lab = filtered[0]
    if is_total_spell_hit(line, text) and word == "Hit":
        return {
            "capPercent": 17,
            "comment": (
                "page states a from-gear hit target (talents cover the rest); "
                "clamp the player's total hit, which already includes talents, at the 17% cap"
            ),
        }
    # First number in the caps text.
    m = re.search(r"(\d+(?:\.\d+)?)", text)
    if not m:
        return {}
    a = float(m.group(1))
    comment = None
    if word == "Hit" and "until" not in lower and "%" not in line:
        comment = (
            "numbered list omits the cap wording; the same page states this cap "
            f"({text.split('(')[0].strip()})"
        )
    if word in PERCENT_SCALE or "%" in text:
        info = {"capPercent": int(a) if a == int(a) else a}
        if comment:
            info["comment"] = comment
        return info
    return {"capValue": int(a) if a == int(a) else a, "capUnit": "raw"}


def tier_display_name(words: list[str], raw_names: list[str]) -> str:
    if "WeaponDps" in words and "WeaponSpeed" in words:
        return "Weapon DPS & Speed"
    key = frozenset(words)
    if key in TIER_NAME:
        return TIER_NAME[key]
    if len(words) == 1:
        return WORD_NAME.get(words[0], words[0])
    return " & ".join(WORD_NAME.get(w, w) for w in words)


def build_tier(raw_stats: list[str], verbatim: str, caps: dict, class_name: str) -> dict | None:
    words: list[str] = []
    seen = set()
    for raw in raw_stats:
        for w in map_stat(raw):
            if w not in seen:
                words.append(w)
                seen.add(w)
    # Paladin "Spell Damage" / "Spell Power" also includes Holy Damage
    # (the Ret page body treats Holy Damage as the same stat family).
    if class_name == "Paladin" and any(w in ("SpellDamage", "SpellPower") for w in words):
        if "HolyDamage" not in seen:
            words.append("HolyDamage")
            seen.add("HolyDamage")
    if not words:
        return None
    # Hunter "Attack Power" (Survival) also accepts ranged AP on items.
    if class_name == "Hunter" and words == ["AttackPower"]:
        words.append("RangedAttackPower")

    leveling = "only while leveling" in (verbatim or "").lower()
    cap = parse_cap(verbatim or "", caps or {}, words)
    name = tier_display_name(words, raw_stats)
    tier: dict = {"name": name, "stats": words}
    if "WeaponDps" in words and "WeaponSpeed" in words:
        tier["special"] = "dps_then_speed"
    if leveling:
        tier["levelingOnly"] = True
    tier.update(cap)
    # Percent caps get a rating scale for the first percent-stat word.
    if "capPercent" in tier or "afterPercent" in tier:
        scale_word = next((w for w in words if w in PERCENT_SCALE), words[0])
        if scale_word in PERCENT_SCALE:
            tier["ratingPerPercent"] = PERCENT_SCALE[scale_word]
    return tier


def apply_second_caps(tiers: list[dict]) -> None:
    """A later occurrence of the same stat inherits the previous cap as its floor."""
    last_hi: dict[str, tuple[str, float]] = {}
    for t in tiers:
        words = t.get("stats") or []
        if not words:
            continue
        word = words[0]
        # After-only floor already set from "after N".
        if "afterPercent" in t or "afterValue" in t:
            unit = "percent" if "afterPercent" in t else "raw"
            val = t.get("afterPercent", t.get("afterValue"))
            last_hi[word] = (unit, val)
            # If a later hard cap is also present (Hit to 17% after 8%), keep both.
            if "capPercent" in t:
                last_hi[word] = ("percent", t["capPercent"])
            elif "capValue" in t:
                last_hi[word] = ("raw", t["capValue"])
            continue
        if word in last_hi and ("capPercent" in t or "capValue" in t):
            unit, val = last_hi[word]
            if unit == "percent" and "afterPercent" not in t:
                t["afterPercent"] = val
            elif unit == "raw" and "afterValue" not in t:
                t["afterValue"] = val
                t["capUnit"] = "raw"
        if "capPercent" in t:
            last_hi[word] = ("percent", t["capPercent"])
        elif "capValue" in t:
            last_hi[word] = ("raw", t["capValue"])


def drop_bear_offensive_dup(spec_name: str, profile: str, verbatim: list, tiers_raw: list) -> tuple[list, list, bool]:
    """Feral Bear Offensive lists Strength twice (items 6 and 8). Keep the first."""
    if spec_name != "Feral (Bear)" or profile != "Offensive":
        return verbatim, tiers_raw, False
    seen_str = False
    new_v, new_t = [], []
    dropped = False
    for line, raw in zip(verbatim, tiers_raw):
        is_str = [norm_stat(x) for x in raw] == ["strength"]
        if is_str and seen_str:
            dropped = True
            continue
        if is_str:
            seen_str = True
        new_v.append(line)
        new_t.append(raw)
    return new_v, new_t, dropped


def lua_num(n) -> str:
    if isinstance(n, float) and n == int(n):
        return str(int(n))
    return str(n)


def lua_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def emit_tier(t: dict, indent: str) -> str:
    parts = [f"name = {lua_str(t['name'])}", "stats = { " + ", ".join(lua_str(w) for w in t["stats"]) + " }"]
    if t.get("special"):
        parts.append(f"special = {lua_str(t['special'])}")
    if t.get("levelingOnly"):
        parts.append("levelingOnly = true")
    if "capPercent" in t:
        parts.append(f"capPercent = {lua_num(t['capPercent'])}")
    if "afterPercent" in t:
        parts.append(f"afterPercent = {lua_num(t['afterPercent'])}")
    if "capValue" in t:
        parts.append(f"capValue = {lua_num(t['capValue'])}")
    if "afterValue" in t:
        parts.append(f"afterValue = {lua_num(t['afterValue'])}")
    if t.get("capUnit") == "raw" or "capValue" in t or "afterValue" in t:
        parts.append('capUnit = "raw"')
    if "ratingPerPercent" in t:
        parts.append(f"ratingPerPercent = {lua_num(t['ratingPerPercent'])}")
    line = indent + "{ " + ", ".join(parts) + " },"
    if t.get("comment"):
        line += " -- " + t["comment"]
    return line


def source_string(rec: dict) -> str:
    url = rec["url"]
    updated = rec.get("updated") or "unknown"
    fetched = rec.get("fetched") or "2026-11-11"
    author = rec.get("author") or "unknown"
    heading = rec.get("heading") or (rec["spec"] + " Stat Priority in WoW Forever")
    bits = [
        f"{url} (updated {updated}, fetched {fetched}). ",
        f"Wowhead {heading}, by {author}. ",
    ]
    intro = rec.get("intro") or ""
    notes = " ".join(rec.get("notes") or []) if isinstance(rec.get("notes"), list) else (rec.get("notes") or "")
    blob = intro + " " + str(notes)
    if rec.get("spec") == "Retribution" or re.search(r"\bbeta\b", blob, re.I) or "will shift" in blob.lower():
        if "beta" in blob.lower() or "will shift" in blob.lower() or rec.get("spec") == "Retribution":
            bits.append(
                "The page is built from beta data and says the priority will shift once "
                "level 60 dungeon and raid gear is available. "
            )
    bits.append("Order-only; no invented numeric weights.")
    return "".join(bits)


def emit_profile(key: str, display: str, rec: dict, tiers: list[dict], extra_comments: list[str]) -> str:
    lines = []
    lines.append(f"\t\t{key} = {{")
    lines.append(f"\t\t\tname = {lua_str(display)},")
    lines.append('\t\t\tkind = "order",')
    lines.append(f"\t\t\turl = {lua_str(rec['url'])},")
    lines.append(f"\t\t\tupdated = {lua_str(rec.get('updated') or '')},")
    lines.append(f"\t\t\tfetched = {lua_str(rec.get('fetched') or '2026-11-11')},")
    if rec.get("profile"):
        lines.append(f"\t\t\tvariant = {lua_str(rec['profile'])},")
    for c in extra_comments:
        lines.append(f"\t\t\t-- {c}")
    lines.append("\t\t\ttiers = {")
    for t in tiers:
        lines.append(emit_tier(t, "\t\t\t\t"))
    lines.append("\t\t\t},")
    src = source_string(rec)
    # Lua long string concat like the existing Ret source, wrapped.
    # Keep one quoted string; Lua allows long lines.
    lines.append(f"\t\t\tsource = {lua_str(src)},")
    lines.append("\t\t},")
    return "\n".join(lines)


HEADER = '''-- THE WEIGHTS. One order-only profile per class AND talent spec, keyed
-- by the same short keys the Gear-for picker uses (ret, arms, fury, …).
-- Wowhead is the SOLE source for every shipped profile (Mightie,
-- 2026-11-11). ForeverDB numeric tables are not shipped.
--
-- Generated by tools/gen_wowhead_priorities.py from
-- data/wowhead_stat_priorities.json (28 Wowhead Forever pages, fetched
-- 2026-11-11). Re-run the generator after updating the JSON; do not
-- hand-edit this region.
--
-- Each profile is kind = "order": walk the published tiers
-- lexicographically, first differing tier decides. Intra-tier bundles
-- use the source-free rule (same direction decides, a conflict is
-- TRADE_OFF, no unit conversion). Caps come from the page itself
-- (melee hit is 8% or 9% depending on the list; several specs have a
-- second cap on the same stat). Leveling-only tagged tiers apply only
-- when the player is below 60. Tanks default to Wowhead's Balanced
-- list (Protection) or Defensive (Feral Bear; that page has no
-- Balanced list). Variants are also in the picker.
--
-- Feral Bear Offensive lists Strength twice (verbatim items 6 and 8);
-- that is a typo, and only the first occurrence is used.
'''


def generate_lua(data: dict) -> str:
    grouped: dict[str, list[str]] = {c: [] for c in CLASS_ORDER}
    comments_for: dict[tuple, list[str]] = {}
    seen_keys = set()

    for rec in data["specs"]:
        class_name = rec["class"]
        spec_name = rec["spec"]
        profile = rec.get("profile")  # None, Defensive, Balanced, Offensive
        token = CLASS_TOKEN[class_name]
        ident = (class_name, spec_name, profile)
        if ident not in SPEC_KEYS:
            raise SystemExit(f"no registry key for {ident}")
        key, display = SPEC_KEYS[ident]
        verbatim = list(rec.get("verbatim") or [])
        tiers_raw = list(rec.get("tiers") or [])
        if len(verbatim) != len(tiers_raw):
            raise SystemExit(f"verbatim/tiers length mismatch for {ident}: {len(verbatim)} vs {len(tiers_raw)}")
        verbatim, tiers_raw, dropped = drop_bear_offensive_dup(spec_name, profile, verbatim, tiers_raw)
        extra = []
        if dropped:
            extra.append(
                "Wowhead typo: the Offensive list prints Strength as both item 6 and item 8. "
                "The second occurrence is dropped; the first is kept."
            )
        if spec_name == "Feral (Bear)" and profile == "Defensive":
            extra.append(
                "The page body cites an Armor cap of 17265, but the numbered list is just "
                "'Armor' with no 'until' wording, so no armor cap is applied."
            )
        if spec_name == "Survival":
            extra.append(
                "The numbered list is '% Hit Chance' with no 'until 9%'; the same page "
                "states the 9% yellow-hit cap in the body, and that cap is applied."
            )
        caps = rec.get("caps") or {}
        tiers = []
        for raw, line in zip(tiers_raw, verbatim):
            t = build_tier(raw, line, caps, class_name)
            if t is None:
                raise SystemExit(f"empty tier for {ident}: {raw}")
            tiers.append(t)
        apply_second_caps(tiers)
        block = emit_profile(key, display, rec, tiers, extra)
        grouped[token].append(block)
        k = (token, key)
        if k in seen_keys:
            raise SystemExit(f"duplicate key {k}")
        seen_keys.add(k)

    expected = set((CLASS_TOKEN[c], k) for (c, s, p), (k, n) in SPEC_KEYS.items())
    if seen_keys != expected:
        raise SystemExit(f"key set mismatch: missing {expected-seen_keys} extra {seen_keys-expected}")

    out = [START, HEADER.rstrip(), "Verdict.WEIGHTS = {"]
    for token in CLASS_ORDER:
        out.append(f"\t{token} = {{")
        out.append("\n".join(grouped[token]))
        out.append("\t},")
    out.append("}")
    out.append(END)
    return "\n".join(out) + "\n"


def splice(lua: str, verdict_text: str) -> str:
    if START in verdict_text and END in verdict_text:
        pre = verdict_text.split(START, 1)[0]
        post = verdict_text.split(END, 1)[1]
        if post.startswith("\n"):
            post = post[1:]
        return pre + lua + post
    # First run: replace the ForeverDB WEIGHTS block.
    # Cut from the "THE WEIGHTS." comment through the closing of Verdict.WEIGHTS.
    m = re.search(
        r"-- THE WEIGHTS\. One profile per class AND talent spec.*?\nVerdict\.WEIGHTS = \{.*?\n\}\n",
        verdict_text,
        flags=re.S,
    )
    if not m:
        raise SystemExit("could not find the WEIGHTS block to replace in Verdict.lua")
    return verdict_text[: m.start()] + lua + verdict_text[m.end():]


def main() -> int:
    data = json.loads(JSON_PATH.read_text())
    lua = generate_lua(data)
    text = VERDICT_PATH.read_text()
    new = splice(lua, text)
    if new == text:
        print("Verdict.lua already up to date")
        return 0
    VERDICT_PATH.write_text(new)
    print(f"wrote {VERDICT_PATH.relative_to(ROOT)} ({len(lua.splitlines())} generated lines)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
