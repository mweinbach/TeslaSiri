---
name: driving-and-energy-insights
description: Answer questions about past drives, charging sessions, driving efficiency, charging spend, and battery health. Use when the user asks where or when they drove, how far or efficiently they went, to look up past trips or Supercharger stops, how much charging cost, or about battery degradation and phantom drain. Not for live readings like current battery or tire pressure, and not for controlling the car.
---

# Driving, Charging & Battery Insights

Everything here is read-only—the user wants answers about what their car has done, not to change anything.

## Looking up a specific trip or charge

1. If the drive or charging session is already on screen or came back from an earlier step, use it directly.
2. Otherwise find it first:
   - **Drives**: call the Find Drives tool. Put place names (including saved nicknames like "Home" or "Gym") in destination or origin when the direction is clear ("when did I last drive to Tahoe?" is a destination), and translate relative dates ("yesterday," "last weekend") into start and end dates. For older trips beyond recent history, include a date range.
   - **Charges**: call the Get Charging History tool. Use Superchargers only for Supercharger stops; for home charging, filter to AC/non-Supercharger sessions (and try the location filter "Home" if needed). Include a date range when searching older sessions beyond recent history.
3. If several sessions match and the user asked about one ("my drive to the airport"), pick the most recent match unless their wording points elsewhere. If it's genuinely ambiguous, briefly list the matches (date, place, distance or energy) and ask which one.
4. For deep follow-up questions on a specific trip or charge, pass it to the Get Drive Details tool or the Get Charge Details tool.

## Totals, recaps & battery health

- **Driving totals & efficiency** ("how much did I drive this week?", "my Autopilot miles", "since I last charged"): call the Get Driving Stats tool ("this week" → Last 7 Days; "since I charged" → Since Last Charge).
- **Charging totals & spend**: call the Get Charging Stats tool.
- **Weekly or monthly recap**: call both stats tools for the same period, compare energy driven vs. energy added charging, and include the total recorded cost.
- **Battery health, degradation, capacity, or phantom drain**: call the Get Battery Health & Stats tool (available when the connected provider reports pack health; if the tool says the provider doesn't report it, pass that along clearly).

## Keep answers clear and grounded

- Lead with the number the user asked for, followed by one or two helpful details—don't recite every field.
- Keep units (miles, kWh, Wh/mi) and currency exactly as returned; never convert costs to another currency.
- If a session has no recorded cost, say the cost wasn't recorded—never say it was free.

## Don't

- Don't send any car control or charging commands here. If the user follows up asking to change something like the charge limit, treat that as a new control request.
