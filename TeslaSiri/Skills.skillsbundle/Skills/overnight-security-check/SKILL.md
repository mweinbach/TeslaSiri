---
name: overnight-security-check
description: Check or secure a parked car for the night or while the user is away. Use for bedtime checks, securing the car overnight, or checking locks, windows, Sentry Mode and charging together before leaving it parked. Use vehicle-control for routine status questions and direct commands.
---

# Overnight Security Check

## 1. Read the car's state once

Use the Get Tesla Vehicle Info tool once with the security, charging, battery, range, and climate topics. For “my car,” omit the vehicle to use the default. If the user names a car, use that vehicle for every read and change. Use the List Cars tool if you need to identify it. If the name is ambiguous, ask which car they mean. If it is unavailable, tell the user and stop.

For a status question, report the readings and stop. When the user asks to secure the car, collect the applicable changes below and send them in one call to the Control Car tool. If the request fails partway through, stop and report the accepted changes and the step the tool could not confirm. Leave the remaining steps pending until the user asks to continue.

## 2. Secure the car

- If the car isn't locked, include locking it.
- Sentry Mode: turn it on only if the user asked for full security, or said the car is parked away from home. Tesla won't run Sentry Mode at 20% battery or below; if the battery is that low, tell the user instead.
- If the user asked about windows, include closing them. The user confirms before the changes run.
- If the charge port door is open and the car isn't plugged in, include closing it.

## 3. Climate

- If climate is on and the user didn't ask to keep it on, include turning it off.
- If Dog Mode is on, leave climate running and mention that Dog Mode is keeping the cabin conditioned. Never turn Dog Mode off unless the user asks.

## 4. Charging

- If the car is unplugged and the battery is under 50%, say so clearly. You can't plug it in.
- If it's plugged in but not charging, and the user wants it charged by morning, include starting charging.
- Only change the charge limit if the user names a limit.

## 5. Report

Give a short checklist: locked or not, Sentry Mode, anything you closed or turned off, battery percent and range, and whether the car is charging, plugged in, or unplugged.

## Don't

- Don't unlock the car, open the trunk or frunk, or turn Sentry Mode off as part of this check.
