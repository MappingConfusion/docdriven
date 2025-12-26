# THIS Repo Example

This example demonstrates using DocDriven with the **THIS** special repository name, which allows you to generate code into the same codebase where your documentation lives.

## Directory Structure

```
this-repo-example/
├── docdriven.json       # Configuration file
├── .env                 # Environment variables (optional for THIS)
├── docs/                # Documentation folder
│   └── tutorial.md      # Source documentation
├── src/                 # Generated code will go here
└── sql/                 # Generated SQL will go here
```

## Key Differences from External Repos

1. **Repo Name**: Use `"THIS"` as the special repository name in `docdriven.json`
2. **No Cloning**: The system knows to generate into the current directory
3. **Default Path**: `DOCDRIVEN_THIS_LOCAL` defaults to `.` (current directory) if not specified
4. **No GitHub Config**: Don't set `DOCDRIVEN_THIS_GITHUB_REPO` - THIS represents the current codebase

## Usage

Generate files locally:
```bash
cd this-repo-example
docdriven push --config docdriven.json
```

The files will be generated directly into `src/` and `sql/` folders in this repository.

## When to Use THIS

Use the THIS pattern when:
- Your documentation lives in the same repository as your code (e.g., `docs/` folder)
- You want to generate code into the current project structure
- You're documenting a single codebase, not multiple external services

For generating into separate repositories, use named repos like `"BACKEND"`, `"FRONTEND"`, etc.
