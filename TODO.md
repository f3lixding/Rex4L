# TODO: Connect Rex4L to one Rex terminal

**Goal:** Attach to one existing terminal pane on a local Rex server, display its current screen and live output, and send basic keyboard input. Rex owns the shell, PTY, and authoritative terminal state. Rex4L keeps a local `libghostty-vt` model only to interpret and draw the server's state.

## 1. Read one real pane

- [ ] Use `rex api call session.list` and `rex api call -s Rex4L session.view` to identify a session and a terminal block. Use the active window's `focused_block_id` if it points to a terminal.
- [ ] Call `com.superlogical.terminal.format` with the block ID and `args.format` set to `text`. As a temporary smoke test, display the returned `content` in a read-only monospace `GtkTextView`. Run the CLI call off the GTK main thread. This is a one-shot preview, not a live attachment.

## 2. Attach to the live terminal stream

- [ ] In `src/rex/client.zig`, open a persistent control WebSocket at `/api/control` (`rex.control.v1`). Call `session.attach` and then `data.connect` on the same connection, with the chosen session and block IDs and `data_ref_id: "terminal"`.
- [ ] In `src/rex/terminal_stream.zig`, use the one-time ticket to open `/api/data` (`rex.data.terminal.v1`). Separate the initial Ghostty snapshot, subsequent VT output, and protocol messages. Use [Rex Rune's wire implementation](https://github.com/shuv1337/rex-rune/blob/master/src/wire.rs) as a reference.

## 3. Render the server's state

- [ ] In `src/terminal/Emulator.zig`, add a snapshot-based constructor using `vt.snapshot`. Bind `TerminalStream` to the restored terminal at a stable address and preserve any parser continuation from the snapshot. Feed only decoded live VT output to `feed()`.
- [ ] In `src/ui/TerminalView.zig` and `src/ui/application_window.zig`, remove the fake banner and blank `80×24` initialization from the live path. Show “Connecting…” until the snapshot is ready. Draw at the server's grid size and schedule render-state updates and redraws on the GTK main thread. Show a visible error if the connection fails.
- [ ] Verify that the pane's existing contents appear on attach and that new output updates the view without polling.

## 4. Send basic input and stop

- [ ] Make the terminal view focusable and send basic key events to Rex with `client.key` on the attached control connection. Block on neither the GTK callback nor the GTK main loop; let the returned output update the view instead of echoing locally.
- [ ] Verify typing, Backspace, and Enter in the single pane. Close Rex4L and confirm the server session keeps running.

**Out of scope:** spawning a local shell or PTY, creating sessions, multiple panes or tabs, remote hosts, resizing or size ownership, automatic reconnect, and advanced terminal input or rendering.
