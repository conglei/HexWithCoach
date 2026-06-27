---
"hex-app": patch
---

Fix the Home / dictation navigation: (1) finishing an in-app note recording now opens that note's detail automatically instead of returning to Home; (2) the Recent items on Home are tappable and open the note; (3) the record mic is moved lower so it's easier to reach; (4) "See all" now always opens the History list — History's navigation stack is owned by ContentView and reset to root on "See all", so it no longer reopens a note you'd previously viewed.
