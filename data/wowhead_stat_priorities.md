# Touchstone — Wowhead WoW: Forever stat priorities

Collected 2026-11-11 (America/New_York) from Wowhead's [Forever class guides hub](https://www.wowhead.com/forever/guides/classes). Wowhead is the sole source. Direct `curl` to wowhead.com returned HTTP 403 (Cloudflare); every page below was read successfully with WebFetch.

## Coverage

All 28 requested specs have a live Wowhead Forever stat-priority page. Nothing was missing or unreadable.

- Warrior: Arms, Fury, Protection (Defensive / Balanced / Offensive)
- Paladin: Holy, Protection (Defensive / Balanced / Offensive), Retribution
- Druid: Balance, Feral Cat, Feral Bear (Defensive / Offensive), Restoration
- Shaman: Elemental, Enhancement, Restoration
- Priest: Discipline, Holy, Shadow
- Mage: Arcane, Fire, Frost
- Warlock: Affliction, Demonology, Destruction
- Rogue: Assassination, Combat, Subtlety
- Hunter: Beast Mastery, Marksmanship, Survival

## Leveling vs endgame

Wowhead does **not** publish a second numbered leveling list on these pages. Almost every DPS/healer list is labeled as a speculative endgame order based on a level-30-capped beta. The only in-list leveling tags are:

- Elemental Shaman item 9: `Strength (Only while leveling)`
- Restoration Shaman item 7: `Spell Damage (Only while leveling)`

A few body sections mention leveling (Fury/Prot Warrior Spirit, Disc Priest Spell Damage, Holy Paladin Strength, Feral Bear Spell Power via Thorns) but those are not alternate numbered lists.

## How to read each section

The numbered list is copied verbatim from the page. Tied stats stay on one line the way Wowhead wrote them (for example `Strength & Attack Power`). Caps and caveats after the list are also from that same page, not from another site.

---

## Warrior

### Warrior — Arms

- **URL:** https://www.wowhead.com/forever/guide/classes/warrior/arms/stat-priority-pve-dps
- **Author:** shoop
- **Page updated:** 2026-11-04 (Wowhead date)
- **Fetched:** 2026-11-11 (America/New_York)

Given that the beta was level-locked at Level 30, it's unclear not only what stats are important for Arms Warrior, but also the availability of stats at Level 60. The priority below is purely speculative for endgame and is based on what we know from beta testing, but has not been tested in-game at Level 60.

**Arms Warrior Stat Priority in WoW Forever**

1. Hit Chance until 8%
2. Expertise until 6.5%
3. Critical Strike Chance
4. Strength
5. Agility
6. Haste
7. Hit Chance after 8%

**Caps (from the same page):**

- Hit Chance: 8% (ability/melee cap vs level 63; 5%/5.5%/6% vs 60/61/62)
- Expertise: 6.5%

**Notes:**

- No separate leveling list.
- Author rule of thumb: an item with 1.5 times more Agility than Strength may yield more DPS; breakpoint depends on total Strength and Crit.
- Hit above 8% still has value (white hits) but ranks below Crit.
- Weapon Skill is discussed in the body (glancing-blow table) but is not in the numbered priority list.
- Impale raises ability crits to 220%. Crit Cap is mentioned as dynamic with Hit; it does not limit racial or ability crit.

---

### Warrior — Fury

- **URL:** https://www.wowhead.com/forever/guide/classes/warrior/fury/stat-priority-pve-dps
- **Author:** Babyhoof
- **Page updated:** 2026-10-29 (Wowhead date)
- **Fetched:** 2026-11-11 (America/New_York)

Given that the beta was level-locked at Level 30, it's unclear not only what stats are important for Fury Warrior, but also the availability of stats at Level 60. The priority below is purely speculative for endgame and is based on what we know from beta testing, but has not been tested in-game at Level 60.

**Fury Warrior Stat Priority in WoW Forever**

1. Weapon Skill until 305
2. Hit Chance until 9%
3. Critical Strike Chance
4. Strength
5. Agility
6. Stamina

**Caps (from the same page):**

- Weapon Skill: 305 (+5 skill)
- Hit Chance: 9% (listed soft cap); body also cites 8% ability miss vs a raid boss and 27% dual-wield white miss, plus 10% off-hand hit from Furious Precision

**Notes:**

- No separate leveling list. Spirit is called valuable while leveling, nearly useless at endgame.
- List says Hit until 9%; body says base 8% ability miss vs a raid boss. Recorded verbatim; this internal mismatch is flagged.
- Body: +5 Weapon Skill (305) reduces the hit cap from 8% to 6% and reduces glancing blows. No Expertise and no Haste on the numbered list.
- Fury talents raise ability crits to 220%. Stamina is last and is described as having no DPS benefit.

---

### Warrior — Protection

- **URL:** https://www.wowhead.com/forever/guide/classes/warrior/protection/stat-priority-pve-tank
- **Author:** Riyani
- **Page updated:** 2026-11-03 (Wowhead date)
- **Fetched:** 2026-11-11 (America/New_York)

In everything from gearing, talents, and rotation, you should think of the balance between defensiveness and offensive throughput/threat as a spectrum, and it's seldom wise to be on either end of that spectrum. As such, when we look at a stat priority, we have to be a bit cautious when we say outline which stats to pursue. Below, you have the best stat priorities for a Defensive, Balanced, and Offensive build, which will be the correct option for your party/raid may be different from other Warriors, but starting with a more balanced approach will be a good idea.

#### Defensive

1. Stamina
2. Defense until 440
3. Armor
4. Agility
5. Defense after 440
6. Parry
7. Dodge
8. Expertise (6.5%) — Soft Cap
9. Block Chance
10. Attack Power/Strength
11. Hit (8%) — Melee Cap
12. Crit
13. Expertise (14%) — Hard Cap
14. Haste

#### Balanced

1. Stamina
2. Expertise (6.5%) — Soft Cap
3. Hit (8%) — Melee Cap
4. Defense until 440
5. Expertise (14%) — Hard Cap
6. Armor
7. Attack Power/Strength
8. Agility
9. Defense after 440
10. Parry
11. Dodge
12. Crit
13. Block Chance
14. Haste

#### Offensive

1. Expertise (6.5%) — Soft Cap
2. Hit (8%) — Melee Cap
3. Expertise (14%) — Hard Cap
4. Crit
5. Attack Power/Strength
6. Stamina (Still need to survive)
7. Haste
8. Agility
9. Defense before 440
10. Armor
11. Defense after 440
12. Parry
13. Dodge
14. Block Chance

