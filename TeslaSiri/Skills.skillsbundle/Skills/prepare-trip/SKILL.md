---
name: prepare-trip
description: Get the user's car or Tesla ready to leave, by checking range and tire pressure, warming or cooling the cabin, and sending the destination to the car's navigation. Use when the user asks to get my car ready, prep the car for a commute or road trip, warm up or cool down my car before leaving, or asks if my car is ready to drive somewhere. Not for a single command like only setting the temperature or only sending an address, and not for securing a parked car overnight.
---

# Prepare a Trip

## 1. Check readiness

Use the Get Tesla Vehicle Info tool with the battery, range, charging, tire pressure, and climate topics. If the user only asks whether the car is ready, answer from those readings and stop.

For “my car,” omit the vehicle to use the default. If the user names a car, use that vehicle for the readings and all changes. Use the List Cars tool when you need to identify the car or answer a question about available controls. If the name is ambiguous, ask which car they mean. If it is unavailable, tell the user and stop.

- Tires: flag any tire under 38 PSI. Most Teslas recommend about 42 PSI cold.
- Range: if the user named a destination or a distance, compare it with the range. If less than about 20% of range would be left at arrival, say so.
  - If the car is plugged in, offer to raise the limit (90% for a long trip, 100% only if asked). Include the agreed limit and any requested start of charging with the other changes. The tool confirms the limit change before sending commands.
  - If it's unplugged, tell the user they'll need to charge before or during the trip.

## 2. Prepare the car

Send the cabin settings, any requested charging changes, and the destination together with the Control Car tool. A target temperature starts HVAC. Choose the cabin settings from the weather and what the user said.

- Freezing outside, or the user mentions ice, frost, or snow: about 22 °C, max defrost on, driver seat heat 3, steering wheel heater on.
- Hot cabin (above about 29 °C or 85 °F): about 20 °C. If the user explicitly asks for seat cooling, use the Set Tesla Seat Heater tool in cooling mode for the same car.
- Otherwise: 21 °C, or the temperature the user asked for.
- Smoke or poor air quality: turn on Bioweapon Defense Mode.

The user may say Fahrenheit. Convert to Celsius (°C = (°F − 32) × 5 ⁄ 9) and keep it between 15 and 28 °C.

## 3. Send the destination

Include the most complete address or place name in the same control request. If the user gave only a business name, include the city if you know it. If a command fails partway through, stop and report the accepted changes and the step the tool could not confirm. Leave the remaining steps pending until the user asks to continue.

## 4. Report

Summarize in a few lines: battery and range, cabin settings that were applied, any low tire, and the destination that was sent. If a command result’s Delivery State is Waking Vehicle, say the car was asleep and the request was sent to wake it rather than claiming climate is already running.

## Don't

- Don't unlock the car or open the trunk or frunk unless the user asked.
- Don't turn Dog Mode off.
