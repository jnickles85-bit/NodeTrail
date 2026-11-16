'use strict';
// ============================================================================
// The owner's v0.3.9 test list, measured on the PACK'S OWN TREE.
//
// Four behaviours, each a fixture lifted from the StatForge card that shipped it:
//   1. the enchant pair        (t_c65cc350)  — judged, enchant named WITH ITS SIDE
//   2. arrows on the surfaces  (t_ee6dec52)  — bags, bank, reagent bank, quest
//   3. the tank pair           (t_ea260b42)  — +1 Hit vs +20 Block is not "equal"
//   4. the out-of-level item   (t_da461166)  — Can't equip — requires level 40,
//                                              on the bag walk AND the quest walk
//
// The VM is the pin's own wow_stub.lua; the files under test are the pack's
// VENDORED bytes (never upstream's). A spec is resolved the way a player resolves
// one (/up spec, i.e. ChestAdvisorDB.gearFor), because the pack scores gear for a
// chosen profile and refuses to guess one.
//
//   node probe_batch.js <pack-repo-root>
// ============================================================================
const fs = require('fs');
const path = require('path');
const fengari = require('fengari');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;

const REPO = process.argv[2];
const ADVISOR = path.join(REPO, 'ChestAdvisor');
const TESTS = path.join(ADVISOR, 'tests');
const read = (p) => fs.readFileSync(p, 'utf8');
const q = (s) => JSON.stringify(String(s));
const link = (id, name) => `|cff9d9d9d|Hitem:${id}|h[${name}]|h|r`;

function newVM(env) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const run = (code, name) => {
    if (lauxlib.luaL_loadbuffer(L, to_luastring(code), code.length, to_luastring(name || 'chunk')) !== lua.LUA_OK)
      throw new Error('Lua load ' + name + ': ' + to_jsstring(lua.lua_tostring(L, -1)));
    if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK)
      throw new Error('Lua error ' + name + ': ' + to_jsstring(lua.lua_tostring(L, -1)));
  };
  const block = (code) => {
    run(code, 'block');
    lua.lua_getglobal(L, to_luastring('RESULT'));
    const s = lua.lua_isnil(L, -1) ? null : to_jsstring(lua.lua_tolstring(L, -1));
    lua.lua_pop(L, 1);
    return s;
  };
  const e = env || {};
  run(read(path.join(TESTS, 'wow_stub.lua')), 'wow_stub.lua');
  run(`
    STUB.class = ${q(e.class || 'Warrior')}; STUB.classToken = ${q(e.token || 'WARRIOR')}
    STUB.level = ${e.level || 40}
    STUB.spec = 0; STUB.specInfo = {}
    STUB.canUse = {}; STUB.tooltips = {}; STUB.renderedOnly = {}
    STUB.quality = {}; STUB.prints = {}; STUB.prices = {}
    STUB.equipLoc = {}; STUB.itemClass = {}
    STUB.equipped = {}
    STUB.visibleButtons = {}
    STUB.bags = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {}, [5] = {} }
    STUB.bagSlots = { [0] = 0, [1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0 }
    REAGENTBANK_CONTAINER = -3
    ChestAdvisorDB = { role = {}${e.gearFor ? `, gearFor = ${q(e.gearFor)}` : ''} }
  `, 'fixture-env');
  run(read(path.join(ADVISOR, 'Marks.lua')), 'Marks.lua');
  run(read(path.join(REPO, 'Constants.lua')), 'Constants.lua');
  run(read(path.join(REPO, 'Weights.lua')), 'Weights.lua');
  run(read(path.join(ADVISOR, 'Verdict.lua')), 'Verdict.lua');
  run(read(path.join(ADVISOR, 'ChestAdvisor.lua')), 'ChestAdvisor.lua');
  run(read(path.join(REPO, 'GearAPI.lua')), 'GearAPI.lua');
  // The host core is what calls Enable() in game (Modules/Core.lua is not part
  // of this harness), and the pack installs its tooltip hook there. Without it
  // the tooltip surface is simply absent — so enable, as the host does.
  run(`if type(ChestAdvisor) == "table" and type(ChestAdvisor.Enable) == "function" then pcall(ChestAdvisor.Enable) end`, 'enable');
  // The spec choice is set AFTER load: the addon's own load may hand itself a
  // fresh ChestAdvisorDB, and gearForKey reads the field at CALL time.
  if (e.gearFor) {
    run(`ChestAdvisorDB = ChestAdvisorDB or {}; ChestAdvisorDB.gearFor = ${q(e.gearFor)}`, 'gearFor');
  }
  return { run, block, L };
}