**Caps (from the same page):**

- Defense: 440
- Expertise soft: 6.5%
- Hit (melee): 8%
- Expertise hard: 14%

**Notes:**

- Three profiles on one page. Author recommends starting with Balanced.
- No separate numbered leveling list. Spirit is called useful while leveling.
- Rough single-target equivalences (Deep Protection Impale build): 1% Expertise before soft cap = 115 AP; 1% Hit before melee cap = 60 AP; 1% Expertise after soft cap before hard cap = 46 AP; 1% Crit = 34 AP; 1% Haste = 21 AP.
- Defense cap is 440 total Defense (unclear how necessary it will be in Forever). Expertise soft cap 6.5%, hard cap 14%; value past 6% is cut in half, past 14% is 0.
- Melee/spell hit caps vs enemy level: 60: 5%/4%; 61: 5.5%/6%; 62: 6%/11%; 63: 8%/17%. Spell hit is not worth pursuing (except Taunt).
- Author warns not to be dogmatic; efficiently itemized threat pieces (e.g. Lionheart Helm) can beat a 'tank-looking' item.
- Recommended starting profile.

---

## Paladin

### Paladin — Holy

- **URL:** https://www.wowhead.com/forever/guide/classes/paladin/holy/stat-priority-pve-healer
- **Author:** Harreks
- **Page updated:** 2026-10-29 (Wowhead date)
- **Fetched:** 2026-11-11 (America/New_York)

Given that the beta was level-locked at Level 30, it's unclear not only what stats are important for Holy Paladin, but also the availability of stats at Level 60. The priority below is purely speculative for endgame and is based on what we know from beta testing, but has not been tested in-game at Level 60.

**Holy Paladin Stat Priority in WoW Forever**

1. Healing Power
2. Intellect
3. Critical Strike
4. Spirit

**Notes:**

- No separate leveling list. Strength is described as relevant only if you want more damage; Agility is least important.
- Heals do not need Hit. Offensive Hit, if wanted, is covered by maxed Divine Precision, so the author says you do not need Hit on gear.
- Reverence lets 30% of Spirit mana regen continue while casting.
- Healing Power items also carry Spell Power; prefer the ones with a much higher healing-power amount.

---

### Paladin — Protection

- **URL:** https://www.wowhead.com/forever/guide/classes/paladin/protection/stat-priority-pve-tank
- **Author:** Riyani
- **Page updated:** 2026-10-28 (Wowhead date)
- **Fetched:** 2026-11-11 (America/New_York)

In everything from gearing, talents, and rotation, you should think of the balance between defensiveness and offensive throughput/threat as a spectrum, and it's seldom wise to be on either end of that spectrum. As such, when we look at a stat priority, we have to be a bit cautious when we say outline which stats to pursue. Below, you have stat priorities for a Defensive, Balanced, and Offensive build, which will be the correct option for your party/raid may be different from other Paladins, but starting with a more balanced approach will be a good idea.

#### Defensive

1. Stamina
2. Defense until 440
3. Armor
4. Agility
5. Block Chance
6. Defense after 440
7. Spell Power (Still need some threat)
8. Parry
9. Dodge
10. Strength
11. Hit (8%) — Melee Cap
12. Expertise (6.5%) — Soft Cap
13. Crit
14. Hit (17%) — Spell Cap
15. Expertise (14%) — Hard Cap
16. Haste
17. Intellect

#### Balanced

1. Stamina
2. Spell Power
3. Hit (8%) — Melee Cap
4. Defense until 440
5. Armor
6. Expertise (6.5%) — Soft Cap
7. Agility
8. Block Chance
9. Defense after 440
10. Parry
11. Dodge
12. Crit
13. Hit (17%) — Spell Cap
14. Expertise (14%) — Hard Cap
15. Haste
16. Strength
17. Intellect

#### Offensive

1. Spell Power
2. Hit (8%) — Melee Cap
3. Expertise (6.5%) — Soft Cap
4. Crit
5. Stamina (Still need to survive)
6. Hit (17%) — Spell Cap
7. Expertise (14%) — Hard Cap
8. Haste
9. Strength
10. Agility
11. Defense before 440
12. Armor
13. Block Chance
14. Defense after 440
15. Parry
16. Dodge
17. Intellect

**Caps (from the same page):**

- Defense: 440
- Hit (melee): 8%
- Expertise soft: 6.5%
- Hit (spell): 17%
- Expertise hard: 14%

**Notes:**

- Three profiles on one page. Author recommends starting with Balanced.
- No separate numbered leveling list.
- Rough single-target Spell Power equivalences: 1% Hit before melee cap = 21 SP; 1% Expertise before soft cap = 15 SP; 1% Crit = 12 SP; 1% Hit after melee cap before spell cap = 9 SP; 1% Expertise after soft cap before hard cap = 7,5 SP; 1% Haste = 7 SP.
- Defense cap 440 (necessity in Forever still unclear). Expertise soft 6.5%, hard 14%. Melee/spell hit vs enemy level: 60: 5%/4%; 61: 5.5%/6%; 62: 6%/11%; 63: 8%/17%. Precision gives 3% melee and spell Hit; in a Shockadin build take only 2/3 Divine Precision to avoid overcapping with Precision.
- Spell Penetration does nothing (no Holy resistance). Expertise is called less valuable than for other tanks because it only affects melee attacks.
- Author warns not to skip efficiently itemized threat pieces such as Stalwart Helm.
- Recommended starting profile.

---

### Paladin — Retribution

- **URL:** https://www.wowhead.com/forever/guide/classes/paladin/retribution/stat-priority-pve-dps
- **Author:** Surveillant
- **Page updated:** 2026-10-31 (Wowhead date)
- **Fetched:** 2026-11-11 (America/New_York)

The priority below is built from the data we have based on the beta. Expect it to shift once Level 60 dungeon and raid gear is available.

**Retribution Paladin Stat Priority in WoW Forever**

1. Weapon Skill
2. Weapon DPS & Speed
3. Hit Chance (9%)
4. Expertise (6.5%)
5. Spell Damage
6. Intellect
7. Strength & Attack Power
8. Agility & Critical Strike Chance
9. Stamina

**Caps (from the same page):**

