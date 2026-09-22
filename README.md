# Reading Receipt for KOReader

Reading Receipt shows a receipt-style summary for the current book and can use that view as the KOReader suspend screen.

This project is being migrated from a userpatch prototype into a regular KOReader plugin. The current plugin entry point loads the receipt implementation from `receipt.lua` and keeps optional statistics experiments separate.

## Install

Place the whole `readingreceipt.koplugin` folder in KOReader's `plugins/` directory, then restart KOReader.

Typical plugin paths:

- Kindle: `/koreader/plugins/readingreceipt.koplugin`
- Kobo: `/.adds/koreader/plugins/readingreceipt.koplugin`
- Android: `koreader/plugins/readingreceipt.koplugin`

## Usage

Open KOReader's plugin menu and choose `Reading Receipt`.

Available actions:

- `Show reading receipt`: show the current book's receipt-style reading summary.
- `Use as suspend screen`: set Reading Receipt as the suspend screen type. The same option is also added to KOReader's `Screensaver` menu after the plugin loads.
- `Show book cover behind receipt`: render the last book's cover behind the receipt on the suspend screen. Enabled by default; turn it off in the plugin or Screensaver menu if you prefer a plain background.
- Tap the barcode area on the receipt to open the reading insights popup.
- `SimpleUI integration`: short setup hint for SimpleUI users.

Enable KOReader's built-in reading statistics plugin for meaningful stats in both the receipt and the insights popup.

When Reading Receipt is used as the suspend screen:

- While you are actively reading a book, the suspend screen shows the full reading receipt.
- After you leave the book, the suspend screen falls back to the last book's cover for faster lock-screen response.

This uses KOReader's `lastfile` setting, so locking from the file manager still works.

## SimpleUI

Reading Receipt registers Dispatcher actions so SimpleUI can bind them through Quick Actions, the Navigation Bar, or gestures:

- `Reading Receipt`
- `Use Reading Receipt as suspend screen`

The plugin does not require SimpleUI. If SimpleUI is installed, use its Quick Actions or Navigation Bar settings to add the Reading Receipt action.

An icon is provided at `icons/readingreceipt.svg` for use with SimpleUI custom icons.

## Plugin Structure

Core files:

- `_meta.lua`: KOReader plugin metadata.
- `main.lua`: plugin entry point, menu registration, and Dispatcher actions.
- `receipt.lua`: receipt UI, suspend-screen integration, and current-book data collection.
- `reading_insights_popup.lua`: reading insights popup opened from the receipt barcode area. Uses a 7-row book list layout, which fits smaller screens such as Kindle Paperwhite 3 better than an 8-row layout.
- `icons/readingreceipt.svg`: optional icon for SimpleUI.
- `icons/star.full.svg`: filled rating star used by the receipt view.
- `icons/star.half.svg`: half-filled rating star used by the receipt view.
- `icons/star.empty.svg`: empty rating star used by the receipt view.

Optional modules:

- `optional/calendar_stats.lua`: standalone reading calendar stats window. Not loaded by default because it overlaps with SimpleUI's own reading statistics features and may conflict with other statistics UI integrations.
