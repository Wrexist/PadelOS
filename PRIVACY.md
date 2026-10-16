# PadelOS Privacy Policy

_Effective: 15 October 2026_

PadelOS does not collect any data.

- **No accounts.** You never sign up or log in.
- **No servers of ours.** Tournaments, players, scores and settings are stored on your
  iPhone and your Apple Watch (and, only for tournaments you share or whose live
  leaderboard you publish, in Apple's iCloud). The developer never receives them.
- **No analytics, no advertising, no tracking.** The app contains no third-party SDKs and
  does not use the advertising identifier.
- **iPhone ⇄ Apple Watch.** Scores are exchanged between your own iPhone and Apple Watch
  using Apple's Watch Connectivity framework. This data does not pass through any server
  operated by the developer.
- **Shared tournaments (optional).** If you tap Invite Players, the tournament (player
  names, schedule and scores) is stored in your own iCloud account using Apple's CloudKit
  and shared with the people who open your invitation link. Points they score are stored
  there too. The developer has no access to this data. Stop Sharing removes it from
  iCloud; a player who taps Leave Tournament removes it from their phone.
- **Live leaderboard (optional).** If you tap Share Live Leaderboard, a read-only
  summary of that tournament — its name, the players' (or teams') names, standings and
  scores — is published to the app's CloudKit **public** database at Apple under a
  random, unguessable link, and updated while sharing is on. Anyone with the link can
  view it in a web browser at `wrexist.github.io/PadelOS/live` (a static page hosted on
  GitHub Pages that loads Apple's CloudKit JS; no cookies, no analytics). Nothing else
  about you or your phone is included. Stop Live Leaderboard, or deleting the
  tournament, removes it. As with any website, Apple and GitHub process the requests
  of people who open the page.
- **Sharing results.** If you tap Share, the standings or results are passed to the share sheet,
  and you choose where they go (for example Messages). Nothing is shared otherwise.
- **Deleting your data.** Delete a tournament in the app (Manage → Delete Tournament), or
  delete the app to remove everything.

Questions: open an issue at <https://github.com/Wrexist/PadelOS/issues>.