- Hit Chance: 9% (safe melee target vs raid bosses; body notes sources disagree on whether Classic hit suppression was removed, and spells have a 16% miss vs a level-63 boss, but Seals/Judgement are melee so only the melee cap is needed)
- Expertise: 6.5% (historical; not confirmed for level-63 bosses)

**Notes:**

- No separate leveling list. Stamina is called more valuable while leveling, in Hardcore, or in PvP.
- Weapon is by far the most important item. Shockadin / Seal of Righteousness wants a faster two-hander; otherwise prefer slower two-handers. First +5 Weapon Skill is called the most valuable PvE breakpoint (up to 3% hit); first +8 reduces glancing penalty.
- Author comment on the same page (not in the list): "I'm aware of the recent major reworks to Retribution Paladin and am working on updating the guide as soon as possible to reflect that information and the latest theorycrafting." Page last updated 2026-10-31, so this list may be pending a rewrite.
- Champion of the Light currently converts 60% of Intellect to Spell Power at 3/3; author says this may change again.
- Haste is discussed in the body as traditionally strong but 'more testing is required' and is not on the numbered list.

---

## Druid

### Druid — Balance

- **URL:** https://www.wowhead.com/forever/guide/classes/druid/balance/stat-priority-pve-dps
- **Author:** DrWonder
- **Page updated:** 2026-10-30 (Wowhead date)
- **Fetched:** 2026-11-11 (America/New_York)

Given that the beta was level-locked at Level 30, it's unclear not only what stats are important for Balance Druid, but also the availability of stats at Level 60. The priority below is purely speculative for endgame and is based on what we know from beta testing, but has not been tested in-game at Level 60.

**Balance Druid Stat Priority in WoW Forever**

1. Hit Chance until 17%
2. Spell Damage
3. Spell Penetration
4. Critical Strike Chance
5. Haste
6. Intellect
7. Spirit
8. Stamina

**Caps (from the same page):**

