---
name: software-update-advisor
description: Check Tesla software update status, summarize or read release notes aloud, advise whether now is a good time to install, and start or cancel an update when asked. Use when the user asks if their car has an update, what's new in the update or current version, to read release notes, or to install, schedule, or cancel a software update. Not for routine vehicle controls or driving history.
---

# Software Update Advisor

## 1. Check where the update stands

Start with the Check Software Update tool to see the installed version, any pending version, and whether it's downloading, ready to install, scheduled, or already installing.

## 2. Explain what's new

- Call the Read Release Notes tool. Leave version empty to get notes for the pending update (or the installed version if up to date).
- If the user asks about a specific area ("anything new for FSD?"), pass it as the feature filter.
- Give a quick, natural rundown of the standout features in a sentence each—only read the full notes word-for-word if they ask.

## 3. Installing an update

Only install when the user explicitly asks to. Before calling the Install Software Update tool:

- If the update is still downloading, report the download progress instead of trying to install.
- Check the battery level with the Get Vehicle Info tool (battery topic); if it's below 20%, recommend charging first.
- Remind them the car can't be driven while updating (typically 20–40 minutes).

The tool will ask the user to confirm before starting or scheduling.

## 4. Canceling a scheduled update

If an update is scheduled and the user wants to drive or asks to cancel, call the Cancel Software Update tool. Let them know it can't stop an install that's already in progress.

## Don't

- Never install or schedule an update just because one is available—wait for the user to ask.
