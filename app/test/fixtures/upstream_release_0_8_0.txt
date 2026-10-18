<!-- Draft: review — the What's new below was written with the
     tag, from CHANGELOG.md's 0.8.0 section — then publish. -->

## What's new

- **Half the download** — about 50 MB now, instead of 100 MB.
- **Your notebook can take half the room** — one button does it.
- **Double-click a notebook to open it**, even with Openote shut.
- **Get deletions back** — your last ten, one click each.
- **OneNote import overhauled** — nothing cut off or doubled up.
- **Every part of the app now works from the keyboard.**

## All of it, in more detail

- **The download is about half the size** — roughly 100 MB down
  to about 50 MB. Openote used to carry a video player inside it;
  now it is fetched once, the first time you play a video. Your
  videos themselves are always on your computer, and if you are
  updating from an older Openote the player you already have
  keeps working — nothing to download.
- **Notebooks can take about half the space they did.** One
  button (sharing window ▸ Storage) stops Openote keeping every
  picture and drawing twice; on two real notebooks it took them
  from 63 MB down to 33 MB apiece. It checks every single picture
  is safe in the notebook's own folder before it removes
  anything, and changes nothing unless all of them are.
- **Double-clicking a notebook now opens it — even when Openote
  is closed.** Opening another notebook switches the window you
  already have, rather than starting a second copy.
- **See who changed what on a page, and get deletions back.** The
  page history button now says which computer each paragraph,
  picture or drawing last came from — and your last ten notable
  deletions (a page, a section, a picture, a recording, a long
  stretch of writing) can each be put back with one click.
  The old copy Openote quietly took of every page every ten
  minutes is gone, and those old copies cannot be brought back —
  if there is an old page version you still want, get it out
  before you update. Undo, the recycle bin and your backups all
  carry on exactly as before.
- **OneNote import overhauled.** Pages no longer come out cut
  off, blank lines and layout are preserved, erased ink stays
  erased, titles land on the right pages, and importing the same
  file twice no longer doubles up your handwriting or paragraphs.
  Re-import a section to pick up the fixes.
- **Sharing and sync are much safer, and faster.** Several ways a
  shared notebook could quietly lose things are fixed — one
  computer's bad copy of a picture can no longer delete the good
  copies everywhere else, a sync that silently stopped now picks
  itself up, a save that never reached the notebook's history now
  says so — and catching up with another computer no longer
  freezes the app.
- **The whole app works from the keyboard.** F6 moves between the
  sidebar, toolbar, page and panels; Ctrl+/ shows every shortcut.
  A paste that cannot be saved now tells you plainly instead of
  doing nothing, and error messages are clearer throughout.
- **Your GitHub key now lives in your computer's own password
  storage** — Credential Manager on Windows, the Keychain on Mac,
  the keyring on Linux — never in a plain file. A key you saved
  before is moved over automatically.
- **Openote can rebuild a notebook's working file from your
  notes** if it is ever damaged or lost. Your notes live in the
  notebook's own folder; the working file is only the copy
  Openote reads while the notebook is open.

## The fine print

- Openote is still in active development. Updates are worth
  taking, but a major update may occasionally break a feature —
  and macOS is the least-tested platform by far.
- On Linux, whether double-clicking a notebook *folder* opens
  Openote depends on your file manager; the **Open this
  notebook** file inside the folder works either way.
- The storage format changed this release: Openote can now tuck
  a notebook's working file out of the way and rebuild it on
  demand. It is opt-in, one notebook at a time, and **Put it
  back** undoes it.

## For the technically curious

This release lands the storage-cluster work: the append-only op
log in the notebook's folder is now the source of truth, and the
SQLite container is demoted to a working copy the app can always
reproduce from that log. Pictures and drawings are stored once,
as content-addressed files verified by re-hash on read-back —
a corrupt copy is set aside and healed rather than deleted, so
one machine's bad blob can never propagate a delete through a
shared notebook. The change set then went through adversarial
review passes whose every confirmed finding was fixed, and the
test suite grew from 1,272 to 1,564 over the cycle.

## Downloads
- **Windows**: `openote-*-windows-x64-setup.exe` — the installer.
  Installs for your user only, so it never asks for an
  administrator password. (Prefer no installer? The
  `…-windows-x64.zip` is the same build — unzip it anywhere and run
  `openote.exe` from inside the folder it extracts.)
- **Linux**: `openote-*-linux-amd64.deb` on Ubuntu/Debian/Mint, or
  `openote-*-linux-x86_64.rpm` on Fedora/RHEL/openSUSE. Double-click
  it, or install from a terminal — then Openote is in your
  applications menu like any other program. To open a notebook from
  your file manager, double-click the **Open this notebook** file
  inside the notebook's folder; whether double-clicking the folder
  itself opens Openote depends on which file manager you use.
  (Neither package fits? The `.tar.gz` runs from anywhere: extract
  it and run `./openote` inside. It has no package manager to ask
  for libmpv, so if you want video to play in the page, install
  `mpv-libs` on Fedora or `libmpv2` on Ubuntu/Debian yourself —
  the app says so too.)
- **macOS**: `openote-*-macos-universal.dmg` — drag Openote to Applications.

---

### Both warnings below are expected. Here is exactly why.

Openote is not code-signed. Signing certificates cost a few hundred
dollars a year each, and while the project is this young that money
is better spent on nothing at all. Nothing about the warnings says
the software is unsafe — only that we have not paid to tell your
operating system who we are. Every build here is produced by the
public workflow in this repository, from the tagged commit, and you
can read both.

**Windows: "Windows protected your PC"**

Click **More info**, then **Run anyway**. SmartScreen shows this for
any installer it has not seen often enough to have an opinion about.

**macOS: "openote is damaged and can't be opened"**

Gatekeeper quarantines unsigned downloads. After copying to
Applications, clear the flag once:

    xattr -cr /Applications/openote.app

Your notes never leave your machine either way — see the project's
local-first principles.