- Hit Chance: 17% (4% from Nature's Reach, so 13% from gear)

**Notes:**

- No separate leveling list.
- List says Spell Penetration; body heading is 'Spell Penetration / Spell Pierce'.
- Body says casters have a 16% miss vs bosses, then 'once you collect 17% hit, your spells will never miss on targets 3 levels or more higher than you.'
- Vengeance raises spell crits to 200%.

---

### Druid — Feral (Cat)

- **URL:** https://www.wowhead.com/forever/guide/classes/druid/feral/stat-priority-pve-dps
- **Author:** Lexolas
- **Page updated:** 2026-10-29 (Wowhead date)
- **Fetched:** 2026-11-11 (America/New_York)

Given that the beta was level-locked at Level 30, it's unclear not only what stats are important for Feral Druid, but also the availability of stats at Level 60. The priority below is purely speculative for endgame and is based on what we know from beta testing, but has not been tested in-game at Level 60.

**Feral Druid Stat Priority in WoW Forever**

1. 1% Critical Strike Chance
2. 1% Hit Chance (8% cap)
3. 1% Reduced Dodge/Parry Chance (6.5% cap)
4. 1% Haste
5. Weapon DPS
6. Agility = Strength
7. Attack Power
8. Intellect
9. Spirit
10. Stamina

**Caps (from the same page):**

- Hit Chance: 8%
- Reduced Dodge/Parry Chance: 6.5%

**Notes:**

- Separate page from Feral Tank. This is the Cat / DPS list. Ranked per 1% for the percentage stats (author lists '1% Crit', '1% Hit', etc.).
- No separate leveling list. Author: Intellect, Spirit, and Stamina give no throughput but help Health and Mana; if you ever tank, Stamina is number 1.
- Agility and Strength are explicitly tied. Feral Druids get no Hit from talents, so all 8% comes from gear. Missed abilities do not spend full Energy.
- Body does not expand much on Expertise/Haste beyond the list.

---

### Druid — Feral (Bear)

- **URL:** https://www.wowhead.com/forever/guide/classes/druid/feral/stat-priority-pve-tank
- **Author:** L0uki
- **Page updated:** 2026-11-03 (Wowhead date)
- **Fetched:** 2026-11-11 (America/New_York)

With limited information at hand about level 60 content, definite stat priorities cannot be established. That said, the priorities listed below offer a safe, reliable starting point suited to a wide range of encounters and scenarios. The defensive priorities emphasize a druid's ability to build up a huge effective health pool, which is further embellished by reaching 440 defense, effectively preventing critical strikes. This gearing approach limits worst-case events while accepting slightly worse average-case performance. Similarly, the offensive priority seeks to limit misses, dodges, and parries before stacking straight damage: since many of our abilities carry a threat modifier, the raw value matters less---as long as the ability connects.

#### Defensive

1. Stamina
2. Defense until 440
3. Armor
4. Agility
5. Avoidance
6. Defense after 440

#### Offensive

1. Hit
2. Reduced Chance to Be Dodged/Parried
3. Haste
4. Crit
5. Weapon DPS
6. Strength
7. Agility
8. Strength

**Caps (from the same page):**

- Defense: 440
- Armor: 17265
- Hit Chance: 8%
- Expertise soft: 6.5%
- Expertise hard: 14%

**Notes:**

- Separate page from Feral DPS (Cat). Defensive and Offensive lists only — no Balanced list.
- No separate numbered leveling list. Spell Power is called a niche leveling/dungeon benefit via Thorns, not pursued at max level.
- Hit aim is the 8% melee cap. Expertise soft cap 6.5% (dodge), hard cap 14% (parry). Armor is useful up to the armor cap of 17,265. Weapon speed is largely irrelevant (Bear Form is a fixed 2.5s before Haste).
- Offensive list item 6 and item 8 are both 'Strength' on the live page. Recorded verbatim; likely a typo.

---

### Druid — Restoration

- **URL:** https://www.wowhead.com/forever/guide/classes/druid/restoration/stat-priority-pve-healer
- **Author:** Frankensteak
- **Page updated:** 2026-11-01 (Wowhead date)
- **Fetched:** 2026-11-11 (America/New_York)

Given that the beta was level-locked at Level 30, it's unclear not only what stats are important for Restoration Druid, but also the availability of stats at Level 60. The priority below is purely speculative for endgame and is based on what we know from beta testing, but has not been tested in-game at Level 60.

**Restoration Druid Stat Priority in WoW Forever**

1. Spell Healing
2. Critical Strike Chance
3. Spell Haste
4. Spirit
5. Intellect
6. MP5
7. Stamina

**Caps (from the same page):**

- GCD: cannot be reduced below 1.0 seconds

**Notes:**

- No separate leveling list. Author says the real job is balancing throughput vs mana, and this ranked list focuses on throughput first because consumables and cooldowns can cover mana. Do not ignore mana stats; a big mana gain for a small Spell Healing loss can still be an upgrade.
- HoTs are intended to crit in Forever. Reflection lets 50% of Spirit regen continue while casting. Living Spirit increases Spirit. Bloom is said to maths out to roughly 1 Spell Healing per point of Spirit if leveraged. 1 Spirit = 0.3 MP5 with Reflection.

---

## Shaman

### Shaman — Elemental

- **URL:** https://www.wowhead.com/forever/guide/classes/shaman/elemental/stat-priority-pve-dps
- **Author:** Lucenia
- **Page updated:** 2026-11-04 (Wowhead date)
- **Fetched:** 2026-11-11 (America/New_York)

Our end-game stat priority is roughly

**Elemental Shaman Stat Priority in WoW Forever**

1. Spell Piercing
2. Haste / Cast Speed
3. Hit Chance until 17%
4. Spell Damage
5. Critical Strike Chance
6. Nature Damage / Fire Damage
7. Intellect
8. Spirit
9. Strength (Only while leveling)
10. Stamina

**Caps (from the same page):**

- Hit Chance: 17% (up to 5% from Tidal Focus, rest from gear)

**Notes:**

- This is labeled an end-game priority. Strength is explicitly '(Only while leveling)'. Author: there isn't necessarily one right answer for how to gear while leveling; find a balance that feels good.
- Unusual among casters: Spell Piercing and Haste are listed above Hit and Spell Damage.
- Body: Elemental ST damage is roughly 70% Nature / 30% Fire; cleave/AoE closer to 40% Nature / 60% Fire. Elemental Fury raises crits to 200%. 10 Spell Piercing vs no resistance adds about 1.8% damage on average at level 60. Haste/Cast Speed stack multiplicatively; GCD floors at 1 second.
- Body says spells have a 17% chance to miss against bosses (other caster pages sometimes say 16% then cap at 17%).

---

### Shaman — Enhancement

- **URL:** https://www.wowhead.com/forever/guide/classes/shaman/enhancement/stat-priority-pve-dps
- **Author:** Yebb
- **Page updated:** 2026-11-03 (Wowhead date)
- **Fetched:** 2026-11-11 (America/New_York)

Given that the beta was level-locked at Level 30, it's unclear not only what stats are important for Enhancement Shaman, but also the availability of stats at Level 60. The priority below is purely speculative for endgame and is based on what we know from beta testing, but has not been tested in-game at Level 60.

**Enhancement Shaman Stat Priority in WoW Forever**

1. Hit Chance to minimum 8%
2. Expertise to 6.5%
3. Intellect
4. Spell Damage
5. Strength
6. Spell Piercing
7. Haste
8. Critical Strike Chance
9. Agility
10. Spirit
11. Stamina

**Caps (from the same page):**

- Hit Chance: 8% melee minimum (going above is useful because of spell damage, but should not be prioritized after the initial 8%)
- Expertise: 6.5%
- Hit Chance (spells): 17% mentioned in the body

**Notes:**

- No separate numbered leveling list.
- Page updated 2026-11-03, before the Nov 10 Mental Dexterity hotfix (150% to 100%). Intellect is still #3, above Strength. Body says 'especially Intelligence has a lot of scaling due to and .' (talent names were stripped from the page text). Flag this as potentially stale relative to the hotfix.
- Author: Enhancement is shaping up to be very spell-centered, so raw Spell Damage is worth focusing on. 10 Spell Piercing vs no resistance adds about 1.8% damage on average at level 60.

---

### Shaman — Restoration

- **URL:** https://www.wowhead.com/forever/guide/classes/shaman/restoration/stat-priority-pve-healer
- **Author:** Woah
- **Page updated:** 2026-11-01 (Wowhead date)
- **Fetched:** 2026-11-11 (America/New_York)

Our end-game stat priority is roughly

**Restoration Shaman Stat Priority in WoW Forever**

1. Spell Healing
2. Critical Strike Chance
3. Haste / Cast Speed
4. Intellect
5. Spirit
6. Mp5
7. Spell Damage (Only while leveling)

**Notes:**

- Labeled an end-game priority. Spell Damage is explicitly '(Only while leveling)'. Author: there isn't necessarily one right answer for how to gear while leveling; aim for the best stats you can find.
- No Stamina on the list. Crit has extra synergy via Water Shield and Ancestral Healing. Haste can make you spend mana faster, a particular concern for healing. GCD floors at 1 second.
- Hit and Spell Piercing are discussed in the body (17% spell hit cap, up to 5% from Tidal Focus) but are not on the healer priority list. Author says you generally will not need Hit on gear for Earth Shock interrupts at endgame.

---

## Priest

### Priest — Discipline

- **URL:** https://www.wowhead.com/forever/guide/classes/priest/discipline/stat-priority-pve-healer
- **Author:** Voulk
- **Page updated:** 2026-10-30 (Wowhead date)
- **Fetched:** 2026-11-11 (America/New_York)

The beta was level-locked at Level 30 and we did not get to see any endgame content so there are still some outlying questions in regards to which stats will be best and which ones will even be available. This guide therefore includes a lot of speculation for now, though it will be quickly updated shortly after the game goes live.

**Discipline Priest Stat Priority in WoW Forever**

1. Healing Power
2. Intellect
3. Spirit
4. Critical Strike Chance
5. Spell Damage
6. Stamina

**Notes:**

- No separate numbered leveling list. Body: Spell Power is particularly good while leveling (you spend a lot of time DPSing even as a healer) and less relevant for endgame, where you'd rather have Healing Power.
- Author: balance throughput vs mana fight-by-fight; for now aim to get a lot of Healing Power, Intellect, and Spirit. More refined comparisons at level 60.
- Heals don't need Hit. When DPS is valuable, cap via Holy Precision rather than Hit on gear. Haste is mentioned in the body (rare; GCD/cast floor 1s; does not affect HoT tick rate) but is not on the list.
- Crit bonuses: Divine Aegis (15% shield) and Renewed Hope (reduces Weakened Soul duration).

---

### Priest — Holy

- **URL:** https://www.wowhead.com/forever/guide/classes/priest/holy/stat-priority-pve-healer
- **Author:** Spanklord
- **Page updated:** 2026-10-31 (Wowhead date)
- **Fetched:** 2026-11-11 (America/New_York)

Given that the beta was level-locked at Level 30, it's unclear not only what stats are ultimately going to be the most important for Holy Priest, but also the general availability of specific stats at Level 60. The priority below is purely speculative for endgame and is based on what we know from beta testing, but has not been tested in-game at Level 60.

**Holy Priest Stat Priority in WoW Forever**

1. Healing Power
2. Intellect
3. Mana per 5 seconds
4. Spirit
5. Spell Critical Strike Chance
6. Stamina

**Notes:**

- No separate leveling list. Spell Hit is explicitly not relevant (heals do not miss).
- In Forever, bonus healing also includes one-third as much bonus damage (a Forever change). Spiritual Guidance at 5 points increases spell healing by up to 25% of total Spirit and spell damage by up to 8% of total Spirit (Classic gave 25% to both).
- Author treats MP5 and Spirit as roughly equal depending on content: MP5 works during chain pulls; Spirit is more available below high-tier gear. Note: Renew cannot critically strike. Inspiration (armor buff on crit heals) is the main reason to take Spell Crit.
- Body formula for Spirit regen while casting uses a 0.15 multiplier 'assuming 3/3 Meditation'; 3/3 Meditation is normally 50%. Flag this as a possible typo on the page, not used in the priority list.

---

### Priest — Shadow

- **URL:** https://www.wowhead.com/forever/guide/classes/priest/shadow/stat-priority-pve-dps
- **Author:** Jereico
- **Page updated:** 2026-10-30 (Wowhead date)
- **Fetched:** 2026-11-11 (America/New_York)

Given that the beta was level-locked at Level 30, it's unclear not only what stats are ultimately going to be the most important for Shadow Priest, but also the general availability of specific stats at Level 60. The priority below is purely speculative for endgame and is based on what we know from beta testing, but has not been tested in-game at Level 60.

**Shadow Priest Stat Priority in WoW Forever**

1. Hit Chance until 17%
2. Spell Critical Strike Chance
3. Spell Damage (Shadow Damage)
4. Intellect
5. Spirit
6. Stamina

**Caps (from the same page):**

- Hit Chance: 17% (Shadow Focus covers part of this; remaining 12% from gear)

**Notes:**

- No separate leveling list. No Haste or Spell Pierce on the list.
- Shadowform raises crits to 200%. Missing long-cooldown spells like Devouring Plague is called a substantial loss; missed spells still cost mana and cooldown.

---

## Mage

### Mage — Arcane

- **URL:** https://www.wowhead.com/forever/guide/classes/mage/arcane/stat-priority-pve-dps
- **Author:** Foolipe
- **Page updated:** 2026-10-28 (Wowhead date)
- **Fetched:** 2026-11-11 (America/New_York)

Given that the beta was level-locked at Level 30, it's unclear not only what stats are important for Arcane Mage, but also the availability of stats at Level 60. The priority below is purely speculative for endgame and is based on what we know from beta testing, but has not been tested in-game at Level 60.

**Arcane Mage Stat Priority in WoW Forever**

1. Hit Chance until 17%
2. Spell Damage (+ Arcane Damage)
3. Critical Strike Chance
4. Spell Piercing
5. Haste
6. Intellect
7. Spirit
8. Stamina

**Caps (from the same page):**

- Hit Chance: 17% (Arcane Focus 5% to main Arcane spells; Precision 6% to Fire and Frost fillers)

**Notes:**

- No separate leveling list.
- Author: Hit value drops as you near the cap, and you can risk being slightly under cap for more offensive stats (more variance). Unlike Classic, you can now fully cap.
- Arcane also scales with Intellect and Max Mana via Arcane Blast and Arcane Wrath. Arcane Mind raises crit damage. Arcane Subtlety gives 15 Spell Piercing passively. Haste is called good but very limited (Troll Berserking, Sky Elf Wind Blessed, maybe Mind Quickening Gem).
- Spell Piercing value at level 60 is 'still not yet confirmed.' Beta appeared to increase damage in 10% buckets (10 to 30%).

---

### Mage — Fire

- **URL:** https://www.wowhead.com/forever/guide/classes/mage/fire/stat-priority-pve-dps
- **Author:** Foolipe
- **Page updated:** 2026-11-03 (Wowhead date)
- **Fetched:** 2026-11-11 (America/New_York)

Given that the beta was level-locked at Level 30, it's unclear not only what stats are important for Fire Mage, but also the availability of stats at Level 60. The priority below is purely speculative for endgame and is based on what we know from beta testing, but has not been tested in-game at Level 60.

**Fire Mage Stat Priority in WoW Forever**

1. Hit Chance until 17%
2. Spell Damage (+ Fire Damage)
3. Critical Strike Chance
4. Spell Piercing
5. Haste
6. Intellect
7. Spirit
8. Stamina

**Caps (from the same page):**

- Hit Chance: 17% (Precision provides 6% to all schools)

**Notes:**

- No separate leveling list. Same skeleton as Arcane, with school damage swapped to Fire.
- Ignite turns 40% of a Fire crit into a DoT. Heating Up also needs crits. Author says you can risk being slightly under the Hit cap for more offensive stats.
- Likely to take Arcane Subtlety (15 Spell Piercing). Haste sources same as Arcane. Spell Piercing value at 60 still unconfirmed.

---

### Mage — Frost

- **URL:** https://www.wowhead.com/forever/guide/classes/mage/frost/stat-priority-pve-dps
- **Author:** Porom
- **Page updated:** 2026-10-29 (Wowhead date)
- **Fetched:** 2026-11-11 (America/New_York)

Given that the beta was level-locked at Level 30, it's unclear not only what stats are important for Frost Mage, but also the availability of stats at Level 60. The priority below is purely speculative for endgame and is based on what we know from beta testing, but has not been tested in-game at Level 60.

**Frost Mage Stat Priority in WoW Forever**

1. Hit Chance until 11-12% (you'll get 5-6 from talents)
2. Critical Strike Chance
3. Spell Damage (+Frost and Arcane Damage)
4. Intellect
5. Spirit
6. Stamina

**Caps (from the same page):**

- Hit Chance: 11-12% from gear (5-6% from talents; body: 6% for Fire and Frost spells and another 5% for Arcane spells in the Arcane tree, toward the usual 17% boss cap)

**Notes:**

- No separate leveling list. No Haste or Spell Piercing on the list, unlike Arcane and Fire.
- Crit is ranked above Spell Damage. Author notes crits are already very common due to Shatter with Fingers of Frost, 'so it remains to be seen how valuable it will be relative to Hit and Spell Power.'
- Body Intellect conversion text mistakenly says 'Druids receive 1% Spell Critical Strike Chance for every 60 points of Intellect' on a Mage page.
- Strength, Agility, and Attack Power are called useless.

---

## Warlock

### Warlock — Affliction

- **URL:** https://www.wowhead.com/forever/guide/classes/warlock/affliction/stat-priority-pve-dps
- **Author:** Zephan
- **Page updated:** 2026-11-11 (Wowhead date)
- **Fetched:** 2026-11-11 (America/New_York)

This order comes from level 60 stat weights in Warlock simulation tools for the Wrack raid build. The SM Ruin build uses the same order.

**Affliction Warlock Stat Priority in WoW: Forever**

1. Spell Power / + Shadow Damage
2. Crit Chance
3. Hit Chance (up to 12% from gear with 5/5 Suppression)
4. Haste
5. Spell Pierce
6. Intellect
7. Spirit

**Caps (from the same page):**

- Hit Chance: 12% from gear and buffs with 5/5 Suppression (17% total; 4% vs same-level targets)

**Notes:**

- Most recently updated page of the set (2026-11-11). Unlike most Wowhead Forever lists, this one is explicitly from level-60 sim weights, not only a beta estimate. No Stamina on the list. No separate leveling list.
- Author-stated sim equivalences: Wrack build 1% Crit ≈ 9 SP, 1% Hit ≈ 7.5 SP, 1% Haste ≈ 2.5 SP, 1 Spell Pierce ≈ 1.25 SP. SM Ruin: 1% Crit ≈ 11 SP, 1% Hit ≈ 9 SP, 1% Haste ≈ 6.5 SP.
- DoT ticks can crit. Pandemic (DoTs/drains/Wrack) and Ruin (Shadow Bolt/Immolate) make almost every crit deal double damage. Haste does not speed DoT ticks, DoT durations, or channeled Wrack/Drain Life. Spell Pierce is 1/10th as effective on DoTs. Past the Hit cap, swap Hit for Spell Power or Crit.

---

### Warlock — Demonology

- **URL:** https://www.wowhead.com/forever/guide/classes/warlock/demonology/stat-priority-pve-dps
- **Author:** Zephan
- **Page updated:** 2026-11-03 (Wowhead date)
- **Fetched:** 2026-11-11 (America/New_York)

The Beta was capped at level 30, so this order is a best estimate for level 60. It comes from stat weights in Warlock simulation tools for the top 2 Demonology raid builds: the Fire build with the Imp and Searing Pain, and the Shadow build with the Sayaad, Shadow Bolt and 5/5 Improved Shadow Bolt.

**Demonology Warlock Stat Priority in WoW: Forever**

1. Spell Power / + Fire Damage or + Shadow Damage (matching your build)
2. Hit Chance (17% from gear, minus 1% per point in Suppression)
3. Crit Chance
4. Haste
5. Spell Pierce
6. Intellect
7. Spirit

**Caps (from the same page):**

- Hit Chance: 17% from gear minus 1% per point in Suppression (Fire build typically 1 point / 16% from gear; Shadow build typically 0 points / full 17%)

**Notes:**

- No separate leveling list. No Stamina on the list. Hit is ranked above Crit, unlike Affliction and Destruction.
- School-specific damage is nearly as good for the matching build and only about a fifth of Spell Power for the other build.
- Author-stated sim equivalences: 1% Hit ≈ 10 SP in both builds. Shadow: Crit ≈ Hit, 1% Haste ≈ 7 SP. Fire: 1% Crit ≈ 7 SP, 1% Haste ≈ 6 SP. Both builds take 5/5 Ruin. Haste does not speed the demon's casts.

---

### Warlock — Destruction

- **URL:** https://www.wowhead.com/forever/guide/classes/warlock/destruction/stat-priority-pve-dps
- **Author:** Zephan
- **Page updated:** 2026-11-03 (Wowhead date)
- **Fetched:** 2026-11-11 (America/New_York)

The Beta was capped at level 30, so this order is a best estimate for level 60. It comes from stat weights in Warlock simulation tools for the Destruction raid build, which uses Incinerate as its filler with the Sayaad out.

**Destruction Warlock Stat Priority in WoW: Forever**

1. Spell Power / + Fire Damage
2. Crit Chance
3. Hit Chance (up to 12% from gear with 5/5 Suppression)
4. Haste
5. Spell Pierce
6. Intellect
7. Spirit

**Caps (from the same page):**

- Hit Chance: 12% from gear and buffs with 5/5 Suppression (17% total)

**Notes:**

- No separate leveling list. No Stamina on the list. Same skeleton as Affliction, with Fire school damage.
- Author: + Fire Damage is worth about two-thirds of Spell Power; + Shadow Damage about a third. 1% Crit and 1% Hit are nearly tied at roughly 9 SP, Crit slightly ahead. 1% Haste ≈ 7 SP. Past the Hit cap, swap Hit for Spell Power or Crit.
- Raid build takes 5/5 Ruin and 3/3 Pandemic. Haste does not speed DoT ticks or the demon.

---

## Rogue

### Rogue — Assassination

- **URL:** https://www.wowhead.com/forever/guide/classes/rogue/assassination/stat-priority-pve-dps
- **Author:** warstry
- **Page updated:** 2026-11-09 (Wowhead date)
- **Fetched:** 2026-11-11 (America/New_York)

Given that the beta was level-locked at Level 30, it's unclear not only what stats are important for Assassination Rogue, but also the availability of stats at Level 60. The priority below is purely speculative for endgame and is based on what we know from beta testing, but has not been tested in-game at Level 60.

**Assassination Rogue Stat Priority in WoW Forever**

1. Hit Chance until 8% (Ability cap)
2. Expertise to 6.5%
3. Weapon skill to 308
4. Hit to 17% (Poison cap)
5. Agility
6. Critical Strike Chance
7. Haste Rating
8. Strength
9. Attack Power
10. Stamina

**Caps (from the same page):**

- Hit Chance (ability): 8%
- Expertise: 6.5%
- Weapon Skill: 308 (glancing-blow soft cap; 5% penalty)
- Hit Chance (poison/spell): 17%
- Hit Chance (dual-wield white): 27% (mentioned in the body, not as a numbered rank)

**Notes:**

- All three Rogue specs share the same numbered list and nearly the same accompanying paragraph. Assassination uniquely stresses Hit up to the 17% poison cap and values Crit more because of Seal Fate. Combat's Haste section also mentions Blade Flurry. Combat is reviewed by Simonize.
- No separate numbered leveling list. Spirit is called moderately valuable while leveling (out-of-combat health regen) with no combat benefit.
- Main-hand weapon DPS is called the biggest damage factor but is not itself a numbered list item (unlike Ret and Feral). Auto-attack Hit still has some value up to the 27% dual-wield cap, below the other caps.
- Crit and Haste are 'currently equal in value,' with Haste likely much harder to find. Haste does not increase Energy regen. 29 Agility = 1% physical Crit; Agility does not convert to Poison Crit, but secondary Crit on items does.
- Assassination uniquely emphasizes Hit through the 17% poison cap because of heavy Poison damage, and values Crit more than the other Rogue specs due to Seal Fate.

---

### Rogue — Combat

- **URL:** https://www.wowhead.com/forever/guide/classes/rogue/combat/stat-priority-pve-dps
- **Author:** warstry (reviewed by Simonize)
- **Page updated:** 2026-10-30 (Wowhead date)
- **Fetched:** 2026-11-11 (America/New_York)

Given that the beta was level-locked at Level 30, it's unclear not only what stats are important for Combat Rogue, but also the availability of stats at Level 60. The priority below is purely speculative for endgame and is based on what we know from beta testing, but has not been tested in-game at Level 60.

**Combat Rogue Stat Priority in WoW Forever**

1. Hit Chance until 8% (Ability cap)
2. Expertise to 6.5%
3. Weapon skill to 308
4. Hit to 17% (Poison cap)
5. Agility
6. Critical Strike Chance
7. Haste Rating
8. Strength
9. Attack Power
10. Stamina

**Caps (from the same page):**

- Hit Chance (ability): 8%
- Expertise: 6.5%
- Weapon Skill: 308 (glancing-blow soft cap; 5% penalty)
- Hit Chance (poison/spell): 17%
- Hit Chance (dual-wield white): 27% (mentioned in the body, not as a numbered rank)

**Notes:**

- All three Rogue specs share the same numbered list and nearly the same accompanying paragraph. Assassination uniquely stresses Hit up to the 17% poison cap and values Crit more because of Seal Fate. Combat's Haste section also mentions Blade Flurry. Combat is reviewed by Simonize.
- No separate numbered leveling list. Spirit is called moderately valuable while leveling (out-of-combat health regen) with no combat benefit.
- Main-hand weapon DPS is called the biggest damage factor but is not itself a numbered list item (unlike Ret and Feral). Auto-attack Hit still has some value up to the 27% dual-wield cap, below the other caps.
- Crit and Haste are 'currently equal in value,' with Haste likely much harder to find. Haste does not increase Energy regen. 29 Agility = 1% physical Crit; Agility does not convert to Poison Crit, but secondary Crit on items does.

---

### Rogue — Subtlety

- **URL:** https://www.wowhead.com/forever/guide/classes/rogue/subtlety/stat-priority-pve-dps
- **Author:** warstry
- **Page updated:** 2026-10-30 (Wowhead date)
- **Fetched:** 2026-11-11 (America/New_York)

Given that the beta was level-locked at Level 30, it's unclear not only what stats are important for Subtlety Rogue, but also the availability of stats at Level 60. The priority below is purely speculative for endgame and is based on what we know from beta testing, but has not been tested in-game at Level 60.

**Subtlety Rogue Stat Priority in WoW Forever**

1. Hit Chance until 8% (Ability cap)
2. Expertise to 6.5%
3. Weapon skill to 308
4. Hit to 17% (Poison cap)
5. Agility
6. Critical Strike Chance
7. Haste Rating
8. Strength
9. Attack Power
10. Stamina

**Caps (from the same page):**

- Hit Chance (ability): 8%
- Expertise: 6.5%
- Weapon Skill: 308 (glancing-blow soft cap; 5% penalty)
- Hit Chance (poison/spell): 17%
- Hit Chance (dual-wield white): 27% (mentioned in the body, not as a numbered rank)

**Notes:**

- All three Rogue specs share the same numbered list and nearly the same accompanying paragraph. Assassination uniquely stresses Hit up to the 17% poison cap and values Crit more because of Seal Fate. Combat's Haste section also mentions Blade Flurry. Combat is reviewed by Simonize.
- No separate numbered leveling list. Spirit is called moderately valuable while leveling (out-of-combat health regen) with no combat benefit.
- Main-hand weapon DPS is called the biggest damage factor but is not itself a numbered list item (unlike Ret and Feral). Auto-attack Hit still has some value up to the 27% dual-wield cap, below the other caps.
- Crit and Haste are 'currently equal in value,' with Haste likely much harder to find. Haste does not increase Energy regen. 29 Agility = 1% physical Crit; Agility does not convert to Poison Crit, but secondary Crit on items does.

---

## Hunter

### Hunter — Beast Mastery

- **URL:** https://www.wowhead.com/forever/guide/classes/hunter/beast-mastery/stat-priority-pve-dps
- **Author:** Docoda (reviewed by Neteyes)
- **Page updated:** 2026-11-04 (Wowhead date)
- **Fetched:** 2026-11-11 (America/New_York)

Given that the beta was level-locked at Level 30, it's unclear not only what stats are important for Beast Mastery Hunter, but also the availability of stats at Level 60. The priority below is purely speculative for endgame and is based on what we know from beta testing, but has not been tested in-game at Level 60.

**Beast Mastery Hunter Stat Priority in WoW Forever**

1. % Hit Chance until 9%
2. % Critical Strike Chance
3. Agility
4. Intellect
5. (Ranged) Attack Power
6. Spirit
7. Stamina

**Caps (from the same page):**

- Hit Chance: 9%

**Notes:**

- No separate leveling list. Marksmanship uniquely says this list 'ranks every stat per 1% or 1 point, depending on how they show up on gear.' BM and Survival do not repeat that sentence but use the same '% Hit' / '% Crit' wording for the first two ranks.
- Body Hit target is 9% so yellow hits never miss on skull-level bosses; also covers normal ranged and two-handed white hits. One-hand whites need more Hit.
- Careful Aim converts Intellect to ranged Attack Power 1-to-1. Body Agility bullets say '1 Agility = 1 ranged Attack Power' immediately after prose that says Hunters gain 2 ranged Attack Power per point of Agility — an internal inconsistency on the page.
- Strength is discussed in the body as only slightly useful for melee weaving and is not on the BM list (unlike Survival).
- Bestial Discipline lets mana regen continue while casting.

---

### Hunter — Marksmanship

- **URL:** https://www.wowhead.com/forever/guide/classes/hunter/marksmanship/stat-priority-pve-dps
- **Author:** Docoda
- **Page updated:** 2026-11-04 (Wowhead date)
- **Fetched:** 2026-11-11 (America/New_York)

Given that the beta was level-locked at Level 30, it's unclear not only what stats are important for Marksmanship Hunter, but also the availability of stats at Level 60. The priority below is purely speculative for endgame and is based on what we know from beta testing, but has not been tested in-game at Level 60. This list ranks every stat per 1% or 1 point, depending on how they show up on gear.

**Marksmanship Hunter Stat Priority in WoW Forever**

1. % Hit Chance until 9%
2. % Critical Strike Chance
3. Agility
4. Intellect
5. (Ranged) Attack Power
6. Spirit
7. Stamina

**Caps (from the same page):**

- Hit Chance: 9%

**Notes:**

- No separate leveling list. Marksmanship uniquely says this list 'ranks every stat per 1% or 1 point, depending on how they show up on gear.' BM and Survival do not repeat that sentence but use the same '% Hit' / '% Crit' wording for the first two ranks.
- Body Hit target is 9% so yellow hits never miss on skull-level bosses; also covers normal ranged and two-handed white hits. One-hand whites need more Hit.
- Careful Aim converts Intellect to ranged Attack Power 1-to-1. Body Agility bullets say '1 Agility = 1 ranged Attack Power' immediately after prose that says Hunters gain 2 ranged Attack Power per point of Agility — an internal inconsistency on the page.
- Same numbered list as Beast Mastery. Rapid Recuperation lets mana regen continue while casting.

---

### Hunter — Survival

- **URL:** https://www.wowhead.com/forever/guide/classes/hunter/survival/stat-priority-pve-dps
- **Author:** Docoda (reviewed by Neteyes)
- **Page updated:** 2026-11-04 (Wowhead date)
- **Fetched:** 2026-11-11 (America/New_York)

Given that the beta was level-locked at Level 30, it's unclear not only what stats are important for Survival Hunter, but also the availability of stats at Level 60. The priority below is purely speculative for endgame and is based on what we know from beta testing, but has not been tested in-game at Level 60.

**Survival Hunter Stat Priority in WoW Forever**

1. % Hit Chance
2. % Critical Strike Chance
3. Agility
4. Strength
5. Attack Power
6. Intellect
7. Spirit
8. Stamina

**Caps (from the same page):**

- Hit Chance: 9% (stated in the body for yellow hits on skull bosses; the numbered list does not print 'until 9%', unlike BM and Marksmanship)

**Notes:**

- No separate leveling list. Marksmanship uniquely says this list 'ranks every stat per 1% or 1 point, depending on how they show up on gear.' BM and Survival do not repeat that sentence but use the same '% Hit' / '% Crit' wording for the first two ranks.
- Body Hit target is 9% so yellow hits never miss on skull-level bosses; also covers normal ranged and two-handed white hits. One-hand whites need more Hit.
- Careful Aim converts Intellect to ranged Attack Power 1-to-1. Body Agility bullets say '1 Agility = 1 ranged Attack Power' immediately after prose that says Hunters gain 2 ranged Attack Power per point of Agility — an internal inconsistency on the page.
- Different from BM/MM: Strength is #4, Attack Power is unparenthesized, and Intellect drops below Strength and Attack Power. The numbered Hit line has no 9% cap printed, but the body still cites 9%.
- Resourcefulness lets mana regen continue while casting. Predator's Edge (melee) and Mortal Shots (ranged) increase crit damage.
- Body still says Intellect 'gets quite some value due to the Careful Aim talent (when talented)' even though Intellect is #6 here.

---

## Surprises and caveats

1. **Retribution may already be stale.** Surveillant's comment on the Ret page says a major Ret rework is not yet reflected, and the page is dated 2026-10-31. This is the list Mightie pasted.
2. **Enhancement still ranks Intellect above Strength** (updated 2026-11-03), which is before the Nov 10 Mental Dexterity hotfix (150% to 100%). Talent names in the Intellect sentence were stripped (`due to and .`).
3. **Feral Bear Offensive list repeats Strength** as both item 6 and item 8. Recorded verbatim; almost certainly a typo.
4. **Fury Hit cap mismatch:** the numbered list says Hit until 9%, the body says an 8% ability miss vs a raid boss (plus Furious Precision for the off-hand).
5. **Elemental ranks Spell Piercing and Haste above Hit and Spell Damage**, unlike every other caster list.
6. **Frost ranks Crit above Spell Damage** and omits Haste and Spell Piercing, unlike Arcane and Fire on the same site. The Frost Intellect section also mistakenly talks about Druids.
7. **Warlock pages are the only ones that cite simulation tools and give numeric equivalences.** Affliction was updated 2026-11-11 (today) and is framed as level-60 sim weights, not a beta estimate.
8. **All three Rogue specs share an identical numbered list.** Differences are only in the commentary (Assassination values poison Hit and Seal Fate Crit more).
9. **Beast Mastery and Marksmanship share one list; Survival does not.** Survival adds Strength, drops the printed 9% Hit cap from the numbered line, and ranks Intellect lower.
10. **Hunter Agility conversion is inconsistent on the page:** prose says 2 ranged AP per Agility; the bullet list says 1.
11. **Feral Cat and Marksmanship are ranked per 1% / 1 point**, not only as a loose order. Other lists are plain priority orders.
12. **Tank pages (Prot Warrior, Prot Paladin, Feral Bear) are multi-profile.** There is no single 'the' list. Authors recommend Balanced for the plate tanks. Feral Bear has no Balanced profile.
13. **Hit caps are not consistent across melee lists:** Arms 8%, Fury 9%, Ret 9%, Rogues 8% then 17%, Hunters 9%, Feral Cat 8%. Authors disagree about Classic hit suppression and 16% vs 17% spell miss.
14. **Holy Priest Meditation math** in the body uses a 0.15 multiplier 'assuming 3/3 Meditation' (normally 50%). Not part of the list, but the page has this typo.

Machine-readable companion: `touchstone-wowhead-stat-priorities.json`.
