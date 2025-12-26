# docdriven

Generate repository structures from documented codeblocks.

## Install

```bash
opam install .
```

## Usage

**List all files:**
```bash
docdriven list                  # all repos
docdriven list BACKEND          # specific repo only
```

**Find unassigned codeblocks:**
```bash
docdriven unassigned               # first 10 unassigned blocks
docdriven unassigned --limit 20    # first 20 unassigned blocks
docdriven unassigned --limit 0     # all unassigned blocks
```

Shows which codeblocks in your documentation aren't assigned to any repository files, helping identify documentation gaps.

**Push to local:**
```bash
docdriven push local BACKEND              # one repo
docdriven push local BACKEND FRONTEND     # multiple repos
docdriven push local --all                # all repos
docdriven push local BACKEND -o custom_dir
```

**Interactive selection:**
```bash
docdriven push local -i BACKEND       # select files with space, confirm with enter
docdriven push github -i --all
```

**Filter by patterns:**
```bash
docdriven push local BACKEND --only="src/*"              # only src/ files
docdriven push local FRONTEND --exclude="tests/*"         # skip tests
docdriven push local --all --only="*.py" --only="*.sql"  # multiple patterns
```

**Push to GitHub:**
```bash
docdriven push github BACKEND       # uses DOCDRIVEN_BACKEND_GITHUB or DOCDRIVEN_GITHUB from .env
docdriven push github --all
docdriven push github BACKEND -t ghp_xxxxx
```

## Config Format

Create `docdriven.json` in your documentation root:

```json
{
  "BACKEND": {
    "src": {
      "main.py": "tutorial.md[python][0]",
      "utils.py": [
        "guide.md[python][0]",
        "guide.md[python][1]"
      ]
    }
  },
  "FRONTEND": {
    "src": {
      "App.tsx": "guide.md[typescript][0]"
    },
    "README.md": "intro.md[markdown][0]"
  }
}
```

Each top-level key (BACKEND, FRONTEND, etc.) is a **repo name** in UPPERCASE.

**Environment Configuration (.env):**

```bash
# Shared GitHub token (fallback for all repos)
DOCDRIVEN_GITHUB=ghp_shared_token

# Per-repo configuration
DOCDRIVEN_BACKEND_LOCAL=./output/backend
DOCDRIVEN_BACKEND_GITHUB_REPO=yourusername/backend-repo

DOCDRIVEN_FRONTEND_LOCAL=./output/frontend
DOCDRIVEN_FRONTEND_GITHUB_REPO=yourusername/frontend-repo
```

**Token Resolution:**
1. CLI flag: `--token ghp_...`
2. Repo-specific: `DOCDRIVEN_<REPONAME>_GITHUB=token`
3. Shared fallback: `DOCDRIVEN_GITHUB=token`
4. Error if none found

**Local Output:**
1. CLI flag: `--output custom_dir`
2. `.env` file: `DOCDRIVEN_<REPONAME>_LOCAL=path`
3. Error if not found

**GitHub Repo:**
1. `.env` file: `DOCDRIVEN_<REPONAME>_GITHUB_REPO=owner/repo`
2. Error if not found

## License

MIT

All source paths are **relative to docdriven.json location**.
