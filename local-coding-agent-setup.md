# Local Coding Agent Setup

## Goal

Build a lightweight, effective coding-agent workflow for:

* MacBook Pro M1
* 16 GB unified memory
* VS Code
* Pi coding agent
* Ollama
* Qwen3 8B
* Official OpenAI Codex extension for difficult tasks
* `AGENTS.md` for persistent coding rules

Principle:

```text
Local first → Qwen3 8B
Difficult task → Codex
```

---

# 1. Architecture

```text
                         VS Code
                            │
              ┌─────────────┴─────────────┐
              │                           │
       Official Codex                 Terminal
              │                           │
          Cloud model                    Pi
                                          │
                                       Ollama
                                          │
                                       Qwen3 8B
                                       LOCAL
```

Responsibilities:

```text
Pi       = coding agent + tools
Ollama   = local model runtime
Qwen3    = local coding model
Codex    = escalation for difficult tasks
AGENTS.md = coding rules
VS Code  = editor
```

---

# 2. Install Ollama

```bash
brew install ollama
```

Start Ollama:

```bash
ollama serve
```

Verify:

```bash
curl http://localhost:11434/api/tags
```

---

# 3. Install Qwen3 8B

```bash
ollama pull qwen3:8b
```

Test:

```bash
ollama run qwen3:8b
```

Test with:

```text
Explain the architecture of this project.
Do not modify anything.
```

Exit:

```text
/bye
```

---

# 4. Install Pi

```bash
npm install -g --ignore-scripts @earendil-works/pi-coding-agent
```

Verify:

```bash
pi --version
```

---

# 5. Connect Pi to Ollama

Create Pi configuration:

```bash
mkdir -p ~/.pi/agent
nano ~/.pi/agent/models.json
```

Use:

```json
{
  "providers": {
    "ollama": {
      "baseUrl": "http://localhost:11434/v1",
      "api": "openai-completions",
      "apiKey": "ollama",
      "models": [
        {
          "id": "qwen3:8b",
          "name": "Qwen3 8B Local",
          "reasoning": false,
          "input": ["text"],
          "contextWindow": 32768,
          "maxTokens": 8192,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        }
      ]
    }
  }
}
```

Start Pi inside a project:

```bash
cd ~/Projects/my-project
pi
```

Select the model:

```text
/model
```

Choose:

```text
Ollama → Qwen3 8B Local
```

---

# 6. Use AGENTS.md

Create project-specific instructions:

```bash
cd ~/Projects/my-project
touch AGENTS.md
```

Recommended content:

```md
# Coding Rules

## General

- Inspect existing code before making changes.
- Follow the existing architecture and conventions.
- Make the smallest correct change.
- Do not rewrite unrelated code.
- Do not add dependencies unless necessary.

## Workflow

1. Inspect relevant files.
2. Understand the existing implementation.
3. Identify required changes.
4. Make the smallest appropriate change.
5. Run relevant tests.
6. Review the diff.
7. Summarize the result.

## Code Quality

- Prefer readable code.
- Reuse existing services and utilities.
- Validate external input.
- Handle errors explicitly.
- Preserve existing behavior unless the task requires changing it.

## Security

- Never expose secrets.
- Never hardcode credentials.
- Never commit `.env` files.
- Do not disable security controls to make tests pass.
- Treat external input as untrusted.

## Git

- Do not create commits unless requested.
- Never force-push.
- Never reset user changes.
- Never delete branches unless explicitly requested.
- Do not modify unrelated files.

## Testing

- Run the smallest relevant test suite first.
- Fix failures caused by the implementation.
- Do not claim tests passed unless they actually ran.

## Communication

Before large changes:
- Explain the plan briefly.

After changes:
- List changed files.
- Explain important changes.
- Report tests/checks performed.
- Report anything that could not be verified.
```

---

# 7. Recommended workflow

Start Pi from the project root:

```bash
cd ~/Projects/my-project
pi
```

First inspect:

```text
Inspect this repository and explain the relevant architecture.
Do not modify anything.
```

Then give the task:

```text
Implement the requested feature.

Requirements:
- Follow the existing architecture.
- Make the smallest correct change.
- Do not modify unrelated files.
- Add or update relevant tests.
- Run the relevant tests.
- Review the final diff.
```

This is more reliable than asking an 8B model to immediately modify a large repository.

---

