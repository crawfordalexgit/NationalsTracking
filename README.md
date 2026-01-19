Nationals Tracking workspace

This folder contains starter scripts to track the Top 50 English 13yo 200m Breaststroke swimmers and generate a minimal Chart.js fragment for testing.

Quick run (from this folder):

```powershell
cd "C:\Users\alex\OneDrive - Mogwai Consultants\00-Tonbridge Swimming\Scripts\Nationals Tracking\scripts"
powershell -NoProfile -ExecutionPolicy Bypass -File run_all.ps1
```

Files of interest:
- `scripts/regen_cache.ps1` — writes `src/swimmer_cache.json` sample
- `scripts/Fetch-HistoricalTimes.ps1` — populates `HistoricalTimes` stub
- `scripts/get_oliver_link.ps1` — downloads rankings and prints Oliver Laszlo personal-best link
- `scripts/run_all.ps1` — runs the above in order
- `src/Get-TopSwimmersChart.ps1` — minimal chart generator
- `debug/debug_generated_chart_fragment.html` — debug fragment
- `src/Top_22_Swimmers_200m_Breaststroke_Chart.html` — generated chart page (after running)

Run the runner to produce `src/debug_allSwimmerData.json` and `debug/debug_generated_chart_fragment.html` for inspection.

## GitHub Pages deployment
A GitHub Actions workflow has been added to build the pipeline and deploy the generated site to GitHub Pages automatically on push to `main`.

- Workflow: `.github/workflows/deploy-pages.yml`
- What it does: runs `scripts/run_all.ps1`, gathers the `src/` folder as the site artifact, and deploys to GitHub Pages.

After you push to `main`, the Actions run will publish the `src/` folder to Pages. Your Chart should be available at:

https://crawfordalexgit.github.io/NationalsTracking/Top_50_Swimmers_200m_Breaststroke_Chart.html

(If your repo is named differently, adjust the URL accordingly.)

## Local development
Use the helper script to run a local server and avoid `file://` issues:

- Start local server: `pwsh .\scripts\serve.ps1 -Port 8000`
- Open: `http://localhost:8000/Top_50_Swimmers_200m_Breaststroke_Chart.html`

## How to push these changes to GitHub (one-off)
If this workspace is not yet a git repo on your machine, run the included helper to initialize, commit and push the files to your repo:

1. Ensure you're in the project root and run (example):

   pwsh .\scripts\git_init_and_push.ps1 -RemoteUrl 'https://github.com/crawfordalexgit/NationalsTracking.git' -CommitMessage 'Initial commit: CI + Pages + serve helper' -Branch 'main'

2. On GitHub, open the **Actions** tab → watch the `Build and Deploy to GitHub Pages` workflow run. If it succeeds, Pages will be deployed.

## Ongoing usage (how to work with this project)
- Local dev loop:
  1. Regenerate data & HTML: `pwsh .\scripts\run_all.ps1`
  2. Serve site locally: `pwsh .\scripts\serve.ps1 -Port 8000`
  3. Open `http://localhost:8000/Top_50_Swimmers_200m_Breaststroke_Chart.html` and test in browser.
- To deploy updates to GitHub Pages:
  1. Commit your changes locally (e.g., `git add . && git commit -m "Update chart generator"`).
  2. Push to `main`: `git push origin main` → Actions will run automatically and re-deploy if successful.

## Troubleshooting Actions
- If the workflow fails, open the workflow run and inspect the `Run pipeline (PowerShell)` step logs. Common issues:
  - Missing modules or network fetch errors: adjust the runner or install packages in the workflow.
  - Smoke tests failing: the Action will stop and prevent deployment; fix tests locally and re-run.

If you'd like, I can also add a separate PR-check workflow (runs on PRs to main) to run the smoke tests and fail the PR on regression.