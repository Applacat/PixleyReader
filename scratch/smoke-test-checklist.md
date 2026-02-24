# Smoke Test Checklist

Run through before each release. Each item should take ~30 seconds.

---

## 1. Launch & Start View

- [x ] Cold launch shows StartView with mascot and folder shortcuts
- [x ] "Read Sample Files" opens Welcome folder and selects 01-Welcome.md
- [x ] Desktop / Documents / Downloads buttons open correct folders
- [x ] "Choose Folder..." opens NSOpenPanel, selecting a folder works
- [x ] Drag a folder onto StartView — opens it
- [x ] Drag a .md file onto StartView — opens parent folder, selects file
- [x ] Drop overlay appears with dashed border while dragging

## 2. Sidebar Navigation

- [X ] Folder tree shows hierarchy (folders first, then files alpha-sorted)
- [ x] Click folder to expand/collapse
- [ x] Click .md file to load it in detail view
- [X ] Arrow keys navigate up/down in tree
- [ X] Left/Right arrows collapse/expand folders
- [ x] Hidden files (dotfiles) are NOT shown
- [ x] Filter field narrows tree in real-time; X clears it

## 3. Markdown Viewing

- [ x] Selected .md file renders with syntax highlighting (what does this mean?)
- [x ] Scroll position restores when switching back to a previously-viewed file
- [ x] Reading progress badge (top-right) updates while scrolling
- [x ] Line numbers show (if enabled in Settings)
- [x ] Links in markdown are clickable



## 4. File Watching & Reload

- [x ] Open a .md file, edit it externally (e.g., in a text editor)
- [x ] "Content updated" reload pill appears at bottom
- [x ] Clicking reload pill refreshes the document
- [x ] Cmd+R forces reload even without external change

## 5. AI Chat (macOS 26+)

- [ x] Cmd+Shift+A toggles chat inspector open/closed
- [X ] With a file selected, chat shows "Ask about this document"
- [X ] Type a question, press Enter — "Thinking..." appears, then response
- [X ] Turn counter shows "Turn 1/3", increments on each exchange
- [X ] After 3 turns, auto-reset banner appears on next question
- [X ] "Forget" button (or Esc) clears conversation
- [X ] With no file selected, chat shows appropriate empty state
- [X ] If Apple Intelligence unavailable, shows FM unavailable view

## 6. Quick Switcher

- [ x] Cmd+P opens overlay with "Go to file..." search field
- [X ] Typing filters files in real-time (up to 20 results)
- [X ] Up/Down arrows change selection
- [X ] Enter opens selected file
- [ X] Esc closes switcher
- [ X] Clicking a result opens it

## 7. Settings

- [X ] Cmd+, opens Settings window
- [X ] **Appearance tab**: Color scheme picker (System/Light/Dark) changes immediately
- [X ] **Appearance tab**: Theme picker changes syntax colors live
- [ X] **Appearance tab**: Font size slider (10-32pt) updates preview
- [X ] **Appearance tab**: Line numbers toggle works
- [X ] **Behavior tab**: Link behavior setting persists across relaunch

## 8. Font Size Shortcuts

- [x ] Cmd++ increases font size
- [x ] Cmd+- decreases font size
- [x ] Changes reflect immediately in markdown view

## 9. Folder Management

- [X ] Cmd+Shift+O opens/changes folder
- [X ] Cmd+W closes current folder, returns to StartView
- [X ] Reopening a recently-used folder works (bookmark still valid)
- [X ] Drag a different folder onto browser view — switches to it

## 10. Find

- [x ] Cmd+F opens find bar in markdown view
- [ x] Cmd+G / Cmd+Shift+G cycle through matches
- [x ] Esc closes find bar

## 11. Error Handling

- [I DONT HAVE A FILE THAT BIG ] Open a very large file (>10 MB if possible) — error banner appears
- [ ] Error banner auto-dismisses after timeout
- [ ] Error banner can be manually dismissed (X button)

## 12. Persistence Across Relaunch

- [X ] Quit and relaunch — last folder reopens
- [X ] Scroll positions preserved for previously-viewed files
- [X ] Settings (theme, font size, color scheme) persist

---

**Time estimate**: ~10 minutes for a full pass.
