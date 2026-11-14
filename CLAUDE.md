# Working on this repo

- After every change, commit it and push straight to `main` on GitHub
  (`git push origin main`). No feature branches or pull requests, and no need
  to ask first.
- Before committing, run the logic tests and make sure they pass:
  `godot --headless --path . --script res://tests/sim_test.gd`
- Don't commit `shots/` (screenshots written by `tests/visual_test.gd`).
- Commit as `reesegodwin <224442274+reesegodwin@users.noreply.github.com>`
  (set it with `-c user.name=... -c user.email=...`), and don't add
  `Co-Authored-By` or `Claude-Session` lines to commit messages.
- End every reply to the user with a next step or suggestion for the game's
  development (what to build, fix or playtest next, and why).
- When a task would be done better with another piece of software or service
  (as Blender was for the models, `tools/blender/`), say so: what it is, what
  it would improve, and what's needed to connect it (installed in the cloud
  session, a host allowed in the environment's network settings, an account or
  API key, or something on the user's own computer). Recommend it before
  starting the work, and don't connect anything that needs the user's account,
  money or computer without asking.
