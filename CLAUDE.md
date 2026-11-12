# Working on this repo

- After every change, commit it and push straight to `main` on GitHub
  (`git push origin main`). No feature branches or pull requests, and no need
  to ask first.
- Before committing, run the logic tests and make sure they pass:
  `godot --headless --path . --script res://tests/sim_test.gd`
- Don't commit `shots/` (screenshots written by `tests/visual_test.gd`).
