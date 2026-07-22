# Mineshift

Mineshift is a minesweeper roguelike in development, built with Godot 4.7 and GDScript.

The current foundation is a five-field run with progressively larger boards, classic minesweeper rules, safe openings, flags, chords, compact transitions, and a board-first minimalist interface.

Each run has three persistent Integrity points. Detonated mines consume Integrity, become neutralized, and dynamically update nearby numbers; newly formed zeroes expand normally. Restarting a field costs one Integrity and is unavailable when only one point remains.

After each of the first four fields, choose one of three free gameplay modules. Modules persist for the run and directly change minesweeper rules. The current set is **Buffer Layer**, **Auto Chord**, **Breach Pulse**, **Expanded Start**, **Restart Cache**, and **Flag Verifier**.

## Controls

- Left click: reveal a cell or chord a revealed number
- Right click: place or remove a flag
- `R`: request a field restart (costs one Integrity)
- `Esc`: pause

Import `project.godot` in Godot 4.7 and press **F6** or **F5** to run.