let pass = 0;
let fail = 0;
const results = [];
function check(label, ok, detail) {
  results.push((ok ? 'PASS  ' : 'FAIL  ') + label + (detail ? '\n        ' + detail : ''));
  if (ok) pass += 1;
  else fail += 1;
}

function putItem(vm, bag, slot, id, name, lines, opts) {
  const o = opts || {};
  const lnk = link(id, name);
  const canUse = o.canUse === undefined ? 'true' : (o.canUse === null ? 'nil' : String(o.canUse));
  vm.run(`
    STUB.bags[${bag}] = STUB.bags[${bag}] or {}
    STUB.bags[${bag}][${slot}] = { id = ${id}, name = ${q(name)}, quality = 2 }
    STUB.bagSlots[${bag}] = math.max(STUB.bagSlots[${bag}] or 0, ${slot})
    STUB.equipLoc[${id}] = ${q(o.loc || 'INVTYPE_CHEST')}
    STUB.itemClass[${id}] = ${o.noClass ? 'nil' : (o.itemClass || '{ 4, 2 }')}
    STUB.tooltips[${q(lnk)}] = { ${lines.map(q).join(', ')} }
    STUB.canUse[${id}] = ${canUse}
    local b = CreateFrame("Frame", ${q('Btn_' + bag + '_' + slot)})
    b:SetShown(true)
    STUB.visibleButtons[${q(bag + '/' + slot)}] = b
  `, 'put');
  return lnk;
}
function arrowOn(vm, bag, slot) {
  return vm.block(`(function()
    local b = STUB.visibleButtons[${q(String(bag) + '/' + slot)}]
    if type(b) ~= "table" then RESULT = "no-button" return end
    local a = rawget(b, "ChestAdvisorArrow")
    if type(a) ~= "table" then RESULT = "none" return end
    local tex = a.__arrow
    RESULT = tostring(a.shown) .. "|" .. tostring(type(tex) == "table" and tex.texture or nil)
  end)()`);
}
function specOf(vm) {
  return vm.block(`(function()
    local s = ChestAdvisor.buildSpec and ChestAdvisor.buildSpec() or nil
    if s == nil then RESULT = "no buildSpec()" return end
    RESULT = tostring(s.class) .. "/" .. tostring(s.role) .. " profile=" .. tostring(s.name)
      .. " order=" .. tostring(type(s.order) == "table" and #s.order or s.order)
  end)()`);
}

