---
name: prepare-trip
description: Get the user's car ready to head out by checking battery, range, tire pressure, and cabin temperature, preconditioning the cabin, adjusting charging if needed, and sending the destination to the car. Use when the user asks to get my car ready, prep for a commute or road trip, warm up or cool down before leaving, or asks whether the car is ready to drive somewhere. Not for a single quick action like only setting the temperature or only sending an address, and not for securing a parked car overnight.
---

# Prepare for a Trip

## 1. Check if the car is ready

Start with one call to the Get Vehicle Info tool requesting battery, range, charging, tire pressure, and climate.

- Leave the vehicle empty for "my car." If the user names a car, keep every read and change on that same car (call the List Cars tool once if you need to identify it; ask if ambiguous; stop if unavailable).
- If they're only asking whether the car is ready, answer from those readings and stop.
- **Tires**: call out any tire below 38 PSI (most Teslas target around 42 PSI cold).
- **Range**: if they mentioned a destination or distance, compare it with current range and flag it if they'd arrive with under ~20% left.
  - Plugged in? Offer to bump the charge limit (90% for a long trip, 100% only if they ask) and start charging if they agree.
  - Unplugged? Let them know they'll need to charge before or during the drive.

## 2. Prep the car in one call

Bundle the cabin settings, any agreed charging changes, and the destination into a single call to the Control Car tool. Setting a target temperature starts climate automatically. Pick sensible defaults from the conditions and what the user asked:

- **Freezing, ice, frost, or snow**: ~72 °F (22 °C), max defrost on, driver seat heat 3, steering wheel heater on.
- **Hot cabin** (above ~85 °F / 29 °C): ~68 °F (20 °C). If they specifically ask for seat cooling or rear seat heat, also call the Set Seat Climate tool for the same car.
- **Smoke or poor air quality**: turn on Bioweapon Defense Mode.
- **Everyday conditions**: 70 °F (21 °C), or whatever temperature the user asked for—pass their value directly in °F (59–82 °F) or °C (15–28 °C) with the matching temperature unit; no manual unit conversion is needed.

When including a destination, pass the most complete address or place name you have (add the city if they only named a business).

## 3. Give a quick pre-departure summary

Wrap up in a few clear lines: battery and range, what cabin or charging changes went through, any low tire, and the destination sent.

- If the result's Delivery State is Waking Vehicle, say the car was asleep and the request was sent to wake it—don't say climate is already running.
- If a command fails partway through, report what succeeded and the first unconfirmed step, then stop until the user asks to continue.

## Don't

- Don't unlock the doors or open the trunk or frunk unless asked. If they ask, that's a separate call to the Unlock or Open Car tool after the prep call.
- Don't turn off Dog Mode.
