---
name: vehicle-control
description: Answer questions about the user's cars, available controls, and current vehicle status, compare readings across cars, or carry out requested changes. Use for questions such as which cars can cool a seat, whether a car is locked, or how much range is left, and for direct or conditional commands such as locking a car or cooling it if the cabin is hot. Trip preparation, overnight security, driving history, and software updates have their own workflows.
---

# Vehicle questions and controls

## Identify the car

For “my car,” omit the vehicle to use the default. For “this one,” a named car, or a follow-up, reuse the vehicle identified on screen or in the conversation. If you still need to identify it, use the List Cars tool once. If several cars match, give their names and ask which one. If the named car is unavailable, say so and stop.

## Choose the tool from what the user asked

- **Cars and capabilities.** For “Which cars do I have?” or “Can my car cool its seats?”, use the List Cars tool. It returns each car, the default marker, and its available controls and specialist actions. Report any “if equipped” qualification. A capability question ends with the answer.
- **Current status.** For “Is my car locked, and how much range is left?”, use the Get Tesla Vehicle Info tool directly with security and range in one call. Request only the topics needed. Lead with the readings and their units. If a reading is old, give its observation time. If a field is missing, say which fact is unknown. Use measured inside temperature for “Is it at 72°F yet?” and charging state for “Is it plugged in?”
- **Several cars.** For “Which of my cars has enough range for a 90-mile round trip?”, list the fleet once if needed, then request range for each car in scope. Compare each estimate with the 90-mile total and answer by car name. Report missing readings individually. If the user leaves out a distance that determines the answer, ask for it.
- **Direct changes.** “Can you lock my car?” asks for an action. Send clear changes for one car together with the Control Car tool. For “Turn on the air, set it to 72°F and lock my car,” pass the cabin target (about 22°C) and doors locked. The target starts HVAC. Omit other settings. Wattie orders the commands and handles required confirmations. For an explicit multi-car command, handle each requested vehicle separately.

## Check a condition before acting

For “If Midnight’s cabin is above 80°F, cool it to 72°F,” read climate once for Midnight. Compare the measured inside temperature with the threshold in the same unit. If it is above 80°F, pass that same vehicle and the requested target to the Control Car tool. If the condition is false, report the reading and stop. If the field or its observation time is missing, or the reading is too old to establish the condition, explain why and leave the car as it is. Keep a conditional change tied to the car that supplied the reading, including when the user started with the default.

## Report the outcome

Say which changes the command result reports as accepted. A cabin target can be accepted before the cabin reaches that temperature. After a partial failure, report the accepted steps and the first unconfirmed step, then stop. If the user asks to continue, check any uncertain outcome that can be observed before acting on the outstanding request. A timeout alone does not establish whether a command ran.

Use the Set Tesla Seat Heater tool in cooling mode for explicitly requested front-seat cooling. Use prepare-trip for departure preparation, overnight-security-check for a bedtime or away routine, driving-and-energy-insights for past sessions, and software-update-advisor for software questions or installations.