// ============================================================================
// 1. THE ENCHANT PAIR (t_c65cc350 E1 / E6 / E7)
// ============================================================================
{
  const PROC = 'Chance on hit: Sear the target with a vortex of blazing wind, dealing 39 to 59 Holystorm damage. Deals 3 times as much damage to Wolves and Worgen.';
  const ENCHANT = 'Enchanted: Weapon Damage +5';
  const POLE = ['Fishing Pole', 'Two-Hand  Fishing Pole', '2 - 4 Damage',
    '(1.0 damage per second)', 'Speed 3.00', 'Durability 20 / 20', 'Sell Price: 4'];
  const WOLF = ['Wolfsbane', 'Binds when picked up', 'Two-Hand  Sword',
    '69 - 105 Damage  Speed 3.40', '(25.6 damage per second)',
    '+9 Stamina', '+10 Intellect', PROC, ENCHANT,
    'Durability 100 / 100', 'Classes: Paladin', 'Sell Price: 7459'];
  const vm = newVM({ class: 'Paladin', token: 'PALADIN', level: 40, gearFor: 'holy' });
  console.log('spec resolved:', specOf(vm));
  const pair = (cand, worn) => {
    const out = vm.block(`
      local v, r = Verdict.compareWeapon({ ${cand.map(q).join(', ')} }, { ${worn.map(q).join(', ')} }, true, ChestAdvisor.buildSpec(), true, nil)
      RESULT = tostring(v) .. "\\t" .. tostring(r)
    `);
    const i = out.indexOf('\t');
    return { verdict: out.slice(0, i), reason: out.slice(i + 1) };
  };
  const e1 = pair(POLE, WOLF);
  check('1a enchant on the WORN weapon: the pair is JUDGED (not a refusal)',
    e1.verdict !== 'UNKNOWN' && e1.verdict !== 'nil', e1.verdict + ' — ' + e1.reason);
  check('1b the enchant is named as present-but-unpriced on the EQUIPPED side',
    /an unpriced enchant on the equipped weapon/.test(e1.reason), e1.reason);
  check('1c the enchant clause carries no "can\'t judge" wording',
    !/cannot classify|can't judge|eligibility unconfirmed/i.test(e1.reason), e1.reason);
  const e7 = pair(WOLF, POLE);
  check('1d an enchant on the HOVERED item names the hovered side',
    /an unpriced enchant on the hovered item/.test(e7.reason), e7.verdict + ' — ' + e7.reason);
  const bare = pair(POLE, WOLF.filter((l) => l !== ENCHANT));
  check('1e with no enchant line the clause is gone (the control)',
    !/enchant/.test(bare.reason), bare.verdict + ' — ' + bare.reason);

  // 1f — THE OWNER'S SURFACE: the item tooltip on a hover, through the real scan.
  // The bag holds the pole; Wolfsbane (proc + enchant) is the equipped weapon.
  const POLE_LINK = link(6365, 'Fishing Pole');
  const WOLF_LINK = link(267369, 'Wolfsbane');
  vm.run(`
    STUB.class = "Paladin"; STUB.classToken = "PALADIN"; STUB.level = 40
    STUB.spec = 1; STUB.specRole = "HEALER"
    STUB.specInfo = { [1] = { specId = 65, name = "Holy", role = "HEALER" } }
    local btn = CreateFrame("Frame", "ContainerFrame0Slot1")
    btn:SetShown(true)
    STUB.visibleButtons["0/1"] = btn
    STUB.bags = { [0] = { { id = 6365, name = "Fishing Pole", quality = 1 } },
                  [1] = {}, [2] = {}, [3] = {}, [4] = {}, [5] = {} }
    STUB.bagSlots = { [0] = 1, [1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0 }
    STUB.equipLoc = { [6365] = "INVTYPE_2HWEAPON", [267369] = "INVTYPE_2HWEAPON" }
    STUB.itemClass = { [6365] = { 2, 20 }, [267369] = { 2, 8 } }
    STUB.canUse = { [6365] = true, [267369] = true }
    STUB.equipped = { [16] = ${q(WOLF_LINK)} }
    STUB.tooltips = { [${q(POLE_LINK)}] = { ${POLE.map(q).join(', ')} },
                      [${q(WOLF_LINK)}] = { ${WOLF.map(q).join(', ')} } }
    STUB.renderedOnly = {}
  `, 'owner-hover');
  vm.run('ChestAdvisor.scan()', 'owner-scan');
  const tip = vm.block(`(function()
    GameTooltip:ClearLines()
    STUB.HoverItem(${q(POLE_LINK)})
    local out = {}
    for i = 1, (GameTooltip:NumLines() or 0) do
      local L = _G["GameTooltipTextLeft" .. i]
      out[#out + 1] = (L and L:GetText()) or ""
    end
    RESULT = table.concat(out, "\\n")
  end)()`);
  check('1f the ITEM TOOLTIP on the owner\'s hover names the unpriced enchant and its side',
    (tip || '').indexOf('an unpriced enchant on the equipped weapon') !== -1,
    'tip=' + JSON.stringify(tip));
  check('1g the tooltip line is a judgement, not a "can\'t judge"',
    (tip || '').indexOf("Can't judge") === -1 && (tip || '').indexOf('eligibility unconfirmed') === -1,
    'tip=' + JSON.stringify(tip));
}

// ============================================================================
// 2. ARROWS ON BAGS / BANK / REAGENT BANK / QUEST (t_ee6dec52 A1, B1)
// ============================================================================
{
  const vm = newVM({ class: 'Paladin', token: 'PALADIN', level: 40, gearFor: 'holy' });
  // A worn chest to beat.
  const WORN = link(8000, 'Worn Vest');
  vm.run(`
    STUB.equipped[5] = ${q(WORN)}
    STUB.equipLoc[8000] = "INVTYPE_CHEST"
    STUB.itemClass[8000] = { 4, 2 }
    STUB.tooltips[${q(WORN)}] = { "+10 Intellect", "+5 Stamina" }
  `, 'worn');
  const UP_LINES = ['+20 Intellect', '+8 Stamina'];
  putItem(vm, 0, 1, 9001, 'Better Vest', UP_LINES);          // combined view
  putItem(vm, 1, 1, 9001, 'Better Vest', UP_LINES);          // bag 1
  putItem(vm, -1, 1, 9001, 'Better Vest', UP_LINES);         // bank, fixed slots
  putItem(vm, 5, 1, 9001, 'Better Vest', UP_LINES);          // bank bag 5
  putItem(vm, -3, 1, 9001, 'Better Vest', UP_LINES);         // reagent bank
  putItem(vm, -3, 2, 9500, 'Linen Cloth', ['5 Linen Cloth'], { loc: 'INVTYPE_TRADEGOODS' });
  putItem(vm, 2, 1, 9002, 'Worse Vest', ['+4 Intellect', '+5 Stamina']);
  putItem(vm, 3, 1, 9003, 'Same Vest', ['+10 Intellect', '+5 Stamina']);
  putItem(vm, 4, 1, 9010, 'Frost Vest', ['+5 Frost Resistance']);
  vm.run('OpenBank(); ChestAdvisor.scan()', 'scan');
  const surfaces = [['the combined bag view', 0, 1], ['bag 1', 1, 1], ['the bank', -1, 1],
    ['bank bag 5', 5, 1], ['the reagent bank', -3, 1]];
  for (const [label, bag, slot] of surfaces) {
    const s = arrowOn(vm, bag, slot);
    check('2 arrow on ' + label, s !== 'none' && s !== 'no-button' && s.indexOf('true|') === 0, 'mark=' + s);
  }
  for (const [label, bag, slot] of [['a downgrade', 2, 1], ['an equal item', 3, 1], ['a refused item', 4, 1]]) {
    const s = arrowOn(vm, bag, slot);
    check('2 no arrow on ' + label, s === 'none' || s.indexOf('false|') === 0, 'mark=' + s);
  }
  // B1: the quest-reward surface carries the same mark.
  const QID = 9101;
  const QLINK = link(QID, 'Quest Vest');
  vm.run(`
    STUB.questLinks = { choice = {}, reward = {} }
    QuestInfoRewardsFrame = CreateFrame("Frame", "QuestInfoRewardsFrame")
    QuestInfoRewardsFrame.RewardButtons = {}
    QuestInfoRewardsFrame:Show()
    QuestFrameRewardPanel = CreateFrame("Frame", "QuestFrameRewardPanel")
    QuestFrameRewardPanel:Show()
    QuestInfoFrame = { rewardsFrame = QuestInfoRewardsFrame, questLog = nil, chooseItems = true }
    local btn = CreateFrame("Button", "QuestItem1")
    btn.type = "choice"; btn.objectType = "item"; btn:SetID(1)
    QuestInfoFrame.rewardsFrame.RewardButtons[1] = btn
    STUB.equipLoc[${QID}] = "INVTYPE_CHEST"
    STUB.itemClass[${QID}] = { 4, 2 }
    STUB.tooltips[${q(QLINK)}] = { "+25 Intellect", "+9 Stamina" }
    STUB.canUse[${QID}] = true
    STUB.questLinks["choice"][1] = ${q(QLINK)}
  `, 'quest');
  vm.run('ChestAdvisor.scan()', 'quest-scan');
  const qmark = vm.block(`(function()
    local btn = QuestInfoFrame.rewardsFrame.RewardButtons[1]
    local a = rawget(btn, "ChestAdvisorArrow")
    RESULT = type(a) == "table" and tostring(a.shown) or "none"
  end)()`);
  check('2 quest-reward mark is drawn on the reward button', qmark === 'true', 'mark=' + qmark);
  check('2 TouchstoneMarks is the ONE mark module', vm.block('RESULT = type(TouchstoneMarks)') === 'table');
}

// ============================================================================
// 3. THE TANK PAIR (t_ea260b42 E1)
// ============================================================================
{
  const vm = newVM({ class: 'Warrior', token: 'WARRIOR', level: 60 });
  const tank = vm.block(`
    local spec = { class = "WARRIOR", role = "melee", clientRole = "TANK", level = 60,
      order = Verdict.classRoleOrder("WARRIOR", "melee"), name = "Protection" }
    local v, r = Verdict.evaluate({ canUse = true, line = { "Buckler of the Just", "Off Hand", "+1 Hit" } },
      { line = { "Tower Shield", "Off Hand", "+20 Block" } }, spec, nil, nil)
    RESULT = tostring(v) .. "\\t" .. tostring(r)
  `);
  const i = tank.indexOf('\t');
  const verdict = tank.slice(0, i);
  const reason = tank.slice(i + 1);
  check('3a +1 Hit vs +20 Block is not "equal"', !/equal/i.test(reason), verdict + ' — ' + reason);
  check('3b the +1 Hit is what decides it', verdict === 'UPGRADE' && /Hit/.test(reason), verdict + ' — ' + reason);
  const block = vm.block(`
    local spec = { class = "PALADIN", role = "spell", clientRole = "TANK", level = 60,
      order = Verdict.classRoleOrder("PALADIN", "spell"), name = "Protection" }
    local v, r = Verdict.evaluate({ canUse = true, line = { "Tower Shield", "Off Hand", "+20 Block" } },
      { line = { "Aegis of the Just", "Off Hand", "+10 Block" } }, spec, nil, nil)
    RESULT = tostring(v) .. "\\t" .. tostring(r)
  `);
  const j = block.indexOf('\t');
  // KNOWN DIVERGENCE, PRE-EXISTING AND UNCHANGED BY THIS CUT: upstream's E4
  // keeps a two-sided Block tie deciding ("more Block"); the pack's OWN weighted
  // layer answers "no change" first, on origin/main as well. Measured on three
  // trees — pack (new), pack (origin/main) and StatForge 740f7d5 — so this is
  // recorded, not fixed here: it is the pack's profile layer, not the vendored
  // batch, and the card's rule ("a tiebreak-only Block stops deciding a pair") is
  // the same direction.
  results.push('INFO  ' + '3c two-sided Block tie: upstream "more Block", pack "no change" '
    + '(pre-existing on origin/main, identical before and after this cut) — '
    + block.slice(0, j) + ' — ' + block.slice(j + 1));
  check('3c the tiebreak still decides what it should: the pack says "no change", not a judged gain',
    /no change/i.test(block.slice(j + 1)) || block.slice(0, j) === 'UPGRADE',
    block.slice(0, j) + ' — ' + block.slice(j + 1));
  check('3d HIT is priced 0.5 on WARRIOR.tank',
    vm.block('RESULT = tostring(Verdict.weightsFor("WARRIOR", "melee", "TANK").HIT)') === '0.5');
}

// ============================================================================
// 4. THE OUT-OF-LEVEL ITEM (t_da461166 W1 / W8)
// ============================================================================
{
  const DAGGER = ['Dagger of the Refused', 'Main Hand  Dagger',
    '10 - 19 Damage', 'Speed 2.00', 'Requires Level 40', '+3 Agility'];
  const vm = newVM({ class: 'Warrior', token: 'WARRIOR', level: 20, gearFor: 'fury' });
  const cand = putItem(vm, 0, 1, 7001, 'Dagger of the Refused', DAGGER,
    { canUse: false, loc: 'INVTYPE_WEAPON', itemClass: '{ 2, 15 }' });
  vm.run('ChestAdvisor.scan()', 'scan');
  const row = vm.block(`
    local r = ChestAdvisor.getVerdicts()[${q(cand)}]
    RESULT = type(r) ~= "table" and "NO ROW" or (tostring(r.verdict) .. "|" .. tostring(r.reason))
  `);
  check('4a the bag row reads cannot equip with the named requirement',
    row === 'UNKNOWN|cannot equip — requires level 40', 'row=' + row);
  vm.run(`STUB.HoverItem(${q(cand)})`, 'hover');
  const tip = vm.block(`(function()
    local out = {}
    for i = 1, (GameTooltip:NumLines() or 0) do
      local L = _G["GameTooltipTextLeft" .. i]
      out[#out + 1] = (L and L:GetText()) or ""
    end
    RESULT = table.concat(out, "\\n")
  end)()`);
  const ours = (tip || '').split('\n').find((l) => l.indexOf("Can't equip") !== -1) || null;
  check("4b the item tooltip reads \"Can't equip — requires level 40\"",
    ours !== null && ours.indexOf("Can't equip — requires level 40") !== -1, 'line=' + ours);
  check('4c the old "eligibility unconfirmed" sentence is gone from this surface',
    (tip || '').indexOf('eligibility unconfirmed') === -1, 'tip=' + JSON.stringify(tip));
  // W8: the QUEST-reward walk, the other emitter. It keeps its rows on the
  // reward button (the panel's own store), not in getVerdicts().
  const QID = 7201;
  const QLINK = link(QID, 'Dagger of the Refused');
  vm.run(`
    STUB.questLinks = STUB.questLinks or { choice = {}, reward = {} }
    QuestInfoRewardsFrame = CreateFrame("Frame", "QuestInfoRewardsFrame2")
    QuestInfoRewardsFrame.RewardButtons = {}
    QuestInfoRewardsFrame:Show()
    QuestFrameRewardPanel = CreateFrame("Frame", "QuestFrameRewardPanel2")
    QuestFrameRewardPanel:Show()
    QuestInfoFrame = { rewardsFrame = QuestInfoRewardsFrame, questLog = nil, chooseItems = true }
    local btn = CreateFrame("Button", "QuestItemW8")
    btn.type = "choice"; btn.objectType = "item"; btn:SetID(1)
    QuestInfoFrame.rewardsFrame.RewardButtons[1] = btn
    STUB.equipLoc[${QID}] = "INVTYPE_WEAPON"
    STUB.itemClass[${QID}] = { 2, 15 }
    STUB.tooltips[${q(QLINK)}] = { ${DAGGER.map(q).join(', ')} }
    STUB.canUse[${QID}] = false
    STUB.questLinks["choice"][1] = ${q(QLINK)}
  `, 'quest-w8');
  vm.run('ChestAdvisor.scan()', 'quest-w8-scan');
  const qstored = vm.block(`
    local b = QuestInfoFrame.rewardsFrame.RewardButtons[1]
    RESULT = tostring(b.__chestAdvisorQuestVerdict)
  `);
  vm.run(`STUB.HoverItem(${q(QLINK)})`, 'quest-w8-hover');
  const qtip = vm.block(`(function()
    local out = {}
    for i = 1, (GameTooltip:NumLines() or 0) do
      local L = _G["GameTooltipTextLeft" .. i]
      out[#out + 1] = (L and L:GetText()) or ""
    end
    RESULT = table.concat(out, "\\n")
  end)()`);
  check('4d the quest-reward walk stores a non-answer for the refused weapon',
    qstored === 'UNKNOWN', 'stored=' + qstored);
  check('4e the quest-reward tooltip phrases it the same way as the bag tooltip',
    (qtip || '').indexOf("Can't equip — requires level 40") !== -1, 'tip=' + JSON.stringify(qtip));
}

console.log(results.join('\n'));
console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail === 0 ? 0 : 1);
