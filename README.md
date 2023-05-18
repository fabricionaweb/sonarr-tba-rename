## Why

Sonarr have the feature to dont import episodes without name. It works fine.
But I was suffering by the problem to have 3 episodes in queue waiting for manual import. Even after one episode got named in the library, I need to discart the others...

## My solution

First you need to set the **Episode Title Required** to **Never** under `Settings > Media Management > Importing` (needs to Show Advanced)

![settings](https://user-images.githubusercontent.com/15933/189546188-0ba13cfb-e360-4f3e-b7af-dfd6a90d6b2d.png)

By doing this you end having episodes with **TBA** imported to the library, which is not good. But the import and upgrade keep working just fine. No needs to manual interaction, which is good. Worth to me.

This script is to keep trying to rename these episodes automatic, based on Sonarr's API.

Assuming you know how to do it, just add a cron to run every day or so `0 0 * * * /your-path/tba_rename.sh`

> **Warning**
> It does not help run it much often, Sonarr API does not refresh so often

## Explained

1. It runs over Sonarr library looking for episodes with "TBA" (to be announced) in the **filename** (for monitored series only).
1. When found one, it will ask Sonarr to try to refresh the serie metadata, trying to get the missing episode name.
   - Refresh Series happens naturally in 12h interval
1. Waits 30 seconds to Sonarr work on the requests.
1. Asks Sonarr to try to rename the episodes:
   - If the metadata was updated before, it will rename and log in the episode history.
   - If the metadata havent been updated, the rename wont have effect. Try the script again few hours later.
