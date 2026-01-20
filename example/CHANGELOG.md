## 1.1.0
* **Services & Characteristics:**
  * Add property filtering for characteristics with visual filter chips
  * Add navigation buttons to navigate between characteristics (previous/next)
  * Improve service sorting (favorites first, system services last)
  * Enhance services list UI with better filtering and navigation
  * Improve format for discovered services to be more detailed and human-readable
  * Move "Copy Services" button to Services panel header

* **Company & Manufacturer Data:**
  * Display company name based on company identifier from manufacturer data
  * Show and filter by company name in device list
  * Enhanced search functionality - now supports searching by company name

* **Scanning & Device Discovery:**
  * Improved scan button visibility - converted to prominent filled button with text label
  * Enhanced "no devices found" state with explicit "Start Scan" call-to-action button
  * Display RSSI values in device details

* **UI & Navigation:**
  * Moved search field to app bar header for better accessibility
  * Moved queue type settings to drawer menu as expandable section
  * Added tooltip to Bluetooth availability icon (tap to view on mobile)
  * Improved overall UI layout and navigation flow

* **Functionality:**
  * Add support for `autoConnect` parameter
  * Persist filters across app sessions
  * Fix clear log button functionality

## 1.0.0
* Initial release