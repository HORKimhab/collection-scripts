# Codex CLI — Developer Cheatsheet

## 1. Start Codex

```bash
codex
```

Start Codex in the current directory.

```bash
codex .
```

Open the current project.

```bash
codex /path/to/project
```

Open a specific project.

```bash
codex "Fix the login bug"
```

Start with a task.

```bash
codex --help
```

Show available commands and options.

```bash
codex --version
```

Show installed version.

---

## 2. Execute Tasks

```bash
codex exec "Analyze this project"
```

Run a task without interactive mode.

```bash
codex exec "Find and fix the bug"
```

Useful for automation and scripts.

```bash
codex exec "Run the tests and explain failures"
```

---

## 3. Resume Sessions

```bash
codex resume
```

Resume a previous session.

```bash
codex resume --last
```

Resume the latest session.

```bash
codex resume --help
```

See resume options.

---

## 4. Interactive Commands

Inside Codex:

```text
/help
```

Show available commands.

```text
/status
```

Show session status.

```text
/clear
```

Clear the current context.

```text
/exit
```

Exit Codex.

---

## 5. Ask Codex to Inspect

```text
Inspect this project first.
Do not modify anything.
Explain the architecture and relevant files.
```

```text
Find where this feature is implemented.
Do not change anything.
```

```text
Find the root cause of this error.
Show me the relevant files and explain why it happens.
```

---

## 6. Ask Codex to Fix

```text
Fix this issue.
Make the smallest safe change.
Do not modify unrelated files.
Run relevant tests after the fix.
```

```text
Implement this feature using the existing project patterns.
Do not introduce unnecessary dependencies.
```

---

## 7. Code Review

```text
Review my current changes.
Look for bugs, security issues, regressions, and bad practices.
Do not modify files.
```

```text
Review the code for performance problems.
Do not modify anything.
```

---

## 8. Tests

```text
Run the relevant tests for this change.
Fix failures caused by your changes.
Do not modify unrelated tests.
```

Common terminal commands:

```bash
npm test
```

```bash
pnpm test
```

```bash
php artisan test
```

---

## 9. Git Commands Used With Codex

```bash
git status
```

Check changed files.

```bash
git diff
```

Review changes.

```bash
git diff --check
```

Check whitespace problems.

```bash
git diff --stat
```

Show changed-file summary.

```bash
git log --oneline -10
```

Show recent commits.

```bash
git branch --show-current
```

Show current branch.

```bash
git show
```

Show latest commit.

---

## 10. Undo Codex Changes

```bash
git restore <file>
```

Discard changes to one file.

```bash
git restore .
```

Discard all unstaged changes.

```bash
git restore --staged <file>
```

Unstage a file.

---

## 11. Commit After Review

```bash
git status
git diff
git diff --check
```

Then:

```bash
git add .
```

```bash
git commit -m "fix: resolve issue"
```

```bash
git push
```

---

## 12. Useful Project Commands

### Node.js

```bash
pnpm install
pnpm dev
pnpm test
pnpm build
pnpm lint
```

### Laravel

```bash
php artisan route:list
php artisan test
php artisan optimize:clear
```

### Docker

```bash
docker ps
docker compose ps
docker compose logs
docker compose up -d
docker compose down
```

---

## 13. Search Code

```bash
grep -R "keyword" .
```

Search the project.

```bash
find . -type f -name "*.php"
```

Find PHP files.

```bash
find . -type f -name "*.js"
```

Find JavaScript files.

For large projects:

```bash
grep -R "keyword" . \
  --exclude-dir=node_modules \
  --exclude-dir=vendor \
  --exclude-dir=.git
```

---

## 14. Best Developer Workflow

```bash
cd my-project

git status

codex
```

Ask Codex:

```text
Inspect first.
Explain the root cause.
Propose the smallest safe fix.
Wait for my approval before modifying files.
```

After the change:

```bash
git diff
git diff --check
```

Run tests:

```bash
pnpm test
```

or:

```bash
php artisan test
```

Finally:

```bash
git status
git add .
git commit -m "fix: ..."
git push
```

---

## 15. Most Used Commands

```bash
codex
codex .
codex "task"
codex --help
codex --version
codex exec "task"
codex resume
codex resume --last

git status
git diff
git diff --check
git log --oneline -10
git restore <file>
git add .
git commit -m "message"
git push
```

## Golden Rule

```text
Inspect → Explain → Approve → Modify → Test → Diff → Commit
```