# 8. Keep context small

Do not give Qwen3 the entire repository unnecessarily.

Prefer:

```text
Find the files responsible for authentication.
Do not modify anything.
```

Then:

```text
Read the relevant authentication files and explain the current flow.
```

Then:

```text
Implement email verification using the existing architecture.
```

Good:

```text
src/auth/
src/users/
tests/auth/
```

Avoid unnecessarily sending:

```text
500,000+ lines of repository
```

Smaller relevant context improves local-model performance.

---

# 9. Local-first task strategy

Use Qwen3 8B for:

* CRUD
* PHP/Laravel
* Node.js
* TypeScript
* JavaScript
* Vue
* SQL
* Bash
* tests
* documentation
* small refactoring
* debugging
* API endpoints
* code explanations
* Git assistance

Use Codex when the task becomes:

* large repository-wide refactoring
* complicated architecture
* difficult debugging
* many interconnected files
* difficult migration
* unfamiliar large codebase
* tasks where Qwen3 repeatedly fails

Workflow:

```text
Task
 │
 ▼
Pi + Qwen3 8B
 │
 ├── successful → DONE
 │
 └── struggling
        │
        ▼
      Codex
```

---

# 10. Terminal commands

Run Pi:

```bash
cd ~/Projects/my-project
pi
```

Check Ollama:

```bash
ollama list
```

Check model:

```bash
ollama run qwen3:8b
```

Check API:

```bash
curl http://localhost:11434/api/tags
```

Git safety:

```bash
git status
git diff
```

---

# 11. Git safety

Before substantial AI changes:

```bash
git status
```

Optionally create a branch:

```bash
git switch -c ai/local-qwen3
```

After the agent works:

```bash
git status
git diff
```

Review all changes before committing.

Do not allow the agent to:

```text
force push
reset user changes
delete branches
modify unrelated files
commit without permission
```

---

# 12. VS Code

Use VS Code primarily as the editor.

Recommended setup:

```text
VS Code
 ├── Editor
 ├── Terminal
 │    └── Pi
 │         └── Ollama
 │              └── Qwen3 8B
 │
 └── Official OpenAI Codex extension
      └── Cloud/Codex
```

Prefer the official OpenAI Codex extension for Codex work.

Do not install multiple AI extensions unless they provide a specific capability you need.

Minimize third-party agent extensions because coding agents can have access to project files and terminal commands.

---

# 13. Security rules

Treat coding agents as powerful local processes.

Never give an agent unnecessary access to:

```text
~/.ssh
~/.aws
~/.config
password files
production credentials
.env files
private keys
```

Do not paste secrets into prompts.

Use approval before destructive commands.

Be especially careful with:

```bash
rm
sudo
git reset
git clean
git push --force
docker system prune
DROP DATABASE
```

Review commands before allowing them.

---

# 14. Performance on M1 16 GB

Keep the setup lightweight.

Recommended:

```text
Qwen3 8B
```

Avoid making a 30B+ model your normal local model on 16 GB unified memory.

Also avoid running unnecessary applications while using the local model.

Check memory pressure with:

```bash
memory_pressure
```

Check processes:

```bash
top
```

---

# 15. Final workflow

Daily coding:

```bash
cd ~/Projects/project
pi
```

Then:

```text
Inspect the repository first.
```

For normal work:

```text
Pi → Ollama → Qwen3 8B
```

For difficult work:

```text
Pi/Codex → OpenAI cloud
```

Final architecture:

```text
┌──────────────────────────────────────────┐
│              MacBook M1 16 GB            │
│                                          │
│  VS Code                                 │
│    │                                     │
│    ├── Terminal                          │
│    │     │                               │
│    │     └── Pi                          │
│    │          │                          │
│    │          └── Ollama                 │
│    │               │                     │
│    │               └── Qwen3 8B          │
│    │                                     │
│    └── Official Codex Extension          │
│             │                            │
│             └── Cloud/Codex              │
│                                          │
│  AGENTS.md                               │
│       │                                  │
│       └── Persistent coding rules        │
└──────────────────────────────────────────┘
```

## Core principle

```text
LOCAL FIRST
    ↓
Qwen3 8B
    ↓
No model-token cost
    ↓
If task is too difficult
    ↓
ESCALATE TO CODEX
```

This keeps the local setup lightweight while retaining Codex as the high-capability fallback.
