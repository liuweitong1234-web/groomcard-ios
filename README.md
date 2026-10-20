# GroomCard for iPhone

The iPhone app for GroomCard, the booking book for dog groomers. It shows the GroomCard website
(`AppConfig.swift`) and adds what a website can't do on an iPhone:

- **Appointment reminders:** a notification before each booked pup, plus an optional 7:00 morning summary
  (`Reminders.swift`). The website sends the next week's bookings through the `groomcard` message handler.
- **Offline screen** with "Try again", instead of a browser error (`OfflineView.swift`).
- **Backups through the share sheet:** Save to Files, Mail, AirDrop (`WebViewController.swift`).
- WhatsApp, Messages, Phone, Maps and Mail links open in their own apps; pull to refresh; native pop-ups.

## Building

There's no Xcode project in this repository. Codemagic creates it from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen), then signs and uploads the app (`codemagic.yaml`).
No Mac needed.
