# Questions to resolve before ordering beyond a sample

The supplier has pointed to `github.com/HBandSDK`, stated that its SDK can
retrieve data without the G band app or cloud, and quoted $30.30 DDP for one
sample to the USA ($15.30 device + $15 shipping). These are supplier statements
from 2026-09-28; the sample test below must verify them.

Ask the H7 supplier for written detail and a working sample demonstration:

1. Which specific HBandSDK repository and SDK version supports this exact H7
   model and firmware? Provide sample code and redistribution terms.
2. Can an independent app pair, sync historical steps and sleep, and read
   heart-rate data with the phone offline and with no G band account or app?
3. What do the calorie numbers mean: active energy, resting plus active, or
   another quantity? What inputs and update frequency does the algorithm use?
4. Are raw accelerometer and PPG samples accessible, or only processed values?
   Is sleep staging available on H7, and which stages are returned?
5. How many days of history remain on the band without a phone sync? Can a
   second phone read it? How are time-zone changes and duplicate syncs handled?
6. Can the SDK be distributed in a paid App Store app without fees, keys,
   vendor servers, forced updates, or data collection? Provide the contract.
7. Supply the exact model's FCC/CE/RoHS reports, battery transport reports,
   test lab IDs, warranty and failure terms, firmware update path, and a
   volume quote including customization, shipping, duties, and replacements.

Acceptance test: one sample must produce repeatable offline steps and sleep
records through our own iPhone build before a production commitment.
