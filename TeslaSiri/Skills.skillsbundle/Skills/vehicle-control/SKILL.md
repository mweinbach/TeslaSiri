---
name: vehicle-control
description: Answer questions about the user's cars, what controls each car supports, and live vehicle status, compare readings across multiple cars, or run direct and conditional vehicle commands. Use for everyday checks like whether the car is locked or how much range is left, and for commands like locking doors, warming or cooling the cabin, adjusting seats, sending an address, or acting only when a condition is met. Not for full trip prep, overnight security routines, past drive or charging history, or software updates.
---

# Everyday Car Questions & Controls

## Pick the right car first

- When the user says "my car," leave the vehicle empty to use their default car.
- When they say "this one," name a specific car, or ask a follow-up, stick with the car already on screen or in the conversation.
- If you still need to find the right car—or they ask which cars they have or what a car supports—call the List Cars tool once.
- If multiple cars match what they said, list their names and ask which one they mean. If the named car isn't on the account, say so and stop.

## Match the tool to the request

- **Fleet & capability questions** ("Which cars do I have?", "Can Midnight cool its seats?"): use the List Cars tool. Keep any "if equipped" caveats in your answer, and stop once you've answered.
- **Specific live readings** ("Is my car locked, and how much range is left?"): call the Get Vehicle Info tool once with only the topics they asked about. Lead with the numbers and units. Mention when a reading is old or missing. Use measured inside temperature for "Is it at 72°F yet?" and charging state for "Is it plugged in?"
- **Broad check-ins** ("How's my car?", "Check my Tesla"): use the Check Vehicle Status tool for an at-a-glance card.
- **Comparing across cars** ("Which car has enough range for a 90-mile trip?"): call the List Cars tool once if needed, then check each car with the Get Vehicle Info tool and compare by car name. Call out missing readings individually, and ask if a required distance was left out.
- **Most vehicle controls** (one change or several together—warming up or cooling down without a specific temperature like "Warm up my car", "Cool down my car", "Precondition my car", turning off AC/heat, locks, defrost, Dog Mode, Bioweapon Defense, Sentry Mode, charging, charge limit/amps, charge port, windows, trunk/frunk, lights, horn): send everything for one car in a single call to the Control Car tool. For bare warm-up/cool-down requests without a temperature, set Climate Power to true without asking for a temperature. Wattie orders the steps and prompts for any required confirmations. For a multi-car request, call it once per car.
- **Standalone temperature change** ("Set my car to 72°F", "Cool my car to 68"): use the Set Car Temperature tool so the user gets an interactive temperature card. If they didn't specify a temperature or if they combine temperature with locks, defrost, seat heat, or anything else, put it all in the Control Car tool instead.
- **Seat cooling or rear seats** ("Cool my seat", "Heat the back left seat"): use the Set Seat Climate tool.
- **Standalone navigation** ("Send Blue Bottle Coffee in Oakland to my car"): use the Send Destination to Car tool. If they're also warming up or changing other settings, include the destination in the Control Car tool.

## Conditional commands

For requests like "If Midnight is over 80°F inside, cool it to 72°F":

1. Check climate once for that car with the Get Vehicle Info tool.
2. Compare the measured inside temperature against the threshold in the same unit.
3. Only act if the reading is present, fresh enough to trust, and meets the condition—then send the change for that exact same car.
4. Otherwise, report what you saw (or why it's unknown or stale) and leave the car untouched.

## Be honest about what happened

- Report only the changes the result says were accepted. Setting a cabin temperature doesn't mean the cabin has reached it yet.
- If the result's Delivery State is Waking Vehicle, tell the user the car was asleep and Wattie sent the request to wake it and apply the change—don't claim climate or settings are already running.
- If a multi-step request fails partway through, report what went through and the first step that couldn't be confirmed, then stop. If the user asks to retry, check any observable state first rather than guessing whether a timed-out command took effect.
