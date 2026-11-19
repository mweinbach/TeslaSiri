# iOS 26 vs. iOS 27 Visual Comparison Screenshots (`liquid-glass-hig`)

Inspect these side-by-side reference comparisons (sourced from *Design for Native*'s iOS 27 analysis) whenever you need exact visual verification of how iOS 27 altered Liquid Glass rendering relative to iOS 26.

| File | Delta Shown | Key Visual Takeaway |
| :--- | :--- | :--- |
| [ios27-borders-vs-shadow.jpg](./ios27-borders-vs-shadow.jpg) | **Light-Surface Borders vs. Drop Shadows** | On pure white backgrounds, iOS 26 glass pills rely on soft hazy shadows; iOS 27 draws crisp, defined perimeter borders so navigation circles and date pills stay distinct without heavy shadows. |
| [ios27-dark-glass-tabbar.jpg](./ios27-dark-glass-tabbar.jpg) | **Dark Mode Glass Lightness & Active Pill Inversion** | iOS 26 dark tab bar is very dark with a lighter gray active selection pill (`Home`); iOS 27 lightens the base dark glass container and **inverts** the active selection pill to a darker capsule for higher contrast. |
| [ios27-clear-vs-tinted-slider.jpg](./ios27-clear-vs-tinted-slider.jpg) | **System Transparency Slider (`Clear` ↔ `Tinted`)** | Demonstrates the dramatic range users control in Settings: near-clear glass refracting Apple Park trees on the left vs. high-opacity frosted tint on the right. Native controls adapt automatically. |
| [ios27-scroll-edge-top.jpg](./ios27-scroll-edge-top.jpg) | **Top Navigation Scroll Edge Default** | iOS 26 used a gradual soft gradient blur; iOS 27 switches the default top navigation bar edge to a crisp non-gradient blur with a subtle bottom border hairline. |
| [ios27-scroll-edge-bottom.jpg](./ios27-scroll-edge-bottom.jpg) | **Bottom Tab Bar Scroll Edge + `Tab(role: .prominent)`** | Left: iOS 27 default has *no* bottom edge blur, letting colorful cards clash sharply behind translucent tab labels. Right: explicitly applying `.scrollEdgeEffectStyle(.soft, for: .bottom)` restores clean legibility. Also shows the iOS 27 detached `+` prominent tab circle. |
