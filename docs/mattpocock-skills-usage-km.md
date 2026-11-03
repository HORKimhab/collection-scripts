# ការប្រើប្រាស់ Matt Pocock Skills (ភាសាខ្មែរ)

> ប្រភព: [github.com/mattpocock/skills](https://github.com/mattpocock/skills) (README + `docs/engineering/*`, `docs/productivity/*`)
> ឯកសារនេះជាការសង្ខេប និងបកប្រែជាភាសាខ្មែរ សម្រាប់ប្រើប្រាស់ផ្ទាល់ខ្លួន។ បើវាខុសពី `SKILL.md` ដើម សូមយក `SKILL.md` ជាការត្រឹមត្រូវ។
> ពាក្យបច្ចេកទេស (spec, ticket, ADR, seam, glossary …) ត្រូវបានរក្សាជាភាសាអង់គ្លេស ដើម្បីងាយស្វែងរក និងប្រើជាមួយ agent។

---

## ១. តើវាជាអ្វី?

**Skills For Real Engineers** គឺជាសំណុំ "skill" (ឯកសារណែនាំ `SKILL.md`) សម្រាប់ coding agent ដូចជា Claude Code, Codex, Copilot, Gemini CLI, Cursor ជាដើម។ គោលបំណងគឺធ្វើ **វិស្វកម្មពិតប្រាកដ មិនមែន vibe coding**។

ខុសពី framework ធំៗ (GSD, BMAD, Spec-Kit) ដែលគ្រប់គ្រងដំណើរការទាំងមូល skill ទាំងនេះ **តូច ងាយកែប្រែ និងអាចផ្គុំបញ្ចូលគ្នាបាន** — អ្នកនៅតែជាអ្នកគ្រប់គ្រង។

---

## ២. ការដំឡើង (៣០ វិនាទី)

> ⚠️ ជ្រើសរើស **តែវិធីមួយ** ក្នុងមួយ agent។ បើដំឡើងទាំង plugin ទាំង skills.sh អ្នកនឹងមាន skill ស្ទួនពីរដង។
> - **Plugin** — update ដោយខ្លួនឯង
> - **skills.sh (`npx skills`)** — copy ឯកសារចូល project អាចកែបាន ប៉ុន្តែត្រូវ update ដោយដៃ

### ជំហានទី ១៖ ទាញយក skills

**Claude Code**

```bash
claude plugin install mattpocock-skills@claude-plugins-official
```

**Codex**

```bash
codex plugin marketplace add mattpocock/skills
codex plugin add mattpocock-skills@mattpocock
```

**GitHub Copilot (CLI និង VS Code)**

```bash
copilot plugin marketplace add mattpocock/skills
copilot plugin install mattpocock-skills@mattpocock
```

បន្ទាប់មកបន្ថែមក្នុង `~/.copilot/settings.json` (ម្តងប៉ុណ្ណោះ)៖

```json
{
  "extraKnownMarketplaces": {
    "mattpocock": { "source": { "source": "github", "repo": "mattpocock/skills" }, "autoUpdate": true }
  }
}
```

ក្នុង VS Code៖ រត់ **Chat: Install Plugin From Source** ហើយបញ្ចូល `https://github.com/mattpocock/skills`។

**Gemini CLI** (update ដោយដៃ — រត់ម្តងទៀតដើម្បី update)

```bash
gemini skills install https://github.com/mattpocock/skills.git --path skills/engineering
gemini skills install https://github.com/mattpocock/skills.git --path skills/productivity
```

**Agent ផ្សេងទៀត ឬចង់បានឯកសារកែបាន**

```bash
npx skills@latest add mattpocock/skills -a <agent>  # cursor, opencode, devin, windsurf, amp, pi
npx skills@latest update                            # update
```

ពេលវាសួរថាយក skill មួយណា — **ត្រូវជ្រើស `setup-matt-pocock-skills` ជានិច្ច**។

### ជំហានទី ២៖ រត់ `/setup-matt-pocock-skills` (ម្តងក្នុងមួយ repo)

វានឹងសួរអ្នក ៣ ចំណុច៖

1. ប្រើ **issue tracker** មួយណា? (GitHub, GitLab, ឯកសារ local ឬផ្សេងទៀត)
2. ប្រើ **label** អ្វីខ្លះពេល triage ticket? (`/triage` ប្រើ label ទាំងនេះ)
3. ចង់រក្សាទុក **docs** ដែលបង្កើតនៅកន្លែងណា?

> 💡 បើ `/triage`, `/to-spec`, `/to-tickets` ឬ `/wayfinder` ចាប់ផ្តើម "ទាយ" ថា issue ទៅណា ឬដាក់ label ដែល tracker របស់អ្នកគ្មាន — មានន័យថា repo នេះមិនទាន់ setup ទេ។ អាចរត់ពាក់កណ្តាល project ក៏បាន។

### ជំហានទី ៣៖ រួចរាល់! 🎉

---

## ៣. ហេតុអ្វីបានជាមាន skills ទាំងនេះ? (បញ្ហា ៤ យ៉ាង)

| # | បញ្ហា | មូលហេតុ | ដំណោះស្រាយ |
| --- | --- | --- | --- |
| 1 | **Agent មិនធ្វើអ្វីដែលខ្ញុំចង់បាន** | គម្លាតទំនាក់ទំនង (misalignment) រវាងអ្នក និង agent | `/grill-me` (មិនមែនកូដ), `/grill-with-docs` (មានកូដ) — ឲ្យ agent សួរអ្នកលម្អិតមុនចាប់ផ្តើម |
| 2 | **Agent និយាយវែងពេក** | Agent មិនស្គាល់ពាក្យបច្ចេកទេសរបស់ project ក៏ប្រើ ២០ ពាក្យជំនួស ១ ពាក្យ | បង្កើត **ភាសារួម (shared language)** ក្នុង `GLOSSARY.md` តាម `/grill-with-docs` |
| 3 | **កូដមិនដំណើរការ** | Agent គ្មាន feedback loop — ធ្វើការដូចមនុស្សបិទភ្នែក | `/tdd` (red-green-refactor), `/diagnosing-bugs` |
| 4 | **Codebase ក្លាយជា "ដុំភក់" (ball of mud)** | Agent សរសេរកូដលឿន ក៏បង្កើនភាពស្មុគស្មាញលឿនដែរ | `/to-spec`, `/improve-codebase-architecture` (រត់រៀងរាល់ពីរបីថ្ងៃ) |

**ឧទាហរណ៍ភាសារួម៖**

- **មុន៖** "មានបញ្ហាពេលមេរៀនមួយនៅក្នុង section នៃវគ្គសិក្សា ត្រូវបានធ្វើឲ្យ 'ពិត' (ពោលគឺផ្តល់កន្លែងក្នុង file system)"
- **ក្រោយ៖** "មានបញ្ហាជាមួយ materialization cascade"

ផលប្រយោជន៍៖ ឈ្មោះ variable/function/file ស្របគ្នា, agent រុករក codebase ងាយ, និងចំណាយ token តិចជាងលើការគិត។

---

## ៤. ប្រភេទ Skill ពីរ

| ប្រភេទ | អ្នកណាហៅបាន | តួនាទី |
| --- | --- | --- |
| **User-invoked** | តែអ្នកប៉ុណ្ណោះ (វាយ `/ឈ្មោះ`) | សម្របសម្រួល (orchestrate) ដំណើរការ |
| **Model-invoked** | អ្នក **ឬ** agent ហៅដោយស្វ័យប្រវត្តិពេលកិច្ចការសម | ផ្ទុកវិន័យ/ចំណេះដឹងដែលប្រើឡើងវិញបាន |

ច្បាប់៖ user-invoked skill អាចហៅ model-invoked skill បាន ប៉ុន្តែ **មិនដែលហៅ user-invoked skill មួយទៀតទេ**។ ដូច្នេះពេល doc និយាយថា "បន្ទាប់មក `/implement`" — នោះគឺជាការណែនាំឲ្យ **អ្នក** វាយ មិនមែន agent ធ្វើឯងទេ។

---

## ៥. លំហូរការងារសំខាន់ (Main build chain)

```txt
grill-with-docs → to-spec → to-tickets → implement → code-review → pr → retro
                                       ↘ implement-spec (ធ្វើស្របគ្នា) ↗
```

| ស្ថានភាព | ចាប់ផ្តើមពី |
| --- | --- |
| មានគំនិតថ្មី ការងារតូច (១ session) | `/grill-with-docs` → `/implement` |
| ការងារធំ ត្រូវការច្រើន session | `/grill-with-docs` → `/to-spec` → `/to-tickets` → `/implement` ម្តងមួយ ticket (ឬ `/implement-spec`) |
| ការងារធំខ្លាំង ផ្លូវមិនច្បាស់ | `/wayfinder` → `/to-spec` → … |
| ការងារមកពីអ្នកដទៃ (issue, bug report, PR) | `/triage` → `/implement` |
| មានអ្វីខូច | `/diagnosing-bugs` → `/retro` |
| មិនដឹងថាត្រូវប្រើមួយណា | `/ask-matt` |

---

## ៦. Engineering Skills

### 6.1 User-invoked (វាយដោយខ្លួនឯង)

#### `/ask-matt` — អ្នកណែនាំផ្លូវ

- **ធ្វើអ្វី៖** សួរថា skill ឬ flow មួយណាសមនឹងស្ថានភាពរបស់អ្នក។ ជា router លើ user-invoked skills ទាំងអស់។
- **ពេលណា៖** ពេលអ្នកមិនប្រាកដថាត្រូវចាប់ផ្តើមពីណា ឬនៅចន្លោះដំណាក់កាល (continue / clear / handoff / delegate / compact?)។
- **ឧទាហរណ៍៖** `/ask-matt ខ្ញុំមាន bug report ពីអតិថិជន គួរធ្វើអ្វីមុន?`

#### `/grill-with-docs` — សួរដេញដោល + កត់ត្រាឯកសារ ⭐

- **ធ្វើអ្វី៖** សួរអ្នកអំពីផែនការរហូតដល់អ្នក និង agent យល់ដូចគ្នា ហើយសរសេរពាក្យបច្ចេកទេសចូល `GLOSSARY.md` និងការសម្រេចចិត្តពិបាកៗជា ADR (`docs/adr/`) **ភ្លាមៗ** ពេលដោះស្រាយបាន។
- **ពេលណា៖** ដើមនៃការផ្លាស់ប្តូរ ក្នុង repo ពេលផែនការនៅស្រពិចស្រពិល។ សមសម្រាប់ការងារ ១ session។ ក៏អាចប្រើលើ repo ដែលគ្មាន docs សោះ៖ "help me document my repo"។
- **ADR ត្រូវមានលក្ខខណ្ឌ ៣ ព្រមគ្នា៖** ពិបាកត្រឡប់វិញ, គួរឲ្យភ្ញាក់ផ្អើលបើគ្មានបរិបទ, និងជា trade-off ពិតប្រាកដ។ ដូច្នេះ session ភាគច្រើនមិនបង្កើត ADR ទេ — នោះជារឿងធម្មតា។
- **ប្រយ័ត្ន៖**
  - ការសម្រេចចិត្តផ្សេងទៀតនៅតែក្នុង conversation ប៉ុណ្ណោះ → **កុំ clear** ត្រូវបន្តទៅ `/to-spec` ក្នុង session ដដែល។
  - ត្រូវការ skill `grilling` និង `domain-modeling` ផងដែរ។ បើវាសួរគ្រប់សំណួរក្នុងពេលតែមួយ ឬមិនប៉ះ `GLOSSARY.md` → skill មិនបាន load ពេញលេញ។ សួរ agent ផ្ទាល់ថា "តើអ្នកបាន load skill អ្វីខ្លះ?"

#### `/triage` — គ្រប់គ្រង issue

- **ធ្វើអ្វី៖** ផ្លាស់ទី issue តាម state machine នៃ triage role (ដោយប្រើ label)។ PR ក៏ត្រូវបានចាត់ទុកជា issue ដែលមានកូដភ្ជាប់។
- **ពេលណា៖** ការងារដែល **មកពីអ្នកដទៃ** (bug report, feature request, PR)។ ចុងបញ្ចប់គឺ issue មាន label `ready-for-agent` និង brief។
- **ឧទាហរណ៍៖** `/triage Show me anything that needs my attention`, `/triage let's look at #42`, `/triage move #42 to ready-for-agent`

#### `/improve-codebase-architecture` — ស្ទង់មើល architecture

- **ធ្វើអ្វី៖** ស្កេន codebase រក "deepening opportunities" បង្ហាញជារបាយការណ៍ HTML ហើយ grill អ្នកលើជម្រើសដែលអ្នករើស។
- **ពេលណា៖** រត់ **រៀងរាល់ពីរបីថ្ងៃ** ក្រៅ chain ដើម្បីតម្រៀបការងារ (មិនមែនធ្វើការងារនោះទេ)។ វាជាការស្ទង់មើល មិនមែនការជួយសង្គ្រោះ codebase ចាស់ទេ។

#### `/setup-matt-pocock-skills` — កំណត់រចនាសម្ព័ន្ធ

- **ធ្វើអ្វី៖** កំណត់ issue tracker, triage labels និងទីតាំង domain docs។
- **ពេលណា៖** ម្តងក្នុងមួយ repo មុនប្រើ engineering skill ផ្សេងទៀត។

#### `/to-spec` — បំលែង conversation ទៅជា spec

- **ធ្វើអ្វី៖** សំយោគអ្វីដែលបានពិភាក្សារួចហើយ ជា spec ហើយ publish ទៅ issue tracker។ **គ្មានការសម្ភាសន៍ថ្មីទេ**។ វាសួរអំពី module/seam ណាដែលប៉ះ មុនសរសេរ។
- **ពេលណា៖** ពេលការងារធំពេកសម្រាប់ agent session តែមួយ ហើយត្រូវបំបែកជាច្រើន session។
- **គន្លឹះ៖** អានឡើងវិញ spec ធៀបនឹងចម្លើយរបស់អ្នក — ចម្លើយច្បាស់លាស់ (លំដាប់, តម្លៃលេខ, លក្ខខណ្ឌអវិជ្ជមាន) ពេលខ្លះក្លាយជាអត្ថបទទន់ខ្សោយ។

#### `/to-tickets` — បំបែកជា ticket

- **ធ្វើអ្វី៖** បំបែក plan/spec/conversation ជា ticket បែប **tracer-bullet** (ចំណិតបញ្ឈរ end-to-end មិនមែនតាម layer) ដោយនីមួយៗប្រកាស blocking edges របស់វា។ សរសេរជាឯកសារ local ឬជា blocking link លើ tracker ពិត។
- **ពេលណា៖** បន្ទាប់ពី `/to-spec` ឬពេលមានផែនការរួចហើយ។

#### `/implement` — សាងសង់

- **ធ្វើអ្វី៖** សាងសង់ការងារពី spec ឬ ticket ដោយប្រើ `/tdd` នៅ seam ដែលបានព្រមព្រៀងទុកមុន ហើយបិទដោយ `/code-review` មុន commit។
- **ពេលណា៖** ម្តងមួយ ticket។ Agent **មិនហៅវាដោយខ្លួនឯងទេ** (`disable-model-invocation: true`)។

#### `/implement-spec` — សាងសង់ spec ទាំងមូលស្របគ្នា

- **ធ្វើអ្វី៖** អនុវត្ត spec ទាំងមូលលើ integration branch មួយ។ ធ្វើការលើ ticket ជា task graph ដោយរត់ implementer subagent ច្រើនក្នុងពេលតែមួយ ហើយបិទដោយ `/code-review` ម្តង។
- **ពេលណា៖** ជំនួសការរត់ `/implement` ម្តងមួយ ticket ពេលចង់បានល្បឿន។

#### `/wayfinder` — ផែនទីសម្រាប់ការងារធំ

- **ធ្វើអ្វី៖** រៀបចំផែនការការងារធំ (លើសពី session មួយ) ជាផែនទីនៃ **decision ticket** លើ issue tracker ហើយដោះស្រាយម្តងមួយៗរហូតដល់ផ្លូវច្បាស់។ Decision ticket មាន ៤ ប្រភេទ (រួមមាន grilling, prototype, research …)។
- **ពេលណា៖** តែពេលការងារ **ធំជាង session មួយ ហើយផ្លូវមិនច្បាស់** ប៉ុណ្ណោះ។
- **កំហុសទូទៅ៖** ប្រើ wayfinder លើ feature ដែលមាន scope ច្បាស់រួចហើយ → ប្រើ `/grill-with-docs` វិញ។

#### `/retro` — ពិនិត្យឡើងវិញក្រោយ session

- **ធ្វើអ្វី៖** ស្នើការកែលម្អបរិស្ថានរបស់ agent (navigation, automated checks, coding standards, steering files, tooling) តម្រៀបពីធ្ងន់ធ្ងរបំផុតមុន។
- **ពេលណា៖** ចុង session ដែល **ពិបាកជាងគួរ** (agent ស្វែងរកយូរ, ធ្វើកំហុសដែល tool អាចចាប់បាន …)។ Session រលូនមានអ្វីតិចតួចសម្រាប់រៀន។

### 6.2 Model-invoked (Agent អាចហៅដោយខ្លួនឯង)

| Skill | ធ្វើអ្វី | ពេលណា / ពាក្យគន្លឹះ |
| --- | --- | --- |
| `/prototype` | បង្កើត prototype បោះចោលបាន៖ HTML មួយឯកសារសម្រាប់សំណួរ state/logic ឬ UI ច្រើនបែបប្តូរបានពី route មួយ | ពេលសំណួរមិនអាចដោះស្រាយដោយការនិយាយ (state machine ស្មុគស្មាញ, UI ដែលមិនអាចស្រមៃបាន) — ឈប់ grill ហើយបង្កើតវាមើល |
| `/diagnosing-bugs` | Loop វិនិច្ឆ័យ bug៖ បង្កើត feedback loop ដែល **ក្រហម** លើ bug → បង្រួម → សន្មត → ដាក់ instrument → ជួសជុល → regression test | "diagnose", "debug this", bug ពិបាក, flaky, regression។ យឺត និងហ្មត់ចត់ដោយចេតនា |
| `/research` | ស្រាវជ្រាវពីប្រភពដើមដែលគួរទុកចិត្ត ហើយរក្សាលទ្ធផលជា Markdown មាន citation ក្នុង repo (រត់ជា background agent) | ពេលត្រូវរកការពិតពីខាងក្រៅ (API ភាគីទីបី, spec, version) ដោយមិនចង់រាំងស្ទះ thread ខ្លួនឯង |
| `/tdd` | Test-driven development ជាមួយ red-green-refactor ម្តងមួយ vertical slice | មាន behaviour ច្បាស់ (input → output ដែលសង្កេតបាន) ហើយចង់បាន test ដែលរស់រានពេល refactor |
| `/domain-modeling` | កសាង domain model៖ ប្រៀបធៀបពាក្យជាមួយ glossary, សាកល្បងជាមួយ edge case, update `GLOSSARY.md` និង ADR | ពេល **ពាក្យ** ជាបញ្ហា។ ⚠️ ការហៅស្វ័យប្រវត្តិខ្សោយ — ហៅវាតាមឈ្មោះជាមួយ `/grill-with-docs` |
| `/codebase-design` | វាក្យសព្ទ និងវិន័យសម្រាប់រចនា **deep module**៖ behaviour ច្រើននៅពីក្រោយ interface តូច នៅ seam ស្អាត test បានតាម interface | ពេលដឹងកូដណាត្រូវរចនាឡើងវិញ ហើយត្រូវគិតអំពី seam, ទំហំ interface |
| `/code-review` | Review diff តាំងពីចំណុចថេរមួយ លើ ២ អ័ក្ស៖ **Standards** (តាម coding standard + Fowler smell) និង **Spec** (ត្រូវតាម issue/spec ឬទេ) រត់ជា subagent ស្របគ្នា | "review this branch/PR", "review since X" |
| `/pr` | ទម្រង់ PR body៖ សង្ខេបជារូបភាពតូចបំផុត, ភស្តុតាង before/after, និងការវាយតម្លៃគ្រោះថ្នាក់ merge (one-way/two-way door + blast radius) | ពេលសរសេរ PR body |
| `/wizard` | បង្កើត bash wizard អន្តរកម្ម ដើម្បីដឹកនាំមនុស្សតាមជំហានដែលតែមនុស្សធ្វើបាន | បង្កើត infra, credential/CI secret, dashboard ភាគីទីបី, migration ម្តង |
| `/resolving-merge-conflicts` | ដោះស្រាយ merge conflict ដោយផ្អែកលើប្រភពដើម (មិនមែនរើស `ours`/`theirs` ងងឹតងងុល) | ពេល git ឈប់ដោយ conflict ដែលវាដោះស្រាយមិនបាន |

---

## ៧. Productivity Skills (មិនមែនសម្រាប់តែកូដ)

### 7.1 User-invoked

| Skill | ធ្វើអ្វី | ពេលណា |
| --- | --- | --- |
| `/grill-me` ⭐ | ត្រូវបានសម្ភាសន៍ដេញដោលអំពីផែនការ/ការរចនា រហូតគ្រប់មែកនៃ design tree ត្រូវបានដោះស្រាយ។ Stateless — គ្មាន repo ក៏ប្រើបាន | ពេលមានគំនិតគួរយកចិត្តទុកដាក់ (feature, ទិសដៅផលិតផល, ការសម្រេចចិត្តអាជីវកម្ម, ការសរសេរ)។ ចាប់ផ្តើមក្នុង **conversation ថ្មី** |
| `/handoff` | បង្រួម conversation ជាឯកសារ handoff ដើម្បីឲ្យ agent ផ្សេងបន្ត | ផ្ញើចំណាំអំពីគោលបំណង session បន្ទាប់។ ល្អសម្រាប់ "branch" ចេញទៅ prototype/teach ហើយត្រឡប់មកវិញ |
| `/teach` | បង្រៀនជំនាញ/គំនិតថ្មីច្រើន session ដោយប្រើ directory បច្ចុប្បន្នជា workspace មាន state | ពេលការរៀនគឺជា project (ភាសា, framework, codebase ថ្មី, certification) |
| `/to-questionnaire` | បំលែងការសម្រេចចិត្តដែលអ្នកមិនអាចឆ្លើយតែម្នាក់ឯង ជាកម្រងសំណួរ Markdown សម្រាប់អ្នកដែលដឹង | ពេលចម្លើយនៅក្នុងក្បាលអ្នកដទៃ (អតិថិជន, អ្នកជំនាញ, exec) |
| `/wait-what` | Agent ពន្យល់សារចុងក្រោយឡើងវិញ ជាភាសាសាមញ្ញ ដោយបន្ថែមបរិបទដែលអ្នកខ្វះ និងប្រើពាក្យពី `GLOSSARY.md` | ភ្លាមៗពេលអ្នកមិនយល់ (jargon, acronym ច្រើន, premise ដែលអ្នកមិនដែលឃើញ) |

**ជ្រើសរើស grilling skill មួយណា?**

| អ្វីដែលអ្នកមាន | ប្រើ |
| --- | --- |
| មិននៅក្នុង repo/working directory | `/grill-me` |
| មាន repo និងការផ្លាស់ប្តូរដែលបញ្ចប់បានក្នុង ១ session | `/grill-with-docs` |
| ការងារធំពេកសម្រាប់ ១ session | `/wayfinder` |
| ការសម្រេចចិត្តជាប់គាំងលើចំណេះដឹងរបស់អ្នកដទៃ | `/to-questionnaire` |

### 7.2 Model-invoked

| Skill | ធ្វើអ្វី |
| --- | --- |
| `/grilling` | បច្ចេកទេសសម្ភាសន៍គោល (primitive) ដែល `grill-me`, `grill-with-docs`, `triage`, `wayfinder` និង `improve-codebase-architecture` ប្រើនៅពីក្រោយ។ សួរម្តងមួយជុំ ហើយរង់ចាំ មុនជុំបន្ទាប់ |
| `/writing-for-agents` | របៀបសរសេរឯកសារសម្រាប់ agent៖ skill, `AGENTS.md`/`CLAUDE.md`, spec, ticket, prompt។ សំណួរសាកល្បង៖ "តើ agent អានឯកសារនេះទេ?" |

---

## ៨. ឧទាហរណ៍ការប្រើប្រាស់ពិត

### ក. Feature តូច (១ session)

```txt
/grill-with-docs ខ្ញុំចង់បន្ថែម --dry-run ទៅ mac-clean.sh
   … ឆ្លើយសំណួរម្តងមួយជុំ …
/implement
/code-review
/retro          (បើ session ពិបាក)
```

### ខ. Feature ធំ (ច្រើន session)

```txt
/grill-with-docs <គំនិត>
/to-spec                  ← ក្នុង session ដដែល កុំ clear!
/to-tickets
/clear
/implement #12            ← ម្តងមួយ ticket ក្នុង session ថ្មីនីមួយៗ
… ឬ /implement-spec ដើម្បីធ្វើស្របគ្នា
```

### គ. Bug

```txt
/diagnosing-bugs sync-telegram.sh ឈប់ដំណើរការពេល file > 2GB
/retro                    ← សួរថាអ្វីអាចការពារ bug នេះបាន
```

### ឃ. ធ្វើការជាមួយ issue របស់អ្នកដទៃ

```txt
/triage Show me anything that needs my attention
/triage move #42 to ready-for-agent
/implement #42
```

---

## ៩. 💡 ការណែនាំបន្ថែម (Suggestions)

ខាងក្រោមនេះជាយោបល់របស់ខ្ញុំ (មិនមែនមកពី repo ដើម) ដោយផ្អែកលើ repo `collection-scripts` នេះ និងការប្រើប្រាស់ជាក់ស្តែង៖

1. **ចាប់ផ្តើមតូចៗ — ៣ skill ដំបូង។** កុំព្យាយាមប្រើទាំង ៣០ ក្នុងពេលតែមួយ។ ចាប់ផ្តើមជាមួយ `/grill-me` (ឬ `/grill-with-docs`), `/diagnosing-bugs`, និង `/code-review`។ ពេលស៊ាំហើយ ទើបបន្ថែម `/to-spec` → `/to-tickets` → `/implement`។

2. **ប្រើ plugin សម្រាប់ Claude Code។** ព្រោះវា update ដោយខ្លួនឯង។ ប្រើ `npx skills` តែពេលអ្នកចង់កែ `SKILL.md` ផ្ទាល់។ កុំដំឡើងទាំងពីរ (skill ស្ទួន)។

3. **ឆ្លើយ grilling ជាភាសាខ្មែរក៏បាន ប៉ុន្តែរក្សា `GLOSSARY.md` ជាភាសាអង់គ្លេស។** ឈ្មោះ variable/function/file គួរតែត្រូវនឹង glossary ដូច្នេះពាក្យក្នុង glossary គួរជាអង់គ្លេស។ អាចបន្ថែមជួរ "ខ្មែរ" ជាការពន្យល់សម្រាប់ក្រុម។

4. **ចំពោះ repo script ដូចជា `collection-scripts`៖** មិនចាំបាច់ប្រើ flow ធំ (`/to-spec`, `/wayfinder`) ទេ។ ការផ្គុំល្អបំផុតគឺ៖
   - `/grill-with-docs` មុនកែ script ធំៗ (ឧ. `sync-telegram.sh`, `mac-clean.sh`)
   - `/wizard` សម្រាប់ជំហានដែលត្រូវចុចក្នុង dashboard (AWS, Google Drive API, Telegram bot token)
   - `/diagnosing-bugs` + `/retro` ពេល script បរាជ័យ
   - `/setup-matt-pocock-skills` → ជ្រើស **local files** ជា issue tracker បើមិនចង់ប្រើ GitHub Issues

5. **កុំ `/clear` ក្រោយ grilling។** ការសម្រេចចិត្តភាគច្រើនមិនចូល `GLOSSARY.md` ឬ ADR ទេ — ពួកវារស់នៅតែក្នុង context។ ត្រូវរត់ `/to-spec` (ឬ `/implement`) ក្នុង session ដដែលជានិច្ច។

6. **ពិនិត្យថា skill load ពេញលេញ។** បើ `/grill-with-docs` សួរសំណួរទាំងអស់ម្តង ឬមិនដែលប៉ះ `GLOSSARY.md` សូមសួរ agent៖ "Which skills did you load?" ហើយហៅ `/domain-modeling` តាមឈ្មោះបើចាំបាច់។

7. **កំណត់ពេល `/improve-codebase-architecture`។** ឧ. រៀងរាល់ថ្ងៃសុក្រ។ អ្នកអាចបន្ថែម reminder ក្នុង calendar ឬ alias ក្នុង `.custom-bash.sh`។

8. **ប្រើ `/retro` ដើម្បីបង្កើត `CLAUDE.md`/`AGENTS.md` សម្រាប់ repo នេះ។** Repo នេះមិនទាន់មាន `CLAUDE.md` ទេ — `/retro` បន្ទាប់ពី session ពិបាកមួយ នឹងស្នើ steering rule ដែលមានប្រយោជន៍ពិតប្រាកដ ជាជាងសរសេរតាមការស្មាន។

9. **`/wait-what` គឺជាមិត្តល្អ** សម្រាប់អ្នកដែលភាសាអង់គ្លេសមិនមែនជាភាសាកំណើត — ប្រើវាភ្លាមៗពេល agent ប្រើ jargon ដែលអ្នកមិនយល់ ហើយអាចបន្ថែម "explain in Khmer" បើចង់បាន។

10. **ប្រើ `/pr` រួមជាមួយច្បាប់ git របស់អ្នក។** `/pr` កំណត់តែទម្រង់ PR body ប៉ុណ្ណោះ — ច្បាប់ commit identity ក្នុង `~/.claude/CLAUDE.md` (គ្មាន `Co-Authored-By`) នៅតែមានអាទិភាព។

---

## ១០. តំណភ្ជាប់

- Repo: <https://github.com/mattpocock/skills>
- Docs លម្អិតតាម skill: `docs/engineering/<skill>.md`, `docs/productivity/<skill>.md` ក្នុង repo ដើម ឬ `https://aihero.dev/skills-<skill>`
- Newsletter: <https://www.aihero.dev/s/skills-newsletter>
