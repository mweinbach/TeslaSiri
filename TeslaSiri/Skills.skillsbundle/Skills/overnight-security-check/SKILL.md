---
name: overnight-security-check
description: Check on or lock down a parked car for the night or while the user is away. Use for bedtime checks, securing the car overnight, or reviewing locks, windows, Sentry Mode, climate, and charging together before leaving the car parked. Not for everyday single-command controls or routine status questions.
---

# Overnight Security Check

## 1. Check the whole picture once

Call the Get Vehicle Info tool once with security, charging, battery, range, and climate.

- Leave the vehicle empty for "my car." If the user names a car, use that same car for every read and change (call the List Cars tool once if you need to identify it; ask if ambiguous; stop if unavailable).
- If they only asked for a check, report what you found and stop.

## 2. Lock down what needs attention

When the user asks to secure the car, combine every needed fix into one call to the Control Car tool:

- **Doors**: lock them if unlocked.
- **Sentry Mode**: turn it on only if they asked for full security or said the car is parked away from home. Skip it and warn them if the battery is at or below 20% (Tesla disables Sentry Mode there).
- **Windows**: include closing them if the user asked about windows or any window is reported open (Wattie will ask to confirm).
- **Rear trunk**: close a powered rear trunk if the security reading shows it is open (Wattie will ask to confirm).
- **Charge port**: close it if the door is open while unplugged.
- **Climate**: turn it off if running and they didn't ask to keep it on—**except** if Dog Mode is active, leave climate running, mention Dog Mode, and never turn it off unless they explicitly ask.
- **Charging**: if plugged in and not charging, start charging when they want it ready by morning. Only change the charge limit if they name one. If unplugged below 50%, call that out clearly since you can't plug it in.

If the request fails partway through, report what succeeded and the first unconfirmed step, then stop until the user asks to continue.

## 3. Give a short bedtime checklist

Keep the reply crisp: lock status, Sentry Mode, anything you closed or turned off, battery and range, and whether it's charging, plugged in, or unplugged. If Delivery State is Waking Vehicle, mention the car was asleep and the request was sent to wake it.

## Don't

- Don't unlock the doors, open the trunk or frunk, or turn Sentry Mode off during an overnight check.
